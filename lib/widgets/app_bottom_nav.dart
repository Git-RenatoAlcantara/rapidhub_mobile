import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'home_shell.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.currentIndex});

  final int currentIndex;

  void _go(BuildContext context, int index) {
    if (index == currentIndex) return;
    if (index < 0 || index >= AppTab.values.length) return;

    // Navega para o [HomeShell], e não para a tela solta: assim a janela do
    // Windows pode ser alargada depois e o layout de desktop assume no lugar.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => HomeShell(tab: AppTab.values[index]),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // No layout de desktop quem navega é a sidebar.
    if (DesktopScope.of(context)) return const SizedBox.shrink();

    Widget item(int index, IconData icon, String label) {
      final active = index == currentIndex;
      final color = active ? AppColors.primary : AppColors.textSecondary;
      return Expanded(
        child: InkWell(
          onTap: () => _go(context, index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.normal)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            item(0, Icons.restaurant_menu_outlined, 'Cardápio'),
            item(1, Icons.receipt_long_outlined, 'Pedidos'),
            item(2, Icons.chat_bubble_outline, 'Conversas'),
            item(3, Icons.settings_outlined, 'Configurações'),
            item(4, Icons.person_outline, 'Perfil'),
          ],
        ),
      ),
    );
  }
}
