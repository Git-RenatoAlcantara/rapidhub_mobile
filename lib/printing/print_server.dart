import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../orders/orders_api.dart';
import 'printer_settings.dart';
import 'thermal_printer.dart';

/// Ponte local que deixa o site (navegador) imprimir na térmica através do
/// app desktop.
///
/// O navegador não abre socket TCP cru na porta 9100, então o webapp faz um
/// `fetch` para este servidor em `127.0.0.1` e o desktop repassa o cupom para
/// a impressora — reusando o mesmo [ThermalPrinter]/ESC/POS do app.
///
/// Escuta só no loopback (nunca na LAN) e libera CORS apenas para a origem do
/// webapp, para nenhuma outra aba conseguir mandar imprimir.
class PrintServer {
  PrintServer({
    PrinterSettingsStore? store,
    this.port = kPrintServerPort,
    Set<String>? allowedOrigins,
  })  : _store = store ?? PrinterSettingsStore(),
        allowedOrigins = allowedOrigins ?? _defaultOrigins;

  /// Origens de produção do webapp aceitas pelo CORS. Localhost/127.0.0.1 (dev)
  /// é liberado à parte em [_isAllowedOrigin], sem precisar listar cada porta.
  static const _defaultOrigins = {
    'https://rapidhub.com.br',
    'https://www.rapidhub.com.br',
  };

  final PrinterSettingsStore _store;
  final int port;
  final Set<String> allowedOrigins;

  HttpServer? _server;

  bool get isRunning => _server != null;

  /// Sobe o servidor. Só faz sentido no desktop — em mobile/web é no-op.
  Future<void> start() async {
    if (_server != null) return;
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: true,
      );
      _server = server;
      unawaited(_serve(server));
    } on SocketException {
      // Porta ocupada (outra instância já é a ponte) — segue sem servidor.
      _server = null;
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _serve(HttpServer server) async {
    await for (final req in server) {
      // Cada requisição é isolada: uma falha não derruba o servidor.
      unawaited(_handle(req).catchError((_) {}));
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    _cors(req, res);

    // Preflight do CORS (e do Private Network Access, quando o Chrome exige).
    if (req.method == 'OPTIONS') {
      res.statusCode = HttpStatus.noContent;
      await res.close();
      return;
    }

    try {
      if (req.method == 'GET' && req.uri.path == '/health') {
        final settings = await _store.load();
        await _json(res, HttpStatus.ok, {
          'ok': true,
          'configured': settings.isConfigured,
          'connection': settings.connection.name,
          'printer': settings.target,
        });
        return;
      }

      if (req.method == 'POST' && req.uri.path == '/print') {
        final order = await _readOrder(req);
        await ThermalPrinter(await _store.load()).printOrder(order);
        await _json(res, HttpStatus.ok, {'ok': true});
        return;
      }

      if (req.method == 'POST' && req.uri.path == '/print/test') {
        await ThermalPrinter(await _store.load()).printTest();
        await _json(res, HttpStatus.ok, {'ok': true});
        return;
      }

      await _json(res, HttpStatus.notFound, {'error': 'Rota inexistente.'});
    } on FormatException {
      await _json(res, HttpStatus.badRequest, {'error': 'JSON inválido.'});
    } on PrinterException catch (e) {
      // Impressora fora do ar / não configurada — 502 para o web distinguir de
      // erro de payload.
      await _json(res, HttpStatus.badGateway, {'error': e.message});
    } catch (e) {
      await _json(res, HttpStatus.internalServerError, {'error': '$e'});
    }
  }

  Future<Order> _readOrder(HttpRequest req) async {
    final body = await utf8.decodeStream(req);
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Esperado um objeto de pedido.');
    }
    // O webapp manda o mesmo formato de /api/orders, então reusamos o parse.
    return Order.fromJson(decoded.cast<String, dynamic>());
  }

  void _cors(HttpRequest req, HttpResponse res) {
    // Ecoa o Origin da requisição quando permitido, em vez de fixar um só —
    // assim produção (rapidhub.com.br) e dev (localhost/ngrok) funcionam sem
    // recompilar. A segurança vem de escutar só no loopback.
    final origin = req.headers.value('origin');
    final allow = (origin != null && _isAllowedOrigin(origin))
        ? origin
        : allowedOrigins.first;
    res.headers
      ..set('Access-Control-Allow-Origin', allow)
      ..set('Vary', 'Origin')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type')
      // Chrome manda um preflight extra ao chamar rede local a partir de um
      // site público; sem este header a chamada é bloqueada.
      ..set('Access-Control-Allow-Private-Network', 'true');
  }

  bool _isAllowedOrigin(String origin) {
    if (allowedOrigins.contains(origin)) return true;
    // Qualquer localhost/127.0.0.1 (qualquer porta/esquema) para dev local.
    final uri = Uri.tryParse(origin);
    final host = uri?.host;
    return host == 'localhost' || host == '127.0.0.1';
  }

  Future<void> _json(HttpResponse res, int status, Object body) async {
    res
      ..statusCode = status
      ..headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    await res.close();
  }
}

/// Porta do loopback usada pela ponte de impressão. Fixa para o webapp saber
/// onde chamar sem configuração.
const int kPrintServerPort = 9110;
