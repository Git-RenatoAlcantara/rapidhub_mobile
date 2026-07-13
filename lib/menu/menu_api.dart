import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Lançado quando o módulo de Cardápio (menu) não está habilitado para a
/// organização — as rotas `/api/menu/*` respondem 403 `MODULE_DISABLED`.
class MenuModuleDisabled implements Exception {
  const MenuModuleDisabled();
}

/// Lançado quando o usuário está autenticado mas o papel dele não permite a
/// ação (403 `FORBIDDEN`). É diferente de módulo desligado: o cardápio existe,
/// só que este operador não pode criar/editar/excluir.
class MenuForbidden implements Exception {
  const MenuForbidden(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Cliente das rotas do Cardápio (`/api/menu/*`).
///
/// Autentica por Bearer token (mesma sessão dos demais ecrãs). A organização
/// ativa vem da sessão no servidor, como no resto do app.
class MenuApi {
  MenuApi({FlutterSecureStorage? storage, http.Client? client})
      : _storage = storage ?? const FlutterSecureStorage(),
        _client = client ?? http.Client();

  final FlutterSecureStorage _storage;

  /// Injetável nos testes; em produção é o cliente padrão do pacote `http`.
  final http.Client _client;

  Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: 'session_token');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Traduz a resposta em exceção ou no corpo já decodificado.
  ///
  /// Um 403 pode significar duas coisas bem diferentes — módulo desligado
  /// (`MODULE_DISABLED`) ou falta de permissão do papel (`FORBIDDEN`) — e
  /// confundir as duas faria o app dizer "ative o módulo" a quem só não pode
  /// editar. Por isso olhamos o `code` do corpo, não só o status.
  dynamic _decode(http.Response resp, String action) {
    dynamic body;
    try {
      body = jsonDecode(resp.body);
    } catch (_) {
      body = null;
    }

    if (resp.statusCode == 403) {
      final code = (body is Map) ? body['code'] : null;
      if (code == 'MODULE_DISABLED') throw const MenuModuleDisabled();
      throw MenuForbidden(_errorMessage(body) ??
          'Você não tem permissão para $action.');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        _errorMessage(body) ?? 'Falha ao $action (${resp.statusCode})',
      );
    }

    return body;
  }

  static String? _errorMessage(dynamic body) {
    if (body is! Map) return null;
    final message = body['message'] ?? body['error'];
    return (message is String && message.isNotEmpty) ? message : null;
  }

  // ── Cardápios (menus) ────────────────────────────────────────────────────

  /// GET /api/menu/menus → cardápios da loja.
  Future<List<Menu>> fetchMenus() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/menu/menus'),
      headers: await _headers(),
    );
    final body = _decode(resp, 'carregar os cardápios');
    final list = (body is Map) ? body['menus'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => Menu.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  /// POST /api/menu/menus → cria um cardápio.
  Future<Menu> createMenu({
    required String name,
    bool isActive = true,
    int? order,
    MenuAvailability? availability,
  }) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/menu/menus'),
      headers: await _headers(),
      body: jsonEncode({
        'name': name,
        'isActive': isActive,
        if (order != null) 'order': order,
        'availability': availability?.toJson(),
      }),
    );
    final body = _decode(resp, 'criar o cardápio');
    return Menu.fromJson((body as Map).cast<String, dynamic>());
  }

  /// PUT /api/menu/menus/[id] → atualiza nome, ordem, toggle e horários.
  ///
  /// `availability` só é enviada quando [touchAvailability] é `true`; assim
  /// dá para renomear um cardápio sem apagar as janelas de horário dele.
  Future<Menu> updateMenu(
    String id, {
    String? name,
    bool? isActive,
    int? order,
    MenuAvailability? availability,
    bool touchAvailability = false,
  }) async {
    final resp = await http.put(
      Uri.parse('$baseUrl/api/menu/menus/$id'),
      headers: await _headers(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (isActive != null) 'isActive': isActive,
        if (order != null) 'order': order,
        if (touchAvailability) 'availability': availability?.toJson(),
      }),
    );
    final body = _decode(resp, 'atualizar o cardápio');
    return Menu.fromJson((body as Map).cast<String, dynamic>());
  }

  /// DELETE /api/menu/menus/[id]. Os produtos ficam sem cardápio (não somem).
  Future<void> deleteMenu(String id) async {
    final resp = await http.delete(
      Uri.parse('$baseUrl/api/menu/menus/$id'),
      headers: await _headers(),
    );
    _decode(resp, 'excluir o cardápio');
  }

  // ── Categorias ───────────────────────────────────────────────────────────

  /// GET /api/menu/categories → categorias do cardápio.
  Future<List<MenuCategory>> fetchCategories() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/menu/categories'),
      headers: await _headers(),
    );
    final body = _decode(resp, 'carregar as categorias');
    final list = (body is Map) ? body['categories'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((c) => MenuCategory.fromJson(c.cast<String, dynamic>()))
        .toList();
  }

  Future<MenuCategory> createCategory({
    required String name,
    int? order,
    bool isActive = true,
  }) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/menu/categories'),
      headers: await _headers(),
      body: jsonEncode({
        'name': name,
        'isActive': isActive,
        if (order != null) 'order': order,
      }),
    );
    final body = _decode(resp, 'criar a categoria');
    return MenuCategory.fromJson((body as Map).cast<String, dynamic>());
  }

  Future<MenuCategory> updateCategory(
    String id, {
    String? name,
    int? order,
    bool? isActive,
  }) async {
    final resp = await http.put(
      Uri.parse('$baseUrl/api/menu/categories/$id'),
      headers: await _headers(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (order != null) 'order': order,
        if (isActive != null) 'isActive': isActive,
      }),
    );
    final body = _decode(resp, 'atualizar a categoria');
    return MenuCategory.fromJson((body as Map).cast<String, dynamic>());
  }

  /// DELETE /api/menu/categories/[id]. Os produtos ficam sem categoria.
  Future<void> deleteCategory(String id) async {
    final resp = await http.delete(
      Uri.parse('$baseUrl/api/menu/categories/$id'),
      headers: await _headers(),
    );
    _decode(resp, 'excluir a categoria');
  }

  // ── Produtos ─────────────────────────────────────────────────────────────

  /// GET /api/menu/products → produtos (opcionalmente por categoria).
  Future<List<MenuProduct>> fetchProducts({String? categoryId}) async {
    final uri = Uri.parse('$baseUrl/api/menu/products').replace(
      queryParameters: categoryId == null ? null : {'categoryId': categoryId},
    );
    final resp = await http.get(uri, headers: await _headers());
    final body = _decode(resp, 'carregar os produtos');
    final list = (body is Map) ? body['products'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((p) => MenuProduct.fromJson(p.cast<String, dynamic>()))
        .toList();
  }

  Future<MenuProduct> createProduct({
    required String name,
    required double price,
    String? description,
    String? categoryId,
    String? menuId,
    bool isAvailable = true,
    List<int> availableWeekdays = const [],
  }) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/menu/products'),
      headers: await _headers(),
      body: jsonEncode({
        'name': name,
        'price': price,
        'description': description,
        'categoryId': categoryId,
        'menuId': menuId,
        'isAvailable': isAvailable,
        'availableWeekdays': availableWeekdays,
      }),
    );
    final body = _decode(resp, 'criar o produto');
    return MenuProduct.fromJson((body as Map).cast<String, dynamic>());
  }

  /// PUT /api/menu/products/[id].
  ///
  /// Atenção: a resposta desta rota **não traz os grupos de opções** (só a
  /// categoria). Quem chama deve recarregar a lista em vez de confiar no
  /// produto devolvido, senão as opções somem da tela.
  Future<void> updateProduct(
    String id, {
    String? name,
    double? price,
    String? description,
    String? categoryId,
    String? menuId,
    bool? isAvailable,
    List<int>? availableWeekdays,
    bool clearCategory = false,
    bool clearMenu = false,
  }) async {
    final resp = await http.put(
      Uri.parse('$baseUrl/api/menu/products/$id'),
      headers: await _headers(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (price != null) 'price': price,
        // `description: null` limpa o campo no servidor — mandar sempre.
        'description': description,
        if (categoryId != null || clearCategory) 'categoryId': categoryId,
        if (menuId != null || clearMenu) 'menuId': menuId,
        if (isAvailable != null) 'isAvailable': isAvailable,
        if (availableWeekdays != null) 'availableWeekdays': availableWeekdays,
      }),
    );
    _decode(resp, 'atualizar o produto');
  }

  Future<void> deleteProduct(String id) async {
    final resp = await http.delete(
      Uri.parse('$baseUrl/api/menu/products/$id'),
      headers: await _headers(),
    );
    _decode(resp, 'excluir o produto');
  }

  // ── Opções do produto ────────────────────────────────────────────────────

  /// PUT /api/menu/products/[id]/options — **substitui todos** os grupos.
  ///
  /// A rota apaga os grupos existentes e recria a partir do payload; mandar
  /// uma lista vazia remove todas as opções do produto.
  Future<MenuProduct> saveOptions(
      String productId, List<MenuOptionGroup> groups) async {
    final resp = await http.put(
      Uri.parse('$baseUrl/api/menu/products/$productId/options'),
      headers: await _headers(),
      body: jsonEncode({
        'groups': [
          for (var i = 0; i < groups.length; i++) groups[i].toJson(i),
        ],
      }),
    );
    final body = _decode(resp, 'salvar as opções');
    return MenuProduct.fromJson((body as Map).cast<String, dynamic>());
  }

  // ── Disponibilidade por data ─────────────────────────────────────────────

  /// GET /api/menu/today → o cardápio efetivo do dia, já resolvido pelo
  /// servidor (toggle + dias da semana + exceções por data).
  ///
  /// Devolve os ids dos produtos vendáveis hoje. Usamos o servidor em vez de
  /// recalcular no app porque a lista de produtos não traz os overrides — e
  /// duas implementações da mesma regra acabariam divergindo.
  Future<Set<String>> fetchAvailableTodayIds({String? date}) async {
    final uri = Uri.parse('$baseUrl/api/menu/today').replace(
      queryParameters: date == null ? null : {'date': date},
    );
    final resp = await http.get(uri, headers: await _headers());
    final body = _decode(resp, 'carregar o cardápio de hoje');
    final categories = (body is Map) ? body['categories'] : null;
    if (categories is! List) return <String>{};

    final ids = <String>{};
    for (final category in categories.whereType<Map>()) {
      final products = category['products'];
      if (products is! List) continue;
      for (final product in products.whereType<Map>()) {
        final id = product['id']?.toString();
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }
    return ids;
  }

  /// GET /api/menu/products/[id]/availability?from=&to= (datas `YYYY-MM-DD`).
  Future<List<AvailabilityOverride>> fetchOverrides(
    String productId, {
    required String from,
    required String to,
  }) async {
    final uri = Uri.parse('$baseUrl/api/menu/products/$productId/availability')
        .replace(queryParameters: {'from': from, 'to': to});
    final resp = await http.get(uri, headers: await _headers());
    final body = _decode(resp, 'carregar a disponibilidade');
    final list = (body is Map) ? body['overrides'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((o) => AvailabilityOverride.fromJson(o.cast<String, dynamic>()))
        .toList();
  }

  /// PUT → cria ou atualiza o bloqueio/liberação do produto naquela data.
  Future<AvailabilityOverride> setOverride(
    String productId, {
    required String date,
    required bool isAvailable,
    String? note,
  }) async {
    final resp = await http.put(
      Uri.parse('$baseUrl/api/menu/products/$productId/availability'),
      headers: await _headers(),
      body: jsonEncode({
        'date': date,
        'isAvailable': isAvailable,
        'note': note,
      }),
    );
    final body = _decode(resp, 'salvar a disponibilidade');
    return AvailabilityOverride.fromJson((body as Map).cast<String, dynamic>());
  }

  /// DELETE → remove o override e devolve o produto à regra semanal.
  Future<void> clearOverride(String productId, {required String date}) async {
    final uri = Uri.parse('$baseUrl/api/menu/products/$productId/availability')
        .replace(queryParameters: {'date': date});
    final resp = await http.delete(uri, headers: await _headers());
    _decode(resp, 'limpar a disponibilidade');
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Modelos
// ══════════════════════════════════════════════════════════════════════════

/// Janela de horário de um cardápio. Minutos desde a meia-noite (0…1440).
class MenuSlot {
  MenuSlot({
    required this.weekday,
    required this.fromMinutes,
    required this.toMinutes,
    this.isActive = true,
  });

  int weekday; // 0 = domingo … 6 = sábado
  int fromMinutes;
  int toMinutes;
  bool isActive;

  factory MenuSlot.fromJson(Map<String, dynamic> json) => MenuSlot(
        weekday: (json['weekday'] is num) ? (json['weekday'] as num).toInt() : 0,
        fromMinutes: (json['fromMinutes'] is num)
            ? (json['fromMinutes'] as num).toInt()
            : 0,
        toMinutes:
            (json['toMinutes'] is num) ? (json['toMinutes'] as num).toInt() : 0,
        isActive: json['isActive'] != false,
      );

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'fromMinutes': fromMinutes,
        'toMinutes': toMinutes,
        'isActive': isActive,
      };

  MenuSlot copy() => MenuSlot(
        weekday: weekday,
        fromMinutes: fromMinutes,
        toMinutes: toMinutes,
        isActive: isActive,
      );
}

/// `{ enabled, timezone?, slots }` — quando `null` no servidor, o cardápio não
/// tem restrição de horário e depende só do toggle `isActive`.
class MenuAvailability {
  MenuAvailability({
    required this.enabled,
    this.timezone,
    List<MenuSlot>? slots,
  }) : slots = slots ?? [];

  bool enabled;
  String? timezone;
  List<MenuSlot> slots;

  static MenuAvailability? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.cast<String, dynamic>();
    final rawSlots = json['slots'];
    return MenuAvailability(
      enabled: json['enabled'] == true,
      timezone: json['timezone']?.toString(),
      slots: (rawSlots is List)
          ? rawSlots
              .whereType<Map>()
              .map((s) => MenuSlot.fromJson(s.cast<String, dynamic>()))
              .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (timezone != null) 'timezone': timezone,
        'slots': slots.map((s) => s.toJson()).toList(),
      };
}

class Menu {
  const Menu({
    required this.id,
    required this.name,
    required this.order,
    required this.isActive,
    required this.productCount,
    this.availability,
  });

  final String id;
  final String name;
  final int order;
  final bool isActive;
  final int productCount;

  /// `null` = sem restrição de horário.
  final MenuAvailability? availability;

  factory Menu.fromJson(Map<String, dynamic> json) {
    final count = json['_count'];
    return Menu(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      order: (json['order'] is num) ? (json['order'] as num).toInt() : 0,
      isActive: json['isActive'] != false,
      productCount:
          (count is Map && count['products'] is num) ? count['products'] : 0,
      availability: MenuAvailability.fromJson(json['availability']),
    );
  }
}

class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.name,
    required this.productCount,
    this.order = 0,
    this.isActive = true,
  });

  final String id;
  final String name;
  final int productCount;
  final int order;
  final bool isActive;

  factory MenuCategory.fromJson(Map<String, dynamic> json) {
    final count = json['_count'];
    return MenuCategory(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      productCount:
          (count is Map && count['products'] is num) ? count['products'] : 0,
      order: (json['order'] is num) ? (json['order'] as num).toInt() : 0,
      isActive: json['isActive'] != false,
    );
  }
}

/// Opção dentro de um grupo (ex.: "Catupiry", +R$ 5,00).
class MenuOption {
  MenuOption({
    required this.name,
    this.priceDelta = 0,
    this.isAvailable = true,
    this.id,
  });

  final String? id;
  String name;
  double priceDelta;
  bool isAvailable;

  factory MenuOption.fromJson(Map<String, dynamic> json) => MenuOption(
        id: json['id']?.toString(),
        name: (json['name'] ?? '').toString(),
        priceDelta: (json['priceDelta'] is num)
            ? (json['priceDelta'] as num).toDouble()
            : 0,
        isAvailable: json['isAvailable'] != false,
      );

  /// A ordem é posicional: mandamos o índice, como faz o webapp.
  Map<String, dynamic> toJson(int index) => {
        'name': name,
        'priceDelta': priceDelta,
        'isAvailable': isAvailable,
        'order': index,
      };

  MenuOption copy() => MenuOption(
        id: id,
        name: name,
        priceDelta: priceDelta,
        isAvailable: isAvailable,
      );
}

/// Grupo de opções (ex.: "Tamanho", escolha 1 de 3).
class MenuOptionGroup {
  MenuOptionGroup({
    required this.name,
    this.minSelect = 0,
    this.maxSelect = 1,
    List<MenuOption>? options,
    this.id,
  }) : options = options ?? [];

  final String? id;
  String name;
  int minSelect;
  int maxSelect;
  List<MenuOption> options;

  /// Obrigatório quando exige ao menos uma escolha.
  bool get isRequired => minSelect > 0;

  factory MenuOptionGroup.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    return MenuOptionGroup(
      id: json['id']?.toString(),
      name: (json['name'] ?? '').toString(),
      minSelect:
          (json['minSelect'] is num) ? (json['minSelect'] as num).toInt() : 0,
      maxSelect:
          (json['maxSelect'] is num) ? (json['maxSelect'] as num).toInt() : 1,
      options: (rawOptions is List)
          ? rawOptions
              .whereType<Map>()
              .map((o) => MenuOption.fromJson(o.cast<String, dynamic>()))
              .toList()
          : [],
    );
  }

  /// O servidor força `maxSelect >= max(minSelect, 1)`; aplicamos a mesma
  /// regra antes de enviar para não salvar um grupo impossível de escolher.
  Map<String, dynamic> toJson(int index) {
    final max = [maxSelect, minSelect, 1].reduce((a, b) => a > b ? a : b);
    return {
      'name': name,
      'minSelect': minSelect,
      'maxSelect': max,
      'order': index,
      'options': [
        for (var i = 0; i < options.length; i++) options[i].toJson(i),
      ],
    };
  }

  MenuOptionGroup copy() => MenuOptionGroup(
        id: id,
        name: name,
        minSelect: minSelect,
        maxSelect: maxSelect,
        options: options.map((o) => o.copy()).toList(),
      );
}

/// Bloqueio/liberação de um produto numa data específica.
class AvailabilityOverride {
  const AvailabilityOverride({
    required this.date,
    required this.isAvailable,
    this.note,
  });

  /// `YYYY-MM-DD`.
  final String date;
  final bool isAvailable;
  final String? note;

  factory AvailabilityOverride.fromJson(Map<String, dynamic> json) =>
      AvailabilityOverride(
        date: (json['date'] ?? '').toString(),
        isAvailable: json['isAvailable'] == true,
        note: (json['note'] is String && (json['note'] as String).isNotEmpty)
            ? json['note'] as String
            : null,
      );
}

class MenuProduct {
  const MenuProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.categoryId,
    required this.categoryName,
    required this.imageUrl,
    required this.isAvailable,
    this.menuId,
    this.availableWeekdays = const [],
    this.order = 0,
    this.optionGroups = const [],
  });

  final String id;
  final String name;
  final String description;
  final double price;
  final String? categoryId;
  final String? categoryName;
  final String? imageUrl;

  /// Toggle manual do produto. `false` = fora do cardápio, sempre.
  final bool isAvailable;

  final String? menuId;

  /// Dias em que o produto é vendido (0 = domingo). Vazio = todos os dias.
  final List<int> availableWeekdays;

  final int order;
  final List<MenuOptionGroup> optionGroups;

  factory MenuProduct.fromJson(Map<String, dynamic> json) {
    final category = json['category'];
    final rawWeekdays = json['availableWeekdays'];
    final rawGroups = json['optionGroups'];
    return MenuProduct(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      price: (json['price'] is num) ? (json['price'] as num).toDouble() : 0,
      categoryId: json['categoryId']?.toString(),
      categoryName: (category is Map) ? category['name']?.toString() : null,
      imageUrl: json['imageUrl']?.toString(),
      isAvailable: json['isAvailable'] != false,
      menuId: json['menuId']?.toString(),
      availableWeekdays: (rawWeekdays is List)
          ? rawWeekdays
              .whereType<num>()
              .map((d) => d.toInt())
              .where((d) => d >= 0 && d <= 6)
              .toList()
          : const [],
      order: (json['order'] is num) ? (json['order'] as num).toInt() : 0,
      optionGroups: (rawGroups is List)
          ? rawGroups
              .whereType<Map>()
              .map((g) => MenuOptionGroup.fromJson(g.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }
}

/// Formata um valor numérico como preço em reais: `28.9` → `R$ 28,90`.
String formatBrl(double value) {
  final s = value.toStringAsFixed(2).replaceAll('.', ',');
  return 'R\$ $s';
}
