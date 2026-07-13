import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../orders/orders_api.dart';
import 'escpos.dart';
import 'printer_settings.dart';

/// Falha ao falar com a impressora — mensagem já pronta para a UI.
class PrinterException implements Exception {
  const PrinterException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Envia cupons ESC/POS para uma impressora térmica de rede (porta RAW 9100).
///
/// Usa apenas `dart:io`, então roda no Windows, macOS, Linux, Android e iOS
/// sem plugin nativo.
class ThermalPrinter {
  const ThermalPrinter(this.settings);

  final PrinterSettings settings;

  static const Duration _timeout = Duration(seconds: 6);

  Future<void> printOrder(Order order) async {
    final bytes = buildOrderReceipt(
      order,
      storeName: settings.storeName,
      columns: settings.columns,
    );
    await _send(bytes, copies: settings.copies);
  }

  Future<void> printTest() async {
    final bytes = buildTestReceipt(
      storeName: settings.storeName,
      columns: settings.columns,
    );
    await _send(bytes);
  }

  Future<void> _send(Uint8List bytes, {int copies = 1}) async {
    if (!settings.isConfigured) {
      throw const PrinterException('Impressora não configurada.');
    }
    Socket? socket;
    try {
      socket = await Socket.connect(
        settings.host.trim(),
        settings.port,
        timeout: _timeout,
      );
      for (var i = 0; i < (copies < 1 ? 1 : copies); i++) {
        socket.add(bytes);
      }
      await socket.flush().timeout(_timeout);
    } on SocketException catch (e) {
      throw PrinterException(
        'Não foi possível conectar em ${settings.host}:${settings.port}. '
        '${e.osError?.message ?? 'Verifique a rede e o IP da impressora.'}',
      );
    } on TimeoutException {
      throw const PrinterException('A impressora não respondeu a tempo.');
    } finally {
      // `destroy` em vez de `close`: a impressora não fecha o lado dela e o
      // `close` ficaria pendurado esperando o FIN.
      socket?.destroy();
    }
  }
}
