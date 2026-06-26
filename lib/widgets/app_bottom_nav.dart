import 'package:flutter/material.dart';

import '../chat_list_screen.dart';
import '../contacts_screen.dart';
import '../reports_screen.dart';
import '../profile_screen.dart';
import '../theme/app_theme.dart';

/// Barra de navegação inferior compartilhada entre as abas principais.
///
/// Cada tela passa o seu [currentIndex]. Tocar numa aba diferente troca de
/// tela com `pushReplacement` (sem animação) para dar a sensação de abas.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.currentIndex});

  final int currentIndex;

  void _go(BuildContext context, int index) {
    if (index == currentIndex) return;

    Widget target;
    switch (index) {
      case 0:
        target = const ChatListScreen();
        break;
      case 1:
        target = const ContactsScreen();
        break;
      case 2:
        target = const ReportsScreen();
        break;
      case 3:
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
            item(0, Icons.chat_bubble_outline, 'Conversas'),
            item(1, Icons.people_outline, 'Contatos'),
            item(2, Icons.bar_chart_outlined, 'Relatórios'),
            item(3, Icons.person_outline, 'Perfil'),
          ],
        ),
      ),
    );
  }
}
