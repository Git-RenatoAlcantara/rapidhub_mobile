import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'store_models.dart';
import 'store_widgets.dart';

/// Editor da pré-venda: com a loja fechada, o agente continua vendendo e o
/// pedido é agendado para a abertura, em vez de ser recusado. Depende do
/// horário de funcionamento estar configurado — sem horário, a loja nunca está
/// "fechada".
class PreOrderEditor extends StatefulWidget {
  const PreOrderEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.disabled = false,
  });

  final PreOrder value;
  final VoidCallback onChanged;
  final bool disabled;

  @override
  State<PreOrderEditor> createState() => _PreOrderEditorState();
}

class _PreOrderEditorState extends State<PreOrderEditor> {
  late final TextEditingController _leadMinutes;
  late final TextEditingController _maxHoursAhead;

  @override
  void initState() {
    super.initState();
    _leadMinutes = TextEditingController(text: '${widget.value.leadMinutes}');
    _maxHoursAhead =
        TextEditingController(text: '${widget.value.maxHoursAhead}');
  }

  @override
  void dispose() {
    _leadMinutes.dispose();
    _maxHoursAhead.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    return StoreSection(
      label: 'Pré-venda (fora do horário)',
      children: [
        StoreCheckbox(
          value: value.enabled,
          label: 'Aceitar pedidos com a loja fechada (agendados para a abertura)',
          enabled: !widget.disabled,
          onChanged: (v) {
            value.enabled = v;
            setState(() {});
            widget.onChanged();
          },
        ),
        if (value.enabled) ...[
          const SizedBox(height: 14),
          _numberRow(
            label: 'Começar o preparo após a abertura',
            controller: _leadMinutes,
            suffix: 'minutos',
            onChanged: (n) {
              value.leadMinutes = n ?? 0;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 12),
          _numberRow(
            label: 'Aceitar até quanto tempo antes da abertura',
            controller: _maxHoursAhead,
            suffix: 'horas',
            onChanged: (n) {
              // Zero desligaria a pré-venda na prática; o mínimo útil é 1 hora.
              value.maxHoursAhead = (n == null || n < 1) ? 1 : n;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 12),
          const StoreHelpText(
            'Fora do horário, o agente monta o pedido normalmente e avisa que o '
            'preparo e a entrega só acontecem na abertura. O pedido fica em '
            '"Agendados" e entra na cozinha sozinho na hora marcada — a comanda '
            'só sai nesse momento. Se a loja demorar mais que a janela acima '
            'para abrir (ex.: fecha domingo inteiro), o pedido é recusado como '
            'antes.',
          ),
        ],
      ],
    );
  }

  Widget _numberRow({
    required String label,
    required TextEditingController controller,
    required String suffix,
    required ValueChanged<int?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 13, height: 1.4)),
        const SizedBox(height: 8),
        Row(
          children: [
            StoreField(
              controller: controller,
              width: 96,
              enabled: !widget.disabled,
              keyboardType: TextInputType.number,
              onChanged: (v) => onChanged(int.tryParse(v.trim())),
            ),
            const SizedBox(width: 10),
            Text(suffix,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      ],
    );
  }
}
