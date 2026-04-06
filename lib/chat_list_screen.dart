import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'chat_screen.dart';
import 'login_screen.dart';
import 'org_selection_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _storage = const FlutterSecureStorage();

  List<dynamic> _chats = [];
  bool _isLoading = true;
  String _errorMessage = '';

  final String baseUrl =
      "https://jvcftgdf.brs.devtunnels.ms:3000"; // ✅ Sem a porta no final se for https!

  @override
  void initState() {
    super.initState();
    _carregarChats();
  }

  Future<void> _carregarChats() async {
    try {
      String? token = await _storage.read(key: 'session_token');
      print("Token lido do cofre: $token");

      final response = await http.get(
        Uri.parse('$baseUrl/api/chats'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print("Status da Resposta: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _chats = data['chats'] ?? [];
          _isLoading = false;
        });
      } else {
        print("Corpo da resposta de erro: ${response.body}");
        setState(() {
          _errorMessage =
              'Erro ao carregar conversas. (Código: ${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      // ✅ IMPRIME O ERRO REAL NO TERMINAL PARA NÓS LERMOS!
      print("🕵️ ERRO FATAL DE CONEXÃO: $e");

      setState(() {
        _errorMessage = 'Erro de conexão. Verifica a tua internet.';
        _isLoading = false;
      });
    }
  }

  Future<void> _fazerLogout() async {
    final token = await _storage.read(key: 'session_token');
    await _storage.delete(key: 'session_token');

    try {
      await http.post(
        Uri.parse('$baseUrl/api/auth/sign-out'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
    } catch (e) {
      print(
          "Aviso: Backend incontactável para o sign-out, mas token local foi apagado.");
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text('Minhas Conversas',
            style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: Colors.blue),
            tooltip: 'Trocar Organização',
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => const OrgSelectionScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Sair',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF161B22),
                  title: const Text('Terminar Sessão',
                      style: TextStyle(color: Colors.white)),
                  content: const Text(
                      'Tens a certeza que queres sair da tua conta?',
                      style: TextStyle(color: Colors.grey)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar',
                          style: TextStyle(color: Colors.blue)),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _fazerLogout();
                      },
                      child: const Text('Sair',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Text(_errorMessage,
                      style: const TextStyle(color: Colors.redAccent)))
              : _chats.isEmpty
                  ? const Center(
                      child: Text('Nenhuma conversa encontrada.',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _chats.length,
                      itemBuilder: (context, index) {
                        final chat = _chats[index];

                        // ✅ Lemos diretamente as propriedades mapeadas no teu backend
                        final chatId = chat['id'];
                        final nomeContato = chat['name'] ?? 'Desconhecido';
                        final ultimaMensagem =
                            chat['lastMessage'] ?? 'Sem mensagens';
                        final tempo = chat['time'] ?? '';
                        final unreadCount = chat['unreadCount'] ?? 0;
                        final avatarUrl = (chat['avatar'] != null &&
                                chat['avatar'].toString().isNotEmpty)
                            ? chat['avatar']
                            : null;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          // Mostra a foto ou um ícone padrão se não tiver
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue[800],
                            backgroundImage: avatarUrl != null
                                ? NetworkImage(avatarUrl)
                                : null,
                            child: avatarUrl == null
                                ? const Icon(Icons.person, color: Colors.white)
                                : null,
                          ),
                          title: Text(
                            nomeContato,
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: unreadCount > 0
                                    ? FontWeight.bold
                                    : FontWeight.normal),
                          ),
                          subtitle: Text(
                            ultimaMensagem,
                            style: TextStyle(
                              color: unreadCount > 0
                                  ? Colors.white70
                                  : Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Coluna com o tempo e a "bolinha" de mensagens não lidas
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                tempo,
                                style: TextStyle(
                                    color: unreadCount > 0
                                        ? Colors.greenAccent
                                        : Colors.grey,
                                    fontSize: 12),
                              ),
                              if (unreadCount > 0) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Colors.greenAccent,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    unreadCount.toString(),
                                    style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ]
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ChatScreen(chatId: chatId),
                              ),
                            );
                          },
                        );
                      },
                    ),
    );
  }
}
