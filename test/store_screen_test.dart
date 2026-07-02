import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rapidhubmobile/store/store_api.dart';
import 'package:rapidhubmobile/store_screen.dart';

/// StoreApi falso: não toca na rede. Configura o cenário de carregamento e
/// captura o `store` enviado no salvar.
class FakeStoreApi extends StoreApi {
  FakeStoreApi({
    this.store = const {},
    this.throwModuleDisabled = false,
    this.throwLoadError = false,
  });

  Map<String, dynamic> store;
  bool throwModuleDisabled;
  bool throwLoadError;

  /// Último `store` recebido em [saveStore].
  Map<String, dynamic>? savedStore;
  int saveCount = 0;

  @override
  Future<Map<String, dynamic>> fetchStore() async {
    if (throwModuleDisabled) throw const StoreModuleDisabled();
    if (throwLoadError) throw Exception('boom');
    return store;
  }

  @override
  Future<void> saveStore(Map<String, dynamic> store) async {
    savedStore = store;
    saveCount++;
  }

  @override
  Future<List<KitchenConnection>> fetchConnections() async => const [];

  @override
  Future<List<KitchenGroupOption>> fetchGroups(String connectionId) async =>
      const [];
}

Widget _wrap(StoreApi api) => MaterialApp(home: StoreScreen(api: api));

/// Monta a tela num viewport alto para que a `ListView` (lazy) construa todas
/// as seções — senão Frete/Retirada ficam fora da tela e não renderizam.
Future<void> _pumpStore(WidgetTester tester, StoreApi api) async {
  await tester.binding.setSurfaceSize(const Size(1000, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_wrap(api));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('módulo desativado mostra aviso e esconde o Salvar',
      (tester) async {
    await _pumpStore(tester, FakeStoreApi(throwModuleDisabled: true));

    expect(find.text('Loja indisponível'), findsOneWidget);
    expect(find.text('Salvar'), findsNothing);
  });

  testWidgets('erro de carregamento mostra "Tentar novamente"', (tester) async {
    await _pumpStore(tester, FakeStoreApi(throwLoadError: true));

    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.textContaining('Não foi possível carregar'), findsOneWidget);
  });

  testWidgets('loja vazia renderiza as 4 seções', (tester) async {
    await _pumpStore(tester, FakeStoreApi(store: {}));

    expect(find.text('GRUPO DA COZINHA'), findsOneWidget);
    expect(find.text('HORÁRIO DE FUNCIONAMENTO'), findsOneWidget);
    expect(find.text('ENTREGA POR BAIRRO'), findsOneWidget);
    expect(find.text('TEMPO DE RETIRADA'), findsOneWidget);
  });

  testWidgets('mexer num campo habilita o Salvar (dirty) e some após salvar',
      (tester) async {
    final api = FakeStoreApi(store: {});
    await _pumpStore(tester, api);

    // Nada mudou ainda: sem aviso de "não salvas".
    expect(find.text('Alterações não salvas'), findsNothing);

    // Ativa "Cobrar frete na entrega".
    await tester.tap(find.text('Cobrar frete na entrega'));
    await tester.pump();

    expect(find.text('Alterações não salvas'), findsOneWidget);

    // Salva.
    await tester.tap(find.text('Salvar'));
    await tester.pump(); // dispara o save (async) e o setState
    await tester.pump();

    expect(api.saveCount, 1);
    expect(find.text('Alterações não salvas'), findsNothing);
  });

  testWidgets('salvar envia o store no formato esperado', (tester) async {
    final api = FakeStoreApi(store: {});
    await _pumpStore(tester, api);

    await tester.tap(find.text('Cobrar frete na entrega'));
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    await tester.pump();

    final saved = api.savedStore!;
    expect(saved.keys,
        containsAll(['kitchenGroup', 'operatingHours', 'deliveryZones', 'pickupTime']));
    final dz = saved['deliveryZones'] as Map;
    expect(dz['enabled'], true);
    expect(dz['mode'], 'flat'); // modo padrão
    expect(saved['kitchenGroup'], isNull);
  });

  testWidgets('carrega config existente e não fica dirty de início',
      (tester) async {
    final api = FakeStoreApi(store: {
      'pickupTime': {'enabled': true, 'estimate': '20 min'},
    });
    await _pumpStore(tester, api);

    // A config carregada não conta como alteração.
    expect(find.text('Alterações não salvas'), findsNothing);
    // O estimate carregado aparece no campo.
    expect(find.text('20 min'), findsOneWidget);
  });
}
