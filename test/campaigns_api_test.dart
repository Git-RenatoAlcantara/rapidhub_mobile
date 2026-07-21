import 'package:flutter_test/flutter_test.dart';
import 'package:rapidhubmobile/campaigns/campaigns_api.dart';

void main() {
  group('Coupon.fromJson', () {
    test('lê discountValue vindo como string (Decimal do Prisma)', () {
      final coupon = Coupon.fromJson(const {
        'id': 'c1',
        'code': 'VOLTA10',
        'discountType': 'percent',
        'discountValue': '10',
        'isActive': true,
        'isPersonalized': true,
        'usedCount': 3,
        'maxUses': 100,
        'minOrder': '25.5',
      });

      expect(coupon.discountValue, 10);
      expect(coupon.minOrder, 25.5);
      expect(coupon.isPersonalized, isTrue);
      expect(coupon.label, 'VOLTA10 · 10%');
    });

    test('valor fixo sai em reais e sem casas quando é inteiro', () {
      final coupon = Coupon.fromJson(const {
        'id': 'c2',
        'code': 'CINCO',
        'discountType': 'fixed',
        'discountValue': 5,
      });

      expect(coupon.discountLabel, r'R$ 5');
      // Sem `isActive` no corpo, o cupom conta como ativo (padrão do servidor).
      expect(coupon.isActive, isTrue);
    });
  });

  group('Campaign.fromJson', () {
    test('só rascunho pode ser editado/disparado', () {
      final draft = Campaign.fromJson(const {'id': 'a', 'status': 'draft'});
      final sent = Campaign.fromJson(const {'id': 'b', 'status': 'sent'});

      expect(draft.isDraft, isTrue);
      expect(sent.isDraft, isFalse);
      expect(campaignStatusLabel(sent.status), 'Concluída');
    });

    test('segmentConfig ausente vira mapa vazio', () {
      final campaign = Campaign.fromJson(const {
        'id': 'a',
        'segmentType': 'inactive',
        'throttleSeconds': 15,
      });

      expect(campaign.segmentConfig, isEmpty);
      expect(campaign.throttleSeconds, 15);
      expect(campaignSegmentLabel(campaign.segmentType), 'Inativos há X dias');
    });
  });

  group('sendableConnections', () {
    test('descarta desconectadas e sobras de pareamento', () {
      final all = [
        const CampaignConnection(
            id: '1', name: 'Balcão', status: 'connected', phone: '5511999'),
        const CampaignConnection(id: '2', name: 'Antiga', status: 'failed'),
        const CampaignConnection(
            id: '3', name: 'pending-1750000000', status: 'connected'),
      ];

      final sendable = sendableConnections(all);

      expect(sendable.map((c) => c.id), ['1']);
      expect(sendable.first.label, 'Balcão · 5511999');
    });
  });
}
