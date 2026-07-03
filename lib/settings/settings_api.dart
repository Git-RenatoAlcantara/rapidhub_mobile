import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Cliente das rotas de Configurações da organização:
/// `/api/settings/daily-report` (relatório diário no WhatsApp) e
/// `/api/organization/settings` (lembretes de agendamento).
class SettingsApi {
  SettingsApi({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: 'session_token');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/settings/daily-report.
  Future<DailyReportSettings> fetchDailyReport() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/settings/daily-report'),
      headers: await _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('Falha ao carregar o relatório diário (${resp.statusCode})');
    }
    final body = jsonDecode(resp.body);
    return DailyReportSettings.fromResponse(
        (body is Map) ? body.cast<String, dynamic>() : const {});
  }

  /// PATCH /api/settings/daily-report.
  Future<void> saveDailyReport({
    required bool enabled,
    required int hour,
    required int minute,
    required bool aiInsights,
  }) async {
    final resp = await http.patch(
      Uri.parse('$baseUrl/api/settings/daily-report'),
      headers: await _headers(),
      body: jsonEncode({
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'aiInsights': aiInsights,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('Falha ao salvar o relatório diário (${resp.statusCode})');
    }
  }

  /// GET /api/organization/settings.
  Future<ReminderSettings> fetchReminder() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/organization/settings'),
      headers: await _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception('Falha ao carregar as configurações (${resp.statusCode})');
    }
    final body = jsonDecode(resp.body);
    return ReminderSettings.fromJson(
        (body is Map) ? body.cast<String, dynamic>() : const {});
  }

  /// PATCH /api/organization/settings.
  Future<void> saveReminder({
    required int minutesBefore,
    required String template,
  }) async {
    final resp = await http.patch(
      Uri.parse('$baseUrl/api/organization/settings'),
      headers: await _headers(),
      body: jsonEncode({
        'reminderMinutesBefore': minutesBefore,
        'reminderTemplate': template,
      }),
    );
    if (resp.statusCode != 200) {
      String message = 'Falha ao salvar as configurações (${resp.statusCode})';
      try {
        final body = jsonDecode(resp.body);
        if (body is Map && body['error'] is String) message = body['error'];
      } catch (_) {}
      throw Exception(message);
    }
  }
}

class DailyReportSettings {
  const DailyReportSettings({
    required this.enabled,
    required this.hour,
    required this.minute,
    required this.aiInsights,
    required this.whatsappReady,
  });

  final bool enabled;
  final int hour;
  final int minute;
  final bool aiInsights;
  final bool whatsappReady;

  factory DailyReportSettings.fromResponse(Map<String, dynamic> json) {
    final s = (json['settings'] is Map)
        ? (json['settings'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return DailyReportSettings(
      enabled: s['enabled'] == true,
      hour: (s['hour'] is num) ? (s['hour'] as num).toInt() : 20,
      minute: (s['minute'] is num) ? (s['minute'] as num).toInt() : 0,
      aiInsights: s['aiInsights'] == true,
      whatsappReady: json['whatsappReady'] == true,
    );
  }

  DailyReportSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    bool? aiInsights,
  }) =>
      DailyReportSettings(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        aiInsights: aiInsights ?? this.aiInsights,
        whatsappReady: whatsappReady,
      );

  String get signature => '$enabled|$hour|$minute|$aiInsights';
}

class ReminderSettings {
  const ReminderSettings({
    required this.minutesBefore,
    required this.template,
  });

  final int minutesBefore;
  final String template;

  factory ReminderSettings.fromJson(Map<String, dynamic> json) =>
      ReminderSettings(
        minutesBefore: (json['reminderMinutesBefore'] is num)
            ? (json['reminderMinutesBefore'] as num).toInt()
            : 120,
        template: (json['reminderTemplate'] ?? '').toString(),
      );

  String get signature => '$minutesBefore|$template';
}
