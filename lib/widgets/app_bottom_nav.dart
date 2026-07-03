import 'package:flutter/material.dart';

import '../cardapio_screen.dart';
import '../pedidos_screen.dart';
import '../chat_list_screen.dart';
import '../profile_screen.dart';
import '../configuracoes_screen.dart';
import '../theme/app_theme.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.currentIndex});

  final int currentIndex;

  void _go(BuildContext context, int index) {
    if (index == currentIndex) return;

    Widget target;
    switch (index) {
      case 0:
        target = const CardapioScreen();
        break;
      case 1:
        target = const PedidosScreen();
        break;
      case 2:
        target = const ChatListScreen();
        break;
      case 3:
        target = const ConfiguracoesScreen();
        break;
      case 4:
        target = const ProfileScreen();
        break;
      default:
        return;
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => target,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
