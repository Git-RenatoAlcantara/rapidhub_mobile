import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Como o app fala com a impressora térmica.
enum PrinterConnection {
  /// TCP RAW porta 9100 — impressora de rede (Ethernet/Wi-Fi).
  network('Rede (IP)'),

  /// Spool RAW do Windows — impressora USB (ou qualquer instalada no sistema).
  /// Só funciona no desktop Windows.
  usb('USB / Windows');

  const PrinterConnection(this.label);

  final String label;
}

/// Configuração da impressora térmica (ESC/POS), por rede ou USB.
class PrinterSettings {
  const PrinterSettings({
    this.connection = PrinterConnection.network,
    this.host = '',
    this.port = 9100,
    this.usbPrinterName = '',
    this.storeName = '',
    this.paperWidth = PaperWidth.mm80,
    this.copies = 1,
    this.autoPrint = true,
  });

  final PrinterConnection connection;

  /// Rede: IP e porta da impressora.
  final String host;
  final int port;

  /// USB: nome da impressora como aparece no Windows.
  final String usbPrinterName;

  final String storeName;
  final PaperWidth paperWidth;

  /// Vias impressas por pedido (ex.: 1 para o cliente, 1 para a cozinha).
  final int copies;

  /// Imprime automaticamente os pedidos novos vistos ao atualizar a lista.
  final bool autoPrint;

  bool get isConfigured => switch (connection) {
        PrinterConnection.network => host.trim().isNotEmpty && port > 0,
        PrinterConnection.usb => usbPrinterName.trim().isNotEmpty,
      };

  /// Rótulo curto do destino atual, para logs e a rota `/health` da ponte.
  String get target => switch (connection) {
        PrinterConnection.network => '$host:$port',
        PrinterConnection.usb => usbPrinterName,
      };

  int get columns => paperWidth.columns;

  PrinterSettings copyWith({
    PrinterConnection? connection,
    String? host,
    int? port,
    String? usbPrinterName,
    String? storeName,
    PaperWidth? paperWidth,
    int? copies,
    bool? autoPrint,
  }) {
    return PrinterSettings(
      connection: connection ?? this.connection,
      host: host ?? this.host,
      port: port ?? this.port,
      usbPrinterName: usbPrinterName ?? this.usbPrinterName,
      storeName: storeName ?? this.storeName,
      paperWidth: paperWidth ?? this.paperWidth,
      copies: copies ?? this.copies,
      autoPrint: autoPrint ?? this.autoPrint,
    );
  }
}

enum PaperWidth {
  mm80(48, '80mm'),
  mm58(32, '58mm');

  const PaperWidth(this.columns, this.label);

  final int columns;
  final String label;
}

/// Persiste a configuração da impressora localmente (não vai para o backend —
/// a impressora é do balcão, não da organização).
class PrinterSettingsStore {
  PrinterSettingsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kConnection = 'printer_connection';
  static const _kHost = 'printer_host';
  static const _kPort = 'printer_port';
  static const _kUsbName = 'printer_usb_name';
  static const _kStoreName = 'printer_store_name';
  static const _kPaper = 'printer_paper';
  static const _kCopies = 'printer_copies';
  static const _kAutoPrint = 'printer_auto_print';

  // Leituras/escritas são sequenciais de propósito: o flutter_secure_storage
  // não é reentrante no Android e operações concorrentes (Future.wait) se
  // atropelam — writes eram perdidos e o IP não persistia.
  Future<PrinterSettings> load() async {
    final connection = await _storage.read(key: _kConnection);
    final host = await _storage.read(key: _kHost);
    final port = await _storage.read(key: _kPort);
    final usbName = await _storage.read(key: _kUsbName);
    final storeName = await _storage.read(key: _kStoreName);
    final paper = await _storage.read(key: _kPaper);
    final copies = await _storage.read(key: _kCopies);
    final autoPrint = await _storage.read(key: _kAutoPrint);
    return PrinterSettings(
      connection: connection == PrinterConnection.usb.name
          ? PrinterConnection.usb
          : PrinterConnection.network,
      host: host ?? '',
      port: int.tryParse(port ?? '') ?? 9100,
      usbPrinterName: usbName ?? '',
      storeName: storeName ?? '',
      paperWidth:
          paper == PaperWidth.mm58.name ? PaperWidth.mm58 : PaperWidth.mm80,
      copies: int.tryParse(copies ?? '') ?? 1,
      // Liga por padrão: só um valor salvo explicitamente ('false') desliga.
      autoPrint: autoPrint == null ? true : autoPrint == 'true',
    );
  }

  Future<void> save(PrinterSettings s) async {
    await _storage.write(key: _kConnection, value: s.connection.name);
    await _storage.write(key: _kHost, value: s.host.trim());
    await _storage.write(key: _kPort, value: s.port.toString());
    await _storage.write(key: _kUsbName, value: s.usbPrinterName.trim());
    await _storage.write(key: _kStoreName, value: s.storeName.trim());
    await _storage.write(key: _kPaper, value: s.paperWidth.name);
    await _storage.write(key: _kCopies, value: s.copies.toString());
    await _storage.write(key: _kAutoPrint, value: s.autoPrint.toString());
  }
}
