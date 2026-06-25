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

String _s(dynamic v) => v?.toString() ?? '';

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
  static const int _messagesPageSize = 40;
  static const double _loadMoreThreshold = 120;

  // Cache de templates aprovados por connectionId (persiste entre aberturas
  // da sheet e entre conversas da mesma conexao).
  static final Map<String, List<Map<String, dynamic>>> _templatesCache = {};

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
  bool _isLoadingMoreMessages = false;
  bool _hasMoreMessages = true;
  String? _oldestMessageCursor;
  bool _isAssumingConversation = false;
  bool _isUpdatingTicketStatus = false;

  // Media / recording state
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  bool _isSendingMedia = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
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
    return _ticketStatus == 'pending';
  }

  String get _ticketStatus {
    final directStatus = _asString(_chatDetails?['ticketStatus']).trim();
    if (directStatus.isNotEmpty) {
      return directStatus.toLowerCase();
    }

    final dynamic ticket = _chatDetails?['ticket'];
    if (ticket is Map) {
      final nestedStatus = _asString(ticket['status']).trim();
      if (nestedStatus.isNotEmpty) {
        return nestedStatus.toLowerCase();
      }
    }

    return _asString(widget.initialTicketStatus).trim().toLowerCase();
  }

  bool get _isOpenConversation {
    return _ticketStatus == 'open';
  }

  String get _connectionId {
    final direct = _asString(_chatDetails?['connectionId']).trim();
    if (direct.isNotEmpty) return direct;
    final dynamic conn = _chatDetails?['connection'];
    if (conn is Map) {
      final nested = _asString(conn['id']).trim();
      if (nested.isNotEmpty) return nested;
    }
    return '';
  }

  Future<void> _archiveTicketIfOpen() async {
    if (_isUpdatingTicketStatus) {
      return;
    }

    if (!_isOpenConversation) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apenas tickets com status open podem ser arquivados.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final token = await _storage.read(key: 'session_token');
    if (_asString(token).isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sessao invalida. Faca login novamente.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (mounted) {
      setState(() {
        _isUpdatingTicketStatus = true;
      });
    }

    try {
      final resp = await http.patch(
        Uri.parse('$baseUrl/api/tickets/${widget.chatId}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'action': 'archive'}),
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        await _loadChatDetails();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ticket arquivado com sucesso.'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Nao foi possivel arquivar o ticket. Status: ${resp.statusCode}',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao arquivar ticket: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao arquivar ticket.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingTicketStatus = false;
        });
      }
    }
  }

  // ───────────────────── SEND TEMPLATE ─────────────────────

  Future<void> _showSendTemplateSheet() async {
    final connectionId = _connectionId;
    if (connectionId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conexao nao identificada para carregar templates.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final token = await _storage.read(key: 'session_token');
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SendTemplateSheet(
        chatId: widget.chatId,
        connectionId: connectionId,
        cachedTemplates: _templatesCache[connectionId],
        onTemplatesLoaded: (list) => _templatesCache[connectionId] = list,
        token: token ?? '',
        baseUrl: baseUrl,
        onSuccess: () {
          Navigator.pop(ctx);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Template enviado com sucesso.'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
      ),
    );
  }

  // ───────────────────── FOLLOW-UP ─────────────────────

  Future<void> _showFollowUpSheet() async {
    final token = await _storage.read(key: 'session_token');
    Map<String, dynamic>? followUp;
    String? fetchError;
    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/tickets/${widget.chatId}/followup'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        final raw = decoded['followUp'];
        if (raw is Map) {
          followUp = Map<String, dynamic>.from(raw);
        }
      } else if (resp.statusCode != 404) {
        fetchError = 'Erro ao carregar follow-up (${resp.statusCode})';
      }
    } catch (_) {
      fetchError = 'Erro de conexao ao carregar follow-up.';
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _FollowUpSheet(
        ticketId: widget.chatId,
        initialFollowUp: followUp,
        fetchError: fetchError,
        token: token ?? '',
        baseUrl: baseUrl,
      ),
    );
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

  String _extractTargetIdFromJson(
    dynamic payload, {
    int depth = 0,
  }) {
    if (payload == null || depth > 6) {
      return '';
    }

    if (payload is Map) {
      final map = Map<String, dynamic>.from(payload);

      final directKeys = <String>[
        'memberId',
        'member_id',
        'userId',
        'user_id',
        'id',
        'sub',
      ];

      for (final key in directKeys) {
        final value = _asString(map[key]).trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') {
          return value;
        }
      }

      final nestedPriorityKeys = <String>[
        'user',
        'member',
        'session',
        'data',
        'result',
        'profile',
        'currentUser',
      ];

      for (final key in nestedPriorityKeys) {
        if (!map.containsKey(key)) {
          continue;
        }
        final nested = _extractTargetIdFromJson(map[key], depth: depth + 1);
        if (nested.isNotEmpty) {
          return nested;
        }
      }

      for (final value in map.values) {
        final nested = _extractTargetIdFromJson(value, depth: depth + 1);
        if (nested.isNotEmpty) {
          return nested;
        }
      }
    }

    if (payload is List) {
      for (final item in payload) {
        final nested = _extractTargetIdFromJson(item, depth: depth + 1);
        if (nested.isNotEmpty) {
          return nested;
        }
      }
    }

    return '';
  }

  String _extractTargetIdFromToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final parts = trimmed.split('.');
    if (parts.length < 2) {
      return '';
    }

    try {
      final normalized = base64Url.normalize(parts[1]);
      final payloadBytes = base64Url.decode(normalized);
      final payloadString = utf8.decode(payloadBytes);
      final dynamic payloadJson = jsonDecode(payloadString);
      return _extractTargetIdFromJson(payloadJson);
    } catch (_) {
      return '';
    }
  }

  String _extractEmailFromToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final parts = trimmed.split('.');
    if (parts.length < 2) {
      return '';
    }

    try {
      final normalized = base64Url.normalize(parts[1]);
      final payloadBytes = base64Url.decode(normalized);
      final payloadString = utf8.decode(payloadBytes);
      final dynamic payloadJson = jsonDecode(payloadString);
      if (payloadJson is! Map) {
        return '';
      }
      final map = Map<String, dynamic>.from(payloadJson);

      final directEmail = _asString(map['email']).trim().toLowerCase();
      if (directEmail.isNotEmpty) {
        return directEmail;
      }

      final dynamic userRaw = map['user'];
      if (userRaw is Map) {
        final userMap = Map<String, dynamic>.from(userRaw);
        final nestedEmail = _asString(userMap['email']).trim().toLowerCase();
        if (nestedEmail.isNotEmpty) {
          return nestedEmail;
        }
      }
    } catch (_) {
      return '';
    }

    return '';
  }

  String _extractUserIdFromOrganizationPayload(
    dynamic payload, {
    String preferredEmail = '',
  }) {
    final members = <Map<String, dynamic>>[];

    void collectMembers(dynamic node, int depth) {
      if (node == null || depth > 6) {
        return;
      }

      if (node is Map) {
        final map = Map<String, dynamic>.from(node);
        final dynamic membersRaw = map['members'];
        if (membersRaw is List) {
          for (final item in membersRaw) {
            if (item is Map) {
              members.add(Map<String, dynamic>.from(item));
            }
          }
        }

        for (final value in map.values) {
          collectMembers(value, depth + 1);
        }
        return;
      }

      if (node is List) {
        for (final item in node) {
          collectMembers(item, depth + 1);
        }
      }
    }

    String userIdFromMember(Map<String, dynamic> member) {
      final directUserId = _asString(member['userId']).trim();
      if (directUserId.isNotEmpty) {
        return directUserId;
      }
      final dynamic userRaw = member['user'];
      if (userRaw is Map) {
        final userMap = Map<String, dynamic>.from(userRaw);
        final nestedUserId = _asString(userMap['id']).trim();
        if (nestedUserId.isNotEmpty) {
          return nestedUserId;
        }
      }
      return '';
    }

    collectMembers(payload, 0);
    if (members.isEmpty) {
      return '';
    }

    final normalizedPreferredEmail = preferredEmail.trim().toLowerCase();
    if (normalizedPreferredEmail.isNotEmpty) {
      for (final member in members) {
        final dynamic userRaw = member['user'];
        if (userRaw is! Map) {
          continue;
        }
        final userMap = Map<String, dynamic>.from(userRaw);
        final memberEmail = _asString(userMap['email']).trim().toLowerCase();
        if (memberEmail.isEmpty || memberEmail != normalizedPreferredEmail) {
          continue;
        }
        final matchedUserId = userIdFromMember(member);
        if (matchedUserId.isNotEmpty) {
          return matchedUserId;
        }
      }
    }

    if (members.length == 1) {
      return userIdFromMember(members.first);
    }

    return '';
  }

  Future<String> _resolveTransferTargetId({
    required String token,
    required Map<String, String> headers,
    required String organizationId,
    String preferredEmail = '',
  }) async {
    final fromToken = _extractTargetIdFromToken(token);
    if (fromToken.isNotEmpty) {
      return fromToken;
    }

    final sessionEndpoints = <String>[
      '/api/auth/get-session',
      '/api/auth/session',
      '/api/auth/me',
      '/api/me',
      '/api/users/me',
      '/api/member/me',
      '/api/members/me',
    ];

    for (final path in sessionEndpoints) {
      try {
        final uri = Uri.parse('$baseUrl$path');
        final resp = await http.get(uri, headers: headers);
        debugPrint('Resolve targetId => GET $uri status=${resp.statusCode}');

        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          continue;
        }
        if (resp.body.trim().isEmpty) {
          continue;
        }

        final dynamic decoded = jsonDecode(resp.body);
        final foundId = _extractTargetIdFromJson(decoded);
        if (foundId.isNotEmpty) {
          return foundId;
        }
      } catch (e) {
        debugPrint('Erro ao buscar sessao para transfer: $e');
      }
    }

    if (organizationId.trim().isNotEmpty) {
      try {
        final orgUri = Uri.parse('$baseUrl/api/auth/get-organization').replace(
          queryParameters: {
            'organizationId': organizationId.trim(),
          },
        );
        final orgResp = await http.get(orgUri, headers: headers);
        debugPrint(
          'Resolve targetId => GET $orgUri status=${orgResp.statusCode}',
        );

        if (orgResp.statusCode >= 200 &&
            orgResp.statusCode < 300 &&
            orgResp.body.trim().isNotEmpty) {
          final dynamic orgDecoded = jsonDecode(orgResp.body);
          final memberUserId = _extractUserIdFromOrganizationPayload(
            orgDecoded,
            preferredEmail: preferredEmail,
          );
          if (memberUserId.isNotEmpty) {
            return memberUserId;
          }
        }
      } catch (e) {
        debugPrint('Erro ao buscar organization para transfer: $e');
      }
    }

    return '';
  }

  Future<void> _assumeConversation() async {
    if (_isAssumingConversation) {
      return;
    }

    setState(() {
      _isAssumingConversation = true;
    });

    final token = await _storage.read(key: 'session_token');
    final tokenValue = _asString(token);
    if (tokenValue.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isAssumingConversation = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sessao expirada. Faz login novamente.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $tokenValue',
    };

    if (_chatDetails == null) {
      await _loadChatDetails();
    }

    final targetCandidates = <Map<String, String>>[];
    final seenTargets = <String>{};
    void addTarget(String targetId, String targetType) {
      final id = targetId.trim();
      final type = targetType.trim().toLowerCase();
      if (id.isEmpty || type.isEmpty) {
        return;
      }
      final key = '$type::$id';
      if (seenTargets.contains(key)) {
        return;
      }
      seenTargets.add(key);
      targetCandidates.add({
        'targetId': id,
        'targetType': type,
      });
    }

    final cachedUserId = _asString(await _storage.read(key: 'current_user_id'));
    addTarget(cachedUserId, 'user');

    final preferredEmail = _firstNonEmpty([
      _asString(await _storage.read(key: 'user_email')).trim().toLowerCase(),
      _extractEmailFromToken(tokenValue),
    ]);
    final organizationId = _asString(_chatDetails?['organizationId']);
    final resolvedTargetId = await _resolveTransferTargetId(
      token: tokenValue,
      headers: headers,
      organizationId: organizationId,
      preferredEmail: preferredEmail,
    );
    if (resolvedTargetId.isNotEmpty) {
      await _storage.write(key: 'current_user_id', value: resolvedTargetId);
    }

    addTarget(resolvedTargetId, 'user');
    addTarget(resolvedTargetId, 'agent');
    addTarget(_asString(_chatDetails?['attendantId']), 'user');
    addTarget(_asString(_chatDetails?['assignedUserId']), 'user');
    addTarget(_asString(_chatDetails?['agentId']), 'agent');
    addTarget(_asString(_chatDetails?['activeAgentId']), 'agent');
    addTarget(_asString(_chatDetails?['departmentId']), 'department');

    for (final target in targetCandidates) {
      debugPrint(
        'Assume target candidate => type=${target['targetType']} id=${target['targetId']}',
      );
    }

    if (targetCandidates.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isAssumingConversation = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel identificar o destino para assumir.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final transferUri =
        Uri.parse('$baseUrl/api/tickets/${widget.chatId}/transfer');
    final attempts = <Future<http.Response> Function()>[
      for (final target in targetCandidates)
        () => http.patch(
              transferUri,
              headers: headers,
              body: jsonEncode(target),
            ),
    ];

    bool success = false;
    int lastStatusCode = 0;
    String lastBody = '';
    String lastError = '';

    for (final attempt in attempts) {
      try {
        final resp = await attempt();
        lastStatusCode = resp.statusCode;
        lastBody = resp.body;
        debugPrint(
          'Assume attempt => ${resp.request?.method} ${resp.request?.url} status=${resp.statusCode}',
        );

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          success = true;
          break;
        }

        if (resp.statusCode == 401 || resp.statusCode == 403) {
          break;
        }
      } catch (e) {
        lastError = '$e';
        debugPrint('Erro ao assumir conversa: $e');
      }
    }

    // Somente API: o estado da tela deve vir do backend.
    if (success) {
      await _loadChatDetails();
      if (_isPendingConversation) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await _loadChatDetails();
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isAssumingConversation = false;
    });

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conversa assumida com sucesso.'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    final apiLabel =
        lastStatusCode > 0 ? 'Status: $lastStatusCode' : 'sem resposta da API';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Nao foi possivel assumir a conversa via API. ($apiLabel)',
        ),
        backgroundColor: Colors.redAccent,
      ),
    );
    debugPrint('Falha ao assumir conversa. Body: $lastBody');
    if (lastError.isNotEmpty) {
      debugPrint('Ultimo erro ao assumir conversa: $lastError');
    }
  }

  Uri _messagesEndpointUri({String? before}) {
    final queryParameters = <String, String>{
      'limit': _messagesPageSize.toString(),
    };

    if (before != null && before.isNotEmpty) {
      queryParameters['before'] = before;
    }

    return Uri.parse('$baseUrl/api/chats/${widget.chatId}/messages').replace(
      queryParameters: queryParameters,
    );
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _isLoading ||
        _isLoadingMoreMessages ||
        !_hasMoreMessages) {
      return;
    }

    if (_scrollController.position.pixels <= _loadMoreThreshold) {
      _loadMessages(loadMore: true);
    }
  }

  String? _resolveOldestMessageCursor() {
    if (_messages.isEmpty) {
      return null;
    }

    final oldestTimestamp = _asString(_messages.first['timestamp']);
    return oldestTimestamp.isEmpty ? null : oldestTimestamp;
  }

  void _keepScrollPositionAfterPrepend(double previousMaxScrollExtent) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      final newMaxScrollExtent = _scrollController.position.maxScrollExtent;
      final delta = newMaxScrollExtent - previousMaxScrollExtent;
      if (delta <= 0) {
        return;
      }

      final targetOffset = _scrollController.offset + delta;
      final clampedOffset = targetOffset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(clampedOffset.toDouble());
    });
  }

  Future<void> _loadMessages({bool loadMore = false}) async {
    if (loadMore) {
      if (_isLoading || _isLoadingMoreMessages || !_hasMoreMessages) {
        return;
      }
      if (_oldestMessageCursor == null || _oldestMessageCursor!.isEmpty) {
        return;
      }
    }

    final beforeCursor = loadMore ? _oldestMessageCursor : null;
    final previousMessageCount = _messages.length;
    final previousCursor = _oldestMessageCursor;
    final previousMaxScrollExtent = loadMore && _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;

    if (mounted) {
      setState(() {
        if (loadMore) {
          _isLoadingMoreMessages = true;
        } else {
          _isLoading = true;
          _hasMoreMessages = true;
        }
      });
    }

    try {
      final token = await _storage.read(key: 'session_token');
      final resp = await http.get(
        _messagesEndpointUri(before: beforeCursor),
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

        final pagination = decoded is Map ? decoded['pagination'] : null;
        final hasMoreFromApi =
            pagination is Map && pagination['hasMore'] is bool
                ? pagination['hasMore'] as bool
                : null;
        final nextBeforeFromApi =
            pagination is Map ? _asString(pagination['nextBefore']) : '';

        if (!mounted) {
          return;
        }

        setState(() {
          if (loadMore) {
            for (final message in normalized) {
              _addOrUpdateMessage(message);
            }
          } else {
            _messages
              ..clear()
              ..addAll(normalized);
          }

          _sortMessages();
          _oldestMessageCursor = nextBeforeFromApi.isNotEmpty
              ? nextBeforeFromApi
              : _resolveOldestMessageCursor();
          final didGrow = _messages.length > previousMessageCount;
          if (hasMoreFromApi != null) {
            _hasMoreMessages = hasMoreFromApi && (didGrow || !loadMore);
          } else {
            _hasMoreMessages = normalized.length >= _messagesPageSize &&
                _oldestMessageCursor != previousCursor;
          }
          if (loadMore && !didGrow) {
            _hasMoreMessages = false;
          }
          _isLoading = false;
          _isLoadingMoreMessages = false;
        });
        if (loadMore) {
          _keepScrollPositionAfterPrepend(previousMaxScrollExtent);
        } else {
          _scrollToBottom();
        }
      } else {
        if (!mounted) {
          return;
        }
        setState(() {
          _isLoading = false;
          _isLoadingMoreMessages = false;
          if (loadMore) {
            _hasMoreMessages = false;
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar mensagens: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _isLoadingMoreMessages = false;
      });
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

  String _normalizeMessageStatus(dynamic rawStatus,
      {String fallback = 'sent'}) {
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
      ..._messages.map(
          (message) => <String, dynamic>{...message, 'itemType': 'message'}),
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
              const Icon(Icons.insert_drive_file,
                  color: Colors.white70, size: 18),
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
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFFBBF24), size: 18),
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

    final shouldRenderText =
        text.isNotEmpty && !(messageType == 'document' && hasMedia);
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
    _scrollController.removeListener(_handleScroll);
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
    final showLoadMoreIndicator = _isLoadingMoreMessages && _hasMoreMessages;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: Text(chatName, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF161B22),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          if (_isOpenConversation)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              color: const Color(0xFF1E2733),
              onSelected: (value) {
                if (value == 'template') _showSendTemplateSheet();
                if (value == 'followup') _showFollowUpSheet();
                if (value == 'archive') _archiveTicketIfOpen();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'template',
                  child: Row(
                    children: [
                      Icon(
                        Icons.send_outlined,
                        color: Colors.white70,
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Enviar Template',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'followup',
                  child: Row(
                    children: [
                      Icon(
                        Icons.schedule_outlined,
                        color: Colors.white70,
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Agendar Follow-up',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'archive',
                  child: Row(
                    children: [
                      Icon(
                        Icons.archive_outlined,
                        color: Colors.white70,
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Arquivar ticket',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
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
                        itemCount: timelineItems.length +
                            (showLoadMoreIndicator ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (showLoadMoreIndicator && index == 0) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                            );
                          }

                          final timelineIndex =
                              showLoadMoreIndicator ? index - 1 : index;
                          final item = timelineItems[timelineIndex];
                          if (_asString(item['itemType']) == 'event') {
                            return _buildTimelineEvent(item);
                          }

                          final message = item;
                          final isMe = _asString(message['sender']) == 'user';
                          final timeLabel =
                              _formatMessageTime(message['timestamp']);
                          final statusIcon = isMe
                              ? _buildMessageStatusIcon(
                                  _asString(message['status']))
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

// ───────────────────── SEND TEMPLATE SHEET ─────────────────────

class _SendTemplateSheet extends StatefulWidget {
  final String chatId;
  final String connectionId;
  final List<Map<String, dynamic>>? cachedTemplates;
  final ValueChanged<List<Map<String, dynamic>>> onTemplatesLoaded;
  final String token;
  final String baseUrl;
  final VoidCallback onSuccess;

  const _SendTemplateSheet({
    required this.chatId,
    required this.connectionId,
    required this.cachedTemplates,
    required this.onTemplatesLoaded,
    required this.token,
    required this.baseUrl,
    required this.onSuccess,
  });

  @override
  State<_SendTemplateSheet> createState() => _SendTemplateSheetState();
}

class _SendTemplateSheetState extends State<_SendTemplateSheet> {
  Map<String, dynamic>? _selected;
  final Map<String, TextEditingController> _varCtrl = {};
  bool _isSending = false;
  String? _sendError;

  List<Map<String, dynamic>> _templates = [];
  bool _loading = false;
  String? _fetchError;

  @override
  void initState() {
    super.initState();
    final cached = widget.cachedTemplates;
    if (cached != null) {
      _templates = cached;
    } else {
      _loadTemplates();
    }
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _loading = true;
      _fetchError = null;
    });
    try {
      final resp = await http.get(
        Uri.parse(
          '${widget.baseUrl}/api/templates/meta?connectionId=${widget.connectionId}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        final raw = decoded['templates'];
        final list = <Map<String, dynamic>>[];
        if (raw is List) {
          list.addAll(
            raw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .where((t) => _s(t['status']).toUpperCase() == 'APPROVED'),
          );
        }
        widget.onTemplatesLoaded(list);
        setState(() {
          _templates = list;
          _loading = false;
        });
      } else {
        setState(() {
          _fetchError = 'Erro ao carregar templates (${resp.statusCode})';
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fetchError = 'Erro de conexao ao carregar templates.';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _vars(Map<String, dynamic> tpl) {
    final result = <Map<String, dynamic>>[];
    final components = tpl['components'];
    if (components is! List) return result;
    for (final comp in components) {
      if (comp is! Map) continue;
      final type = _s(comp['type']).toUpperCase();
      final text = _s(comp['text']);
      final format = _s(comp['format']).toUpperCase();
      if ((type == 'HEADER' && format == 'TEXT') || type == 'BODY') {
        for (final m in RegExp(r'\{\{([^}]+)\}\}').allMatches(text)) {
          final name = m.group(1)!.trim();
          result.add({
            'componentType': type == 'HEADER' ? 'header' : 'body',
            'name': name,
          });
        }
      }
    }
    return result;
  }

  void _select(Map<String, dynamic> tpl) {
    for (final c in _varCtrl.values) c.dispose();
    _varCtrl.clear();
    for (final v in _vars(tpl)) {
      _varCtrl['${v['componentType']}:${v['name']}'] = TextEditingController();
    }
    setState(() {
      _selected = tpl;
      _sendError = null;
    });
  }

  Future<void> _send() async {
    final tpl = _selected;
    if (tpl == null) return;
    setState(() {
      _isSending = true;
      _sendError = null;
    });
    try {
      final variables = _vars(tpl);
      List<Map<String, dynamic>>? components;
      if (variables.isNotEmpty) {
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final v in variables) {
          final key = '${v['componentType']}:${v['name']}';
          final val = _varCtrl[key]?.text.trim() ?? '';
          grouped.putIfAbsent(v['componentType'] as String, () => []);
          grouped[v['componentType']]!.add({
            'parameter_name': v['name'],
            'type': 'text',
            'text': val,
          });
        }
        components = grouped.entries
            .map((e) => {'type': e.key, 'parameters': e.value})
            .toList();
      }
      final body = <String, dynamic>{
        'templateName': _s(tpl['name']),
        'languageCode': _s(tpl['language']),
        if (components != null) 'components': components,
      };
      final resp = await http.post(
        Uri.parse(
          '${widget.baseUrl}/api/chats/${widget.chatId}/send-template',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode(body),
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        widget.onSuccess();
      } else {
        final decoded = jsonDecode(resp.body);
        final errMsg = _s(decoded['error']).isNotEmpty
            ? _s(decoded['error'])
            : _s(decoded['message']).isNotEmpty
                ? _s(decoded['message'])
                : 'Erro ao enviar template (${resp.statusCode})';
        setState(() => _sendError = errMsg);
      }
    } catch (e) {
      setState(() => _sendError = 'Erro de conexao');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    for (final c in _varCtrl.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
              child: Row(
                children: [
                  if (_selected != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selected = null;
                          _sendError = null;
                        }),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selected != null
                              ? _s(_selected!['name'])
                              : 'Enviar Template',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _selected != null
                              ? 'Preencha os parametros e envie'
                              : 'Selecione um template aprovado',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selected == null)
                    IconButton(
                      onPressed: _loading ? null : _loadTemplates,
                      icon: const Icon(Icons.refresh,
                          color: Colors.white54, size: 20),
                      tooltip: 'Recarregar templates',
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: _loading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white54),
                          ),
                          SizedBox(height: 14),
                          Text(
                            'Carregando templates...',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
                    )
                  : _fetchError != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _fetchError!,
                                  style:
                                      const TextStyle(color: Colors.redAccent),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 14),
                                OutlinedButton.icon(
                                  onPressed: _loadTemplates,
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Tentar novamente'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white70,
                                    side: const BorderSide(
                                        color: Colors.white24),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _selected == null
                          ? _buildList(controller)
                          : _buildForm(controller),
            ),
          ],
        );
      },
    );
  }

  Widget _buildList(ScrollController controller) {
    if (_templates.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum template aprovado encontrado.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _templates.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final tpl = _templates[i];
        final name = _s(tpl['name']);
        final language = _s(tpl['language']);
        final category = _s(tpl['category']);
        String bodyText = '';
        final comps = tpl['components'];
        if (comps is List) {
          for (final c in comps) {
            if (c is Map && _s(c['type']).toUpperCase() == 'BODY') {
              bodyText = _s(c['text']);
              break;
            }
          }
        }
        return InkWell(
          onTap: () => _select(tpl),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2733),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      language,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                if (bodyText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(bodyText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12))
                ],
                if (category.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(category.toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          fontWeight: FontWeight.bold))
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildForm(ScrollController controller) {
    final tpl = _selected!;
    final variables = _vars(tpl);
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_sendError != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
            ),
            child: Text(
              _sendError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PREVIEW',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              ...() {
                final comps = tpl['components'];
                if (comps is! List) return <Widget>[];
                return comps.map<Widget>((comp) {
                  if (comp is! Map) return const SizedBox.shrink();
                  final type = _s(comp['type']).toUpperCase();
                  final text = _s(comp['text']);
                  if ((type == 'HEADER' ||
                          type == 'BODY' ||
                          type == 'FOOTER') &&
                      text.isNotEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(text,
                          style: TextStyle(
                              color: type == 'FOOTER'
                                  ? Colors.white38
                                  : Colors.white70,
                              fontSize: type == 'HEADER' ? 14 : 12,
                              fontWeight: type == 'HEADER'
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                    );
                  }
                  return const SizedBox.shrink();
                }).toList();
              }(),
            ],
          ),
        ),
        if (variables.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Parametros',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ...variables.map((v) {
            final key = '${v['componentType']}:${v['name']}';
            return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                    controller: _varCtrl[key],
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                        labelText: '{{${v['name']}}} (${v['componentType']})',
                        labelStyle: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF0D1117),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Colors.white12)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Colors.white12)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Colors.blue)))));
          })
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: _isSending ? null : _send,
            child: _isSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Enviar Template'),
          ),
        ),
      ],
    );
  }
}

// ───────────────────── FOLLOW-UP SHEET ─────────────────────

class _FollowUpSheet extends StatefulWidget {
  final String ticketId;
  final Map<String, dynamic>? initialFollowUp;
  final String? fetchError;
  final String token;
  final String baseUrl;

  const _FollowUpSheet({
    required this.ticketId,
    this.initialFollowUp,
    this.fetchError,
    required this.token,
    required this.baseUrl,
  });

  @override
  State<_FollowUpSheet> createState() => _FollowUpSheetState();
}

class _FollowUpSheetState extends State<_FollowUpSheet> {
  Map<String, dynamic>? _followUp;
  bool _showForm = false;
  bool _isLoading = false;
  String? _opError;
  final _messageCtrl = TextEditingController();
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  @override
  void initState() {
    super.initState();
    _followUp = widget.initialFollowUp;
    _showForm = true;
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String _formatDt(DateTime dt) {
    final d = dt.toLocal();
    return '${_pad(d.day)}/${_pad(d.month)}/${d.year} ${_pad(d.hour)}:${_pad(d.minute)}';
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pendente';
      case 'sent':
        return 'Enviado';
      case 'cancelled':
        return 'Cancelado';
      case 'failed':
        return 'Falhou';
      case 'paused':
        return 'Pausado';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.amber;
      case 'sent':
        return Colors.green;
      case 'cancelled':
        return Colors.grey;
      case 'failed':
        return Colors.redAccent;
      case 'paused':
        return Colors.orange;
      default:
        return Colors.white54;
    }
  }

  Future<void> _pause() async {
    final id = _s(_followUp?['id']);
    if (id.isEmpty) return;
    setState(() {
      _isLoading = true;
      _opError = null;
    });
    try {
      final resp = await http.post(
        Uri.parse(
          '${widget.baseUrl}/api/tickets/${widget.ticketId}/followup/$id/pause',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        final raw = decoded['followUp'];
        if (raw is Map) {
          setState(() => _followUp = Map<String, dynamic>.from(raw));
        }
      } else {
        setState(() => _opError = 'Erro ao pausar (${resp.statusCode})');
      }
    } catch (e) {
      setState(() => _opError = 'Erro de conexao');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resume() async {
    final id = _s(_followUp?['id']);
    if (id.isEmpty) return;
    setState(() {
      _isLoading = true;
      _opError = null;
    });
    try {
      final resp = await http.post(
        Uri.parse(
          '${widget.baseUrl}/api/tickets/${widget.ticketId}/followup/$id/resume',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        final raw = decoded['followUp'];
        if (raw is Map) {
          setState(() => _followUp = Map<String, dynamic>.from(raw));
        }
      } else {
        setState(() => _opError = 'Erro ao retomar (${resp.statusCode})');
      }
    } catch (e) {
      setState(() => _opError = 'Erro de conexao');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cancel() async {
    final id = _s(_followUp?['id']);
    if (id.isEmpty) return;
    setState(() {
      _isLoading = true;
      _opError = null;
    });
    try {
      final resp = await http.delete(
        Uri.parse(
          '${widget.baseUrl}/api/tickets/${widget.ticketId}/followup/$id',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        setState(() {
          _followUp = null;
          _showForm = true;
        });
      } else {
        setState(() => _opError = 'Erro ao cancelar (${resp.statusCode})');
      }
    } catch (e) {
      setState(() => _opError = 'Erro de conexao');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _create() async {
    final message = _messageCtrl.text.trim();
    if (message.isEmpty) {
      setState(() => _opError = 'Informe a mensagem do follow-up.');
      return;
    }
    if (_scheduledDate == null || _scheduledTime == null) {
      setState(() => _opError = 'Informe a data e hora.');
      return;
    }
    final scheduled = DateTime(
      _scheduledDate!.year,
      _scheduledDate!.month,
      _scheduledDate!.day,
      _scheduledTime!.hour,
      _scheduledTime!.minute,
    );
    if (scheduled.isBefore(DateTime.now())) {
      setState(() => _opError = 'A data deve ser no futuro.');
      return;
    }
    setState(() {
      _isLoading = true;
      _opError = null;
    });
    try {
      final resp = await http.post(
        Uri.parse(
          '${widget.baseUrl}/api/tickets/${widget.ticketId}/followup',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({
          'message': message,
          'scheduledFor': scheduled.toUtc().toIso8601String(),
          'type': 'followup',
        }),
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        final rawFu = decoded['followUp'] ?? decoded;
        if (rawFu is Map) {
          setState(() {
            _followUp = Map<String, dynamic>.from(rawFu);
            _showForm = false;
            _messageCtrl.clear();
            _scheduledDate = null;
            _scheduledTime = null;
          });
        } else {
          if (mounted) Navigator.pop(context);
        }
      } else {
        final decoded = jsonDecode(resp.body);
        final errMsg = _s(decoded['error']).isNotEmpty
            ? _s(decoded['error'])
            : 'Erro ao criar follow-up (${resp.statusCode})';
        setState(() => _opError = errMsg);
      }
    } catch (e) {
      setState(() => _opError = 'Erro de conexao');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _scheduledDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ??
          TimeOfDay.fromDateTime(
            DateTime.now().add(const Duration(hours: 1)),
          ),
    );
    if (picked != null && mounted) setState(() => _scheduledTime = picked);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.schedule_outlined,
                    color: Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Follow-up',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  if (widget.fetchError != null) _errorBox(widget.fetchError!),
                  if (_opError != null) _errorBox(_opError!),
                  if (_followUp != null) ...[_buildExistingCard(), const SizedBox(height: 16)],
                  _buildNewForm(context),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
      ),
      child: Text(
        msg,
        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
      ),
    );
  }

  Widget _buildExistingCard() {
    final fu = _followUp!;
    final status = _s(fu['status']);
    final message = _s(fu['message']);
    final scheduledFor = _s(fu['scheduledFor']);
    DateTime? scheduledDt;
    if (scheduledFor.isNotEmpty) {
      scheduledDt = DateTime.tryParse(scheduledFor)?.toLocal();
    }
    final canPause = status == 'pending';
    final canResume = status == 'paused';
    final canCancel = status == 'pending' || status == 'paused';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2733),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: _statusColor(status).withOpacity(0.4)),
                ),
                child: Text(_statusLabel(status),
                    style: TextStyle(
                        color: _statusColor(status),
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
              if (scheduledDt != null) ...[
                const SizedBox(width: 8),
                Text(_formatDt(scheduledDt),
                    style: const TextStyle(color: Colors.white54, fontSize: 11))
              ],
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(message,
                style: const TextStyle(color: Colors.white70, fontSize: 13))
          ],
          if (canPause || canResume || canCancel) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (canPause)
                  _actionBtn(
                      label: 'Pausar',
                      icon: Icons.pause_outlined,
                      color: Colors.orange,
                      onPressed: _isLoading ? null : _pause),
                if (canResume) ...[
                  if (canPause) const SizedBox(width: 8),
                  _actionBtn(
                      label: 'Retomar',
                      icon: Icons.play_arrow_outlined,
                      color: Colors.green,
                      onPressed: _isLoading ? null : _resume)
                ],
                if (canCancel) ...[
                  const SizedBox(width: 8),
                  _actionBtn(
                      label: 'Cancelar',
                      icon: Icons.close,
                      color: Colors.redAccent,
                      onPressed: _isLoading ? null : _cancel)
                ],
                if (_isLoading) ...[
                  const SizedBox(width: 10),
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white54))
                ],
              ],
            )
          ],
        ],
      ),
    );
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 12)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withOpacity(0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildNewForm(BuildContext context) {
    final dateLabel = _scheduledDate != null
        ? '${_pad(_scheduledDate!.day)}/${_pad(_scheduledDate!.month)}/${_scheduledDate!.year}'
        : 'Selecionar data';
    final timeLabel = _scheduledTime != null
        ? '${_pad(_scheduledTime!.hour)}:${_pad(_scheduledTime!.minute)}'
        : 'Selecionar hora';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_followUp != null)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Novo follow-up',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        TextField(
          controller: _messageCtrl,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Mensagem do follow-up...',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF0D1117),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.blue)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(dateLabel, style: const TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white12),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.access_time_outlined, size: 16),
                label: Text(timeLabel, style: const TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white12),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
          onPressed: _isLoading ? null : _create,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Agendar Follow-up'),
        ),
      ],
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
