import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'menu_api.dart';

/// Editor dos grupos de opções de um produto (tamanho, borda, adicionais…).
///
/// Trabalha sobre cópias mutáveis dos modelos e devolve a lista inteira a cada
/// mudança — quem salva decide quando chamar a API, que substitui **todos** os
/// grupos de uma vez (`PUT /api/menu/products/[id]/options`).
class OptionGroupsEditor extends StatelessWidget {
  const OptionGroupsEditor({
    super.key,
    required this.groups,
    required this.onChanged,
    this.enabled = true,
  });

  final List<MenuOptionGroup> groups;
  final ValueChanged<List<MenuOptionGroup>> onChanged;
  final bool enabled;

  void _emit() => onChanged([...groups]);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Opções',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: enabled
                  ? () {
                      groups.add(MenuOptionGroup(name: ''));
                      _emit();
                    }
                  : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Novo grupo'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
        const Text(
          'Ex.: grupo "Tamanho" com as opções Pequena e Grande. O preço da '
          'opção é somado ao do produto.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (groups.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text('Nenhum grupo de opções.',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          )
        else
          for (var i = 0; i < groups.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _GroupCard(
                // A chave usa a identidade do objeto: sem ela, remover um grupo
                // do meio faria o Flutter reaproveitar o estado (e os textos)
                // do grupo seguinte.
                key: ObjectKey(groups[i]),
                group: groups[i],
                enabled: enabled,
                onRemove: () {
                  groups.removeAt(i);
                  _emit();
                },
                onChanged: _emit,
              ),
            ),
      ],
    );
  }
}

class _GroupCard extends StatefulWidget {
  const _GroupCard({
    super.key,
    required this.group,
    required this.onRemove,
    required this.onChanged,
    required this.enabled,
  });

  final MenuOptionGroup group;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  late final TextEditingController _name =
      TextEditingController(text: widget.group.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  enabled: widget.enabled,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: AppTheme.inputDecoration(
                    hint: 'Nome do grupo (ex.: Tamanho)',
                  ),
                  onChanged: (v) {
                    group.name = v;
                    widget.onChanged();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Remover grupo',
                onPressed: widget.enabled ? widget.onRemove : null,
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.danger, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: 'Mín.',
                  value: group.minSelect,
                  enabled: widget.enabled,
                  onChanged: (v) {
                    setState(() {
                      group.minSelect = v;
                      // O servidor força `maxSelect >= max(minSelect, 1)`;
                      // subir o mínimo acima do máximo aqui salvaria um grupo
                      // que ninguém consegue preencher.
                      if (group.maxSelect < group.minSelect) {
                        group.maxSelect = group.minSelect;
                      }
                    });
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  label: 'Máx.',
                  value: group.maxSelect,
                  min: 1,
                  enabled: widget.enabled,
                  onChanged: (v) {
                    setState(() {
                      group.maxSelect = v;
                      if (group.minSelect > group.maxSelect) {
                        group.minSelect = group.maxSelect;
                      }
                    });
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            group.isRequired
                ? 'Obrigatório: o cliente escolhe de ${group.minSelect} a '
                    '${group.maxSelect} opções.'
                : 'Opcional: o cliente escolhe até ${group.maxSelect} opções.',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const Divider(height: 24, color: AppColors.border),
          for (var i = 0; i < group.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _OptionRow(
                key: ObjectKey(group.options[i]),
                option: group.options[i],
                enabled: widget.enabled,
                onRemove: () {
                  setState(() => group.options.removeAt(i));
                  widget.onChanged();
                },
                onChanged: widget.onChanged,
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.enabled
                  ? () {
                      setState(() => group.options.add(MenuOption(name: '')));
                      widget.onChanged();
                    }
                  : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Adicionar opção'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatefulWidget {
  const _OptionRow({
    super.key,
    required this.option,
    required this.onRemove,
    required this.onChanged,
    required this.enabled,
  });

  final MenuOption option;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
  late final TextEditingController _name =
      TextEditingController(text: widget.option.name);

  late final TextEditingController _price = TextEditingController(
    text: widget.option.priceDelta == 0
        ? ''
        : widget.option.priceDelta.toStringAsFixed(2).replaceAll('.', ','),
  );

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: _name,
            enabled: widget.enabled,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 14),
            decoration: AppTheme.inputDecoration(hint: 'Opção'),
            onChanged: (v) {
              widget.option.name = v;
              widget.onChanged();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _price,
            enabled: widget.enabled,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 14),
            decoration: AppTheme.inputDecoration(hint: '+ R\$'),
            onChanged: (v) {
              final raw = v.trim().replaceAll('.', '').replaceAll(',', '.');
              // Campo vazio ou meio digitado ("1,") vale zero — não dá para
              // recusar a tecla, senão o operador não consegue apagar.
              widget.option.priceDelta = double.tryParse(raw) ?? 0;
              widget.onChanged();
            },
          ),
        ),
        IconButton(
          tooltip: 'Remover opção',
          onPressed: widget.enabled ? widget.onRemove : null,
          icon: const Icon(Icons.close,
              color: AppColors.textSecondary, size: 18),
        ),
      ],
    );
  }
}

/// Campo numérico com botões de −/+ (mín. e máx. de escolhas).
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.enabled,
    this.min = 0,
  });

  /// Teto do schema do servidor: até 50 opções por grupo.
  static const int _max = 50;

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final int min;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: (enabled && value > min)
                ? () => onChanged(value - 1)
                : null,
            icon: const Icon(Icons.remove, size: 16),
            color: AppColors.textSecondary,
          ),
          Text('$value',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: (enabled && value < _max)
                ? () => onChanged(value + 1)
                : null,
            icon: const Icon(Icons.add, size: 16),
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}
