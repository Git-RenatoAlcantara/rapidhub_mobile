import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rapidhubmobile/orders/orders_api.dart';
import 'package:rapidhubmobile/store/store_api.dart';
import 'package:rapidhubmobile/store/store_models.dart';
import 'package:rapidhubmobile/store_dashboard_screen.dart';

/// Devolve pedidos fixos e registra o intervalo pedido pelo painel.
class _FakeOrdersApi extends OrdersApi {
  _FakeOrdersApi(this.orders);

  final List<Order> orders;
  DateTime? lastFrom;
  DateTime? lastTo;

  @override
  Future<List<Order>> fetchOrders({
    String? status,
    DateTime? from,
    DateTime? to,
  }) async {
    lastFrom = from;
    lastTo = to;
    return orders;
  }
}

class _FakeStoreApi extends StoreApi {
  @override
  Future<Map<String, dynamic>> fetchStore() async => <String, dynamic>{};
}

Order _order(OrderStatus status, double total) => Order(
      id: 'o-${status.name}-$total',
      orderNumber: 1,
      customerName: 'Cliente',
      fulfillment: 'delivery',
      status: status,
      total: total,
      items: const [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now().add(const Duration(minutes: 20)),
    );

void main() {
  group('MenuMode', () {
    test('marmitex é reconhecido', () {
      expect(MenuMode.parse('marmitex'), MenuMode.marmitex);
      expect(MenuMode.marmitex.value, 'marmitex');
    });

    test('valor ausente ou desconhecido cai em regular', () {
      expect(MenuMode.parse(null), MenuMode.regular);
      expect(MenuMode.parse(''), MenuMode.regular);
      expect(MenuMode.parse('pizzaria'), MenuMode.regular);
    });
  });

  group('abandonmentTriggerStage', () {
    test('aceita os valores do webapp', () {
      for (final stage in kAbandonmentStages) {
        expect(parseAbandonmentStage(stage.value), stage.value);
      }
    });

    test('vazio ou desconhecido cai no padrão', () {
      expect(parseAbandonmentStage(null), 'delivery_address');
      expect(parseAbandonmentStage(''), 'delivery_address');
      expect(parseAbandonmentStage('inventado'), 'delivery_address');
    });
  });

  group('DashboardPeriod.range', () {
    final now = DateTime(2026, 7, 13, 15, 30); // segunda-feira

    test('hoje cobre o dia inteiro', () {
      final r = DashboardPeriod.today.range(now);
      expect(r.from, DateTime(2026, 7, 13));
      expect(r.to, DateTime(2026, 7, 13, 23, 59, 59, 999));
    });

    test('ontem cobre o dia anterior inteiro', () {
      final r = DashboardPeriod.yesterday.range(now);
      expect(r.from, DateTime(2026, 7, 12));
      expect(r.to, DateTime(2026, 7, 12, 23, 59, 59, 999));
    });

    test('7 dias inclui hoje e os 6 anteriores', () {
      final r = DashboardPeriod.last7.range(now);
      expect(r.from, DateTime(2026, 7, 7));
      expect(r.to, DateTime(2026, 7, 13, 23, 59, 59, 999));
      expect(r.to.difference(r.from).inDays, 6);
    });

    test('30 dias inclui hoje e os 29 anteriores', () {
      final r = DashboardPeriod.last30.range(now);
      expect(r.from, DateTime(2026, 6, 14));
      expect(r.to, DateTime(2026, 7, 13, 23, 59, 59, 999));
    });
  });

  group('Painel da Loja', () {
    testWidgets('Vendas soma tudo menos os cancelados', (tester) async {
      final orders = _FakeOrdersApi([
        _order(OrderStatus.completed, 100),
        _order(OrderStatus.preparing, 50), // em preparo: conta
        _order(OrderStatus.outForDelivery, 30), // saiu pra entrega: conta
        _order(OrderStatus.canceled, 999), // cancelado: NÃO conta
      ]);

      await tester.pumpWidget(MaterialApp(
        home: StoreDashboardScreen(
          storeApi: _FakeStoreApi(),
          ordersApi: orders,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('R\$ 180,00'), findsOneWidget); // 100 + 50 + 30
      expect(find.text('4'), findsOneWidget); // Pedidos: inclui o cancelado
      expect(find.text('20 min'), findsOneWidget); // preparo médio
    });

    testWidgets('trocar o período refaz a busca com o novo intervalo',
        (tester) async {
      final orders = _FakeOrdersApi([_order(OrderStatus.completed, 10)]);

      await tester.pumpWidget(MaterialApp(
        home: StoreDashboardScreen(
          storeApi: _FakeStoreApi(),
          ordersApi: orders,
        ),
      ));
      await tester.pumpAndSettle();

      // Padrão: hoje → intervalo de um dia.
      expect(orders.lastFrom, isNotNull);
      expect(orders.lastTo!.difference(orders.lastFrom!).inDays, 0);

      await tester.tap(find.text('30 dias'));
      await tester.pumpAndSettle();

      expect(orders.lastTo!.difference(orders.lastFrom!).inDays, 29);
      expect(find.text('RESULTADO — 30 DIAS'), findsOneWidget);
    });
  });
}
