import 'dart:convert';

/// Modelos e conversões das configurações da Loja (nível de organização).
///
/// Espelham os configs do webapp (`components/orders/*-config.ts`) para que os
/// objetos salvos em `Organization.metadata.store` via `/api/store` tenham o
/// mesmo formato consumido pelas funções de domínio do backend.

// ============================================================
// Tipo de cardápio (store.menuMode)
// ============================================================

/// Como o agente consulta e vende os itens do cardápio.
enum MenuMode {
  regular('regular', 'Restaurante/Pizzaria'),
  marmitex('marmitex', 'Marmitex por dia');

  const MenuMode(this.value, this.label);

  final String value;
  final String label;

  /// Qualquer valor fora do enum cai em [MenuMode.regular], como no webapp.
  static MenuMode parse(Object? raw) =>
      raw == 'marmitex' ? MenuMode.marmitex : MenuMode.regular;
}

// ============================================================
// Gatilho de abandono (store.abandonmentTriggerStage)
// ============================================================

/// Etapa em que o cliente passa a contar como "no funil" e liga o cronômetro
/// de recuperação automática.
class AbandonmentStage {
  const AbandonmentStage(this.value, this.label);

  final String value;
  final String label;
}

const String kDefaultAbandonmentStage = 'delivery_address';

const List<AbandonmentStage> kAbandonmentStages = [
  AbandonmentStage(
      'delivery_address', 'Ao informar endereço de entrega (Padrão)'),
  AbandonmentStage('product_selection', 'Ao escolher produto/iniciar pedido'),
  AbandonmentStage('pickup_selected', 'Ao selecionar retirada presencial'),
  AbandonmentStage('any_intent', 'Qualquer um dos acima'),
];

/// Cai no padrão quando o valor salvo é vazio ou desconhecido.
String parseAbandonmentStage(Object? raw) {
  final value = (raw ?? '').toString();
  final known = kAbandonmentStages.any((s) => s.value == value);
  return known ? value : kDefaultAbandonmentStage;
}

// ============================================================
// Pizza meio-a-meio (store.halfPriceRule)
// ============================================================

/// Como cobrar uma pizza com dois ou mais sabores. String vazia = desligado —
/// o agente recusa o meio-a-meio e oferece sabor único, em vez de somar duas
/// pizzas inteiras e dobrar o total silenciosamente.
class HalfPriceRuleOption {
  const HalfPriceRuleOption(this.value, this.label);
  final String value;
  final String label;
}

const List<HalfPriceRuleOption> kHalfPriceRules = [
  HalfPriceRuleOption('', 'Desligado (só sabor único)'),
  HalfPriceRuleOption('expensive', 'Cobrar o sabor mais caro'),
  HalfPriceRuleOption('average', 'Cobrar a média dos sabores'),
];

/// Qualquer valor fora do enum do webapp vira desligado.
String parseHalfPriceRule(Object? raw) =>
    (raw == 'expensive' || raw == 'average') ? raw.toString() : '';

// ============================================================
// Grupo da cozinha
// ============================================================

/// Grupo de WhatsApp que recebe a comanda ao fechar o pedido.
class KitchenGroup {
  const KitchenGroup({
    required this.connectionId,
    required this.groupId,
    this.groupName,
  });

  final String connectionId;
  final String groupId;
  final String? groupName;

  KitchenGroup copyWith({
    String? connectionId,
    String? groupId,
    String? groupName,
    bool clearGroupName = false,
  }) {
    return KitchenGroup(
      connectionId: connectionId ?? this.connectionId,
      groupId: groupId ?? this.groupId,
      groupName: clearGroupName ? null : (groupName ?? this.groupName),
    );
  }

  /// Lê `store.kitchenGroup` salvo.
  static KitchenGroup? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final connectionId = raw['connectionId'];
    final groupId = raw['groupId'];
    if (connectionId is String && groupId is String) {
      final groupName = raw['groupName'];
      return KitchenGroup(
        connectionId: connectionId,
        groupId: groupId,
        groupName: groupName is String ? groupName : null,
      );
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'connectionId': connectionId,
        'groupId': groupId,
        'groupName': groupName,
      };
}

// ============================================================
// Horário de funcionamento
// ============================================================

const List<String> kWeekdayLabels = [
  'Domingo',
  'Segunda',
  'Terça',
  'Quarta',
  'Quinta',
  'Sexta',
  'Sábado',
];

const String kDefaultTimezone = 'America/Sao_Paulo';

/// Fusos do Brasil (mesma lista do webapp).
const List<TimezoneOption> kTimezoneOptions = [
  TimezoneOption('America/Sao_Paulo', 'Brasília (São Paulo)'),
  TimezoneOption('America/Manaus', 'Amazonas (Manaus)'),
  TimezoneOption('America/Cuiaba', 'Mato Grosso (Cuiabá)'),
  TimezoneOption('America/Campo_Grande', 'Mato Grosso do Sul'),
  TimezoneOption('America/Belem', 'Pará (Belém)'),
  TimezoneOption('America/Fortaleza', 'Ceará (Fortaleza)'),
  TimezoneOption('America/Rio_Branco', 'Acre (Rio Branco)'),
];

class TimezoneOption {
  const TimezoneOption(this.value, this.label);
  final String value;
  final String label;
}

String minutesToHHMM(int m) {
  final safe = m.clamp(0, 1439);
  final h = safe ~/ 60;
  final mm = safe % 60;
  return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}

int hhmmToMinutes(String value) {
  final parts = value.split(':');
  final h = int.tryParse(parts.isNotEmpty ? parts[0] : '');
  final m = int.tryParse(parts.length > 1 ? parts[1] : '');
  if (h == null || m == null) return 0;
  return (h * 60 + m).clamp(0, 1439);
}

/// Uma linha por dia da semana no editor (janela única, "HH:MM").
class OhDay {
  OhDay({required this.active, required this.from, required this.to});
  bool active;
  String from;
  String to;
}

class OperatingHours {
  OperatingHours({
    required this.enabled,
    required this.timezone,
    required this.days,
  });

  bool enabled;
  String timezone;
  List<OhDay> days; // sempre 7 (índice = weekday)

  /// Estado inicial: 7 dias inativos, janela padrão 18:00–23:00.
  factory OperatingHours.initial() => OperatingHours(
        enabled: false,
        timezone: kDefaultTimezone,
        days: List.generate(
          7,
          (_) => OhDay(active: false, from: '18:00', to: '23:00'),
        ),
      );

  /// Lê `store.operatingHours` para o formato do editor.
  factory OperatingHours.fromMetadata(dynamic metadata) {
    final oh = (metadata is Map) ? metadata['operatingHours'] : null;
    if (oh is! Map) return OperatingHours.initial();

    final days = List.generate(
      7,
      (_) => OhDay(active: false, from: '18:00', to: '23:00'),
    );
    final rawSlots = oh['slots'];
    if (rawSlots is List) {
      for (final raw in rawSlots) {
        if (raw is! Map) continue;
        final wd = raw['weekday'];
        if (wd is! int || wd < 0 || wd > 6) continue;
        days[wd] = OhDay(
          active: raw['isActive'] != false,
          from: raw['fromMinutes'] is num
              ? minutesToHHMM((raw['fromMinutes'] as num).round())
              : '18:00',
          to: raw['toMinutes'] is num
              ? minutesToHHMM((raw['toMinutes'] as num).round())
              : '23:00',
        );
      }
    }

    final tz = oh['timezone'];
    return OperatingHours(
      enabled: oh['enabled'] == true,
      timezone: (tz is String && tz.trim().isNotEmpty) ? tz : kDefaultTimezone,
      days: days,
    );
  }

  /// Converte para o formato salvo em `store.operatingHours`.
  Map<String, dynamic> toMetadata() {
    final slots = <Map<String, dynamic>>[];
    for (var weekday = 0; weekday < days.length; weekday++) {
      final d = days[weekday];
      if (!d.active) continue;
      slots.add({
        'weekday': weekday,
        'fromMinutes': hhmmToMinutes(d.from),
        'toMinutes': hhmmToMinutes(d.to),
        'isActive': true,
      });
    }
    return {'enabled': enabled, 'timezone': timezone, 'slots': slots};
  }

  String get signature => jsonEncode(toMetadata());
}

// ============================================================
// Frete / Entrega
// ============================================================

enum DeliveryMode { flat, zones }

String deliveryModeToString(DeliveryMode mode) =>
    mode == DeliveryMode.flat ? 'flat' : 'zones';

class DzZone {
  DzZone({required this.bairro, required this.fee, required this.eta});
  String bairro;
  double fee;
  String eta; // prazo estimado, texto livre
}

class DeliveryZones {
  DeliveryZones({
    required this.enabled,
    required this.mode,
    required this.flatFee,
    required this.flatEta,
    required this.minimumOrder,
    required this.zones,
  });

  bool enabled;
  DeliveryMode mode;
  double flatFee; // taxa fixa (R$) quando mode=flat; 0 = frete grátis
  String flatEta;
  double minimumOrder; // pedido mínimo global (R$); 0 = sem mínimo (modo zones)
  List<DzZone> zones;

  /// Agente novo: modo taxa fixa (mais simples e comum).
  factory DeliveryZones.initial() => DeliveryZones(
        enabled: false,
        mode: DeliveryMode.flat,
        flatFee: 0,
        flatEta: '',
        minimumOrder: 0,
        zones: [],
      );

  /// Lê `store.deliveryZones` para o formato do editor.
  factory DeliveryZones.fromMetadata(dynamic metadata) {
    final dz = (metadata is Map) ? metadata['deliveryZones'] : null;
    if (dz is! Map) return DeliveryZones.initial();

    final rawZones = dz['zones'];
    final zones = <DzZone>[];
    if (rawZones is List) {
      for (final raw in rawZones) {
        final z = (raw is Map) ? raw : const {};
        zones.add(DzZone(
          bairro: z['bairro'] is String ? z['bairro'] as String : '',
          fee: z['fee'] is num ? (z['fee'] as num).toDouble() : 0,
          eta: z['eta'] is String ? z['eta'] as String : '',
        ));
      }
    }

    // Modo (retrocompatível): usa `mode` se válido; senão 'zones' quando já há
    // bairros (config legada), senão 'flat'.
    final rawMode = dz['mode'];
    final DeliveryMode mode;
    if (rawMode == 'flat') {
      mode = DeliveryMode.flat;
    } else if (rawMode == 'zones') {
      mode = DeliveryMode.zones;
    } else {
      mode = zones.isNotEmpty ? DeliveryMode.zones : DeliveryMode.flat;
    }

    final flatFee = dz['flatFee'];
    final minimumOrder = dz['minimumOrder'];
    final flatEta = dz['flatEta'];
    return DeliveryZones(
      enabled: dz['enabled'] == true,
      mode: mode,
      flatFee: (flatFee is num && flatFee > 0) ? flatFee.toDouble() : 0,
      flatEta: flatEta is String ? flatEta : '',
      minimumOrder:
          (minimumOrder is num && minimumOrder > 0) ? minimumOrder.toDouble() : 0,
      zones: zones,
    );
  }

  /// Converte para o formato salvo em `store.deliveryZones`.
  Map<String, dynamic> toMetadata() {
    final outZones = <Map<String, dynamic>>[];
    for (final z in zones) {
      final bairro = z.bairro.trim();
      if (bairro.isEmpty) continue;
      final eta = z.eta.trim();
      outZones.add({
        'bairro': bairro,
        'fee': (z.fee.isFinite && z.fee >= 0) ? z.fee : 0,
        if (eta.isNotEmpty) 'eta': eta,
      });
    }
    final flatEtaTrim = flatEta.trim();
    return {
      'enabled': enabled,
      'mode': deliveryModeToString(mode),
      'flatFee': (flatFee.isFinite && flatFee > 0) ? flatFee : 0,
      if (flatEtaTrim.isNotEmpty) 'flatEta': flatEtaTrim,
      'minimumOrder':
          (minimumOrder.isFinite && minimumOrder > 0) ? minimumOrder : 0,
      'zones': outZones,
    };
  }

  String get signature => jsonEncode(toMetadata());
}

/// Normaliza bairro p/ casamento (espelha `normalizeBairro` do backend).
String normalizeBairro(String value) {
  // Remove acentos comuns do PT-BR e colapsa espaços.
  const withAccents = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  const withoutAccents = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
  final buffer = StringBuffer();
  for (final ch in value.split('')) {
    final idx = withAccents.indexOf(ch);
    buffer.write(idx >= 0 ? withoutAccents[idx] : ch);
  }
  return buffer.toString().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

class DzZoneIssue {
  const DzZoneIssue({required this.empty, required this.duplicate});
  final bool empty;
  final bool duplicate;
}

class DzSummary {
  const DzSummary({
    required this.count,
    required this.feeMin,
    required this.feeMax,
    required this.allFree,
    required this.minimumOrder,
  });
  final int count;
  final double feeMin;
  final double feeMax;
  final bool allFree;
  final double minimumOrder;
}

class DeliveryZonesValidation {
  const DeliveryZonesValidation({required this.issues, required this.summary});
  final List<DzZoneIssue> issues;
  final DzSummary? summary;
}

/// Validação pura p/ o editor: marca bairro vazio/duplicado e resume as zonas.
DeliveryZonesValidation validateDeliveryZones(DeliveryZones value) {
  final seen = <String>{};
  final issues = value.zones.map((z) {
    final name = z.bairro.trim();
    if (name.isEmpty) return const DzZoneIssue(empty: true, duplicate: false);
    final key = normalizeBairro(name);
    final duplicate = seen.contains(key);
    seen.add(key);
    return DzZoneIssue(empty: false, duplicate: duplicate);
  }).toList();

  final valid = value.zones.where((z) => z.bairro.trim().isNotEmpty).toList();
  if (valid.isEmpty) {
    return DeliveryZonesValidation(issues: issues, summary: null);
  }

  final fees =
      valid.map((z) => (z.fee.isFinite && z.fee > 0) ? z.fee : 0.0).toList();
  final feeMin = fees.reduce((a, b) => a < b ? a : b);
  final feeMax = fees.reduce((a, b) => a > b ? a : b);

  return DeliveryZonesValidation(
    issues: issues,
    summary: DzSummary(
      count: valid.length,
      feeMin: feeMin,
      feeMax: feeMax,
      allFree: feeMax == 0,
      minimumOrder: value.minimumOrder > 0 ? value.minimumOrder : 0,
    ),
  );
}

/// Formata R$ ao estilo do webapp: inteiro sem casas, senão vírgula decimal.
String fmtBRL(double n) {
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n.toStringAsFixed(2).replaceAll('.', ',');
}

// ============================================================
// Pré-venda (store.preOrder)
// ============================================================

/// Pedido fechado com a loja fechada e agendado para a abertura. Depende do
/// horário de funcionamento estar configurado — sem horário, a loja nunca está
/// "fechada" e a pré-venda nunca dispara.
class PreOrder {
  PreOrder({
    required this.enabled,
    required this.leadMinutes,
    required this.maxHoursAhead,
  });

  bool enabled;

  /// Minutos após a abertura em que o preparo começa.
  int leadMinutes;

  /// Só aceita pré-venda se a loja abrir dentro desta janela (horas).
  int maxHoursAhead;

  factory PreOrder.initial() =>
      PreOrder(enabled: false, leadMinutes: 0, maxHoursAhead: 24);

  /// Lê `store.preOrder` para o formato do editor.
  factory PreOrder.fromMetadata(dynamic metadata) {
    final po = (metadata is Map) ? metadata['preOrder'] : null;
    if (po is! Map) return PreOrder.initial();

    int number(Object? raw, int fallback) {
      if (raw is num && raw.isFinite && raw >= 0) return raw.round();
      return fallback;
    }

    return PreOrder(
      enabled: po['enabled'] == true,
      leadMinutes: number(po['leadMinutes'], 0),
      maxHoursAhead: number(po['maxHoursAhead'], 24),
    );
  }

  /// Converte para o formato salvo em `store.preOrder`.
  Map<String, dynamic> toMetadata() => {
        'enabled': enabled,
        'leadMinutes': leadMinutes < 0 ? 0 : leadMinutes,
        // Zero desligaria a pré-venda na prática; o mínimo útil é 1 hora.
        'maxHoursAhead': maxHoursAhead < 1 ? 1 : maxHoursAhead,
      };

  String get signature => jsonEncode(toMetadata());
}

// ============================================================
// Tempo de retirada
// ============================================================

class PickupTime {
  PickupTime({required this.enabled, required this.estimate});
  bool enabled;
  String estimate; // prazo estimado, texto livre

  factory PickupTime.initial() => PickupTime(enabled: false, estimate: '');

  /// Lê `store.pickupTime` para o formato do editor.
  factory PickupTime.fromMetadata(dynamic metadata) {
    final pt = (metadata is Map) ? metadata['pickupTime'] : null;
    if (pt is! Map) return PickupTime.initial();
    final estimate = pt['estimate'];
    return PickupTime(
      enabled: pt['enabled'] == true,
      estimate: estimate is String ? estimate : '',
    );
  }

  /// Converte para o formato salvo em `store.pickupTime`.
  Map<String, dynamic> toMetadata() =>
      {'enabled': enabled, 'estimate': estimate.trim()};

  String get signature => jsonEncode(toMetadata());
}
