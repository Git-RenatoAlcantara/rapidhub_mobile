import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// `true` nas três plataformas desktop; usado para blindar tudo que depende de
/// janela/bandeja e não existe em mobile/web.
bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Instância viva do gerenciador — mantida em variável de topo para os
/// listeners não serem coletados pelo GC.
_DesktopManager? _manager;

/// Argumento que o Windows passa ao iniciar o app pelo autostart. Sinaliza para
/// subir direto na bandeja, sem abrir a janela na cara do operador.
const String kStartHiddenFlag = '--start-hidden';

/// Prepara janela, ícone de bandeja e autostart. No-op fora do desktop.
///
/// Deve rodar depois de `WidgetsFlutterBinding.ensureInitialized()` e antes do
/// `runApp`. Assim a ponte de impressão ([PrintServer]) fica sempre acessível:
/// o app inicia com o Windows e continua servindo minimizado na bandeja.
///
/// [args] são os argumentos de linha de comando do `main` — quando trazem
/// [kStartHiddenFlag] (caso do autostart), a janela nasce escondida.
Future<void> setupDesktop(List<String> args) async {
  if (!isDesktop) return;

  await windowManager.ensureInitialized();
  // Fechar no "X" esconde em vez de encerrar — a ponte precisa seguir de pé.
  await windowManager.setPreventClose(true);

  final info = await PackageInfo.fromPlatform();
  launchAtStartup.setup(
    appName: info.appName,
    appPath: Platform.resolvedExecutable,
    // Boot pelo Windows entra escondido; abrir o app à mão (sem a flag) mostra.
    args: [kStartHiddenFlag],
  );
  // Liga o início automático por padrão (idempotente — reescreve a chave).
  await launchAtStartup.enable();

  _manager = _DesktopManager();
  await _manager!.init();

  if (args.contains(kStartHiddenFlag)) {
    await windowManager.hide();
  }
}

class _DesktopManager with WindowListener, TrayListener {
  Future<void> init() async {
    windowManager.addListener(this);
    trayManager.addListener(this);
    await _buildTray();
  }

  Future<void> _buildTray() async {
    await trayManager.setIcon('assets/icon/tray.ico');
    await trayManager.setToolTip('RapidHub — impressão');
    final enabled = await launchAtStartup.isEnabled();
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: 'Abrir RapidHub'),
      MenuItem.separator(),
      MenuItem.checkbox(
        key: 'startup',
        label: 'Iniciar com o Windows',
        checked: enabled,
      ),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Sair'),
    ]));
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  // --- Bandeja ---------------------------------------------------------------

  @override
  void onTrayIconMouseDown() => _show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem item) async {
    switch (item.key) {
      case 'show':
        await _show();
      case 'startup':
        // Alterna e reflete o novo estado no check do menu.
        if (await launchAtStartup.isEnabled()) {
          await launchAtStartup.disable();
        } else {
          await launchAtStartup.enable();
        }
        await _buildTray();
      case 'quit':
        await _quit();
    }
  }

  // --- Janela ----------------------------------------------------------------

  @override
  void onWindowClose() async {
    // Intercepta o "X": esconde para a bandeja em vez de encerrar o processo.
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }

  Future<void> _quit() async {
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}
