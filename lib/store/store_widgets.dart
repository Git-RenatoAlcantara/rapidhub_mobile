import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Casca de uma seção da Loja: rótulo em maiúsculas + card com o conteúdo.
/// Espelha o padrão visual dos editores da loja no webapp.
class StoreSection extends StatelessWidget {
  const StoreSection({
    super.key,
    required this.label,
    required this.children,
  });

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// Linha com checkbox + label, no estilo escuro do app.
class StoreCheckbox extends StatelessWidget {
  const StoreCheckbox({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: enabled ? (v) => onChanged(v ?? false) : null,
                activeColor: AppColors.primary,
                side: const BorderSide(color: AppColors.borderStrong),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Texto de ajuda (legenda) das seções.
class StoreHelpText extends StatelessWidget {
  const StoreHelpText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12.5,
        height: 1.5,
      ),
    );
  }
}

/// Campo de texto compacto padronizado para os editores da loja.
class StoreField extends StatelessWidget {
  const StoreField({
    super.key,
    required this.controller,
    this.hint,
    this.label,
    this.enabled = true,
    this.keyboardType,
    this.onChanged,
    this.width,
    this.errorBorderColor,
    this.prefixIcon,
  });

  final TextEditingController controller;
  final String? hint;
  final String? label;
  final bool enabled;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final double? width;
  final Color? errorBorderColor;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder borderWith(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: width),
        );

    final border = errorBorderColor ?? AppColors.borderStrong;

    final field = TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        filled: true,
        fillColor: AppColors.background,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, color: AppColors.textSecondary, size: 18),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: borderWith(border),
        focusedBorder: borderWith(
            errorBorderColor ?? AppColors.primary, errorBorderColor != null ? 1 : 1.5),
        disabledBorder: borderWith(AppColors.border),
        border: borderWith(border),
      ),
    );

    return width == null ? field : SizedBox(width: width, child: field);
  }
}
