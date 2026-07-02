import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'store_models.dart';
import 'store_widgets.dart';

/// Converte texto (aceita vírgula decimal) em double >= 0.
double _parseMoney(String raw) {
  final v = double.tryParse(raw.trim().replaceAll(',', '.')) ?? 0;
  return v < 0 ? 0 : v;
}

String _moneyText(double v) => v == 0 ? '' : fmtBRL(v);

/// Controllers de uma linha de zona (bairro, taxa, prazo).
class _ZoneControllers {
  _ZoneControllers(DzZone z)
      : bairro = TextEditingController(text: z.bairro),
        fee = TextEditingController(text: _moneyText(z.fee)),
        eta = TextEditingController(text: z.eta);
  final TextEditingController bairro;
  final TextEditingController fee;
  final TextEditingController eta;
  void dispose() {
    bairro.dispose();
    fee.dispose();
    eta.dispose();
  }
}

/// Editor de zonas de entrega (frete). Dois modos: taxa fixa (um valor) e por
/// bairro (tabela + pedido mínimo).
class DeliveryZonesEditor extends StatefulWidget {
  const DeliveryZonesEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.disabled = false,
  });

  final DeliveryZones value;
  final VoidCallback onChanged;
  final bool disabled;

  @override
  State<DeliveryZonesEditor> createState() => _DeliveryZonesEditorState();
}

class _DeliveryZonesEditorState extends State<DeliveryZonesEditor> {
  late final TextEditingController _flatFee;
  late final TextEditingController _flatEta;
  late final TextEditingController _minimumOrder;
  late List<_ZoneControllers> _zoneCtrls;

  @override
  void initState() {
    super.initState();
    _flatFee = TextEditingController(text: _moneyText(widget.value.flatFee));
    _flatEta = TextEditingController(text: widget.value.flatEta);
    _minimumOrder =
        TextEditingController(text: _moneyText(widget.value.minimumOrder));
    _zoneCtrls = widget.value.zones.map(_ZoneControllers.new).toList();
  }

  @override
  void dispose() {
    _flatFee.dispose();
    _flatEta.dispose();
    _minimumOrder.dispose();
    for (final c in _zoneCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _notify() => widget.onChanged();

  void _addZone() {
    final zone = DzZone(bairro: '', fee: 0, eta: '');
    widget.value.zones.add(zone);
    _zoneCtrls.add(_ZoneControllers(zone));
    setState(() {});
    _notify();
  }

  void _removeZone(int index) {
    widget.value.zones.removeAt(index);
    _zoneCtrls.removeAt(index).dispose();
    setState(() {});
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final validation = validateDeliveryZones(value);
    final summary = validation.summary;

    return StoreSection(
      label: 'Entrega por bairro',
      children: [
        StoreCheckbox(
          value: value.enabled,
          label: 'Cobrar frete na entrega',
          enabled: !widget.disabled,
          onChanged: (v) {
            value.enabled = v;
            setState(() {});
            _notify();
          },
        ),
        if (value.enabled) ...[
          const SizedBox(height: 14),
          _buildModeToggle(value),
          const SizedBox(height: 14),
          if (value.mode == DeliveryMode.flat)
            _buildFlatMode(value)
          else
            _buildZonesMode(value, validation, summary),
        ],
      ],
    );
  }

  Widget _buildModeToggle(DeliveryZones value) {
    Widget option(DeliveryMode mode, String label) {
      final active = value.mode == mode;
      return GestureDetector(
        onTap: widget.disabled
            ? null
            : () {
                value.mode = mode;
                setState(() {});
                _notify();
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          option(DeliveryMode.flat, 'Taxa fixa'),
          option(DeliveryMode.zones, 'Por bairro'),
        ],
      ),
    );
  }

  Widget _buildFlatMode(DeliveryZones value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.local_shipping,
                color: AppColors.textSecondary, size: 18),
            const SizedBox(width: 10),
            StoreField(
              controller: _flatFee,
              label: 'Valor (R\$)',
              width: 110,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) {
                value.flatFee = _parseMoney(v);
                _notify();
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StoreField(
                controller: _flatEta,
                hint: 'prazo, ex: 40-60 min',
                onChanged: (v) {
                  value.flatEta = v;
                  _notify();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const StoreHelpText(
          'Um valor único para qualquer endereço. Deixe 0 para frete grátis. '
          'A retirada no balcão não tem taxa.',
        ),
      ],
    );
  }

  Widget _buildZonesMode(
    DeliveryZones value,
    DeliveryZonesValidation validation,
    DzSummary? summary,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary != null) _buildSummaryChip(summary),
        if (summary != null) const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.shopping_cart_outlined,
                color: AppColors.textSecondary, size: 18),
            const SizedBox(width: 10),
            const Text('Pedido mínimo (R\$)',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            const Spacer(),
            StoreField(
              controller: _minimumOrder,
              hint: '0',
              width: 100,
              keyboardType: const TextInputType.numberWithOptions(),
              onChanged: (v) {
                value.minimumOrder = _parseMoney(v);
                _notify();
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (value.zones.isEmpty)
          const StoreHelpText(
            'Nenhum bairro cadastrado. Bairros não cadastrados não recebem '
            'entrega.',
          ),
        ...List.generate(
          value.zones.length,
          (i) => _buildZoneRow(i, validation.issues[i]),
        ),
        const SizedBox(height: 8),
        if (!widget.disabled)
          OutlinedButton.icon(
            onPressed: _addZone,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Adicionar bairro'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(
                  color: AppColors.borderStrong,
                  style: BorderStyle.solid),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        const SizedBox(height: 12),
        const StoreHelpText(
          'O agente pergunta o bairro e informa a taxa/prazo automaticamente. '
          'Bairro fora da lista: o agente avisa que não há entrega e oferece '
          'retirada no balcão.',
        ),
      ],
    );
  }

  Widget _buildSummaryChip(DzSummary summary) {
    final feeText = summary.allFree
        ? 'frete grátis'
        : summary.feeMin == summary.feeMax
            ? 'frete R\$ ${fmtBRL(summary.feeMin)}'
            : 'frete R\$ ${fmtBRL(summary.feeMin)}–${fmtBRL(summary.feeMax)}';
    final minText =
        summary.minimumOrder > 0 ? ' · mín. R\$ ${fmtBRL(summary.minimumOrder)}' : '';
    final text =
        '${summary.count} ${summary.count == 1 ? 'bairro' : 'bairros'} · $feeText$minText';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.receipt_long,
              color: AppColors.textSecondary, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneRow(int index, DzZoneIssue issue) {
    final ctrls = _zoneCtrls[index];
    final zone = widget.value.zones[index];

    final bairroBorder = issue.empty
        ? AppColors.danger
        : issue.duplicate
            ? const Color(0xFFD29922)
            : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: StoreField(
                  controller: ctrls.bairro,
                  hint: 'Bairro',
                  enabled: !widget.disabled,
                  errorBorderColor: bairroBorder,
                  onChanged: (v) {
                    zone.bairro = v;
                    setState(() {}); // revalida (vazio/duplicado/resumo)
                    _notify();
                  },
                ),
              ),
              const SizedBox(width: 8),
              StoreField(
                controller: ctrls.fee,
                hint: '0',
                width: 66,
                enabled: !widget.disabled,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) {
                  zone.fee = _parseMoney(v);
                  setState(() {});
                  _notify();
                },
              ),
              const SizedBox(width: 8),
              StoreField(
                controller: ctrls.eta,
                hint: 'ex: 40-60',
                width: 92,
                enabled: !widget.disabled,
                onChanged: (v) {
                  zone.eta = v;
                  _notify();
                },
              ),
              IconButton(
                onPressed: widget.disabled ? null : () => _removeZone(index),
                icon: const Icon(Icons.close, size: 18),
                color: AppColors.textSecondary,
                tooltip: 'Remover bairro',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (issue.empty)
            const Padding(
              padding: EdgeInsets.only(left: 2, top: 2),
              child: Text(
                'Informe o nome do bairro — linhas vazias não são salvas',
                style: TextStyle(color: AppColors.danger, fontSize: 11),
              ),
            )
          else if (issue.duplicate)
            const Padding(
              padding: EdgeInsets.only(left: 2, top: 2),
              child: Text(
                'Bairro repetido — vale a 1ª',
                style: TextStyle(color: Color(0xFFD29922), fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
