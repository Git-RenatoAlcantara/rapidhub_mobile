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
  ///
  /// [status] filtra por um status específico em todos os dias. [from]/[to]
  /// recortam por data de criação (o backend aceita um ou outro, não os dois).
  Future<List<Order>> fetchOrders({
    String? status,
    DateTime? from,
    DateTime? to,
  }) async {
    final query = <String, String>{
      if (status != null) 'status': status,
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
    };
    final uri = Uri.parse('$baseUrl/api/orders').replace(
      queryParameters: query.isEmpty ? null : query,
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

/// Opção escolhida num item (tamanho, borda, adicional…).
///
/// O backend grava as chaves em português (`grupo`/`nome`), como as monta o
/// handler `finalizar-pedido`. Manter os mesmos nomes evita traduzir no parse.
class OrderOption {
  const OrderOption({
    required this.grupo,
    required this.nome,
    required this.priceDelta,
  });

  final String grupo;
  final String nome;
  final double priceDelta;

  factory OrderOption.fromJson(Map<String, dynamic> json) => OrderOption(
        grupo: (json['grupo'] ?? '').toString(),
        nome: (json['nome'] ?? '').toString(),
        priceDelta: (json['priceDelta'] is num)
            ? (json['priceDelta'] as num).toDouble()
            : 0,
      );
}

class OrderItem {
  const OrderItem({
    required this.name,
    required this.quantity,
    required this.lineTotal,
    this.unitPrice = 0,
    this.options = const [],
    this.notes,
  });

  final String name;
  final int quantity;
  final double lineTotal;
  final double unitPrice;

  /// Tamanho, borda, adicionais — já com o preço somado em [lineTotal].
  final List<OrderOption> options;

  /// Observação do cliente para este item ("sem cebola").
  final String? notes;

  /// "Grande, Catupiry" — as opções em uma linha, para o cupom e a lista.
  String get optionsSummary =>
      options.map((o) => o.nome).where((n) => n.isNotEmpty).join(', ');

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    final rawNotes = json['notes'];
    return OrderItem(
      name: (json['name'] ?? '').toString(),
      quantity: (json['quantity'] is num) ? json['quantity'] : 1,
      lineTotal: (json['lineTotal'] is num)
          ? (json['lineTotal'] as num).toDouble()
          : 0,
      unitPrice: (json['unitPrice'] is num)
          ? (json['unitPrice'] as num).toDouble()
          : 0,
      options: (rawOptions is List)
          ? rawOptions
              .whereType<Map>()
              .map((o) => OrderOption.fromJson(o.cast<String, dynamic>()))
              .toList()
          : const [],
      notes: (rawNotes is String && rawNotes.trim().isNotEmpty)
          ? rawNotes
          : null,
    );
  }
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
    this.updatedAt,
    this.customerPhone,
    this.address,
    this.paymentMethod,
    this.changeFor,
    this.notes,
    this.subtotal = 0,
    this.deliveryFee = 0,
  });

  final String id;
  final int orderNumber;
  final String customerName;
  final String fulfillment;
  final OrderStatus status;
  final double total;
  final List<OrderItem> items;
  final DateTime? createdAt;

  /// Última mudança de status — base do tempo médio de preparo no painel.
  final DateTime? updatedAt;

  final String? customerPhone;

  /// Endereço da entrega. Nulo nos pedidos de retirada.
  final String? address;

  /// `pix` | `cash` | `card`.
  final String? paymentMethod;

  /// Valor para o qual o entregador deve levar troco (só em dinheiro).
  final double? changeFor;

  /// Observação geral do pedido.
  final String? notes;

  final double subtotal;
  final double deliveryFee;

  bool get isPickup => fulfillment == 'pickup';

  String get fulfillmentLabel => isPickup ? 'Retirada' : 'Entrega';

  /// Rótulo da forma de pagamento, como no webapp. Método desconhecido é
  /// mostrado cru, em vez de sumir do cupom.
  String get paymentLabel {
    switch (paymentMethod) {
      case 'pix':
        return 'Pix';
      case 'cash':
        return 'Dinheiro';
      case 'card':
        return 'Cartão';
      case null:
        return '—';
      default:
        return paymentMethod!;
    }
  }

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
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString())
          ?.toLocal(),
      customerPhone: _text(json['customerPhone']),
      address: _text(json['address']),
      paymentMethod: _text(json['paymentMethod']),
      changeFor:
          (json['changeFor'] is num) ? (json['changeFor'] as num).toDouble() : null,
      notes: _text(json['notes']),
      subtotal:
          (json['subtotal'] is num) ? (json['subtotal'] as num).toDouble() : 0,
      deliveryFee: (json['deliveryFee'] is num)
          ? (json['deliveryFee'] as num).toDouble()
          : 0,
    );
  }

  /// String não-vazia, ou `null`. O backend manda `null` e, em alguns casos,
  /// string vazia — os dois significam "não informado".
  static String? _text(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Resumo dos itens, com as opções escolhidas:
  /// "Pizza (Grande, Catupiry) x1, Coca-Cola x1".
  String get itemsSummary => items.map((i) {
        final opts = i.optionsSummary;
        final name = opts.isEmpty ? i.name : '${i.name} ($opts)';
        return '$name x${i.quantity}';
      }).join(', ');
}
