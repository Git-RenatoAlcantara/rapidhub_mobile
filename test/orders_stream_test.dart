import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rapidhubmobile/orders/orders_api.dart';
import 'package:rapidhubmobile/orders/orders_stream.dart';
import 'package:rapidhubmobile/pedidos_screen.dart';

/// Stream de pedidos controlado pelo teste — não abre socket nenhum.
class _FakeOrdersStream extends OrdersStream {
  final _controller = StreamController<OrderEvent>.broadcast();

  @override
  Stream<OrderEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {}

  void emit(OrderEvent event) => _controller.add(event);

  @override
  Future<void> dispose() async => _controller.close();
}

class _FakeOrdersApi extends OrdersApi {
  _FakeOrdersApi(this.orders);

  final List<Order> orders;

  @override
  Future<List<Order>> fetchOrders({
    String? status,
    DateTime? from,
    DateTime? to,
  }) async =>
      orders;
}

Order _order({
  required int number,
  required OrderStatus status,
  String name = 'Cliente',
}) =>
    Order(
      id: 'ord_$number',
      orderNumber: number,
      customerName: name,
      fulfillment: 'delivery',
      status: status,
      total: 25,
      items: const [OrderItem(name: 'Item', quantity: 1, lineTotal: 25)],
      createdAt: DateTime(2026, 7, 13, 12),
    );

void main() {
  testWidgets('pedido novo do SSE entra na lista sem refresh', (tester) async {
    final stream = _FakeOrdersStream();

    await tester.pumpWidget(MaterialApp(
      home: PedidosScreen(api: _FakeOrdersApi(const []), stream: stream),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('#77'), findsNothing);

    stream.emit(OrderEvent(
      OrderEventType.created,
      _order(number: 77, status: OrderStatus.received, name: 'Ana'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('#77 • Ana'), findsOneWidget);
  });

  testWidgets('mudança de status pelo SSE atualiza o pedido no lugar',
      (tester) async {
    final stream = _FakeOrdersStream();
    final existing = _order(number: 12, status: OrderStatus.received);

    await tester.pumpWidget(MaterialApp(
      home: PedidosScreen(api: _FakeOrdersApi([existing]), stream: stream),
    ));
    await tester.pumpAndSettle();

    // "Recebido" (singular) só aparece no selo do cartão; "Em preparo" também
    // é rótulo de aba e de estatística, daí comparar a contagem.
    expect(find.text('Recebido'), findsOneWidget);
    final preparingBefore = find.text('Em preparo').evaluate().length;

    stream.emit(OrderEvent(
      OrderEventType.statusChanged,
      _order(number: 12, status: OrderStatus.preparing),
    ));
    await tester.pumpAndSettle();

    // Continua um único cartão — atualizado, não duplicado.
    expect(find.text('#12 • Cliente'), findsOneWidget);
    expect(find.text('Recebido'), findsNothing);
    expect(find.text('Em preparo').evaluate().length, preparingBefore + 1);
  });

  group('OrderEventType.parse', () {
    test('reconhece os tipos que o servidor manda', () {
      expect(OrderEventType.parse('order_created'), OrderEventType.created);
      expect(OrderEventType.parse('order_status_changed'),
          OrderEventType.statusChanged);
    });

    test('tipo desconhecido vira null', () {
      expect(OrderEventType.parse('ticket_update'), isNull);
      expect(OrderEventType.parse(null), isNull);
    });
  });
}
