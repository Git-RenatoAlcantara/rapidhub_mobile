import 'package:flutter/material.dart';

/// Paleta e tokens visuais do RapidHub.
///
/// Baseado nos layouts gerados no Stitch (ver `docs/stitch/`).
class AppColors {
  AppColors._();

  /// Fundo principal da aplicação.
  static const Color background = Color(0xFF0D1117);

  /// Superfícies elevadas: cards, sheets, bolhas de mensagem.
  static const Color surface = Color(0xFF161B22);

  /// Superfície ligeiramente mais clara (inputs, chips).
  static const Color surfaceAlt = Color(0xFF1C2430);

  /// Bordas sutis.
  static const Color border = Color(0xFF21262D);
  static const Color borderStrong = Color(0xFF30363D);

  /// Acento primário (azul da marca).
  static const Color primary = Color(0xFF2F81F7);
  static const Color primaryDim = Color(0xFF1F6FEB);

  /// Destaque secundário — usado para a IA.
  static const Color ai = Color(0xFFA371F7);

  /// Status de sucesso / online.
  static const Color success = Color(0xFF2ECC71);

  /// Alerta de erro.
  static const Color danger = Color(0xFFF85149);

  /// Texto principal.
  static const Color textPrimary = Color(0xFFE6EDF3);

  /// Texto secundário / legendas.
  static const Color textSecondary = Color(0xFF8B949E);
}

/// Tema escuro central do app.
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.background,
        primary: AppColors.primary,
        secondary: AppColors.ai,
        error: AppColors.danger,
        onPrimary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionHandleColor: AppColors.primary,
      ),
    );
  }

  /// Decoração padrão para campos de texto escuros.
  static InputDecoration inputDecoration({
    required String hint,
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    OutlineInputBorder borderWith(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.background,
      prefixIcon:
          prefixIcon == null ? null : Icon(prefixIcon, color: AppColors.textSecondary, size: 20),
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: borderWith(AppColors.borderStrong),
      focusedBorder: borderWith(AppColors.primary, 1.5),
      border: borderWith(AppColors.borderStrong),
    );
  }
}
