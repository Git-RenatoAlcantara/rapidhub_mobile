import 'package:flutter_test/flutter_test.dart';
import 'package:rapidhubmobile/store/store_models.dart';

void main() {
  group('helpers de horário', () {
    test('minutesToHHMM formata e limita', () {
      expect(minutesToHHMM(0), '00:00');
      expect(minutesToHHMM(1080), '18:00');
      expect(minutesToHHMM(1110), '18:30');
      expect(minutesToHHMM(9999), '23:59'); // limita a 1439
    });

    test('hhmmToMinutes converte e trata inválidos', () {
      expect(hhmmToMinutes('18:00'), 1080);
      expect(hhmmToMinutes('02:15'), 135);
      expect(hhmmToMinutes('lixo'), 0);
    });
  });

  group('fmtBRL', () {
    test('inteiro sem casas, decimal com vírgula', () {
      expect(fmtBRL(0), '0');
      expect(fmtBRL(5), '5');
      expect(fmtBRL(5.5), '5,50');
      expect(fmtBRL(12.9), '12,90');
    });
  });

  group('normalizeBairro', () {
    test('remove acentos, minúsculas e colapsa espaços', () {
      expect(normalizeBairro('Jardim  América'), 'jardim america');
      expect(normalizeBairro('SÃO João '), 'sao joao');
      expect(normalizeBairro('Centro'), 'centro');
    });
  });

  group('KitchenGroup', () {
    test('fromJson válido', () {
      final kg = KitchenGroup.fromJson({
        'connectionId': 'c1',
        'groupId': 'g1',
        'groupName': 'Cozinha',
      });
      expect(kg, isNotNull);
      expect(kg!.connectionId, 'c1');
      expect(kg.groupId, 'g1');
      expect(kg.groupName, 'Cozinha');
    });

    test('fromJson inválido retorna null', () {
      expect(KitchenGroup.fromJson(null), isNull);
      expect(KitchenGroup.fromJson({'connectionId': 'c1'}), isNull);
      expect(KitchenGroup.fromJson('texto'), isNull);
    });

    test('toJson', () {
      const kg = KitchenGroup(connectionId: 'c1', groupId: 'g1');
      expect(kg.toJson(), {
        'connectionId': 'c1',
        'groupId': 'g1',
        'groupName': null,
      });
    });
  });

  group('OperatingHours', () {
    test('initial: desativado, 7 dias inativos', () {
      final oh = OperatingHours.initial();
      expect(oh.enabled, false);
      expect(oh.timezone, kDefaultTimezone);
      expect(oh.days.length, 7);
      expect(oh.days.every((d) => !d.active), true);
    });

    test('toMetadata só inclui dias ativos como slots', () {
      final oh = OperatingHours.initial();
      oh.enabled = true;
      oh.days[1].active = true; // Segunda
      oh.days[1].from = '18:00';
      oh.days[1].to = '23:00';

      final meta = oh.toMetadata();
      expect(meta['enabled'], true);
      expect(meta['timezone'], kDefaultTimezone);
      final slots = meta['slots'] as List;
      expect(slots.length, 1);
      expect(slots.first, {
        'weekday': 1,
        'fromMinutes': 1080,
        'toMinutes': 1380,
        'isActive': true,
      });
    });

    test('fromMetadata reconstrói dias a partir dos slots', () {
      final oh = OperatingHours.fromMetadata({
        'operatingHours': {
          'enabled': true,
          'timezone': 'America/Manaus',
          'slots': [
            {'weekday': 5, 'fromMinutes': 1080, 'toMinutes': 120, 'isActive': true},
          ],
        },
      });
      expect(oh.enabled, true);
      expect(oh.timezone, 'America/Manaus');
      expect(oh.days[5].active, true);
      expect(oh.days[5].from, '18:00');
      expect(oh.days[5].to, '02:00'); // vira a meia-noite
      expect(oh.days[0].active, false);
    });

    test('round-trip toMetadata -> fromMetadata preserva a assinatura', () {
      final oh = OperatingHours.initial();
      oh.enabled = true;
      oh.days[3].active = true;
      final rebuilt =
          OperatingHours.fromMetadata({'operatingHours': oh.toMetadata()});
      expect(rebuilt.signature, oh.signature);
    });
  });

  group('DeliveryZones', () {
    test('toMetadata modo flat', () {
      final dz = DeliveryZones.initial();
      dz.enabled = true;
      dz.mode = DeliveryMode.flat;
      dz.flatFee = 8;
      dz.flatEta = '40-60 min';

      final meta = dz.toMetadata();
      expect(meta['enabled'], true);
      expect(meta['mode'], 'flat');
      expect(meta['flatFee'], 8);
      expect(meta['flatEta'], '40-60 min');
      expect(meta['zones'], isEmpty);
    });

    test('flatEta vazio é omitido', () {
      final dz = DeliveryZones.initial()..enabled = true;
      expect(dz.toMetadata().containsKey('flatEta'), false);
    });

    test('toMetadata modo zones filtra bairros vazios e faz trim', () {
      final dz = DeliveryZones.initial();
      dz.enabled = true;
      dz.mode = DeliveryMode.zones;
      dz.minimumOrder = 30;
      dz.zones = [
        DzZone(bairro: '  Centro  ', fee: 5, eta: ' 30 min '),
        DzZone(bairro: '', fee: 10, eta: ''), // descartado
      ];

      final meta = dz.toMetadata();
      expect(meta['mode'], 'zones');
      expect(meta['minimumOrder'], 30);
      final zones = meta['zones'] as List;
      expect(zones.length, 1);
      expect(zones.first, {'bairro': 'Centro', 'fee': 5, 'eta': '30 min'});
    });

    test('fromMetadata infere modo zones quando há bairros e sem mode', () {
      final dz = DeliveryZones.fromMetadata({
        'deliveryZones': {
          'enabled': true,
          'zones': [
            {'bairro': 'Centro', 'fee': 5},
          ],
        },
      });
      expect(dz.mode, DeliveryMode.zones);
      expect(dz.zones.single.bairro, 'Centro');
      expect(dz.zones.single.fee, 5);
    });

    test('fromMetadata sem dados usa initial (flat)', () {
      final dz = DeliveryZones.fromMetadata({});
      expect(dz.mode, DeliveryMode.flat);
      expect(dz.enabled, false);
    });
  });

  group('validateDeliveryZones', () {
    test('marca bairro vazio e duplicado', () {
      final dz = DeliveryZones.initial();
      dz.zones = [
        DzZone(bairro: 'Centro', fee: 5, eta: ''),
        DzZone(bairro: 'centro', fee: 7, eta: ''), // duplicado (normalizado)
        DzZone(bairro: '', fee: 0, eta: ''), // vazio
      ];

      final result = validateDeliveryZones(dz);
      expect(result.issues[0].empty, false);
      expect(result.issues[0].duplicate, false);
      expect(result.issues[1].duplicate, true);
      expect(result.issues[2].empty, true);
    });

    test('resumo calcula contagem e faixa de taxa', () {
      final dz = DeliveryZones.initial();
      dz.minimumOrder = 25;
      dz.zones = [
        DzZone(bairro: 'A', fee: 5, eta: ''),
        DzZone(bairro: 'B', fee: 10, eta: ''),
      ];

      final summary = validateDeliveryZones(dz).summary!;
      expect(summary.count, 2);
      expect(summary.feeMin, 5);
      expect(summary.feeMax, 10);
      expect(summary.allFree, false);
      expect(summary.minimumOrder, 25);
    });

    test('resumo é null quando não há bairros válidos', () {
      final dz = DeliveryZones.initial();
      dz.zones = [DzZone(bairro: '', fee: 0, eta: '')];
      expect(validateDeliveryZones(dz).summary, isNull);
    });
  });

  group('PickupTime', () {
    test('toMetadata faz trim do estimate', () {
      final pt = PickupTime(enabled: true, estimate: '  20 a 30 min  ');
      expect(pt.toMetadata(), {'enabled': true, 'estimate': '20 a 30 min'});
    });

    test('fromMetadata', () {
      final pt = PickupTime.fromMetadata({
        'pickupTime': {'enabled': true, 'estimate': '15 min'},
      });
      expect(pt.enabled, true);
      expect(pt.estimate, '15 min');
    });

    test('fromMetadata sem dados usa initial', () {
      final pt = PickupTime.fromMetadata({});
      expect(pt.enabled, false);
      expect(pt.estimate, '');
    });
  });
}
