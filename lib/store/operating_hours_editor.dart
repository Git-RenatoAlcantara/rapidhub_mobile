import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'store_models.dart';
import 'store_widgets.dart';

/// Editor do horário de funcionamento da loja (bloqueio de pedidos fora do
/// horário). Janela única por dia; término menor que o início = vira a
/// meia-noite (ex.: 18:00–02:00).
class OperatingHoursEditor extends StatelessWidget {
  const OperatingHoursEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.disabled = false,
  });

  final OperatingHours value;
  final VoidCallback onChanged;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return StoreSection(
      label: 'Horário de funcionamento',
      children: [
        StoreCheckbox(
          value: value.enabled,
          label: 'Bloquear pedidos fora do horário',
          enabled: !disabled,
          onChanged: (v) {
            value.enabled = v;
            onChanged();
          },
        ),
        if (value.enabled) ...[
          const SizedBox(height: 14),
          _buildTimezone(),
          const SizedBox(height: 14),
          ...List.generate(value.days.length, _buildDayRow),
          const SizedBox(height: 12),
          const StoreHelpText(
            'Fora do horário, o agente avisa o cliente que a loja está fechada '
            '(e quando abre) e não registra pedidos. Para virar a madrugada, '
            'use término menor que o início — ex.: 18:00 às 02:00.',
          ),
        ],
      ],
    );
  }

  Widget _buildTimezone() {
    return Row(
      children: [
        const Icon(Icons.schedule, color: AppColors.textSecondary, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: InputDecorator(
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.background,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.borderStrong),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.borderStrong),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value.timezone,
                isExpanded: true,
                isDense: true,
                dropdownColor: AppColors.surfaceAlt,
                iconEnabledColor: AppColors.textSecondary,
                style:
                    const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                items: kTimezoneOptions
                    .map((tz) => DropdownMenuItem(
                          value: tz.value,
                          child: Text(tz.label, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: disabled
                    ? null
                    : (tz) {
                        if (tz == null) return;
                        value.timezone = tz;
                        onChanged();
                      },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDayRow(int index) {
    final day = value.days[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 118,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: day.active,
                    onChanged: disabled
                        ? null
                        : (v) {
                            day.active = v ?? false;
                            onChanged();
                          },
                    activeColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.borderStrong),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kWeekdayLabels[index],
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (day.active)
            Expanded(
              child: Row(
                children: [
                  _timeButton(index, isFrom: true),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('às',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ),
                  _timeButton(index, isFrom: false),
                ],
              ),
            )
          else
            const Expanded(
              child: Text('Fechado',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _timeButton(int index, {required bool isFrom}) {
    final day = value.days[index];
    final text = isFrom ? day.from : day.to;
    return Builder(
      builder: (context) => OutlinedButton(
        onPressed: disabled
            ? null
            : () async {
                final parts = text.split(':');
                final initial = TimeOfDay(
                  hour: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 18,
                  minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
                );
                final picked = await showTimePicker(
                  context: context,
                  initialTime: initial,
                  builder: (ctx, child) => MediaQuery(
                    data: MediaQuery.of(ctx)
                        .copyWith(alwaysUse24HourFormat: true),
                    child: child!,
                  ),
                );
                if (picked == null) return;
                final formatted =
                    '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                if (isFrom) {
                  day.from = formatted;
                } else {
                  day.to = formatted;
                }
                onChanged();
              },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.background,
          side: const BorderSide(color: AppColors.borderStrong),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
      ),
    );
  }
}
