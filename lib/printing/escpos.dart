import 'dart:typed_data';

import '../menu/menu_api.dart' show formatBrl;
import '../orders/orders_api.dart';

/// Gerador de comandos ESC/POS (padrão Epson) para impressoras térmicas.
///
/// Trabalha em bytes crus: o mesmo buffer serve tanto para socket TCP (porta
/// 9100) quanto para qualquer outro transporte que aceite dados RAW.
class EscPos {
  EscPos({this.columns = 48});

  /// Colunas da fonte A: 48 em bobina de 80mm, 32 em 58mm.
  final int columns;

  final BytesBuilder _b = BytesBuilder();

  static const int _esc = 0x1B;
  static const int _gs = 0x1D;

  /// Reinicia a impressora e seleciona a code page PC850 (latim ocidental).
  EscPos init() {
    _b.add([_esc, 0x40]); // ESC @
    _b.add([_esc, 0x74, 0x02]); // ESC t 2 → PC850
    return this;
  }

  EscPos align(EscPosAlign a) {
    _b.add([_esc, 0x61, a.index]); // ESC a n
    return this;
  }

  EscPos bold(bool on) {
    _b.add([_esc, 0x45, on ? 1 : 0]); // ESC E n
    return this;
  }

  /// Multiplica o tamanho do caractere. `GS ! n`, onde o nibble alto é a
  /// largura e o baixo a altura (0 = 1x, 1 = 2x).
  EscPos size({bool doubleWidth = false, bool doubleHeight = false}) {
    final n = (doubleWidth ? 0x10 : 0) | (doubleHeight ? 0x01 : 0);
    _b.add([_gs, 0x21, n]); // GS ! n
    return this;
  }

  EscPos text(String value) {
    _b.add(_encodeCp850(value));
    _b.add([0x0A]);
    return this;
  }

  /// Linha com texto à esquerda e à direita, preenchida até [columns].
  /// Se não couber, [left] é truncado para preservar o valor da direita.
  EscPos row(String left, String right) {
    final space = columns - right.length;
    final l = left.length > space
        ? (space > 1 ? left.substring(0, space - 1) : '')
        : left;
    final pad = columns - l.length - right.length;
    return text('$l${' ' * (pad < 1 ? 1 : pad)}$right');
  }

  EscPos divider([String char = '-']) => text(char * columns);

  EscPos feed([int lines = 1]) {
    _b.add([_esc, 0x64, lines]); // ESC d n
    return this;
  }

  /// Corte parcial após avançar o papel. `GS V 66 n`.
  EscPos cut() {
    _b.add([_gs, 0x56, 0x42, 0x00]);
    return this;
  }

  /// Pulso na gaveta de dinheiro (pino 2), quando houver uma ligada.
  EscPos openDrawer() {
    _b.add([_esc, 0x70, 0x00, 0x19, 0xFA]); // ESC p 0 25 250
    return this;
  }

  Uint8List bytes() => _b.toBytes();
}

enum EscPosAlign { left, center, right }

/// Monta o cupom de um pedido pronto para envio à impressora.
Uint8List buildOrderReceipt(
  Order order, {
  required String storeName,
  int columns = 48,
}) {
  final p = EscPos(columns: columns)..init();

  if (storeName.trim().isNotEmpty) {
    p
      ..align(EscPosAlign.center)
      ..size(doubleWidth: true, doubleHeight: true)
      ..bold(true)
      ..text(storeName.trim())
      ..size()
      ..bold(false);
  }

  p
    ..align(EscPosAlign.center)
    ..size(doubleHeight: true)
    ..bold(true)
    ..text('PEDIDO #${order.orderNumber}')
    ..size()
    ..bold(false)
    ..text(order.fulfillmentLabel.toUpperCase())
    ..text(_formatDateTime(order.createdAt))
    ..align(EscPosAlign.left)
    ..divider()
    ..text('Cliente: ${order.customerName}');

  if (order.customerPhone != null) {
    p.text('Telefone: ${order.customerPhone}');
  }
  // Endereço só existe (e só importa) na entrega.
  if (!order.isPickup && order.address != null) {
    p.text('Endereço: ${order.address}');
  }

  p
    ..text('Status: ${order.status.label}')
    ..divider();

  for (final item in order.items) {
    p.row('${item.quantity}x ${item.name}', formatBrl(item.lineTotal));
    // Opções e observação entram recuadas, abaixo do item a que pertencem.
    if (item.optionsSummary.isNotEmpty) {
      p.text('   + ${item.optionsSummary}');
    }
    if (item.notes != null) {
      p.text('   obs: ${item.notes}');
    }
  }

  p.divider();

  // Subtotal e taxa só aparecem quando somam algo além do total — em pedidos
  // antigos (sem esses campos) o cupom continua com uma linha só de total.
  if (order.subtotal > 0) {
    p.row('Subtotal', formatBrl(order.subtotal));
  }
  if (order.deliveryFee > 0) {
    p.row('Taxa de entrega', formatBrl(order.deliveryFee));
  }

  p
    ..bold(true)
    ..size(doubleHeight: true)
    ..row('TOTAL', formatBrl(order.total))
    ..size()
    ..bold(false)
    ..divider()
    ..row('Pagamento', order.paymentLabel);

  if (order.paymentMethod == 'cash' && order.changeFor != null) {
    p.row('Troco para', formatBrl(order.changeFor!));
  }

  if (order.notes != null) {
    p
      ..divider()
      ..bold(true)
      ..text('OBSERVAÇÕES')
      ..bold(false)
      ..text(order.notes!);
  }

  p
    ..feed(2)
    ..align(EscPosAlign.center)
    ..text('RapidHub')
    ..feed(3)
    ..cut();

  return p.bytes();
}

/// Cupom de teste usado pelo botão "Imprimir teste" nas configurações.
Uint8List buildTestReceipt({required String storeName, int columns = 48}) {
  final p = EscPos(columns: columns)
    ..init()
    ..align(EscPosAlign.center)
    ..size(doubleWidth: true, doubleHeight: true)
    ..bold(true)
    ..text(storeName.trim().isEmpty ? 'RapidHub' : storeName.trim())
    ..size()
    ..bold(false)
    ..text('Teste de impressão')
    ..align(EscPosAlign.left)
    ..divider()
    ..text('Acentuação: ção, ã, é, ô, ü, Ç')
    ..row('Coluna esquerda', 'direita')
    ..row('2x Smash Clássico', formatBrl(39.8))
    ..divider()
    ..bold(true)
    ..row('TOTAL', formatBrl(39.8))
    ..bold(false)
    ..feed(3)
    ..cut();
  return p.bytes();
}

String _formatDateTime(DateTime? dt) {
  if (dt == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)}/${dt.year} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

/// Acentos do português na code page PC850. Caracteres fora do mapa caem para
/// um equivalente ASCII (ou `?`), já que a impressora não os representa.
const Map<int, int> _cp850 = {
  0xE7: 0x87, // ç
  0xC7: 0x80, // Ç
  0xE1: 0xA0, // á
  0xE0: 0x85, // à
  0xE2: 0x83, // â
  0xE3: 0xC6, // ã
  0xC1: 0xB5, // Á
  0xC0: 0xB7, // À
  0xC2: 0xB6, // Â
  0xC3: 0xC7, // Ã
  0xE9: 0x82, // é
  0xEA: 0x88, // ê
  0xC9: 0x90, // É
  0xCA: 0xD2, // Ê
  0xED: 0xA1, // í
  0xCD: 0xD6, // Í
  0xF3: 0xA2, // ó
  0xF4: 0x93, // ô
  0xF5: 0xE4, // õ
  0xD3: 0xE0, // Ó
  0xD4: 0xE2, // Ô
  0xD5: 0xE5, // Õ
  0xFA: 0xA3, // ú
  0xFC: 0x81, // ü
  0xDA: 0xE9, // Ú
  0xDC: 0x9A, // Ü
};

/// Fallback ASCII quando o caractere não existe na PC850.
const Map<int, int> _asciiFallback = {
  0x2013: 0x2D, // – → -
  0x2014: 0x2D, // — → -
  0x2018: 0x27, // ‘ → '
  0x2019: 0x27, // ’ → '
  0x201C: 0x22, // “ → "
  0x201D: 0x22, // ” → "
  0x2022: 0x2A, // • → *
};

Uint8List _encodeCp850(String value) {
  final out = Uint8List(value.runes.length);
  var i = 0;
  for (final rune in value.runes) {
    if (rune < 0x80) {
      out[i++] = rune;
    } else if (_cp850.containsKey(rune)) {
      out[i++] = _cp850[rune]!;
    } else if (_asciiFallback.containsKey(rune)) {
      out[i++] = _asciiFallback[rune]!;
    } else {
      out[i++] = 0x3F; // ?
    }
  }
  return out;
}
