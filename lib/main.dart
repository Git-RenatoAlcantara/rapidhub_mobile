import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// Importa os teus ecrãs
import 'desktop/desktop_boot.dart';
import 'printing/print_server.dart';
import 'splash_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/home_shell.dart' show kDesktopBreakpoint;

/// Scroll adaptativo: em janela larga (Windows) desenha a barra de rolagem que
/// se espera de um app desktop; em tela de celular ela some, como antes.
/// Nos dois casos dá para arrastar com o mouse, além da roda e do toque.
class _AdaptiveScrollBehavior extends MaterialScrollBehavior {
  const _AdaptiveScrollBehavior();

  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    final wide = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    return wide ? super.buildScrollbar(context, child, details) : child;
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

Future<void> main(List<String> args) async {
  // Garante que os widgets do Flutter estão inicializados antes de correr a app
  WidgetsFlutterBinding.ensureInitialized();
  // No desktop: autostart com o Windows + janela que minimiza para a bandeja,
  // para o app seguir servindo a ponte de impressão sem ficar no caminho.
  await setupDesktop(args);
  // Sobe a ponte local para o site (navegador) imprimir na térmica pelo app.
  // Em mobile/web o start() é no-op.
  unawaited(PrintServer().start());
  runApp(const RapidhubApp());
}

class RapidhubApp extends StatelessWidget {
  const RapidhubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hubi',
      debugShowCheckedModeBanner: false,
      // Usamos o tema escuro como padrão para combinar com o teu sistema web
      theme: AppTheme.dark,
      scrollBehavior: const _AdaptiveScrollBehavior(),

      // A SplashScreen reproduz o video da marca e, ao terminar, decide
      // entre OrgSelectionScreen (com sessão) ou LoginScreen (sem sessão).
      home: const SplashScreen(),
    );
  }
}
