import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cardapio_screen.dart';
import '../chat_list_screen.dart';
import '../configuracoes_screen.dart';
import '../desktop/update_checker.dart';
import '../pedidos_screen.dart';
import '../profile_screen.dart';
import '../theme/app_theme.dart';

/// Largura a partir da qual o app assume o layout de desktop (sidebar lateral,
/// abas que preservam estado). Abaixo disso continua o layout de celular.
const double kDesktopBreakpoint = 900;

/// As abas principais, na mesma ordem usada pela barra inferior do celular.
enum AppTab {
  cardapio(Icons.restaurant_menu_outlined, 'Cardápio'),
  pedidos(Icons.receipt_long_outlined, 'Pedidos'),
  conversas(Icons.chat_bubble_outline, 'Conversas'),
  configuracoes(Icons.settings_outlined, 'Configurações'),
  perfil(Icons.person_outline, 'Perfil');

  const AppTab(this.icon, this.label);

  final IconData icon;
  final String label;

  Widget get screen {
    switch (this) {
      case AppTab.cardapio:
        return const CardapioScreen();
      case AppTab.pedidos:
        return const PedidosScreen();
      case AppTab.conversas:
        return const ChatListScreen();
      case AppTab.configuracoes:
        return const ConfiguracoesScreen();
      case AppTab.perfil:
        return const ProfileScreen();
    }
  }
}

/// Marca a subárvore que está dentro do layout de desktop. A barra inferior se
/// esconde ao encontrá-la — quem navega ali é a sidebar.
class DesktopScope extends InheritedWidget {
  const DesktopScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopScope>() != null;

  @override
  bool updateShouldNotify(DesktopScope oldWidget) => false;
}

/// Casca das telas principais: escolhe o layout pela largura da janela.
///
/// É o alvo de navegação das abas — tanto da sidebar (desktop) quanto da barra
/// inferior (celular). Assim, redimensionar a janela do Windows troca o layout
/// sem perder a aba atual.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, this.tab = AppTab.conversas});

  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kDesktopBreakpoint) {
          return _DesktopShell(initialTab: tab);
        }
        return tab.screen;
      },
    );
  }
}

/// Layout de desktop: sidebar fixa à esquerda e o conteúdo num [IndexedStack],
/// que mantém as telas vivas — trocar de aba não recarrega os pedidos nem
/// perde a rolagem das conversas.
class _DesktopShell extends StatefulWidget {
  const _DesktopShell({required this.initialTab});

  final AppTab initialTab;

  @override
  State<_DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<_DesktopShell> {
  late AppTab _tab = widget.initialTab;

  /// Acima disso o conteúdo para de esticar e fica centralizado — texto com
  /// linhas de 1900px é ilegível.
  static const double _maxContentWidth = 1400;

  String _version = '';
  UpdateInfo? _update;
  bool _updateDismissed = false;

  @override
  void initState() {
    super.initState();
    _loadVersionAndUpdate();
  }

  Future<void> _loadVersionAndUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final update = await const UpdateChecker().check();
    if (!mounted) return;
    setState(() {
      _version = info.version;
      _update = update;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showUpdate = _update != null && !_updateDismissed;
    return DesktopScope(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            if (showUpdate)
              _UpdateBar(
                info: _update!,
                onDismiss: () => setState(() => _updateDismissed = true),
              ),
            Expanded(
              child: Row(
                children: [
                  _Sidebar(
                    current: _tab,
                    version: _version,
                    onSelect: (t) => setState(() => _tab = t),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: _maxContentWidth),
                        child: IndexedStack(
                          index: _tab.index,
                          children: [for (final t in AppTab.values) t.screen],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Faixa fina no topo avisando que saiu versão nova, com botão que abre o
/// download do instalador no navegador.
class _UpdateBar extends StatelessWidget {
  const _UpdateBar({required this.info, required this.onDismiss});

  final UpdateInfo info;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.system_update, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nova versão ${info.version} disponível.',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(info.downloadUrl),
                mode: LaunchMode.externalApplication,
              ),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Atualizar',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              tooltip: 'Depois',
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.current,
    required this.version,
    required this.onSelect,
  });

  final AppTab current;
  final String version;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Text(
                'Hubi',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            for (final tab in AppTab.values)
              _SidebarItem(
                tab: tab,
                active: tab == current,
                onTap: () => onSelect(tab),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                version.isEmpty ? 'RapidHub' : 'RapidHub • $version',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  final AppTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color =
        widget.active ? AppColors.primary : AppColors.textSecondary;
    final background = widget.active
        ? AppColors.primary.withValues(alpha: 0.12)
        : (_hovered ? AppColors.surfaceAlt : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(widget.tab.icon, color: color, size: 20),
              const SizedBox(width: 12),
              Text(
                widget.tab.label,
                style: TextStyle(
                  color: widget.active ? AppColors.textPrimary : color,
                  fontSize: 14,
                  fontWeight:
                      widget.active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
