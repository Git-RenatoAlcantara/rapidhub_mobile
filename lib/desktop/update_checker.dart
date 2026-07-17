import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';

/// Dados da versão nova publicada, quando há uma mais recente que a instalada.
class UpdateInfo {
  const UpdateInfo({required this.version, required this.downloadUrl});

  /// Versão disponível no servidor (ex.: `1.0.3`).
  final String version;

  /// URL que baixa o instalador da plataforma atual.
  final String downloadUrl;
}

/// Consulta o backend (`/api/app/status`) e diz se saiu versão nova do app para
/// esta plataforma. Nunca lança: qualquer falha (offline, JSON estranho) vira
/// `null` — aviso de atualização não pode travar o boot.
class UpdateChecker {
  const UpdateChecker();

  /// Plataforma que o backend conhece, ou `null` onde não há instalador
  /// gerenciado (web, iOS, macOS, Linux).
  static String? get _platform {
    if (kIsWeb) return null;
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    return null;
  }

  Future<UpdateInfo?> check() async {
    final platform = _platform;
    if (platform == null) return null;

    try {
      final info = await PackageInfo.fromPlatform();
      final res = await http
          .get(Uri.parse('$baseUrl/api/app/status'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body);
      if (body is! Map) return null;
      final entry = body[platform];
      if (entry is! Map || entry['available'] != true) return null;

      final remote = entry['version']?.toString();
      if (remote == null || remote.isEmpty) return null;

      if (_compare(remote, info.version) <= 0) return null; // já atualizado.
      return UpdateInfo(
        version: remote,
        downloadUrl: '$baseUrl/api/app/download?platform=$platform',
      );
    } catch (_) {
      return null;
    }
  }

  /// Compara duas versões `x.y.z` numericamente. `>0` se [a] é mais nova que
  /// [b]. Ignora sufixo de build (`1.0.2+3`) e um `v` inicial.
  static int _compare(String a, String b) {
    final pa = _parts(a);
    final pb = _parts(b);
    for (var i = 0; i < pa.length && i < pb.length; i++) {
      if (pa[i] != pb[i]) return pa[i] - pb[i];
    }
    return pa.length - pb.length;
  }

  static List<int> _parts(String v) {
    final core = v.replaceFirst(RegExp(r'^v'), '').split('+').first;
    return core
        .split('.')
        .map((p) => int.tryParse(p.trim()) ?? 0)
        .toList(growable: false);
  }
}
