import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Lançado quando o módulo de Cardápio (menu) não está habilitado para a
/// organização — as rotas `/api/menu/*` respondem 403 `MODULE_DISABLED`.
class MenuModuleDisabled implements Exception {
  const MenuModuleDisabled();
}

/// Cliente das rotas do Cardápio (`/api/menu/categories` e `/api/menu/products`).
///
/// Autentica por Bearer token (mesma sessão dos demais ecrãs). A organização
/// ativa vem da sessão no servidor, como no resto do app.
class MenuApi {
  MenuApi({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: 'session_token');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/menu/categories → categorias do cardápio.
  Future<List<MenuCategory>> fetchCategories() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/menu/categories'),
      headers: await _headers(),
    );
    if (resp.statusCode == 403) throw const MenuModuleDisabled();
    if (resp.statusCode != 200) {
      throw Exception('Falha ao carregar categorias (${resp.statusCode})');
    }
    final body = jsonDecode(resp.body);
    final list = (body is Map) ? body['categories'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((c) => MenuCategory.fromJson(c.cast<String, dynamic>()))
        .toList();
  }

  /// GET /api/menu/products → produtos (opcionalmente por categoria).
  Future<List<MenuProduct>> fetchProducts({String? categoryId}) async {
    final uri = Uri.parse('$baseUrl/api/menu/products').replace(
      queryParameters: categoryId == null ? null : {'categoryId': categoryId},
    );
    final resp = await http.get(uri, headers: await _headers());
    if (resp.statusCode == 403) throw const MenuModuleDisabled();
    if (resp.statusCode != 200) {
      throw Exception('Falha ao carregar produtos (${resp.statusCode})');
    }
    final body = jsonDecode(resp.body);
    final list = (body is Map) ? body['products'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((p) => MenuProduct.fromJson(p.cast<String, dynamic>()))
        .toList();
  }
}

class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.name,
    required this.productCount,
  });

  final String id;
  final String name;
  final int productCount;

  factory MenuCategory.fromJson(Map<String, dynamic> json) {
    final count = json['_count'];
    return MenuCategory(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      productCount:
          (count is Map && count['products'] is num) ? count['products'] : 0,
    );
  }
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
  });

  final String id;
  final String name;
  final String description;
  final double price;
  final String? categoryId;
  final String? categoryName;
  final String? imageUrl;
  final bool isAvailable;

  factory MenuProduct.fromJson(Map<String, dynamic> json) {
    final category = json['category'];
    return MenuProduct(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      price: (json['price'] is num) ? (json['price'] as num).toDouble() : 0,
      categoryId: json['categoryId']?.toString(),
      categoryName:
          (category is Map) ? category['name']?.toString() : null,
      imageUrl: json['imageUrl']?.toString(),
      isAvailable: json['isAvailable'] != false,
    );
  }
}

/// Formata um valor numérico como preço em reais: `28.9` → `R$ 28,90`.
String formatBrl(double value) {
  final s = value.toStringAsFixed(2).replaceAll('.', ',');
  return 'R\$ $s';
}
