import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;

  const ChatScreen({super.key, required this.chatId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String baseUrl = "https://jvcftgdf.brs.devtunnels.ms:3000";
  final _storage = const FlutterSecureStorage();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _startListeningToMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final token = await _storage.read(key: 'session_token');
      final resp = await http.get(
        Uri.parse('$baseUrl/api/chats/${widget.chatId}/messages'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print("Messages status: ${resp.statusCode}");

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final messages = data['messages'] as List? ?? [];
        setState(() {
          _messages.addAll(
              messages.map((m) => Map<String, dynamic>.from(m)).toList());
          _isLoading = false;
        });
        _scrollToBottom();
      } else {
        print("Messages error: ${resp.body}");
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print("Erro ao carregar mensagens: $e");
      setState(() => _isLoading = false);
    }
  }

  void _startListeningToMessages() async {
    final streamUrl = '$baseUrl/api/chats/${widget.chatId}/stream';
    final token = await _storage.read(key: 'session_token');

    print("--SUBSCRIBING TO SSE---");

    SSEClient.subscribeToSSE(
      method: SSERequestType.GET,
      url: streamUrl,
      header: {
        "Accept": "text/event-stream",
        "Cache-Control": "no-cache",
        "Authorization": "Bearer ${token ?? ''}",
      },
    ).listen((event) {
      if (event.data != null && event.data!.isNotEmpty) {
        try {
          final data = jsonDecode(event.data!);
          // Handle MESSAGE_RECEIVED events from SSE
          if (data is Map<String, dynamic>) {
            final msgData = data['data'] ?? data;
            // Avoid duplicating messages already loaded
            final msgId = msgData['messageId'] ?? msgData['id'];
            final alreadyExists = _messages.any((m) => m['id'] == msgId);
            if (!alreadyExists && msgData['text'] != null) {
              setState(() {
                _messages.add(Map<String, dynamic>.from(msgData));
              });
              _scrollToBottom();
            }
          }
        } catch (e) {
          print("Erro ao ler mensagem SSE: $e");
        }
      }
    }, onError: (error) {
      print("Erro na conexão SSE: $error");
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    // Add optimistic message to UI
    setState(() {
      _messages.add({
        'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
        'text': text,
        'sender': 'user',
        'status': 'pending',
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
    _scrollToBottom();

    final token = await _storage.read(key: 'session_token');
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/chats/${widget.chatId}/send'),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"text": text, "type": "text"}),
      );
      print("Send status: ${resp.statusCode}");
      print("Send body: ${resp.body}");
    } catch (e) {
      print("Erro ao enviar: $e");
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    SSEClient.unsubscribeFromSSE();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text('Chat', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF161B22),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.blue))
                : _messages.isEmpty
                    ? const Center(
                        child: Text('Sem mensagens.',
                            style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          // sender "user" = outbound (agent), "bot" = inbound (customer)
                          final isMe = msg['sender'] == 'user';
                          final msgText = msg['text'] ?? msg['body'] ?? '';
                          final status = msg['status'] ?? '';

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? Colors.blue[700]
                                    : const Color(0xFF1E2733),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(12),
                                  topRight: const Radius.circular(12),
                                  bottomLeft: Radius.circular(isMe ? 12 : 0),
                                  bottomRight: Radius.circular(isMe ? 0 : 12),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    msgText,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  if (isMe && status == 'pending')
                                    const Padding(
                                      padding: EdgeInsets.only(top: 4),
                                      child: Icon(Icons.access_time,
                                          size: 12, color: Colors.white54),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: const Color(0xFF161B22),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Escreve uma mensagem...',
                        hintStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: const Color(0xFF0D1117),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: IconButton(
                      icon:
                          const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
