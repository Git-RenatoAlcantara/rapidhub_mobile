import 'package:flutter/material.dart';

// Importa os teus ecrãs
import 'splash_screen.dart';
import 'theme/app_theme.dart';

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

      // A SplashScreen reproduz o video da marca e, ao terminar, decide
      // entre OrgSelectionScreen (com sessão) ou LoginScreen (sem sessão).
      home: const SplashScreen(),
    );
  }
}
