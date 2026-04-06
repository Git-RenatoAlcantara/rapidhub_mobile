import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Importa os teus ecrãs
import 'login_screen.dart';
import 'org_selection_screen.dart';

void main() {
  // Garante que os widgets do Flutter estão inicializados antes de correr a app
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RapidhubApp());
}

class RapidhubApp extends StatelessWidget {
  const RapidhubApp({super.key});

  // Função que vai ao "cofre" ver se já temos um cookie de sessão guardado
  Future<bool> _verificarSeEstaLogado() async {
    const storage = FlutterSecureStorage();
    String? token = await storage.read(key: 'session_token');

    // Retorna verdadeiro se o token existir, falso se for nulo
    return token != null && token.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rapidhub',
      debugShowCheckedModeBanner: false,
      // Usamos o tema escuro como padrão para combinar com o teu sistema web
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        primaryColor: Colors.blue,
      ),

      // O FutureBuilder permite-nos mostrar um ecrã de carregamento enquanto
      // verificamos o armazenamento seguro
      home: FutureBuilder<bool>(
        future: _verificarSeEstaLogado(),
        builder: (context, snapshot) {
          // 1. Enquanto está à procura do cookie, mostra a rodinha a girar
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body:
                  Center(child: CircularProgressIndicator(color: Colors.blue)),
            );
          }

          // 2. O snapshot.data contém o resultado da nossa função (true ou false)
          final isLoggedIn = snapshot.data ?? false;

          // 3. A grande decisão: Para onde vamos?
          if (isLoggedIn) {
            // Se já tem login, vai direto para o Chat!
            // (Numa app real, aqui irias para um ecrã de "Lista de Chats")
            return const OrgSelectionScreen(); // ✅ Escolher organização primeiro
          } else {
            // Se não tem login, mostra o ecrã de Login
            return const LoginScreen();
          }
        },
      ),
    );
  }
}
