import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Envia bytes crus (ESC/POS) para uma impressora instalada no Windows via a
/// API de spool `winspool.drv`, usando o datatype `RAW` — o driver não tenta
/// renderizar nada, só repassa os bytes. É o caminho para impressoras USB (ou
/// qualquer uma que apareça na lista do Windows) sem plugin nativo.
///
/// Só existe no Windows: `dart:ffi` liga direto na DLL do sistema.
class WindowsRawPrinter {
  WindowsRawPrinter._();

  static final DynamicLibrary _winspool = DynamicLibrary.open('winspool.drv');

  static final _openPrinter = _winspool.lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>),
      int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>)>(
    'OpenPrinterW',
  );

  static final _closePrinter =
      _winspool.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
    'ClosePrinter',
  );

  static final _startDocPrinter = _winspool.lookupFunction<
      Uint32 Function(IntPtr, Uint32, Pointer<Uint8>),
      int Function(int, int, Pointer<Uint8>)>('StartDocPrinterW');

  static final _endDocPrinter =
      _winspool.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
    'EndDocPrinter',
  );

  static final _startPagePrinter =
      _winspool.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
    'StartPagePrinter',
  );

  static final _endPagePrinter =
      _winspool.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
    'EndPagePrinter',
  );

  static final _writePrinter = _winspool.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>),
      int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)>('WritePrinter');

  static final _enumPrinters = _winspool.lookupFunction<
      Int32 Function(Uint32, Pointer<Utf16>, Uint32, Pointer<Uint8>, Uint32,
          Pointer<Uint32>, Pointer<Uint32>),
      int Function(int, Pointer<Utf16>, int, Pointer<Uint8>, int,
          Pointer<Uint32>, Pointer<Uint32>)>('EnumPrintersW');

  // PRINTER_ENUM_LOCAL (0x2) | PRINTER_ENUM_CONNECTIONS (0x4): impressoras
  // instaladas na máquina + as conectadas por rede/compartilhamento.
  static const int _enumFlags = 0x2 | 0x4;

  /// Nomes das impressoras instaladas no Windows (o que o operador escolhe).
  static List<String> listPrinters() {
    const level = 4; // PRINTER_INFO_4W: só nome, rápido, não abre cada driver.
    final needed = calloc<Uint32>();
    final returned = calloc<Uint32>();
    try {
      // 1ª chamada com buffer zero: descobre quantos bytes o Windows precisa.
      _enumPrinters(
          _enumFlags, nullptr, level, nullptr, 0, needed, returned);
      final size = needed.value;
      if (size == 0) return const [];

      final buffer = calloc<Uint8>(size);
      try {
        final ok = _enumPrinters(
            _enumFlags, nullptr, level, buffer, size, needed, returned);
        if (ok == 0) return const [];

        final count = returned.value;
        final names = <String>[];
        // PRINTER_INFO_4W = { LPWSTR pPrinterName; LPWSTR pServerName;
        // DWORD Attributes; } → 24 bytes com padding em x64. O nome é o 1º ponteiro.
        const stride = 24;
        for (var i = 0; i < count; i++) {
          final namePtr =
              (buffer + i * stride).cast<Pointer<Utf16>>().value;
          if (namePtr != nullptr) {
            names.add(namePtr.toDartString());
          }
        }
        return names;
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(needed);
      calloc.free(returned);
    }
  }

  /// Manda [bytes] para a impressora [printerName]. Lança [Exception] com
  /// mensagem pronta para a UI se qualquer etapa do spool falhar.
  static void printRaw(String printerName, Uint8List bytes) {
    final name = printerName.toNativeUtf16();
    final handlePtr = calloc<IntPtr>();
    try {
      if (_openPrinter(name, handlePtr, nullptr) == 0) {
        throw Exception('Impressora "$printerName" não encontrada no Windows.');
      }
      final handle = handlePtr.value;
      try {
        // DOC_INFO_1W = { LPWSTR pDocName; LPWSTR pOutputFile; LPWSTR pDatatype; }
        final docName = 'RapidHub'.toNativeUtf16();
        final datatype = 'RAW'.toNativeUtf16();
        final docInfo = calloc<Uint8>(3 * sizeOf<Pointer>());
        try {
          docInfo.cast<Pointer<Utf16>>().value = docName;
          (docInfo + sizeOf<Pointer>()).cast<Pointer<Utf16>>().value = nullptr;
          (docInfo + 2 * sizeOf<Pointer>()).cast<Pointer<Utf16>>().value =
              datatype;

          if (_startDocPrinter(handle, 1, docInfo) == 0) {
            throw Exception('Falha ao iniciar a impressão (StartDocPrinter).');
          }
          try {
            if (_startPagePrinter(handle) == 0) {
              throw Exception('Falha ao iniciar a página (StartPagePrinter).');
            }
            final buf = calloc<Uint8>(bytes.length);
            final written = calloc<Uint32>();
            try {
              buf.asTypedList(bytes.length).setAll(0, bytes);
              if (_writePrinter(handle, buf, bytes.length, written) == 0) {
                throw Exception('Falha ao enviar dados (WritePrinter).');
              }
              // O spooler pode aceitar a chamada mas gravar menos bytes (fila
              // cheia, driver que não é RAW). Sem isso o app diria "enviado"
              // com nada saindo no papel.
              if (written.value != bytes.length) {
                throw Exception(
                    'Spooler gravou ${written.value}/${bytes.length} bytes. '
                    'A impressora pode não aceitar dados RAW (ESC/POS) — veja '
                    'o driver.');
              }
            } finally {
              calloc.free(buf);
              calloc.free(written);
              _endPagePrinter(handle);
            }
          } finally {
            _endDocPrinter(handle);
          }
        } finally {
          calloc.free(docName);
          calloc.free(datatype);
          calloc.free(docInfo);
        }
      } finally {
        _closePrinter(handle);
      }
    } finally {
      calloc.free(name);
      calloc.free(handlePtr);
    }
  }
}
