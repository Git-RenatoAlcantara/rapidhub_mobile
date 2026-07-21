import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Lançado quando o módulo de Campanhas não está habilitado para a organização
/// — as rotas `/api/campaigns` e `/api/coupons` respondem 403 `MODULE_DISABLED`.
class CampaignsModuleDisabled implements Exception {
  const CampaignsModuleDisabled();
}

/// 403 `FORBIDDEN`: o módulo existe, mas o papel deste usuário não pode agir.
class CampaignsForbidden implements Exception {
  const CampaignsForbidden(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Cliente das rotas de Campanhas e Cupons (`/api/campaigns/*`, `/api/coupons/*`).
///
/// Autentica por Bearer token (mesma sessão dos demais ecrãs). A organização
/// ativa vem da sessão no servidor, como no resto do app.
class CampaignsApi {
  CampaignsApi({FlutterSecureStorage? storage, http.Client? client})
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
  /// Um 403 pode ser módulo desligado (`MODULE_DISABLED`) ou falta de permissão
  /// do papel (`FORBIDDEN`) — mesma distinção que a `MenuApi` faz.
  dynamic _decode(http.Response resp, String action) {
    dynamic body;
    try {
      body = jsonDecode(resp.body);
    } catch (_) {
      body = null;
    }

    if (resp.statusCode == 403) {
      final code = (body is Map) ? body['code'] : null;
      if (code == 'MODULE_DISABLED') throw const CampaignsModuleDisabled();
      throw CampaignsForbidden(
          _errorMessage(body) ?? 'Você não tem permissão para $action.');
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

  // ── Campanhas ────────────────────────────────────────────────────────────

  /// GET /api/campaigns → campanhas da org (mais recentes primeiro).
  Future<List<Campaign>> fetchCampaigns() async {
    final resp = await _client.get(
      Uri.parse('$baseUrl/api/campaigns'),
      headers: await _headers(),
    );
    final body = _decode(resp, 'carregar as campanhas');
    final list = (body is Map) ? body['campaigns'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((c) => Campaign.fromJson(c.cast<String, dynamic>()))
        .toList();
  }

  /// POST /api/campaigns → cria a campanha em rascunho.
  Future<Campaign> createCampaign({
    required String name,
    required String connectionId,
    required String segmentType,
    required Map<String, dynamic> segmentConfig,
    required String messageText,
    String? couponId,
    int throttleSeconds = 8,
  }) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/campaigns'),
      headers: await _headers(),
      body: jsonEncode({
        'name': name,
        'connectionId': connectionId,
        'segmentType': segmentType,
        'segmentConfig': segmentConfig,
        'messageText': messageText,
        'couponId': couponId,
        'throttleSeconds': throttleSeconds,
      }),
    );
    final body = _decode(resp, 'criar a campanha');
    final campaign = (body is Map) ? body['campaign'] : null;
    return Campaign.fromJson((campaign as Map).cast<String, dynamic>());
  }

  /// PATCH /api/campaigns/[id] — o servidor só aceita campanha em rascunho.
  Future<void> updateCampaign(
    String id, {
    String? name,
    String? connectionId,
    String? segmentType,
    Map<String, dynamic>? segmentConfig,
    String? messageText,
    String? couponId,
    bool clearCoupon = false,
    int? throttleSeconds,
  }) async {
    final resp = await _client.patch(
      Uri.parse('$baseUrl/api/campaigns/$id'),
      headers: await _headers(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (connectionId != null) 'connectionId': connectionId,
        if (segmentType != null) 'segmentType': segmentType,
        if (segmentConfig != null) 'segmentConfig': segmentConfig,
        if (messageText != null) 'messageText': messageText,
        // Sem o flag, `couponId: null` sairia omitido e o cupom antigo ficaria.
        if (couponId != null || clearCoupon) 'couponId': couponId,
        if (throttleSeconds != null) 'throttleSeconds': throttleSeconds,
      }),
    );
    _decode(resp, 'atualizar a campanha');
  }

  Future<void> deleteCampaign(String id) async {
    final resp = await _client.delete(
      Uri.parse('$baseUrl/api/campaigns/$id'),
      headers: await _headers(),
    );
    _decode(resp, 'excluir a campanha');
  }

  /// POST /api/campaigns/[id]/send → enfileira o disparo. Devolve o total.
  Future<int> sendCampaign(String id) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/campaigns/$id/send'),
      headers: await _headers(),
    );
    final body = _decode(resp, 'disparar a campanha');
    final total = (body is Map) ? body['total'] : null;
    return (total is num) ? total.toInt() : 0;
  }

  /// POST /api/campaigns/[id]/duplicate → rascunho novo com a mesma config.
  ///
  /// É assim que o webapp faz "reenviar": os contadores da original ficam
  /// intactos e o operador ainda precisa clicar em Disparar.
  Future<void> duplicateCampaign(String id) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/campaigns/$id/duplicate'),
      headers: await _headers(),
    );
    _decode(resp, 'duplicar a campanha');
  }

  /// GET /api/campaigns/preview → quantos contatos o segmento pega, sem enviar.
  Future<int> previewCount({
    required String segmentType,
    int? inactiveDays,
    String? dateFrom,
    String? dateTo,
    String? phone,
  }) async {
    final uri = Uri.parse('$baseUrl/api/campaigns/preview').replace(
      queryParameters: {
        'segmentType': segmentType,
        if (inactiveDays != null) 'inactiveDays': '$inactiveDays',
        if (dateFrom != null && dateFrom.isNotEmpty) 'dateFrom': dateFrom,
        if (dateTo != null && dateTo.isNotEmpty) 'dateTo': dateTo,
        if (phone != null && phone.isNotEmpty) 'phones': phone,
      },
    );
    final resp = await _client.get(uri, headers: await _headers());
    final body = _decode(resp, 'contar os destinatários');
    final count = (body is Map) ? body['count'] : null;
    return (count is num) ? count.toInt() : 0;
  }

  // ── Cupons ───────────────────────────────────────────────────────────────

  /// GET /api/coupons → cupons da org.
  Future<List<Coupon>> fetchCoupons() async {
    final resp = await _client.get(
      Uri.parse('$baseUrl/api/coupons'),
      headers: await _headers(),
    );
    final body = _decode(resp, 'carregar os cupons');
    final list = (body is Map) ? body['coupons'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((c) => Coupon.fromJson(c.cast<String, dynamic>()))
        .toList();
  }

  Future<Coupon> createCoupon({
    required String code,
    required String discountType,
    required double discountValue,
    double? minOrder,
    int? maxUses,
    int? perContactLimit,
    String? validUntil,
    bool isActive = true,
    bool isPersonalized = false,
  }) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/coupons'),
      headers: await _headers(),
      body: jsonEncode({
        'code': code,
        'discountType': discountType,
        'discountValue': discountValue,
        'minOrder': minOrder,
        'maxUses': maxUses,
        'perContactLimit': perContactLimit,
        'validUntil': validUntil,
        'isActive': isActive,
        'isPersonalized': isPersonalized,
      }),
    );
    final body = _decode(resp, 'criar o cupom');
    final coupon = (body is Map) ? body['coupon'] : null;
    return Coupon.fromJson((coupon as Map).cast<String, dynamic>());
  }

  /// PATCH /api/coupons/[id]. O código e o `isPersonalized` não são editáveis
  /// no servidor — códigos já entregues ao cliente não podem mudar de sentido.
  Future<void> updateCoupon(
    String id, {
    String? discountType,
    double? discountValue,
    double? minOrder,
    int? maxUses,
    int? perContactLimit,
    String? validUntil,
    bool clearValidUntil = false,
    bool? isActive,
  }) async {
    final resp = await _client.patch(
      Uri.parse('$baseUrl/api/coupons/$id'),
      headers: await _headers(),
      body: jsonEncode({
        if (discountType != null) 'discountType': discountType,
        if (discountValue != null) 'discountValue': discountValue,
        'minOrder': minOrder,
        'maxUses': maxUses,
        if (perContactLimit != null) 'perContactLimit': perContactLimit,
        if (validUntil != null || clearValidUntil) 'validUntil': validUntil,
        if (isActive != null) 'isActive': isActive,
      }),
    );
    _decode(resp, 'atualizar o cupom');
  }

  Future<void> deleteCoupon(String id) async {
    final resp = await _client.delete(
      Uri.parse('$baseUrl/api/coupons/$id'),
      headers: await _headers(),
    );
    _decode(resp, 'excluir o cupom');
  }

  // ── Conexões ─────────────────────────────────────────────────────────────

  /// GET /api/connections → conexões da org, já filtradas para as que podem
  /// disparar. Ver [sendableConnections].
  Future<List<CampaignConnection>> fetchConnections() async {
    final resp = await _client.get(
      Uri.parse('$baseUrl/api/connections'),
      headers: await _headers(),
    );
    final body = _decode(resp, 'carregar as conexões');
    final list = (body is Map) ? body['connections'] : null;
    if (list is! List) return const [];
    final all = list
        .whereType<Map>()
        .map((c) => CampaignConnection.fromJson(c.cast<String, dynamic>()))
        .toList();
    return sendableConnections(all);
  }
}

/// Só conexão conectada pode disparar campanha. A org acumula conexões `failed`,
/// `qr_code` e sobras de pareamento (`pending-<timestamp>`), e escolher uma
/// conexão morta faria a campanha sair sem erro visível.
List<CampaignConnection> sendableConnections(List<CampaignConnection> all) {
  return all
      .where((c) => c.status == 'connected' && !c.name.startsWith('pending-'))
      .toList();
}

// ══════════════════════════════════════════════════════════════════════════
// Modelos
// ══════════════════════════════════════════════════════════════════════════

/// Segmento de clientes que a campanha atinge.
class CampaignSegment {
  const CampaignSegment(this.value, this.label);
  final String value;
  final String label;
}

const List<CampaignSegment> kCampaignSegments = [
  CampaignSegment('all', 'Todos os clientes'),
  CampaignSegment('inactive', 'Inativos há X dias'),
  CampaignSegment('purchase_period', 'Compraram num período'),
  CampaignSegment('favorite', 'Com produto favorito'),
  CampaignSegment('specific', 'Número específico'),
];

String campaignSegmentLabel(String value) {
  for (final s in kCampaignSegments) {
    if (s.value == value) return s.label;
  }
  return value;
}

const Map<String, String> kCampaignStatusLabels = {
  'draft': 'Rascunho',
  'scheduled': 'Agendada',
  'sending': 'Enviando',
  'sent': 'Concluída',
  'canceled': 'Cancelada',
};

String campaignStatusLabel(String status) =>
    kCampaignStatusLabels[status] ?? status;

class Campaign {
  const Campaign({
    required this.id,
    required this.name,
    required this.segmentType,
    required this.status,
    required this.totalRecipients,
    required this.sentCount,
    required this.failedCount,
    required this.optOutSkipped,
    required this.connectionId,
    required this.messageText,
    required this.throttleSeconds,
    this.couponId,
    this.segmentConfig = const {},
  });

  final String id;
  final String name;
  final String segmentType;
  final String status;
  final int totalRecipients;
  final int sentCount;
  final int failedCount;
  final int optOutSkipped;
  final String connectionId;
  final String messageText;
  final int throttleSeconds;
  final String? couponId;
  final Map<String, dynamic> segmentConfig;

  /// Só rascunho pode ser editado ou disparado sem duplicar antes.
  bool get isDraft => status == 'draft';

  factory Campaign.fromJson(Map<String, dynamic> json) {
    final config = json['segmentConfig'];
    int intOf(Object? raw) => (raw is num) ? raw.toInt() : 0;
    return Campaign(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      segmentType: (json['segmentType'] ?? 'all').toString(),
      status: (json['status'] ?? 'draft').toString(),
      totalRecipients: intOf(json['totalRecipients']),
      sentCount: intOf(json['sentCount']),
      failedCount: intOf(json['failedCount']),
      optOutSkipped: intOf(json['optOutSkipped']),
      connectionId: (json['connectionId'] ?? '').toString(),
      messageText: (json['messageText'] ?? '').toString(),
      throttleSeconds:
          (json['throttleSeconds'] is num) ? intOf(json['throttleSeconds']) : 8,
      couponId: json['couponId']?.toString(),
      segmentConfig:
          (config is Map) ? config.cast<String, dynamic>() : const {},
    );
  }
}

class Coupon {
  const Coupon({
    required this.id,
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.isActive,
    required this.isPersonalized,
    required this.usedCount,
    this.maxUses,
    this.minOrder,
    this.perContactLimit,
    this.validUntil,
  });

  final String id;
  final String code;

  /// `percent` ou `fixed`.
  final String discountType;
  final double discountValue;
  final bool isActive;

  /// Código exclusivo por cliente: cada contato recebe um código derivado
  /// (`VOLTA10-A3F9`) que só vale para ele.
  final bool isPersonalized;

  final int usedCount;
  final int? maxUses;
  final double? minOrder;
  final int? perContactLimit;

  /// ISO completo, como vem do servidor. `null` = sem validade.
  final String? validUntil;

  /// `VOLTA10 · 10%` / `VOLTA10 · R$ 5`.
  String get label => '$code · $discountLabel';

  String get discountLabel => discountType == 'percent'
      ? '${_trim(discountValue)}%'
      : 'R\$ ${_trim(discountValue)}';

  static String _trim(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(2).replaceAll('.', ',');

  /// Prisma serializa Decimal como string; `num` cobre o caso de vir número.
  static double? _decimal(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  factory Coupon.fromJson(Map<String, dynamic> json) => Coupon(
        id: (json['id'] ?? '').toString(),
        code: (json['code'] ?? '').toString(),
        discountType: (json['discountType'] ?? 'percent').toString(),
        discountValue: _decimal(json['discountValue']) ?? 0,
        isActive: json['isActive'] != false,
        isPersonalized: json['isPersonalized'] == true,
        usedCount:
            (json['usedCount'] is num) ? (json['usedCount'] as num).toInt() : 0,
        maxUses:
            (json['maxUses'] is num) ? (json['maxUses'] as num).toInt() : null,
        minOrder: _decimal(json['minOrder']),
        perContactLimit: (json['perContactLimit'] is num)
            ? (json['perContactLimit'] as num).toInt()
            : null,
        validUntil: json['validUntil']?.toString(),
      );
}

class CampaignConnection {
  const CampaignConnection({
    required this.id,
    required this.name,
    required this.status,
    this.phone,
  });

  final String id;
  final String name;
  final String status;
  final String? phone;

  /// O número entra no rótulo porque disparar pela conexão errada é silencioso.
  String get label => (phone != null && phone!.isNotEmpty)
      ? '$name · $phone'
      : name;

  factory CampaignConnection.fromJson(Map<String, dynamic> json) =>
      CampaignConnection(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        status: (json['status'] ?? '').toString(),
        phone: json['phone']?.toString(),
      );
}
