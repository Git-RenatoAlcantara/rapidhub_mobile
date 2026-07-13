import 'dart:async';
import 'dart:convert';

import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import 'orders_api.dart';

/// O que aconteceu com o pedido do outro lado da linha.
enum OrderEventType {
  created,
  statusChanged;

  /// `null` para qualquer tipo que não conheçamos — o chamador ignora.
  static OrderEventType? parse(Object? raw) {
    switch (raw) {
      case 'order_created':
        return OrderEventType.created;
      case 'order_status_changed':
        return OrderEventType.statusChanged;
      default:
        return null;
    }
  }
}

class OrderEvent {
  const OrderEvent(this.type, this.order);

  final OrderEventType type;
  final Order order;
}

/// Pedidos em tempo real via SSE (`GET /api/orders/stream`).
///
/// O servidor manda um frame por evento, sem nome de evento:
/// `data: {"type":"order_created","order":{…},"timestamp":"…"}`, além de
/// comentários de heartbeat a cada 30s (que chegam com `data` vazio).
class OrdersStream {
  OrdersStream({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  final StreamController<OrderEvent> _controller =
      StreamController<OrderEvent>.broadcast();

  StreamSubscription<SSEModel>? _sub;

  Stream<OrderEvent> get events => _controller.stream;

  Future<void> connect() async {
    final token = await _storage.read(key: 'session_token');
    await _sub?.cancel();

    _sub = SSEClient.subscribeToSSE(
      method: SSERequestType.GET,
      url: '$baseUrl/api/orders/stream',
      header: {
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Authorization': 'Bearer ${token ?? ''}',
      },
    ).listen(
      _onFrame,
      // Queda de rede não pode derrubar a tela: o pacote reconecta sozinho e,
      // enquanto isso, o pull-to-refresh continua sendo o plano B.
      onError: (_) {},
    );
  }

  void _onFrame(SSEModel event) {
    final payload = event.data;
    if (payload == null || payload.trim().isEmpty) return; // heartbeat
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return;

      final type = OrderEventType.parse(decoded['type']);
      if (type == null) return;

      final raw = decoded['order'];
      if (raw is! Map) return;

      _controller.add(
        OrderEvent(type, Order.fromJson(raw.cast<String, dynamic>())),
      );
    } catch (_) {
      // Frame malformado: ignora e segue ouvindo.
    }
  }

  Future<void> dispose() async {
    // Só cancela esta assinatura. `SSEClient.unsubscribeFromSSE()` é global e
    // derrubaria também os streams de conversas.
    await _sub?.cancel();
    _sub = null;
    await _controller.close();
  }
}
