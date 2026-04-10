import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'config.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String? initialTicketStatus;
  final String? initialChatName;
  final String? initialConnectionLabel;
  final List<String>? initialContactTags;

  const ChatScreen({
    super.key,
    required this.chatId,
    this.initialTicketStatus,
    this.initialChatName,
    this.initialConnectionLabel,
    this.initialContactTags,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, dynamic>> _messages = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _ticketEvents = <Map<String, dynamic>>[];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  StreamSubscription<dynamic>? _sseSubscription;
  Map<String, dynamic>? _chatDetails;
  String? _connectionLabel;
  List<String> _contactTags = <String>[];
  bool _isLoading = true;
  bool _isAssumingConversation = false;

  // Media / recording state
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  bool _isSendingMedia = false;

  @override
  void initState() {
    super.initState();
    _loadChatDetails();
    _loadMessages();
    _loadTicketEvents();
    _startListeningToMessages();
  }

  // ───────────────────── MEDIA SENDING ─────────────────────

  Future<void> _sendMediaFile({
    required File file,
    required String type,
  }) async {
    if (_isSendingMedia) return;

    setState(() => _isSendingMedia = true);

    final fileName = file.path.split(Platform.pathSeparator).last;
    var mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    // lookupMimeType may not resolve .m4a; ensure audio MIME for recorded files
    if (type == 'audio' && mimeType == 'application/octet-stream') {
      final ext = fileName.split('.').last.toLowerCase();
      if (ext == 'm4a') {
        mimeType = 'audio/mp4';
      } else if (ext == 'ogg' || ext == 'oga') {
        mimeType = 'audio/ogg';
      } else if (ext == 'wav') {
        mimeType = 'audio/wav';
      } else if (ext == 'aac') {
        mimeType = 'audio/aac';
      }
    }
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    final optimistic = <String, dynamic>{
      'id': tempId,
      'text': type == 'audio' ? '' : fileName,
      'sender': 'user',
      'status': 'pending',
      'timestamp': DateTime.now().toIso8601String(),
      'type': type,
      'mediaUrl': file.path,
      'mimeType': mimeType,
    };

    setState(() {
      _addOrUpdateMessage(optimistic);
      _sortMessages();
    });
    _scrollToBottom();

    try {
      if (!await file.exists()) {
        debugPrint('Arquivo nao encontrado: ${file.path}');
        _updateMessageStatus(messageId: tempId, status: 'failed');
        return;
      }

      final fileLength = await file.length();
      if (fileLength == 0) {
        debugPrint('Arquivo vazio: ${file.path}');
        _updateMessageStatus(messageId: tempId, status: 'failed');
        return;
      }

      debugPrint(
          'Enviando midia: type=$type, mime=$mimeType, size=$fileLength, path=${file.path}');

      final token = await _storage.read(key: 'session_token');

      // Step 1: Upload file to /api/upload to get a media key
      final uploadUri = Uri.parse('$baseUrl/api/upload');
      final uploadRequest = http.MultipartRequest('POST', uploadUri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(await http.MultipartFile.fromPath(
          'file',
          file.path,
          contentType: MediaType.parse(mimeType),
        ));

      final uploadStreamed = await uploadRequest.send();
      final uploadResp = await http.Response.fromStream(uploadStreamed);

      debugPrint(
          'Resposta upload: status=${uploadResp.statusCode}, body=${uploadResp.body}');

      if (uploadResp.statusCode < 200 || uploadResp.statusCode >= 300) {
        _updateMessageStatus(messageId: tempId, status: 'failed');
        return;
      }

      final uploadData = jsonDecode(uploadResp.body);
      final mediaKey = _asString(uploadData['file']?['key']);

      if (mediaKey.isEmpty) {
        debugPrint('Upload retornou sem key');
        _updateMessageStatus(messageId: tempId, status: 'failed');
        return;
      }

      // Step 2: Send message with the media key (same endpoint as web frontend)
      final sendUri = Uri.parse('$baseUrl/api/chats/${widget.chatId}/messages');
      final resp = await http.post(
        sendUri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'text': type == 'audio' ? '' : fileName,
          'sender': 'user',
          'type': type,
          'mediaKey': mediaKey,
          'mimeType': mimeType,
          'fileName': fileName,
          'fileSize': fileLength,
        }),
      );

      debugPrint(
          'Resposta envio midia: status=${resp.statusCode}, body=${resp.body}');

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        try {
          final dynamic decoded = jsonDecode(resp.body);
          final dynamic responseMessage =
              decoded is Map<String, dynamic> ? decoded['message'] : null;
          if (responseMessage is Map) {
            final normalized =
                _normalizeMessage(Map<String, dynamic>.from(responseMessage));
            setState(() {
              _addOrUpdateMessage(normalized);
              _sortMessages();
            });
          } else {
            _updateMessageStatus(messageId: tempId, status: 'sent');
          }
        } catch (_) {
          _updateMessageStatus(messageId: tempId, status: 'sent');
        }
      } else {
        _updateMessageStatus(messageId: tempId, status: 'failed');
      }
    } catch (e) {
      debugPrint('Erro ao enviar midia: $e');
      _updateMessageStatus(messageId: tempId, status: 'failed');
    } finally {
      if (mounted) setState(() => _isSendingMedia = false);
    }
  }

  // ───────────────────── AUDIO RECORDING ─────────────────────

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecordingAndSend();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Permissao de microfone negada.'),
              backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _recordingDuration += const Duration(seconds: 1);
        });
      });
    } catch (e) {
      debugPrint('Erro ao iniciar gravacao: $e');
    }
  }

  Future<void> _stopRecordingAndSend() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    try {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);

      if (path != null && path.isNotEmpty) {
        await _sendMediaFile(file: File(path), type: 'audio');
      }
    } catch (e) {
      debugPrint('Erro ao parar gravacao: $e');
      setState(() => _isRecording = false);
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    try {
      await _audioRecorder.stop();
    } catch (_) {}

    if (mounted) setState(() => _isRecording = false);
  }

  // ───────────────────── PICKERS ─────────────────────

  Future<void> _pickImage({required ImageSource source}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    await _sendMediaFile(file: File(picked.path), type: 'image');
  }

  Future<void> _pickVideo({required ImageSource source}) async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 5),
    );
    if (picked == null) return;
    await _sendMediaFile(file: File(picked.path), type: 'video');
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    final mime = lookupMimeType(path) ?? 'application/octet-stream';
    String type = 'document';
    if (mime.startsWith('image/')) type = 'image';
    if (mime.startsWith('video/')) type = 'video';
    if (mime.startsWith('audio/')) type = 'audio';

    await _sendMediaFile(file: File(path), type: type);
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    await _sendMediaFile(file: File(path), type: 'audio');
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E2733),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _AttachmentOption(
                icon: Icons.photo,
                label: 'Galeria (Foto)',
                color: Colors.green,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(source: ImageSource.gallery);
                },
              ),
              _AttachmentOption(
                icon: Icons.camera_alt,
                label: 'Camera (Foto)',
                color: Colors.blue,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(source: ImageSource.camera);
                },
              ),
              _AttachmentOption(
                icon: Icons.videocam,
                label: 'Galeria (Video)',
                color: Colors.orange,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickVideo(source: ImageSource.gallery);
                },
              ),
              _AttachmentOption(
                icon: Icons.video_camera_back,
                label: 'Camera (Video)',
                color: Colors.redAccent,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickVideo(source: ImageSource.camera);
                },
              ),
              _AttachmentOption(
                icon: Icons.audio_file,
                label: 'Arquivo de Audio',
                color: Colors.purple,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAudioFile();
                },
              ),
              _AttachmentOption(
                icon: Icons.insert_drive_file,
                label: 'Documento',
                color: Colors.teal,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickDocument();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────── ORIGINAL METHODS (unchanged) ─────────────────────

  Future<void> _loadChatDetails() async {
    try {
      final token = await _storage.read(key: 'session_token');
      final resp = await http.get(
        Uri.parse('$baseUrl/api/chats/${widget.chatId}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (resp.statusCode != 200) {
        return;
      }

      final dynamic decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final dynamic rawChat = decoded['chat'];
      if (rawChat is! Map) {
        return;
      }

      if (!mounted) {
        return;
      }

      final details = Map<String, dynamic>.from(rawChat);
      final ticketConnection = _extractConnectionLabel(details);
      setState(() {
        _chatDetails = details;
        if (ticketConnection.isNotEmpty) {
          _connectionLabel = ticketConnection;
        }
      });
      _loadContactMeta();
    } catch (e) {
      debugPrint('Erro ao carregar detalhes do chat: $e');
    }
  }

  Future<void> _loadContactMeta() async {
    final contactId = _asString(_chatDetails?['contactId']);
    if (contactId.isEmpty) {
      return;
    }

    try {
      final token = await _storage.read(key: 'session_token');
      final resp = await http.get(
        Uri.parse('$baseUrl/api/contacts'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (resp.statusCode != 200) {
        return;
      }

      final dynamic decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final rawContacts = decoded['contacts'];
      if (rawContacts is! List) {
        return;
      }

      Map<String, dynamic>? contact;
      for (final item in rawContacts) {
        if (item is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(item);
        if (_asString(map['id']) == contactId) {
          contact = map;
          break;
        }
      }

      if (contact == null || !mounted) {
        return;
      }

      final tagsRaw = contact['tags'];
      final tags = <String>[];
      if (tagsRaw is List) {
        for (final tag in tagsRaw) {
          final value = _asString(tag).trim();
          if (value.isNotEmpty) {
            tags.add(value);
          }
        }
      }

      setState(() {
        _contactTags = tags;
      });
    } catch (e) {
      debugPrint('Erro ao carregar meta do contato: $e');
    }
  }

  bool get _isPendingConversation {
    final status = _asString(
      _chatDetails?['ticketStatus'] ?? widget.initialTicketStatus,
    ).toLowerCase();
    return status == 'pending';
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

  String _firstNonEmpty(List<String> values, {String fallback = ''}) {
    for (final value in values) {
      if (value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return fallback;
  }

  String get _effectiveConnectionLabel {
    if (_asString(_connectionLabel).isNotEmpty) {
      return _asString(_connectionLabel);
    }
    if (_asString(widget.initialConnectionLabel).isNotEmpty) {
      return _asString(widget.initialConnectionLabel);
    }
    return '';
  }

  List<String> get _effectiveContactTags {
    if (_contactTags.isNotEmpty) {
      return _contactTags;
    }
    final initial = widget.initialContactTags ?? <String>[];
    final normalized = initial
        .map((tag) => _asString(tag).trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    return normalized;
  }

  DateTime? _latestInboundMessageTime() {
    for (final message in _messages.reversed) {
      if (_asString(message['sender']) == 'user') {
        continue;
      }
      final timestamp = DateTime.tryParse(_asString(message['timestamp']));
      if (timestamp != null) {
        return timestamp.toLocal();
      }
    }
    return null;
  }

  bool _isMetaWindowExpired() {
    final lastInbound = _latestInboundMessageTime();
    if (lastInbound == null) {
      return false;
    }
    final expiresAt = lastInbound.add(const Duration(hours: 24));
    return DateTime.now().isAfter(expiresAt);
  }

  String _metaWindowLabel() {
    final lastInbound = _latestInboundMessageTime();
    if (lastInbound == null) {
      return 'Meta: sem referencia';
    }

    final expiresAt = lastInbound.add(const Duration(hours: 24));
    final remaining = expiresAt.difference(DateTime.now());

    if (remaining.inSeconds <= 0) {
      return 'Meta: expirada';
    }

    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);

    if (hours > 0) {
      return 'Meta: $hours h ${minutes}m';
    }
    return 'Meta: ${remaining.inMinutes}m';
  }

  Widget _buildInfoBadge({
    required IconData icon,
    required String text,
    required Color borderColor,
    Color? textColor,
    Color? iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF111B26),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor ?? borderColor),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: textColor ?? Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _assumeConversation() async {
    if (_isAssumingConversation) {
      return;
    }

    setState(() {
      _isAssumingConversation = true;
    });

    final token = await _storage.read(key: 'session_token');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    final attempts = <Future<http.Response> Function()>[
      () => http.post(
            Uri.parse('$baseUrl/api/chats/${widget.chatId}/assume'),
            headers: headers,
          ),
      () => http.patch(
            Uri.parse('$baseUrl/api/chats/${widget.chatId}'),
            headers: headers,
            body: jsonEncode({'action': 'assume'}),
          ),
      () => http.patch(
            Uri.parse('$baseUrl/api/chats/${widget.chatId}'),
            headers: headers,
            body: jsonEncode({'status': 'open'}),
          ),
    ];

    bool success = false;
    int lastStatusCode = 0;
    String lastBody = '';

    try {
      for (final attempt in attempts) {
        final resp = await attempt();
        lastStatusCode = resp.statusCode;
        lastBody = resp.body;

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          success = true;
          break;
        }

        if (resp.statusCode == 404 || resp.statusCode == 405) {
          continue;
        }

        break;
      }
    } catch (e) {
      debugPrint('Erro ao assumir conversa: $e');
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isAssumingConversation = false;
      if (success) {
        final current = _chatDetails ?? <String, dynamic>{};
        _chatDetails = {
          ...current,
          'ticketStatus': 'open',
        };
      }
    });

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conversa assumida com sucesso.'),
          backgroundColor: Colors.green,
        ),
      );
      _loadChatDetails();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Nao foi possivel assumir a conversa. (Status: $lastStatusCode)',
        ),
        backgroundColor: Colors.redAccent,
      ),
    );
    debugPrint('Falha ao assumir conversa. Body: $lastBody');
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

      if (resp.statusCode == 200) {
        final dynamic decoded = jsonDecode(resp.body);
        final List<dynamic> rawMessages =
            decoded is Map && decoded['messages'] is List
                ? decoded['messages'] as List<dynamic>
                : <dynamic>[];

        final normalized = rawMessages
            .whereType<Map>()
            .map((raw) => _normalizeMessage(Map<String, dynamic>.from(raw)))
            .toList();

        setState(() {
          _messages
            ..clear()
            ..addAll(normalized);
          _sortMessages();
          _isLoading = false;
        });
        _scrollToBottom();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Erro ao carregar mensagens: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTicketEvents() async {
    try {
      final token = await _storage.read(key: 'session_token');
      final resp = await http.get(
        Uri.parse('$baseUrl/api/tickets/${widget.chatId}/events'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (resp.statusCode != 200) {
        return;
      }

      final dynamic decoded = jsonDecode(resp.body);
      if (decoded is! List) {
        return;
      }

      final normalized = decoded
          .whereType<Map>()
          .map((raw) => _normalizeTicketEvent(Map<String, dynamic>.from(raw)))
          .toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _ticketEvents
          ..clear()
          ..addAll(normalized);
      });
    } catch (e) {
      debugPrint('Erro ao carregar eventos do ticket: $e');
    }
  }

  Future<void> _startListeningToMessages() async {
    final streamUrl = '$baseUrl/api/chats/${widget.chatId}/stream';
    final token = await _storage.read(key: 'session_token');

    _sseSubscription = SSEClient.subscribeToSSE(
      method: SSERequestType.GET,
      url: streamUrl,
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
          if (eventType == 'message_status') {
            _updateMessageStatus(
              messageId: _asString(decoded['messageId']),
              status: _asString(decoded['status']),
            );
            return;
          }

          dynamic rawMessage = decoded['message'] ?? decoded['data'];
          rawMessage ??= decoded;
          if (rawMessage is! Map) {
            return;
          }

          final normalized =
              _normalizeMessage(Map<String, dynamic>.from(rawMessage));
          setState(() {
            _addOrUpdateMessage(normalized);
            _sortMessages();
          });
          _scrollToBottom();
        } catch (e) {
          debugPrint('Erro ao ler mensagem SSE: $e');
        }
      },
      onError: (error) {
        debugPrint('Erro na conexao SSE: $error');
      },
    );
  }

  Future<void> _sendMessage() async {
    if (_isPendingConversation) {
      return;
    }

    final text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }

    _messageController.clear();
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMessage = <String, dynamic>{
      'id': tempId,
      'text': text,
      'sender': 'user',
      'status': 'pending',
      'timestamp': DateTime.now().toIso8601String(),
      'type': 'text',
      'mediaUrl': '',
      'mimeType': '',
    };

    setState(() {
      _addOrUpdateMessage(optimisticMessage);
      _sortMessages();
    });
    _scrollToBottom();

    final token = await _storage.read(key: 'session_token');
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/chats/${widget.chatId}/messages'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'text': text,
          'sender': 'user',
          'type': 'text',
        }),
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        try {
          final dynamic decoded = jsonDecode(resp.body);
          final dynamic responseMessage =
              decoded is Map<String, dynamic> ? decoded['message'] : null;
          if (responseMessage is Map) {
            final normalized =
                _normalizeMessage(Map<String, dynamic>.from(responseMessage));
            setState(() {
              _addOrUpdateMessage(normalized);
              _sortMessages();
            });
          } else {
            _updateMessageStatus(messageId: tempId, status: 'sent');
          }
        } catch (_) {
          _updateMessageStatus(messageId: tempId, status: 'sent');
        }
      } else {
        _updateMessageStatus(messageId: tempId, status: 'failed');
      }
    } catch (e) {
      debugPrint('Erro ao enviar: $e');
      _updateMessageStatus(messageId: tempId, status: 'failed');
    }
  }

  void _updateMessageStatus({
    required String messageId,
    required String status,
  }) {
    if (messageId.isEmpty || status.isEmpty) {
      return;
    }

    final index = _messages
        .indexWhere((message) => _asString(message['id']) == messageId);
    if (index == -1) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _messages[index] = <String, dynamic>{
        ..._messages[index],
        'status': _normalizeMessageStatus(status),
      };
    });
  }

  String _normalizeMessageStatus(dynamic rawStatus, {String fallback = 'sent'}) {
    final status = _asString(rawStatus).trim().toLowerCase();
    if (status == 'read') return 'read';
    if (status == 'delivered') return 'delivered';
    if (status == 'sent') return 'sent';
    if (status == 'pending') return 'pending';
    if (status == 'failed' || status == 'error') return 'failed';
    return fallback;
  }

  Map<String, dynamic> _normalizeTicketEvent(Map<String, dynamic> raw) {
    final fallbackId = 'event_${DateTime.now().microsecondsSinceEpoch}';
    return <String, dynamic>{
      'id': _asString(raw['id']).isNotEmpty ? _asString(raw['id']) : fallbackId,
      'eventType': _asString(raw['eventType']).toLowerCase(),
      'message': _asString(raw['message']).isNotEmpty
          ? _asString(raw['message'])
          : 'Atualizacao do ticket',
      'createdAt': _asString(raw['createdAt']).isNotEmpty
          ? _asString(raw['createdAt'])
          : DateTime.now().toIso8601String(),
    };
  }

  DateTime _parseEventDate(Map<String, dynamic> event) {
    final timestamp = _asString(event['createdAt']);
    final parsed = DateTime.tryParse(timestamp);
    return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime _parseTimelineDate(Map<String, dynamic> timelineItem) {
    final itemType = _asString(timelineItem['itemType']);
    if (itemType == 'event') {
      return _parseEventDate(timelineItem);
    }
    return _parseMessageDate(timelineItem);
  }

  List<Map<String, dynamic>> _buildTimelineItems() {
    final items = <Map<String, dynamic>>[
      ..._messages
          .map((message) => <String, dynamic>{...message, 'itemType': 'message'}),
      ..._ticketEvents
          .map((event) => <String, dynamic>{...event, 'itemType': 'event'}),
    ];

    items.sort(
      (a, b) => _parseTimelineDate(a).compareTo(_parseTimelineDate(b)),
    );
    return items;
  }

  String _formatMessageTime(dynamic rawTimestamp) {
    final timestamp = _asString(rawTimestamp);
    if (timestamp.isEmpty) {
      return '';
    }
    final parsed = DateTime.tryParse(timestamp);
    if (parsed == null) {
      return timestamp;
    }
    final local = parsed.toLocal();
    final hours = local.hour.toString().padLeft(2, '0');
    final minutes = local.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  String _formatEventDateTime(dynamic rawTimestamp) {
    final timestamp = _asString(rawTimestamp);
    if (timestamp.isEmpty) {
      return '';
    }
    final parsed = DateTime.tryParse(timestamp);
    if (parsed == null) {
      return timestamp;
    }
    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hours = local.hour.toString().padLeft(2, '0');
    final minutes = local.minute.toString().padLeft(2, '0');
    final seconds = local.second.toString().padLeft(2, '0');
    return '$day/$month/$year $hours:$minutes:$seconds';
  }

  Widget? _buildMessageStatusIcon(String rawStatus) {
    final status = _normalizeMessageStatus(rawStatus, fallback: '');
    if (status.isEmpty) {
      return null;
    }

    if (status == 'pending') {
      return const Icon(
        Icons.access_time,
        size: 13,
        color: Colors.white54,
      );
    }
    if (status == 'failed') {
      return const Icon(
        Icons.error_outline,
        size: 14,
        color: Colors.redAccent,
      );
    }
    if (status == 'read') {
      return const Icon(
        Icons.done_all,
        size: 15,
        color: Color(0xFF60A5FA),
      );
    }
    if (status == 'delivered') {
      return const Icon(
        Icons.done_all,
        size: 15,
        color: Colors.white70,
      );
    }
    if (status == 'sent') {
      return const Icon(
        Icons.done,
        size: 14,
        color: Colors.white70,
      );
    }
    return null;
  }

  Widget _buildTimelineEvent(Map<String, dynamic> event) {
    final eventType = _asString(event['eventType']).toLowerCase();
    final icon = eventType == 'status_changed'
        ? Icons.swap_horiz_rounded
        : Icons.info_outline_rounded;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2730),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: Colors.white54),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _asString(event['message']),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _formatEventDateTime(event['createdAt']),
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _normalizeMessage(Map<String, dynamic> raw) {
    final type = _detectMessageType(raw);
    final mediaUrl = _extractMediaUrl(raw);
    final sender = _resolveSender(raw);
    final fallbackId = 'msg_${DateTime.now().microsecondsSinceEpoch}';

    return <String, dynamic>{
      'id': _asString(raw['id']).isNotEmpty
          ? _asString(raw['id'])
          : (_asString(raw['messageId']).isNotEmpty
              ? _asString(raw['messageId'])
              : fallbackId),
      'text': _asString(raw['text']).isNotEmpty
          ? _asString(raw['text'])
          : (_asString(raw['body']).isNotEmpty
              ? _asString(raw['body'])
              : _asString(raw['content'])),
      'sender': sender,
      'status': _normalizeMessageStatus(raw['status']),
      'timestamp': _asString(raw['timestamp']).isNotEmpty
          ? _asString(raw['timestamp'])
          : DateTime.now().toIso8601String(),
      'type': type,
      'mediaUrl': mediaUrl,
      'mimeType': _asString(raw['mimeType']),
      'mediaDescriptionShort': _asString(raw['mediaDescriptionShort']),
      'mediaDescriptionFull': _asString(raw['mediaDescriptionFull']),
    };
  }

  String _resolveSender(Map<String, dynamic> raw) {
    final sender = _asString(raw['sender']).toLowerCase();
    if (sender == 'contact') {
      return 'bot';
    }
    if (sender.isNotEmpty) {
      return sender;
    }

    final from = _asString(raw['from']).toLowerCase();
    if (from == 'contact') {
      return 'bot';
    }
    if (from.isNotEmpty) {
      return from;
    }

    return 'bot';
  }

  String _detectMessageType(Map<String, dynamic> raw) {
    final rawType = _asString(raw['type']).toLowerCase();
    if (rawType.isNotEmpty && rawType != 'unknown') {
      return rawType;
    }

    final mime = _asString(raw['mimeType']).toLowerCase();
    if (mime.startsWith('image/')) {
      return 'image';
    }
    if (mime.startsWith('video/')) {
      return 'video';
    }
    if (mime.startsWith('audio/')) {
      return 'audio';
    }
    if (_extractMediaUrl(raw).isNotEmpty) {
      return 'document';
    }
    return 'text';
  }

  String _extractMediaUrl(Map<String, dynamic> raw) {
    final directKeys = <String>[
      'mediaUrl',
      'url',
      'attachmentUrl',
      'fileUrl',
    ];

    for (final key in directKeys) {
      final value = _asString(raw[key]);
      if (value.isNotEmpty) {
        return value;
      }
    }

    final media = raw['media'];
    if (media is Map) {
      final mediaMap = Map<String, dynamic>.from(media);
      for (final key in directKeys) {
        final value = _asString(mediaMap[key]);
        if (value.isNotEmpty) {
          return value;
        }
      }
    }

    return '';
  }

  String _asString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  bool _isLocalFilePath(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized.startsWith('/')) {
      return true;
    }
    final windowsPathPattern = RegExp(r'^[a-zA-Z]:[\\/]');
    return windowsPathPattern.hasMatch(normalized);
  }

  Future<void> _openDocumentUrl(String mediaUrl) async {
    if (mediaUrl.trim().isEmpty) {
      return;
    }

    try {
      Uri? targetUri;
      if (_isLocalFilePath(mediaUrl)) {
        final file = File(mediaUrl);
        if (!await file.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Arquivo nao encontrado para abrir.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }
        targetUri = Uri.file(file.path);
      } else {
        targetUri = Uri.tryParse(mediaUrl);
      }

      if (targetUri == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Link do documento invalido.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final opened = await launchUrl(
        targetUri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nao foi possivel abrir o documento.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao abrir documento: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao abrir documento.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  DateTime _parseMessageDate(Map<String, dynamic> message) {
    final timestamp = _asString(message['timestamp']);
    final parsed = DateTime.tryParse(timestamp);
    return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _sortMessages() {
    _messages.sort(
      (a, b) => _parseMessageDate(a).compareTo(_parseMessageDate(b)),
    );
  }

  void _addOrUpdateMessage(Map<String, dynamic> incomingMessage) {
    final incomingId = _asString(incomingMessage['id']);

    if (incomingId.isNotEmpty) {
      final index = _messages
          .indexWhere((message) => _asString(message['id']) == incomingId);
      if (index >= 0) {
        _messages[index] = <String, dynamic>{
          ..._messages[index],
          ...incomingMessage,
        };
        return;
      }
    }

    final pendingIndex = _messages.indexWhere(
      (message) =>
          _asString(message['status']) == 'pending' &&
          _asString(message['sender']) ==
              _asString(incomingMessage['sender']) &&
          _asString(message['text']) == _asString(incomingMessage['text']) &&
          _asString(message['type']) == _asString(incomingMessage['type']),
    );

    if (pendingIndex >= 0) {
      _messages[pendingIndex] = <String, dynamic>{
        ..._messages[pendingIndex],
        ...incomingMessage,
        'status': 'sent',
      };
      return;
    }

    _messages.add(incomingMessage);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildMediaWidget(
    Map<String, dynamic> message,
    bool isMe,
  ) {
    final messageType = _asString(message['type']).toLowerCase();
    final mediaUrl = _asString(message['mediaUrl']);

    if (mediaUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    if (messageType == 'image') {
      Widget imageWidget;
      if (mediaUrl.startsWith('/') ||
          mediaUrl.startsWith('C:') ||
          mediaUrl.startsWith('c:')) {
        imageWidget = Image.file(
          File(mediaUrl),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _MediaErrorPlaceholder(
                label: 'Falha ao carregar imagem', isMe: isMe);
          },
        );
      } else {
        imageWidget = Image.network(
          mediaUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              height: 180,
              alignment: Alignment.center,
              color: Colors.black26,
              child: const CircularProgressIndicator(
                  color: Colors.white70, strokeWidth: 2),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return _MediaErrorPlaceholder(
                label: 'Falha ao carregar imagem', isMe: isMe);
          },
        );
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260, minWidth: 160),
          child: imageWidget,
        ),
      );
    }

    if (messageType == 'video') {
      return _VideoPlayerBubble(
        key: ValueKey('video_${_asString(message['id'])}'),
        url: mediaUrl,
        isMe: isMe,
      );
    }

    if (messageType == 'audio' || messageType == 'voice') {
      return _AudioPlayerBubble(
        key: ValueKey('audio_${_asString(message['id'])}'),
        url: mediaUrl,
        isMe: isMe,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openDocumentUrl(mediaUrl),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMe ? Colors.blue[800] : const Color(0xFF253140),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _asString(message['text']).isNotEmpty
                          ? _asString(message['text'])
                          : 'Documento',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Toque para abrir',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaUnavailablePlaceholder(Map<String, dynamic> message) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24), size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Midia nao disponivel',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _asString(message['text']).isNotEmpty
                      ? _asString(message['text'])
                      : 'Arquivo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(Map<String, dynamic> message, bool isMe) {
    final text = _asString(message['text']);
    final mediaUrl = _asString(message['mediaUrl']);
    final shortDescription = _asString(message['mediaDescriptionShort']);
    final fullDescription = _asString(message['mediaDescriptionFull']);
    final messageType = _asString(message['type']).toLowerCase();
    final hasMedia = mediaUrl.isNotEmpty && messageType != 'text';

    final children = <Widget>[];

    if (hasMedia) {
      children.add(_buildMediaWidget(message, isMe));
    } else if (messageType == 'image' ||
        messageType == 'video' ||
        messageType == 'audio' ||
        messageType == 'voice' ||
        messageType == 'document') {
      children.add(_buildMediaUnavailablePlaceholder(message));
    }

    final shouldRenderText = text.isNotEmpty && !(messageType == 'document' && hasMedia);
    if (shouldRenderText) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 8));
      }
      children.add(
        Text(
          text,
          style: const TextStyle(color: Colors.white),
        ),
      );
    }

    if (shortDescription.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 8));
      }
      children.add(
        Text(
          shortDescription,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    if (fullDescription.isNotEmpty && fullDescription != shortDescription) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 6));
      }
      children.add(
        Text(
          fullDescription,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 11,
          ),
        ),
      );
    }

    if (children.isEmpty) {
      children.add(
        const Text(
          '[mensagem sem conteudo]',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  String _formatRecordingDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _sseSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatName = _asString(_chatDetails?['name']).isNotEmpty
        ? _asString(_chatDetails?['name'])
        : (_asString(widget.initialChatName).isNotEmpty
            ? _asString(widget.initialChatName)
            : 'Chat');
    final timelineItems = _buildTimelineItems();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: Text(chatName, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF161B22),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            color: const Color(0xFF11161E),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_effectiveConnectionLabel.isNotEmpty) ...[
                    _buildInfoBadge(
                      icon: Icons.phone_enabled,
                      text: 'Conexao $_effectiveConnectionLabel',
                      borderColor: Colors.tealAccent,
                      textColor: Colors.tealAccent,
                      iconColor: Colors.tealAccent,
                    ),
                    const SizedBox(width: 8),
                  ],
                  _buildInfoBadge(
                    icon: Icons.person,
                    text: _asString(_chatDetails?['agent']).isNotEmpty
                        ? _asString(_chatDetails?['agent'])
                        : 'Sem atendente',
                    borderColor: const Color(0xFF3B82F6),
                    textColor: const Color(0xFF93C5FD),
                    iconColor: const Color(0xFF93C5FD),
                  ),
                  if (_effectiveContactTags.isNotEmpty)
                    const SizedBox(width: 8),
                  ..._effectiveContactTags.take(2).map(
                        (tag) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _buildInfoBadge(
                            icon: Icons.local_offer,
                            text: tag,
                            borderColor: const Color(0xFFA78BFA),
                            textColor: const Color(0xFFD8B4FE),
                            iconColor: const Color(0xFFD8B4FE),
                          ),
                        ),
                      ),
                  const SizedBox(width: 8),
                  _buildInfoBadge(
                    icon: Icons.schedule,
                    text: _metaWindowLabel(),
                    borderColor: _isMetaWindowExpired()
                        ? const Color(0xFFEF4444)
                        : const Color(0xFFF59E0B),
                    textColor: _isMetaWindowExpired()
                        ? const Color(0xFFFCA5A5)
                        : const Color(0xFFFCD34D),
                    iconColor: _isMetaWindowExpired()
                        ? const Color(0xFFFCA5A5)
                        : const Color(0xFFFCD34D),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.blue),
                  )
                : timelineItems.isEmpty
                    ? const Center(
                        child: Text(
                          'Sem mensagens ou eventos.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: timelineItems.length,
                        itemBuilder: (context, index) {
                          final item = timelineItems[index];
                          if (_asString(item['itemType']) == 'event') {
                            return _buildTimelineEvent(item);
                          }

                          final message = item;
                          final isMe = _asString(message['sender']) == 'user';
                          final timeLabel = _formatMessageTime(message['timestamp']);
                          final statusIcon = isMe
                              ? _buildMessageStatusIcon(_asString(message['status']))
                              : null;

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.78,
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
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: _buildMessageContent(message, isMe),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        timeLabel,
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 10,
                                        ),
                                      ),
                                      if (statusIcon != null) ...[
                                        const SizedBox(width: 4),
                                        statusIcon,
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          // ── INPUT BAR ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: const Color(0xFF161B22),
            child: SafeArea(
              child: _isPendingConversation
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2733),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Conversa em atendimento por IA.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _isAssumingConversation
                                  ? null
                                  : _assumeConversation,
                              child: _isAssumingConversation
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Assumir conversa'),
                            ),
                          ),
                        ],
                      ),
                    )
                  : _isRecording
                      // ── RECORDING BAR ──
                      ? Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent),
                              onPressed: _cancelRecording,
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.circle,
                                color: Colors.redAccent, size: 10),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Gravando... ${_formatRecordingDuration(_recordingDuration)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            CircleAvatar(
                              backgroundColor: Colors.redAccent,
                              child: IconButton(
                                icon: const Icon(Icons.stop,
                                    color: Colors.white, size: 20),
                                onPressed: _stopRecordingAndSend,
                              ),
                            ),
                          ],
                        )
                      // ── NORMAL INPUT BAR ──
                      : Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.attach_file,
                                  color: Colors.white70),
                              onPressed: _isSendingMedia
                                  ? null
                                  : _showAttachmentOptions,
                            ),
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Escreve uma mensagem...',
                                  hintStyle:
                                      const TextStyle(color: Colors.grey),
                                  filled: true,
                                  fillColor: const Color(0xFF0D1117),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                            const SizedBox(width: 4),
                            CircleAvatar(
                              backgroundColor: Colors.blue,
                              child: IconButton(
                                icon: const Icon(Icons.mic,
                                    color: Colors.white, size: 20),
                                onPressed:
                                    _isSendingMedia ? null : _toggleRecording,
                              ),
                            ),
                            const SizedBox(width: 4),
                            CircleAvatar(
                              backgroundColor: Colors.blue,
                              child: IconButton(
                                icon: const Icon(Icons.send,
                                    color: Colors.white, size: 20),
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

// ───────────────────── ATTACHMENT OPTION TILE ─────────────────────

class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.15),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }
}

// ───────────────────── EXISTING WIDGETS (unchanged) ─────────────────────

class _MediaErrorPlaceholder extends StatelessWidget {
  final String label;
  final bool isMe;

  const _MediaErrorPlaceholder({
    required this.label,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isMe ? Colors.blue[800] : const Color(0xFF253140),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image_outlined, color: Colors.white70),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _AudioPlayerBubble extends StatefulWidget {
  final String url;
  final bool isMe;

  const _AudioPlayerBubble({
    super.key,
    required this.url,
    required this.isMe,
  });

  @override
  State<_AudioPlayerBubble> createState() => _AudioPlayerBubbleState();
}

class _AudioPlayerBubbleState extends State<_AudioPlayerBubble> {
  late final AudioPlayer _player;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isLoading = false;
  bool _isPlaying = false;
  bool _isPrepared = false;
  bool _isPreparing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _bindStreams();
  }

  void _bindStreams() {
    _durationSub = _player.durationStream.listen((duration) {
      if (!mounted) {
        return;
      }
      setState(() {
        _duration = duration ?? Duration.zero;
      });
    });

    _positionSub = _player.positionStream.listen((position) {
      if (!mounted) {
        return;
      }
      setState(() {
        _position = position;
      });
    });

    _playerStateSub = _player.playerStateStream.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPlaying = state.playing;
      });
    });
  }

  Future<bool> _prepare() async {
    if (_isPrepared) {
      return true;
    }
    if (_isPreparing) {
      return false;
    }

    _isPreparing = true;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      await _player.setUrl(widget.url);
      _isPrepared = true;
      return true;
    } catch (e) {
      _error = 'Audio indisponivel';
      debugPrint('Erro ao carregar audio: $e');
      return false;
    } finally {
      _isPreparing = false;
      if (!mounted) {
        return false;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePlayback() async {
    if (_isLoading || _isPreparing) {
      return;
    }
    if (!_isPrepared) {
      final prepared = await _prepare();
      if (!prepared || !mounted) {
        return;
      }
    }
    if (_error != null) {
      return;
    }

    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _seekTo(double value) async {
    if (!_isPrepared) {
      return;
    }
    final target = Duration(milliseconds: value.round());
    await _player.seek(target);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _positionSub?.cancel();
    _playerStateSub?.cancel();
    unawaited(_player.stop());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _duration.inMilliseconds;
    final sliderMax = maxMs > 0 ? maxMs.toDouble() : 1.0;
    final clampedPositionMs =
        maxMs > 0 ? _position.inMilliseconds.clamp(0, maxMs).toDouble() : 0.0;

    if (_error != null) {
      return _MediaErrorPlaceholder(label: _error!, isMe: widget.isMe);
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.isMe
                ? const [Color(0xFF2D7EF9), Color(0xFF2069D8)]
                : const [Color(0xFF293547), Color(0xFF202C3B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _isLoading ? null : _togglePlayback,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(21),
                ),
                child: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isLoading)
                    const Text(
                      'Carregando audio...',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Audio',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _isPrepared
                              ? '${_formatDuration(_position)} / ${_formatDuration(_duration)}'
                              : 'Toque para reproduzir',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white38,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: clampedPositionMs,
                      min: 0,
                      max: sliderMax,
                      onChanged: !_isLoading && _isPrepared && maxMs > 0
                          ? _seekTo
                          : null,
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

class _VideoPlayerBubble extends StatefulWidget {
  final String url;
  final bool isMe;

  const _VideoPlayerBubble({
    super.key,
    required this.url,
    required this.isMe,
  });

  @override
  State<_VideoPlayerBubble> createState() => _VideoPlayerBubbleState();
}

class _VideoPlayerBubbleState extends State<_VideoPlayerBubble> {
  VideoPlayerController? _controller;
  bool _isLoading = false;
  bool _isPreparing = false;
  String? _error;

  Future<bool> _prepareIfNeeded() async {
    if (_controller != null) {
      return true;
    }
    if (_isPreparing) {
      return false;
    }

    _isPreparing = true;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final controller =
          VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await controller.initialize();
      controller.setLooping(false);
      controller.addListener(_videoListener);

      if (!mounted) {
        controller.removeListener(_videoListener);
        await controller.dispose();
        _isPreparing = false;
        return false;
      }

      setState(() {
        _controller = controller;
        _isLoading = false;
        _isPreparing = false;
      });
      return true;
    } catch (e) {
      debugPrint('Erro ao carregar video: $e');
      _isPreparing = false;
      if (!mounted) {
        return false;
      }
      setState(() {
        _error = 'Video indisponivel';
        _isLoading = false;
      });
      return false;
    }
  }

  void _videoListener() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _togglePlayback() async {
    var controller = _controller;
    if (controller == null) {
      final ready = await _prepareIfNeeded();
      if (!ready || !mounted) {
        return;
      }
      controller = _controller;
      if (controller == null) {
        return;
      }
    }

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_videoListener);
      unawaited(controller.pause());
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _MediaErrorPlaceholder(label: _error!, isMe: widget.isMe);
    }

    if (_controller == null) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: widget.isMe ? Colors.blue[800] : const Color(0xFF253140),
          borderRadius: BorderRadius.circular(10),
        ),
        child: InkWell(
          onTap: _togglePlayback,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_isLoading)
                const CircularProgressIndicator(
                  color: Colors.white70,
                  strokeWidth: 2,
                )
              else
                const Icon(
                  Icons.play_circle_fill,
                  size: 56,
                  color: Colors.white70,
                ),
            ],
          ),
        ),
      );
    }

    final controller = _controller!;
    final aspectRatio = controller.value.aspectRatio <= 0
        ? (16 / 9)
        : controller.value.aspectRatio;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: aspectRatio,
            child: VideoPlayer(controller),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: _togglePlayback),
            ),
          ),
          if (!controller.value.isPlaying)
            const Icon(
              Icons.play_circle_fill,
              size: 56,
              color: Colors.white70,
            ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 0,
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.only(bottom: 8),
              colors: const VideoProgressColors(
                playedColor: Colors.white,
                bufferedColor: Colors.white54,
                backgroundColor: Colors.white24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
