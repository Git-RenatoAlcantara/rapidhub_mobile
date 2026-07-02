import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'store_models.dart';
import 'store_widgets.dart';

/// Editor do tempo de retirada no balcão. Quando habilitado, o agente informa
/// ao cliente esse prazo estimado sempre que ele escolher retirar na loja.
class PickupTimeEditor extends StatefulWidget {
  const PickupTimeEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.disabled = false,
  });

  final PickupTime value;
  final VoidCallback onChanged;
  final bool disabled;

  @override
  State<PickupTimeEditor> createState() => _PickupTimeEditorState();
}

class _PickupTimeEditorState extends State<PickupTimeEditor> {
  late final TextEditingController _estimate;

  @override
  void initState() {
    super.initState();
    _estimate = TextEditingController(text: widget.value.estimate);
  }

  @override
  void dispose() {
    _estimate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    return StoreSection(
      label: 'Tempo de retirada',
      children: [
        StoreCheckbox(
          value: value.enabled,
          label: 'Informar tempo de retirada ao cliente',
          enabled: !widget.disabled,
          onChanged: (v) {
            value.enabled = v;
            setState(() {});
            widget.onChanged();
          },
        ),
        if (value.enabled) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.timer_outlined,
                  color: AppColors.textSecondary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: StoreField(
                  controller: _estimate,
                  hint: 'Ex.: 20 a 30 minutos',
                  enabled: !widget.disabled,
                  onChanged: (v) {
                    value.estimate = v;
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const StoreHelpText(
            'Ao fechar um pedido para retirada no balcão, o agente avisa o '
            'cliente que ele poderá buscar em aproximadamente esse tempo. Não '
            'afeta as entregas (o prazo de entrega fica no frete).',
          ),
        ],
      ],
    );
  }
}
