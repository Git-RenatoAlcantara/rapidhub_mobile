import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rapidhubmobile/orders/orders_api.dart';

/// Payload no formato exato de `serializeOrder` (app/api/orders/_lib.ts).
const _json = '''
{
  "id": "ord_1",
  "orderNumber": 87,
  "customerName": "João Conceição",
  "customerPhone": "(11) 98888-7777",
  "fulfillment": "delivery",
  "address": "Rua das Flores, 123",
  "paymentMethod": "cash",
  "changeFor": 100,
  "notes": "Interfone quebrado",
  "subtotal": 47.8,
  "deliveryFee": 7,
  "total": 54.8,
  "status": "preparing",
  "createdAt": "2026-07-13T17:32:00.000Z",
  "updatedAt": "2026-07-13T17:52:00.000Z",
  "items": [
    {
      "id": "it_1",
      "name": "Pizza",
      "quantity": 1,
      "unitPrice": 39.8,
      "lineTotal": 39.8,
      "options": [
        { "grupo": "Tamanho", "nome": "Grande", "priceDelta": 10 },
        { "grupo": "Borda", "nome": "Catupiry", "priceDelta": 5 }
      ],
      "notes": "sem cebola"
    }
  ]
}
''';

void main() {
  test('Order.fromJson lê os campos do serializeOrder do webapp', () {
    final order =
        Order.fromJson(jsonDecode(_json) as Map<String, dynamic>);

    expect(order.orderNumber, 87);
    expect(order.customerPhone, '(11) 98888-7777');
    expect(order.address, 'Rua das Flores, 123');
    expect(order.paymentMethod, 'cash');
    expect(order.paymentLabel, 'Dinheiro');
    expect(order.changeFor, 100);
    expect(order.notes, 'Interfone quebrado');
    expect(order.subtotal, 47.8);
    expect(order.deliveryFee, 7);
    expect(order.total, 54.8);
    expect(order.isPickup, isFalse);
    expect(order.fulfillmentLabel, 'Entrega');
    expect(order.updatedAt, isNotNull);
  });

  test('OrderItem lê opções (chaves grupo/nome) e observação', () {
    final order =
        Order.fromJson(jsonDecode(_json) as Map<String, dynamic>);
    final item = order.items.single;

    expect(item.unitPrice, 39.8);
    expect(item.notes, 'sem cebola');
    expect(item.options.map((o) => o.nome), ['Grande', 'Catupiry']);
    expect(item.options.first.grupo, 'Tamanho');
    expect(item.options.first.priceDelta, 10);
    expect(item.optionsSummary, 'Grande, Catupiry');
    expect(order.itemsSummary, 'Pizza (Grande, Catupiry) x1');
  });

  test('pedido antigo, sem os campos novos, ainda faz parse', () {
    final order = Order.fromJson({
      'id': 'ord_old',
      'orderNumber': 1,
      'customerName': 'Cliente',
      'fulfillment': 'pickup',
      'status': 'completed',
      'total': 20,
      'items': [
        {'name': 'Café', 'quantity': 2, 'lineTotal': 20}
      ],
      'createdAt': '2026-01-01T10:00:00.000Z',
    });

    expect(order.address, isNull);
    expect(order.paymentMethod, isNull);
    expect(order.paymentLabel, '—');
    expect(order.subtotal, 0);
    expect(order.deliveryFee, 0);
    expect(order.items.single.options, isEmpty);
    expect(order.items.single.notes, isNull);
  });
}
