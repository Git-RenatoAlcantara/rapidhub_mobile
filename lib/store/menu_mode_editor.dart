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

/// Regra de preço da pizza meio-a-meio (`store.halfPriceRule`).
class HalfPriceRuleEditor extends StatelessWidget {
  const HalfPriceRuleEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.disabled = false,
  });

  /// `''` = desligado; `expensive` ou `average`.
  final String value;
  final ValueChanged<String> onChanged;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return StoreSection(
      label: 'Pizza meio a meio',
      children: [
        _StoreDropdown<String>(
          value: value,
          enabled: !disabled,
          items: [
            for (final rule in kHalfPriceRules)
              DropdownMenuItem(value: rule.value, child: Text(rule.label)),
          ],
          onChanged: (v) => onChanged(v ?? ''),
        ),
        const SizedBox(height: 12),
        const StoreHelpText(
          'Como cobrar uma pizza com dois sabores. Só entram no meio a meio os '
          'produtos marcados como "aceita meio a meio" no cardápio. Desligado, '
          'o agente oferece sabor único em vez de cobrar duas pizzas.',
        ),
      ],
    );
  }
}

/// Cupom que acompanha a mensagem de recuperação de abandono
/// (`store.abandonmentCouponId`).
class AbandonmentCouponEditor extends StatelessWidget {
  const AbandonmentCouponEditor({
    super.key,
    required this.value,
    required this.coupons,
    required this.onChanged,
    this.disabled = false,
  });

  /// `''` = só o lembrete, sem cupom.
  final String value;

  /// Cupons ativos, no formato `(id, rótulo)`. Vazio esconde o seletor.
  final List<CouponChoice> coupons;

  final ValueChanged<String> onChanged;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return StoreSection(
      label: 'Cupom na recuperação',
      children: [
        if (coupons.isEmpty)
          const StoreHelpText(
            'Nenhum cupom ativo. Crie um em Campanhas para usar aqui.',
          )
        else ...[
          _StoreDropdown<String>(
            // O cupom salvo pode ter sido desativado ou excluído desde então;
            // um valor sem item correspondente quebraria o DropdownButton.
            value: coupons.any((c) => c.id == value) ? value : '',
            enabled: !disabled,
            items: [
              const DropdownMenuItem(
                  value: '', child: Text('Sem cupom (só o lembrete)')),
              for (final c in coupons)
                DropdownMenuItem(value: c.id, child: Text(c.label)),
            ],
            onChanged: (v) => onChanged(v ?? ''),
          ),
          const SizedBox(height: 12),
          const StoreHelpText(
            'O cliente que sumiu recebe um cupom junto do lembrete. Se o cupom '
            'for exclusivo por cliente, o código sai personalizado — e na '
            'próxima compra o desconto entra sozinho.',
          ),
        ],
      ],
    );
  }
}

/// Cupom no formato mínimo que o seletor da Loja precisa. Evita que a tela da
/// Loja dependa dos modelos do módulo de Campanhas.
class CouponChoice {
  const CouponChoice({required this.id, required this.label});
  final String id;
  final String label;
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
