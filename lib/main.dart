import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// Importa os teus ecrãs
import 'splash_screen.dart';
import 'theme/app_theme.dart';

/// Comportamento de scroll estilo mobile: sem a barra de rolagem que o desktop
/// (Windows/web) desenha por padrão, mas permitindo arrastar com o mouse além
/// da roda e do toque. Mantém o app com a mesma aparência do celular.
class _MobileScrollBehavior extends MaterialScrollBehavior {
  const _MobileScrollBehavior();

  @override
  Widget buildScrollbar(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

void main() {
  // Garante que os widgets do Flutter estão inicializados antes de correr a app
  WidgetsFlutterBinding.ensureInitialized();
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
      // Sem barras de rolagem estilo desktop — mantém a cara de app mobile.
      scrollBehavior: const _MobileScrollBehavior(),

      // A SplashScreen reproduz o video da marca e, ao terminar, decide
      // entre OrgSelectionScreen (com sessão) ou LoginScreen (sem sessão).
      home: const SplashScreen(),
    );
  }
}
