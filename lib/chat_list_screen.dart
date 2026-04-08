import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'chat_screen.dart';
import 'config.dart';
import 'login_screen.dart';
import 'org_selection_screen.dart';

enum _ChatListTab {
  ai,
  ativos,
  grupos,
}

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  StreamSubscription<dynamic>? _ticketsStreamSubscription;

  List<Map<String, dynamic>> _chats = <Map<String, dynamic>>[];
  _ChatListTab _activeTab = _ChatListTab.ativos;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _carregarChats();
    _startListeningToChatListUpdates();
  }

  Future<void> _carregarChats() async {
    try {
      final token = await _storage.read(key: 'session_token');
      final response = await http.get(
        Uri.parse('$baseUrl/api/chats'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);
        final List<dynamic> rawChats =
            data is Map && data['chats'] is List ? data['chats'] as List : [];
        final chats = rawChats
            .whereType<Map>()
            .map((chat) => _normalizeChat(Map<String, dynamic>.from(chat)))
            .toList();

        setState(() {
          _chats = chats;
          _isLoading = false;
        });
        _hydrateChatsContactMeta();
      } else {
        setState(() {
          _errorMessage =
              'Erro ao carregar conversas. (Codigo: ${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar chats: $e');
      setState(() {
        _errorMessage = 'Erro de conexao. Verifica a tua internet.';
        _isLoading = false;
      });
    }
  }

  Future<void> _startListeningToChatListUpdates() async {
    final token = await _storage.read(key: 'session_token');
    await _ticketsStreamSubscription?.cancel();

    _ticketsStreamSubscription = SSEClient.subscribeToSSE(
      method: SSERequestType.GET,
      url: '$baseUrl/api/chats/stream',
      header: {
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Authorization': 'Bearer ${token ?? ''}',
      },
    ).listen(
      (event) {
        final payload = event.data;
        if (payload == null || payload.isEmpty) {
          return;
        }

        try {
          final dynamic decoded = jsonDecode(payload);
          if (decoded is! Map<String, dynamic>) {
            return;
          }

          final eventType = _asString(decoded['type']).toLowerCase();
          if (eventType != 'ticket_update') {
            return;
          }

          final dynamic ticketRaw = decoded['ticket'];
          if (ticketRaw is! Map) {
            return;
          }

          final ticket = Map<String, dynamic>.from(ticketRaw);
          final ticketId = _asString(decoded['ticketId']).isNotEmpty
              ? _asString(decoded['ticketId'])
              : _asString(ticket['id']);
          if (ticketId.isEmpty) {
            return;
          }

          ticket['id'] = ticketId;
          ticket['time'] = _formatRelativeTime(ticket['time']);

          if (!mounted) {
            return;
          }

          setState(() {
            _upsertChat(ticket);
          });
          _hydrateChatsContactMeta();
        } catch (e) {
          debugPrint('Erro ao processar SSE da lista: $e');
        }
      },
      onError: (error) {
        debugPrint('Erro no SSE da lista de conversas: $error');
        if (mounted) {
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              _startListeningToChatListUpdates();
            }
          });
        }
      },
    );
  }

  void _upsertChat(Map<String, dynamic> incomingChat) {
    final normalizedIncoming = _normalizeChat(incomingChat);
    final incomingChatId = _asString(normalizedIncoming['id']);
    if (incomingChatId.isEmpty) {
      return;
    }

    final existingIndex = _chats.indexWhere(
      (chat) => _asString(chat['id']) == incomingChatId,
    );

    if (existingIndex >= 0) {
      final merged = {
        ..._chats[existingIndex],
        ...normalizedIncoming,
      };
      _chats.removeAt(existingIndex);
      _chats.insert(0, merged);
      return;
    }

    _chats.insert(0, normalizedIncoming);
  }

  Future<void> _hydrateChatsContactMeta() async {
    if (_chats.isEmpty) {
      return;
    }

    final token = await _storage.read(key: 'session_token');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    final contactIdByChatId = <String, String>{};
    final connectionIdByChatId = <String, String>{};
    final connectionLabelByChatId = <String, String>{};
    final missingContactIdsFor = <String>[];

    for (final chat in _chats) {
      final chatId = _asString(chat['id']);
      if (chatId.isEmpty) {
        continue;
      }

      final knownConnectionId = _asString(chat['connectionId']);
      if (knownConnectionId.isNotEmpty) {
        connectionIdByChatId[chatId] = knownConnectionId;
      }

      final ticketConnection = _extractConnectionLabel(chat);
      if (ticketConnection.isNotEmpty) {
        connectionLabelByChatId[chatId] = ticketConnection;
      }

      final contactId = _asString(chat['contactId']);
      if (contactId.isNotEmpty) {
        contactIdByChatId[chatId] = contactId;
      } else {
        missingContactIdsFor.add(chatId);
      }
    }

    if (missingContactIdsFor.isNotEmpty) {
      final responses = await Future.wait(
        missingContactIdsFor.map(
          (chatId) => http.get(
            Uri.parse('$baseUrl/api/chats/$chatId'),
            headers: headers,
          ),
        ),
      );

      for (var i = 0; i < responses.length; i++) {
        final resp = responses[i];
        if (resp.statusCode != 200) {
          continue;
        }
        try {
          final decoded = jsonDecode(resp.body);
          if (decoded is! Map<String, dynamic>) {
            continue;
          }
          final rawChat = decoded['chat'];
          if (rawChat is! Map) {
            continue;
          }
          final details = _normalizeChat(Map<String, dynamic>.from(rawChat));
          final contactId = _asString(details['contactId']);
          final connectionId = _asString(details['connectionId']);
          final ticketConnection = _extractConnectionLabel(details);

          if (contactId.isNotEmpty) {
            contactIdByChatId[missingContactIdsFor[i]] = contactId;
          }
          if (connectionId.isNotEmpty) {
            connectionIdByChatId[missingContactIdsFor[i]] = connectionId;
          }
          if (ticketConnection.isNotEmpty) {
            connectionLabelByChatId[missingContactIdsFor[i]] = ticketConnection;
          }
        } catch (_) {}
      }
    }

    if (contactIdByChatId.isEmpty && connectionIdByChatId.isEmpty) {
      return;
    }

    final contactsById = <String, Map<String, dynamic>>{};
    if (contactIdByChatId.isNotEmpty) {
      try {
        final contactsResp = await http.get(
          Uri.parse('$baseUrl/api/contacts'),
          headers: headers,
        );
        if (contactsResp.statusCode == 200) {
          final decodedContacts = jsonDecode(contactsResp.body);
          if (decodedContacts is Map<String, dynamic>) {
            final rawContacts = decodedContacts['contacts'];
            if (rawContacts is List) {
              for (final item in rawContacts) {
                if (item is! Map) {
                  continue;
                }
                final contact = Map<String, dynamic>.from(item);
                final id = _asString(contact['id']);
                if (id.isNotEmpty) {
                  contactsById[id] = contact;
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Erro ao carregar contatos para meta: $e');
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _chats = _chats.map((chat) {
        final chatId = _asString(chat['id']);
        final contactId =
            contactIdByChatId[chatId] ?? _asString(chat['contactId']);
        final connectionId =
            connectionIdByChatId[chatId] ?? _asString(chat['connectionId']);
        final connectionLabel = _firstNonEmpty([
          _extractConnectionLabel(chat),
          connectionLabelByChatId[chatId] ?? '',
        ]);

        final baseChat = {
          ...chat,
          if (contactId.isNotEmpty) 'contactId': contactId,
          if (connectionId.isNotEmpty) 'connectionId': connectionId,
          if (connectionLabel.isNotEmpty) 'connection': connectionLabel,
        };

        final contact = contactId.isNotEmpty ? contactsById[contactId] : null;
        if (contact == null) {
          return baseChat;
        }

        final tags = <String>[];
        final rawTags = contact['tags'];
        if (rawTags is List) {
          for (final tag in rawTags) {
            final value = _asString(tag).trim();
            if (value.isNotEmpty) {
              tags.add(value);
            }
          }
        }

        return {
          ...baseChat,
          'contactTags': tags,
        };
      }).toList();
    });
  }

  bool _isAiChat(Map<String, dynamic> chat) {
    final status = _asString(chat['ticketStatus']).toLowerCase();
    if (status == 'pending') {
      return true;
    }
    if (status == 'open' || status == 'closed') {
      return false;
    }
    return _asString(chat['agent']).isEmpty;
  }

  bool _isAtivoChat(Map<String, dynamic> chat) {
    final status = _asString(chat['ticketStatus']).toLowerCase();
    if (status == 'open') {
      return true;
    }
    if (status == 'pending' || status == 'closed') {
      return false;
    }
    return _asString(chat['agent']).isNotEmpty;
  }

  bool _isGrupoChat(Map<String, dynamic> chat) {
    final status = _asString(chat['ticketStatus']).toLowerCase();
    final isGroup = chat['isGroup'] == true;
    return isGroup && status != 'closed';
  }

  List<Map<String, dynamic>> _visibleChats() {
    if (_activeTab == _ChatListTab.ai) {
      return _chats.where(_isAiChat).toList();
    }
    if (_activeTab == _ChatListTab.ativos) {
      return _chats.where(_isAtivoChat).toList();
    }
    return _chats.where(_isGrupoChat).toList();
  }

  String _asString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  String _firstNonEmpty(List<String> values, {String fallback = ''}) {
    for (final value in values) {
      if (value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return fallback;
  }

  String _formatConnectionLabel(String name, String phone) {
    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    if (cleanName.isNotEmpty && cleanPhone.isNotEmpty) {
      return '$cleanName - $cleanPhone';
    }
    if (cleanPhone.isNotEmpty) {
      return cleanPhone;
    }
    return cleanName;
  }

  Map<String, dynamic> _normalizeChat(Map<String, dynamic> chat) {
    final normalized = Map<String, dynamic>.from(chat);
    final connectionLabel = _extractConnectionLabel(normalized);
    if (connectionLabel.isNotEmpty) {
      normalized['connection'] = connectionLabel;
    }
    return normalized;
  }

  String _extractConnectionLabel(Map<String, dynamic> chat) {
    final dynamic connectionRaw = chat['connection'];

    String directConnection = '';
    String nestedName = '';
    String nestedPhone = '';
    String nestedLabel = '';

    if (connectionRaw is String) {
      directConnection = connectionRaw.trim();
    } else if (connectionRaw is Map) {
      final connectionMap = Map<String, dynamic>.from(connectionRaw);
      nestedName = _firstNonEmpty([
        _asString(connectionMap['name']),
        _asString(connectionMap['displayName']),
      ]);
      nestedPhone = _firstNonEmpty([
        _asString(connectionMap['phone']),
        _asString(connectionMap['number']),
      ]);
      nestedLabel = _firstNonEmpty([
        _asString(connectionMap['label']),
        _formatConnectionLabel(nestedName, nestedPhone),
      ]);
    }

    final name = _firstNonEmpty([
      _asString(chat['connectionName']),
      _asString(chat['connection_name']),
      _asString(chat['connectionDisplayName']),
      nestedName,
    ]);

    final phone = _firstNonEmpty([
      _asString(chat['connectionPhone']),
      _asString(chat['connection_phone']),
      nestedPhone,
    ]);

    return _firstNonEmpty([
      _formatConnectionLabel(name, phone),
      _asString(chat['connectionLabel']),
      _asString(chat['connection_label']),
      nestedLabel,
      directConnection,
      phone,
      name,
    ]);
  }

  String _formatRelativeTime(dynamic rawTime) {
    final text = _asString(rawTime);
    if (text.isEmpty) {
      return '';
    }

    final parsedDate = DateTime.tryParse(text);
    if (parsedDate == null) {
      return text;
    }

    final now = DateTime.now();
    final diff = now.difference(parsedDate.toLocal());

    if (diff.inMinutes < 1) {
      return 'agora';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d';
    }

    final day = parsedDate.day.toString().padLeft(2, '0');
    final month = parsedDate.month.toString().padLeft(2, '0');
    return '$day/$month';
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
    } catch (_) {}

    if (!mounted) {
      return;
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  Widget _buildChatBadge({
    required IconData icon,
    required String text,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF131C27),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accentColor.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: accentColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: accentColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab({
    required String label,
    required int count,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              color: active ? Colors.blue : const Color(0xFF1E2733),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? Colors.blueAccent : Colors.white12,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: active ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.white10,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      color: active ? Colors.blue[800] : Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ticketsStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aiCount = _chats.where(_isAiChat).length;
    final ativosCount = _chats.where(_isAtivoChat).length;
    final gruposCount = _chats.where(_isGrupoChat).length;
    final visibleChats = _visibleChats();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title:
            const Text('Minhas Conversas', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: Colors.blue),
            tooltip: 'Trocar Organizacao',
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const OrgSelectionScreen(),
                ),
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
                  title: const Text(
                    'Terminar Sessao',
                    style: TextStyle(color: Colors.white),
                  ),
                  content: const Text(
                    'Tens a certeza que queres sair da tua conta?',
                    style: TextStyle(color: Colors.grey),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _fazerLogout();
                      },
                      child: const Text(
                        'Sair',
                        style: TextStyle(color: Colors.redAccent),
                      ),
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
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                )
              : Column(
                  children: [
                    Container(
                      color: const Color(0xFF161B22),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: Row(
                        children: [
                          _buildTab(
                            label: 'IA',
                            count: aiCount,
                            active: _activeTab == _ChatListTab.ai,
                            onTap: () {
                              setState(() => _activeTab = _ChatListTab.ai);
                            },
                          ),
                          _buildTab(
                            label: 'Ativos',
                            count: ativosCount,
                            active: _activeTab == _ChatListTab.ativos,
                            onTap: () {
                              setState(() => _activeTab = _ChatListTab.ativos);
                            },
                          ),
                          _buildTab(
                            label: 'Grupos',
                            count: gruposCount,
                            active: _activeTab == _ChatListTab.grupos,
                            onTap: () {
                              setState(() => _activeTab = _ChatListTab.grupos);
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: visibleChats.isEmpty
                          ? Center(
                              child: Text(
                                _activeTab == _ChatListTab.ai
                                    ? 'Nenhuma conversa em atendimento por IA.'
                                    : _activeTab == _ChatListTab.ativos
                                        ? 'Nenhuma conversa ativa encontrada.'
                                        : 'Nenhum grupo encontrado.',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: visibleChats.length,
                              itemBuilder: (context, index) {
                                final chat = visibleChats[index];
                                final chatId = chat['id'];
                                final nomeContato = chat['name'] ?? 'Desconhecido';
                                final ultimaMensagem =
                                    chat['lastMessage'] ?? 'Sem mensagens';
                                final tempo = chat['time'] ?? '';
                                final ticketStatus =
                                    _asString(chat['ticketStatus']).toLowerCase();
                                final rawConnection = _asString(chat['connection']).trim();
                                final connection = rawConnection;
                                final agent = _asString(chat['agent']);
                                final contactTagsRaw = chat['contactTags'];
                                final contactTags = contactTagsRaw is List
                                    ? contactTagsRaw
                                        .map((tag) => _asString(tag).trim())
                                        .where((tag) => tag.isNotEmpty)
                                        .toList()
                                    : <String>[];
                                final unreadCount = chat['unreadCount'] ?? 0;
                                final avatarUrl = (chat['avatar'] != null &&
                                        chat['avatar'].toString().isNotEmpty)
                                    ? chat['avatar']
                                    : null;

                                return ListTile(
                                  isThreeLine: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.blue[800],
                                    backgroundImage: avatarUrl != null
                                        ? NetworkImage(avatarUrl)
                                        : null,
                                    child: avatarUrl == null
                                        ? const Icon(
                                            Icons.person,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                  title: Text(
                                    nomeContato,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: unreadCount > 0
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        ultimaMensagem,
                                        style: TextStyle(
                                          color: unreadCount > 0
                                              ? Colors.white70
                                              : Colors.grey,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 5),
                                          Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          if (connection.isNotEmpty)
                                            _buildChatBadge(
                                              icon: Icons.phone_enabled,
                                              text: connection,
                                              accentColor: Colors.tealAccent,
                                            ),
                                          if (agent.isNotEmpty)
                                            _buildChatBadge(
                                              icon: Icons.person,
                                              text: agent,
                                              accentColor:
                                                  const Color(0xFF93C5FD),
                                            ),
                                          ...contactTags.take(2).map(
                                            (tag) => _buildChatBadge(
                                              icon: Icons.local_offer,
                                              text: tag,
                                              accentColor:
                                                  const Color(0xFFD8B4FE),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
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
                                          fontSize: 12,
                                        ),
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
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ]
                                    ],
                                  ),
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ChatScreen(
                                          chatId: chatId,
                                          initialTicketStatus: ticketStatus,
                                          initialChatName: _asString(chat['name']),
                                          initialConnectionLabel: rawConnection,
                                          initialContactTags: contactTags,
                                        ),
                                      ),
                                    );
                                    if (mounted) {
                                      _carregarChats();
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
