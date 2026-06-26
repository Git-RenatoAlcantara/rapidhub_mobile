import 'package:flutter/material.dart';

/// Logo oficial do RapidHub (mascote em balão de mensagem).
///
/// Centraliza o uso de `assets/icon/logo.png` para manter consistência
/// entre as telas (AppBars, etc.).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
