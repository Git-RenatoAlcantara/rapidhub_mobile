import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rapidhubmobile/orders/orders_api.dart';
import 'package:rapidhubmobile/printing/escpos.dart';
import 'package:rapidhubmobile/printing/printer_settings.dart';
import 'package:rapidhubmobile/printing/thermal_printer.dart';

Order _order() => Order(
      id: 'o1',
      orderNumber: 42,
      customerName: 'João Conceição',
      customerPhone: '(11) 98888-7777',
      fulfillment: 'delivery',
      address: 'Rua das Flores, 123 - Centro',
      paymentMethod: 'cash',
      changeFor: 100,
      notes: 'Interfone quebrado, ligar ao chegar',
      subtotal: 47.8,
      deliveryFee: 7,
      status: OrderStatus.received,
      total: 54.8,
      items: const [
        OrderItem(
          name: 'Smash Clássico',
          quantity: 2,
          lineTotal: 39.8,
          options: [
            OrderOption(grupo: 'Ponto', nome: 'Bem passado', priceDelta: 0),
            OrderOption(grupo: 'Adicional', nome: 'Bacon', priceDelta: 4),
          ],
          notes: 'sem cebola',
        ),
        OrderItem(name: 'Coca-Cola', quantity: 1, lineTotal: 8.0),
      ],
      createdAt: DateTime(2026, 7, 13, 14, 32),
    );

void main() {
  group('EscPos', () {
    test('inicia a impressora e seleciona a code page PC850', () {
      final bytes = buildOrderReceipt(_order(), storeName: 'Burger Co');
      expect(bytes.sublist(0, 5), [0x1B, 0x40, 0x1B, 0x74, 0x02]);
    });

    test('termina com corte parcial', () {
      final bytes = buildOrderReceipt(_order(), storeName: 'Burger Co');
      expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 0x42, 0x00]);
    });

    test('codifica acentos em PC850', () {
      final bytes = EscPos().text('ção').bytes();
      // ç=0x87, ã=0xC6, o=0x6F, LF
      expect(bytes, [0x87, 0xC6, 0x6F, 0x0A]);
    });

    test('row preenche a linha até a largura do papel', () {
      final bytes = EscPos(columns: 48).row('TOTAL', 'R\$ 47,80').bytes();
      expect(bytes.length, 49); // 48 colunas + LF
      expect(String.fromCharCodes(bytes.sublist(0, 48)),
          'TOTAL${' ' * 35}R\$ 47,80');
    });

    test('row trunca o texto da esquerda quando não cabe', () {
      final bytes = EscPos(columns: 20)
          .row('Nome de item muito comprido', 'R\$ 8,00')
          .bytes();
      expect(bytes.length, 21);
      expect(String.fromCharCodes(bytes.sublist(0, 20)).length, 20);
      expect(String.fromCharCodes(bytes.sublist(0, 20)), endsWith('R\$ 8,00'));
    });

    test('cupom traz endereço, telefone, pagamento e troco', () {
      final text =
          String.fromCharCodes(buildOrderReceipt(_order(), storeName: 'Burger Co'));
      expect(text, contains('Rua das Flores, 123 - Centro'));
      expect(text, contains('(11) 98888-7777'));
      expect(text, contains('Dinheiro'));
      expect(text, contains('Troco para'));
      expect(text, contains('R\$ 100,00'));
      expect(text, contains('Interfone quebrado, ligar ao chegar'));
    });

    test('cupom detalha opções e observação de cada item', () {
      final text =
          String.fromCharCodes(buildOrderReceipt(_order(), storeName: 'Burger Co'));
      expect(text, contains('+ Bem passado, Bacon'));
      expect(text, contains('obs: sem cebola'));
    });

    test('cupom separa subtotal, taxa de entrega e total', () {
      final text =
          String.fromCharCodes(buildOrderReceipt(_order(), storeName: 'Burger Co'));
      expect(text, contains('Subtotal'));
      expect(text, contains('R\$ 47,80'));
      expect(text, contains('Taxa de entrega'));
      expect(text, contains('R\$ 7,00'));
      expect(text, contains('R\$ 54,80'));
    });

    test('pedido de retirada não imprime endereço', () {
      final pickup = Order(
        id: 'o2',
        orderNumber: 43,
        customerName: 'Maria',
        fulfillment: 'pickup',
        address: 'Endereço antigo que não deve sair',
        paymentMethod: 'pix',
        status: OrderStatus.received,
        total: 10,
        items: const [OrderItem(name: 'Café', quantity: 1, lineTotal: 10)],
        createdAt: DateTime(2026, 7, 13, 9, 0),
      );
      final text =
          String.fromCharCodes(buildOrderReceipt(pickup, storeName: 'Burger Co'));
      expect(text, contains('RETIRADA'));
      expect(text, isNot(contains('Endereço')));
      expect(text, contains('Pix'));
      expect(text, isNot(contains('Troco'))); // troco só em dinheiro
    });

    test('58mm usa 32 colunas', () {
      final bytes = buildOrderReceipt(_order(),
          storeName: 'Burger Co', columns: PaperWidth.mm58.columns);
      // A linha do divisor tem exatamente 32 hifens.
      expect(String.fromCharCodes(bytes), contains('-' * 32));
      expect(String.fromCharCodes(bytes), isNot(contains('-' * 33)));
    });
  });

  group('ThermalPrinter', () {
    test('envia o cupom por TCP e repete conforme as vias', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final received = <int>[];
      final done = server.first.then((socket) async {
        await for (final chunk in socket) {
          received.addAll(chunk);
        }
      });

      final printer = ThermalPrinter(PrinterSettings(
        host: server.address.address,
        port: server.port,
        storeName: 'Burger Co',
        copies: 2,
      ));
      await printer.printOrder(_order());
      await done;
      await server.close();

      final one = buildOrderReceipt(_order(), storeName: 'Burger Co');
      expect(received.length, one.length * 2);
      expect(Uint8List.fromList(received.sublist(0, one.length)), one);

      final text = String.fromCharCodes(received);
      expect(text, contains('PEDIDO #42'));
      expect(text, contains('2x Smash Cl')); // acento vira byte PC850
      expect(text, contains('ENTREGA'));
      expect(text, contains('13/07/2026 14:32'));
    });

    test('erro de conexão vira PrinterException com mensagem legível',
        () async {
      // Porta 1 do loopback: nada escutando.
      const printer = ThermalPrinter(
        PrinterSettings(host: '127.0.0.1', port: 1),
      );
      expect(
        () => printer.printTest(),
        throwsA(isA<PrinterException>().having(
          (e) => e.message,
          'message',
          contains('127.0.0.1:1'),
        )),
      );
    });

    test('recusa imprimir sem host configurado', () {
      const printer = ThermalPrinter(PrinterSettings());
      expect(
        () => printer.printTest(),
        throwsA(isA<PrinterException>()),
      );
    });
  });
}
