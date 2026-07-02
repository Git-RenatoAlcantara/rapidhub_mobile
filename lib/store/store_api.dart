import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Lançado quando o módulo de Cardápio (menu) não está habilitado para a
/// organização — a API `/api/store` responde 403 `MODULE_DISABLED`.
class StoreModuleDisabled implements Exception {
  const StoreModuleDisabled();
}

/// Cliente das rotas da Loja (`/api/store` e `/api/menu/kitchen-options`).
///
/// Autentica por Bearer token (mesma sessão dos demais ecrãs). A organização
/// ativa vem da sessão no servidor, como no resto do app.
class StoreApi {
  StoreApi({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: 'session_token');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/store → `store` (objeto com kitchenGroup/operatingHours/…).
  Future<Map<String, dynamic>> fetchStore() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/store'),
      headers: await _headers(),
    );
    if (resp.statusCode == 403) throw const StoreModuleDisabled();
    if (resp.statusCode != 200) {
      throw Exception('Falha ao carregar a loja (${resp.statusCode})');
    }
    final body = jsonDecode(resp.body);
    final store = (body is Map) ? body['store'] : null;
    return (store is Map) ? store.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// PUT /api/store com `{ store }`.
  Future<void> saveStore(Map<String, dynamic> store) async {
    final resp = await http.put(
      Uri.parse('$baseUrl/api/store'),
      headers: await _headers(),
      body: jsonEncode({'store': store}),
    );
    if (resp.statusCode == 403) throw const StoreModuleDisabled();
    if (resp.statusCode != 200) {
      throw Exception('Falha ao salvar a loja (${resp.statusCode})');
    }
  }

  /// GET /api/menu/kitchen-options → conexões compatíveis com grupos.
  Future<List<KitchenConnection>> fetchConnections() async {
    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/menu/kitchen-options'),
        headers: await _headers(),
      );
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(resp.body);
      final list = (body is Map) ? body['connections'] : null;
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((c) => KitchenConnection(
                id: (c['id'] ?? '').toString(),
                name: (c['name'] ?? '').toString(),
                status: (c['status'] ?? '').toString(),
              ))
          .where((c) => c.id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('kitchen-options connections error: $e');
      return const [];
    }
  }

  /// GET /api/menu/kitchen-options?connectionId=… → grupos da conexão.
  Future<List<KitchenGroupOption>> fetchGroups(String connectionId) async {
    try {
      final resp = await http.get(
        Uri.parse(
          '$baseUrl/api/menu/kitchen-options?connectionId=${Uri.encodeComponent(connectionId)}',
        ),
        headers: await _headers(),
      );
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(resp.body);
      final list = (body is Map) ? body['groups'] : null;
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((g) => KitchenGroupOption(
                id: (g['id'] ?? '').toString(),
                name: (g['name'] ?? '').toString(),
              ))
          .where((g) => g.id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('kitchen-options groups error: $e');
      return const [];
    }
  }
}

class KitchenConnection {
  const KitchenConnection({
    required this.id,
    required this.name,
    required this.status,
  });
  final String id;
  final String name;
  final String status;
  bool get connected => status == 'connected';
}

class KitchenGroupOption {
  const KitchenGroupOption({required this.id, required this.name});
  final String id;
  final String name;
}
