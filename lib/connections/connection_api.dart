import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Erro amigável vindo das rotas de conexão `rapidhub-wpp`. Carrega a mensagem
/// já pronta para exibir na UI.
class ConnectionApiError implements Exception {
  const ConnectionApiError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Resultado do `POST /init`: a Connection foi criada e a instância iniciada no
/// servidor WWebJS. `qrCode` é ignorado neste fluxo (só usamos código).
class InitResult {
  const InitResult({required this.connectionId, required this.status});
  final String connectionId;
  final String status;
}

/// Snapshot do polling de status. `connected` encerra o polling.
class ConnectionStatus {
  const ConnectionStatus({
    required this.connected,
    required this.status,
    this.instanceMissing = false,
    this.lastError,
  });

  final bool connected;
  final String status;
  final bool instanceMissing;
  final String? lastError;
}

/// Cliente das rotas de conexão não oficial (`/api/connections/rapidhub-wpp/*`).
///
/// Fluxo de código de verificação (sem QR):
///   1. [init] cria a Connection e inicia a sessão → `connectionId`.
///   2. [requestPairingCode] gera o código que o usuário digita no WhatsApp.
///   3. [fetchStatus] em polling até `connected: true`.
///
/// Autentica por Bearer token (mesma sessão do resto do app).
class ConnectionApi {
  ConnectionApi({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: 'session_token');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Extrai a mensagem de erro do corpo JSON, com um fallback.
  String _errorMessage(http.Response resp, String fallback) {
    try {
      final body = jsonDecode(resp.body);
      if (body is Map && body['error'] is String) {
        return body['error'] as String;
      }
    } catch (_) {}
    return fallback;
  }

  /// POST /api/connections/rapidhub-wpp/init → cria a conexão e inicia a sessão.
  Future<InitResult> init({String? name}) async {
    final http.Response resp;
    try {
      resp = await http.post(
        Uri.parse('$baseUrl/api/connections/rapidhub-wpp/init'),
        headers: await _headers(),
        body: jsonEncode({
          if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        }),
      );
    } catch (e) {
      debugPrint('connection init error: $e');
      throw const ConnectionApiError('Erro de conexão. Verifica a tua internet.');
    }

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw ConnectionApiError(
        _errorMessage(resp, 'Falha ao iniciar a conexão (${resp.statusCode}).'),
      );
    }

    final body = jsonDecode(resp.body);
    final connectionId = (body is Map) ? body['connectionId'] : null;
    if (connectionId is! String || connectionId.isEmpty) {
      throw const ConnectionApiError('Resposta inválida do servidor ao iniciar.');
    }
    return InitResult(
      connectionId: connectionId,
      status: (body is Map ? body['status'] : null)?.toString() ?? '',
    );
  }

  /// POST /api/connections/rapidhub-wpp/{id}/pairing-code → gera o código.
  ///
  /// [phoneNumber] deve conter apenas dígitos, com DDI (ex.: "5511999999999").
  Future<String> requestPairingCode(
    String connectionId,
    String phoneNumber,
  ) async {
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    final http.Response resp;
    try {
      resp = await http.post(
        Uri.parse(
          '$baseUrl/api/connections/rapidhub-wpp/'
          '${Uri.encodeComponent(connectionId)}/pairing-code',
        ),
        headers: await _headers(),
        body: jsonEncode({'phoneNumber': digits}),
      );
    } catch (e) {
      debugPrint('pairing-code error: $e');
      throw const ConnectionApiError('Erro de conexão. Verifica a tua internet.');
    }

    final body = jsonDecode(resp.body);
    final code = (body is Map) ? body['code'] : null;
    if (resp.statusCode != 200 || code == null) {
      throw ConnectionApiError(
        _errorMessage(resp, 'Falha ao gerar o código de verificação.'),
      );
    }
    return code.toString();
  }

  /// GET /api/connections/rapidhub-wpp/{id}/status → status atual da sessão.
  Future<ConnectionStatus> fetchStatus(String connectionId) async {
    final resp = await http.get(
      Uri.parse(
        '$baseUrl/api/connections/rapidhub-wpp/'
        '${Uri.encodeComponent(connectionId)}/status',
      ),
      headers: await _headers(),
    );

    final body = jsonDecode(resp.body);
    final map = (body is Map) ? body : const {};

    if (resp.statusCode == 404 || map['instanceMissing'] == true) {
      return ConnectionStatus(
        connected: false,
        status: (map['status'] ?? 'missing').toString(),
        instanceMissing: true,
        lastError: map['lastError']?.toString(),
      );
    }

    return ConnectionStatus(
      connected: map['connected'] == true,
      status: (map['status'] ?? '').toString(),
      lastError: map['lastError']?.toString(),
    );
  }
}
