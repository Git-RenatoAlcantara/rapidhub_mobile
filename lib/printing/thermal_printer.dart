import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../orders/orders_api.dart';
import 'escpos.dart';
import 'printer_settings.dart';
import 'windows_raw_printer.dart';

/// Falha ao falar com a impressora — mensagem já pronta para a UI.
class PrinterException implements Exception {
  const PrinterException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Envia cupons ESC/POS para a impressora térmica, por rede (TCP RAW 9100) ou
/// por USB (spool RAW do Windows).
///
/// O caminho de rede usa só `dart:io` (roda em qualquer plataforma). O caminho
/// USB liga na API de spool do Windows via `dart:ffi` — só existe no desktop
/// Windows.
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
    final n = copies < 1 ? 1 : copies;
    switch (settings.connection) {
      case PrinterConnection.network:
        await _sendNetwork(bytes, n);
      case PrinterConnection.usb:
        await _sendUsb(bytes, n);
    }
  }

  Future<void> _sendUsb(Uint8List bytes, int copies) async {
    if (!Platform.isWindows) {
      throw const PrinterException(
          'Impressão USB só está disponível no app desktop do Windows.');
    }
    try {
      for (var i = 0; i < copies; i++) {
        WindowsRawPrinter.printRaw(settings.usbPrinterName.trim(), bytes);
      }
    } on Exception catch (e) {
      throw PrinterException(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _sendNetwork(Uint8List bytes, int copies) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        settings.host.trim(),
        settings.port,
        timeout: _timeout,
      );
      for (var i = 0; i < copies; i++) {
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
