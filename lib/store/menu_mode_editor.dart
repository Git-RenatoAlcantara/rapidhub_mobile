import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'store_models.dart';
import 'store_widgets.dart';

/// Tipo de cardápio (`store.menuMode`): define como o agente consulta e vende
/// os itens — catálogo fixo (restaurante/pizzaria) ou marmitex do dia.
class MenuModeEditor extends StatelessWidget {
  const MenuModeEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.disabled = false,
  });

  final MenuMode value;
  final ValueChanged<MenuMode> onChanged;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return StoreSection(
      label: 'Tipo de cardápio',
      children: [
        _StoreDropdown<MenuMode>(
          value: value,
          enabled: !disabled,
          items: [
            for (final mode in MenuMode.values)
              DropdownMenuItem(value: mode, child: Text(mode.label)),
          ],
          onChanged: (v) => onChanged(v ?? MenuMode.regular),
        ),
        const SizedBox(height: 12),
        const StoreHelpText(
          'Define como o agente consulta e vende os itens do cardápio. No modo '
          'marmitex, o cardápio varia por dia da semana.',
        ),
      ],
    );
  }
}

/// Gatilho de abandono (`store.abandonmentTriggerStage`): a partir de qual
/// etapa o cliente entra no funil e liga o cronômetro de recuperação.
class AbandonmentStageEditor extends StatelessWidget {
  const AbandonmentStageEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.disabled = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return StoreSection(
      label: 'Gatilho de abandono',
      children: [
        _StoreDropdown<String>(
          value: value,
          enabled: !disabled,
          items: [
            for (final stage in kAbandonmentStages)
              DropdownMenuItem(value: stage.value, child: Text(stage.label)),
          ],
          onChanged: (v) => onChanged(v ?? kDefaultAbandonmentStage),
        ),
        const SizedBox(height: 12),
        const StoreHelpText(
          'Escolha em qual etapa do fluxo o cliente passa a contar como "no '
          'funil" e tem o cronômetro de recuperação automática ativado.',
        ),
      ],
    );
  }
}

/// Dropdown no estilo escuro dos demais campos da Loja.
class _StoreDropdown<T> extends StatelessWidget {
  const _StoreDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.enabled,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          icon: const Icon(Icons.expand_more, color: AppColors.textSecondary),
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 14),
          items: items,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}
