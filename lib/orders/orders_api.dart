import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Lançado quando o módulo de Cardápio (menu) não está habilitado — as rotas
/// `/api/orders*` respondem 403 `MODULE_DISABLED`.
class OrdersModuleDisabled implements Exception {
  const OrdersModuleDisabled();
}

/// Cliente das rotas de Pedidos (`/api/orders` e `/api/orders/[id]/status`).
class OrdersApi {
  OrdersApi({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: 'session_token');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/orders → pedidos em andamento (qualquer dia) + concluídos de hoje.
  /// Passar [status] filtra por um status específico em todos os dias.
  Future<List<Order>> fetchOrders({String? status}) async {
    final uri = Uri.parse('$baseUrl/api/orders').replace(
      queryParameters: status == null ? null : {'status': status},
    );
    final resp = await http.get(uri, headers: await _headers());
    if (resp.statusCode == 403) throw const OrdersModuleDisabled();
    if (resp.statusCode != 200) {
      throw Exception('Falha ao carregar pedidos (${resp.statusCode})');
    }
    final body = jsonDecode(resp.body);
    final list = (body is Map) ? body['orders'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((o) => Order.fromJson(o.cast<String, dynamic>()))
        .toList();
  }

  /// PATCH /api/orders/[id]/status com `action: advance` → avança uma etapa.
  Future<Order?> advance(String orderId,
      {bool notifyCustomer = true}) async {
    return _patchStatus(orderId, {
      'action': 'advance',
      'notifyCustomer': notifyCustomer,
    });
  }

  /// PATCH /api/orders/[id]/status com `action: cancel` → cancela o pedido.
  Future<Order?> cancel(String orderId, {bool notifyCustomer = true}) async {
    return _patchStatus(orderId, {
      'action': 'cancel',
      'notifyCustomer': notifyCustomer,
    });
  }

  Future<Order?> _patchStatus(
      String orderId, Map<String, dynamic> payload) async {
    final resp = await http.patch(
      Uri.parse('$baseUrl/api/orders/$orderId/status'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    if (resp.statusCode == 403) throw const OrdersModuleDisabled();
    if (resp.statusCode != 200) {
      String message = 'Falha ao atualizar o pedido (${resp.statusCode})';
      try {
        final body = jsonDecode(resp.body);
        if (body is Map && body['error'] is String) message = body['error'];
      } catch (_) {}
      throw Exception(message);
    }
    final body = jsonDecode(resp.body);
    final order = (body is Map) ? body['order'] : null;
    return (order is Map)
        ? Order.fromJson(order.cast<String, dynamic>())
        : null;
  }
}

/// Status do pedido, espelhando a máquina de estados do backend.
enum OrderStatus {
  received,
  preparing,
  ready,
  outForDelivery,
  awaitingPickup,
  completed,
  canceled,
  unknown;

  static OrderStatus parse(String raw) {
    switch (raw) {
      case 'received':
        return OrderStatus.received;
      case 'preparing':
        return OrderStatus.preparing;
      case 'ready':
        return OrderStatus.ready;
      case 'out_for_delivery':
        return OrderStatus.outForDelivery;
      case 'awaiting_pickup':
        return OrderStatus.awaitingPickup;
      case 'completed':
        return OrderStatus.completed;
      case 'canceled':
        return OrderStatus.canceled;
      default:
        return OrderStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case OrderStatus.received:
        return 'Recebido';
      case OrderStatus.preparing:
        return 'Em preparo';
      case OrderStatus.ready:
        return 'Pronto';
      case OrderStatus.outForDelivery:
        return 'Saiu para entrega';
      case OrderStatus.awaitingPickup:
        return 'Aguardando retirada';
      case OrderStatus.completed:
        return 'Concluído';
      case OrderStatus.canceled:
        return 'Cancelado';
      case OrderStatus.unknown:
        return 'Desconhecido';
    }
  }

  bool get isTerminal =>
      this == OrderStatus.completed || this == OrderStatus.canceled;
}

class OrderItem {
  const OrderItem({
    required this.name,
    required this.quantity,
    required this.lineTotal,
  });

  final String name;
  final int quantity;
  final double lineTotal;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        name: (json['name'] ?? '').toString(),
        quantity: (json['quantity'] is num) ? json['quantity'] : 1,
        lineTotal:
            (json['lineTotal'] is num) ? (json['lineTotal'] as num).toDouble() : 0,
      );
}

class Order {
  const Order({
    required this.id,
    required this.orderNumber,
    required this.customerName,
    required this.fulfillment,
    required this.status,
    required this.total,
    required this.items,
    required this.createdAt,
  });

  final String id;
  final int orderNumber;
  final String customerName;
  final String fulfillment;
  final OrderStatus status;
  final double total;
  final List<OrderItem> items;
  final DateTime? createdAt;

  factory Order.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return Order(
      id: (json['id'] ?? '').toString(),
      orderNumber: (json['orderNumber'] is num) ? json['orderNumber'] : 0,
      customerName: (json['customerName'] ?? 'Cliente').toString(),
      fulfillment: (json['fulfillment'] ?? 'delivery').toString(),
      status: OrderStatus.parse((json['status'] ?? '').toString()),
      total: (json['total'] is num) ? (json['total'] as num).toDouble() : 0,
      items: (rawItems is List)
          ? rawItems
              .whereType<Map>()
              .map((i) => OrderItem.fromJson(i.cast<String, dynamic>()))
              .toList()
          : const [],
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString())
          ?.toLocal(),
    );
  }

  /// Resumo dos itens: "Smash Clássico x1, Coca-Cola x1".
  String get itemsSummary =>
      items.map((i) => '${i.name} x${i.quantity}').join(', ');
}
