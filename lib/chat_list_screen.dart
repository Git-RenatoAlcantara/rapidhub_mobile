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
import 'theme/app_theme.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_logo.dart';

enum _ChatListTab {
  ai,
  ativos,
  grupos,
}

class _ChatListFilters {
  const _ChatListFilters({
    this.search = '',
    this.searchAllMessages = false,
    this.statusIds = const <String>[],
    this.attendantIds = const <String>[],
    this.departments = const <String>[],
    this.tags = const <String>[],
    this.connectionIds = const <String>[],
    this.dateFrom,
    this.dateTo,
  });

  final String search;
  final bool searchAllMessages;
  final List<String> statusIds;
  final List<String> attendantIds;
  final List<String> departments;
  final List<String> tags;
  final List<String> connectionIds;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  bool get hasAny =>
      search.trim().isNotEmpty ||
      searchAllMessages ||
      statusIds.isNotEmpty ||
      attendantIds.isNotEmpty ||
      departments.isNotEmpty ||
      tags.isNotEmpty ||
      connectionIds.isNotEmpty ||
      dateFrom != null ||
      dateTo != null;

  int get appliedCount {
    var count = 0;
    if (search.trim().isNotEmpty) {
      count++;
    }
    if (searchAllMessages) {
      count++;
    }
    if (statusIds.isNotEmpty) {
      count++;
    }
    if (attendantIds.isNotEmpty) {
      count++;
    }
    if (departments.isNotEmpty) {
      count++;
    }
    if (tags.isNotEmpty) {
      count++;
    }
    if (connectionIds.isNotEmpty) {
      count++;
    }
    if (dateFrom != null) {
      count++;
    }
    if (dateTo != null) {
      count++;
    }
    return count;
  }
}

class _FilterOption {
  const _FilterOption({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;
}

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  static const int _chatListCursorPageSize = 40;
  static const double _chatListLoadMoreThreshold = 220;

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ScrollController _chatListScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<dynamic>? _ticketsStreamSubscription;

  String _quickSearch = '';

  List<Map<String, dynamic>> _chats = <Map<String, dynamic>>[];
  _ChatListTab _activeTab = _ChatListTab.ativos;
  int? _apiAiCount;
  int? _apiAtivosCount;
  int? _apiGruposCount;
  int? _apiArquivadosCount;
  bool _isLoading = true;
  bool _isLoadingMoreChats = false;
  bool _hasMoreChats = true;
  String? _nextCursor;
  bool _didShowPaginationHint = false;
  String _errorMessage = '';
  _ChatListFilters _filters = const _ChatListFilters();

  @override
  void initState() {
    super.initState();
    _chatListScrollController.addListener(_handleChatListScroll);
    _carregarChats();
    _startListeningToChatListUpdates();
  }

  void _handleChatListScroll() {
    if (!_chatListScrollController.hasClients ||
        _isLoading ||
        _isLoadingMoreChats ||
        !_hasMoreChats) {
      return;
    }

    final position = _chatListScrollController.position;
    final shouldLoadMore =
        position.pixels >=
        (position.maxScrollExtent - _chatListLoadMoreThreshold);
    if (shouldLoadMore) {
      _carregarChats(loadMore: true);
    }
  }

  Uri _buildChatsUri({required bool loadMore}) {
    final query = <String, List<String>>{
      'limit': <String>[_chatListCursorPageSize.toString()],
    };
    final cursor = _asString(_nextCursor).trim();
    if (loadMore && cursor.isNotEmpty) {
      query['cursor'] = <String>[cursor];
    }
    _appendChatFilters(query);

    final queryString = _buildQueryString(query);
    if (queryString.isEmpty) {
      return Uri.parse('$baseUrl/api/chats');
    }
    return Uri.parse('$baseUrl/api/chats?$queryString');
  }

  String _buildQueryString(Map<String, List<String>> query) {
    final parts = <String>[];
    for (final entry in query.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) {
        continue;
      }
      for (final value in entry.value) {
        final cleanValue = value.trim();
        if (cleanValue.isEmpty) {
          continue;
        }
        parts.add(
          '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(cleanValue)}',
        );
      }
    }
    return parts.join('&');
  }

  void _appendChatFilters(Map<String, List<String>> query) {
    final search = _filters.search.trim();
    if (search.isNotEmpty) {
      query['search'] = <String>[search];
    }
    if (_filters.searchAllMessages && search.isNotEmpty) {
      query['searchAllMessages'] = const <String>['true'];
    }

    final normalizedStatuses = _filters.statusIds
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toList();
    final enumStatuses = normalizedStatuses
        .where((value) => value == 'open' || value == 'pending' || value == 'closed')
        .toList();
    final pipelineStatusIds = normalizedStatuses
        .where((value) => value != 'open' && value != 'pending' && value != 'closed')
        .toList();
    _appendMultiValueFilter(query, 'status', enumStatuses);
    _appendMultiValueFilter(query, 'ticketStatus', enumStatuses);
    _appendMultiValueFilter(query, 'statusId', pipelineStatusIds);

    final attendantIds = _filters.attendantIds
        .where((value) => _looksLikeId(value))
        .toList();
    _appendMultiValueFilter(query, 'attendantId', attendantIds);
    _appendMultiValueFilter(query, 'responsibleId', attendantIds);

    _appendMultiValueFilter(query, 'department', _filters.departments);
    _appendMultiValueFilter(query, 'tag', _filters.tags);
    final connectionIds = _filters.connectionIds
        .where((value) => _looksLikeId(value))
        .toList();
    _appendMultiValueFilter(query, 'connectionId', connectionIds);
    if (_filters.dateFrom != null) {
      query['dateFrom'] = <String>[_formatDateForApi(_filters.dateFrom!)];
    }
    if (_filters.dateTo != null) {
      query['dateTo'] = <String>[_formatDateForApi(_filters.dateTo!)];
    }
  }

  void _appendMultiValueFilter(
    Map<String, List<String>> query,
    String key,
    List<String> values,
  ) {
    if (values.isEmpty) {
      return;
    }
    query[key] = values;
  }

  String _formatDateForApi(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatDateForLabel(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString().padLeft(4, '0');
    return '$day/$month/$year';
  }

  List<String> _parseFilterList(String raw) {
    final values = raw
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final seen = <String>{};
    final unique = <String>[];
    for (final value in values) {
      final key = value.toLowerCase();
      if (seen.add(key)) {
        unique.add(value);
      }
    }
    return unique;
  }

  bool _looksLikeId(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(r'^[a-zA-Z0-9_-]{8,}$').hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  String _toTitleCase(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }
    return normalized
        .split(RegExp(r'\s+'))
        .map((word) {
          if (word.isEmpty) {
            return '';
          }
          return '${word[0].toUpperCase()}${word.substring(1)}';
        })
        .join(' ');
  }

  String _statusLabelFromValue(String rawStatus) {
    final normalized = rawStatus.trim().toLowerCase();
    if (normalized == 'open' ||
        normalized == 'aberto' ||
        normalized == 'ativo' ||
        normalized == 'ativos') {
      return 'Ativos';
    }
    if (normalized == 'pending' ||
        normalized == 'pendente' ||
        normalized == 'pendentes' ||
        normalized == 'ia' ||
        normalized == 'ai') {
      return 'IA';
    }
    if (normalized == 'closed' ||
        normalized == 'arquivado' ||
        normalized == 'arquivados' ||
        normalized == 'archived') {
      return 'Arquivados';
    }
    return _toTitleCase(normalized);
  }

  List<_FilterOption> _sortedOptionsFromMap(
    Map<String, String> source, {
    int limit = 60,
  }) {
    final options = source.entries
        .map(
          (entry) => _FilterOption(
            value: entry.key,
            label: entry.value,
          ),
        )
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    if (options.length <= limit) {
      return options;
    }
    return options.take(limit).toList();
  }

  List<String> _resolveSelectedLabels(
    List<String> selectedValues,
    List<_FilterOption> options,
  ) {
    if (selectedValues.isEmpty) {
      return const <String>[];
    }
    final labelsByValue = <String, String>{
      for (final option in options) option.value: option.label,
    };
    return selectedValues
        .map((value) => labelsByValue[value] ?? value)
        .toList();
  }

  List<_FilterOption> _buildStatusFilterOptions() {
    final optionsByLabel = <String, _FilterOption>{};
    for (final chat in _chats) {
      final normalizedStatus = _normalizeTicketStatus(_asString(chat['ticketStatus']));
      final fallbackStatus = _firstNonEmpty([
        normalizedStatus,
        _asString(chat['status']),
        _asString(chat['statusId']),
        _asString(chat['ticketStatusId']),
      ]);
      if (fallbackStatus.isEmpty) {
        continue;
      }
      final label = _statusLabelFromValue(fallbackStatus);
      if (label.isEmpty) {
        continue;
      }
      final value = label == 'IA'
          ? 'pending'
          : label == 'Ativos'
              ? 'open'
              : label == 'Arquivados'
                  ? 'closed'
                  : fallbackStatus;
      optionsByLabel[label.toLowerCase()] = _FilterOption(
        value: value,
        label: label,
      );
    }
    final options = optionsByLabel.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return options.take(20).toList();
  }

  List<_FilterOption> _buildAttendantFilterOptions() {
    final values = <String, String>{};
    for (final chat in _chats) {
      final attendantId = _asString(chat['attendantId']).trim();
      final attendantName = _firstNonEmpty([
        _asString(chat['agent']),
        _asString(chat['attendantName']),
        _asString(chat['activeAgentName']),
        attendantId,
      ]);
      final value = attendantId.isNotEmpty ? attendantId : attendantName;
      if (value.isEmpty || attendantName.isEmpty) {
        continue;
      }
      values[value] = attendantName;
    }
    return _sortedOptionsFromMap(values, limit: 40);
  }

  List<_FilterOption> _buildDepartmentFilterOptions() {
    final values = <String, String>{};
    for (final chat in _chats) {
      final department = _asString(chat['department']).trim();
      if (department.isEmpty) {
        continue;
      }
      values[department] = department;
    }
    return _sortedOptionsFromMap(values, limit: 40);
  }

  List<_FilterOption> _buildTagFilterOptions() {
    final values = <String, String>{};
    for (final chat in _chats) {
      final tagsRaw = chat['contactTags'];
      if (tagsRaw is! List) {
        continue;
      }
      for (final tag in tagsRaw) {
        final value = _asString(tag).trim();
        if (value.isEmpty) {
          continue;
        }
        values[value] = value;
      }
    }
    return _sortedOptionsFromMap(values, limit: 60);
  }

  List<_FilterOption> _buildConnectionFilterOptions() {
    final values = <String, String>{};
    for (final chat in _chats) {
      final connectionId = _asString(chat['connectionId']).trim();
      final connectionLabel = _asString(chat['connection']).trim();
      final value = connectionId.isNotEmpty ? connectionId : connectionLabel;
      final label = connectionLabel.isNotEmpty ? connectionLabel : value;
      if (value.isEmpty || label.isEmpty) {
        continue;
      }
      values[value] = label;
    }
    return _sortedOptionsFromMap(values, limit: 40);
  }

  DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _endOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day, 23, 59, 59, 999);
  }

  bool _containsIgnoreCase(List<String> values, String candidate) {
    final normalizedCandidate = candidate.trim().toLowerCase();
    if (normalizedCandidate.isEmpty) {
      return false;
    }
    return values.any((value) => value.trim().toLowerCase() == normalizedCandidate);
  }

  bool _matchesClientFilters(Map<String, dynamic> chat) {
    if (!_filters.hasAny) {
      return true;
    }

    final search = _filters.search.trim().toLowerCase();
    if (search.isNotEmpty) {
      final canMatch = <String>[
        _asString(chat['name']),
        _asString(chat['lastMessage']),
        _asString(chat['department']),
        _asString(chat['agent']),
        _asString(chat['connection']),
      ].any((value) => value.toLowerCase().contains(search));
      if (!canMatch) {
        return false;
      }
    }

    if (_filters.statusIds.isNotEmpty) {
      final normalizedTicketStatus = _normalizeTicketStatus(_asString(chat['ticketStatus']));
      final normalizedStatusLabel = _statusLabelFromValue(normalizedTicketStatus).toLowerCase();
      final statusIdCandidates = <String>[
        _asString(chat['statusId']),
        _asString(chat['ticketStatusId']),
        _asString(chat['ticketStatus']),
        normalizedTicketStatus,
        normalizedStatusLabel,
      ];
      final statusMatches = statusIdCandidates.any(
        (statusId) => _containsIgnoreCase(_filters.statusIds, statusId),
      );
      if (!statusMatches) {
        return false;
      }
    }

    if (_filters.attendantIds.isNotEmpty) {
      final attendantCandidates = <String>[
        _asString(chat['attendantId']),
        _asString(chat['agent']),
        _asString(chat['attendantName']),
      ];
      final attendantMatches = attendantCandidates.any(
        (attendant) => _containsIgnoreCase(_filters.attendantIds, attendant),
      );
      if (!attendantMatches) {
        return false;
      }
    }

    if (_filters.departments.isNotEmpty &&
        !_containsIgnoreCase(_filters.departments, _asString(chat['department']))) {
      return false;
    }

    if (_filters.connectionIds.isNotEmpty) {
      final connectionCandidates = <String>[
        _asString(chat['connectionId']),
        _asString(chat['connection']),
      ];
      final connectionMatches = connectionCandidates.any(
        (connection) => _containsIgnoreCase(_filters.connectionIds, connection),
      );
      if (!connectionMatches) {
        return false;
      }
    }

    if (_filters.tags.isNotEmpty) {
      final tagsRaw = chat['contactTags'];
      final tags = tagsRaw is List
          ? tagsRaw
              .map((tag) => _asString(tag).trim())
              .where((tag) => tag.isNotEmpty)
              .toList()
          : <String>[];
      final hasTagMatch = tags.any((tag) => _containsIgnoreCase(_filters.tags, tag));
      if (!hasTagMatch) {
        return false;
      }
    }

    if (_filters.dateFrom != null || _filters.dateTo != null) {
      final updatedAtRaw = _firstNonEmpty([
        _asString(chat['updatedAt']),
        _asString(chat['updatedAtRaw']),
      ]);
      final updatedAt = DateTime.tryParse(updatedAtRaw)?.toLocal();
      if (updatedAt == null) {
        return false;
      }
      if (_filters.dateFrom != null && updatedAt.isBefore(_startOfDay(_filters.dateFrom!))) {
        return false;
      }
      if (_filters.dateTo != null && updatedAt.isAfter(_endOfDay(_filters.dateTo!))) {
        return false;
      }
    }

    return true;
  }

  String _compactFilterValues(List<String> values) {
    if (values.isEmpty) {
      return '';
    }
    if (values.length <= 2) {
      return values.join(', ');
    }
    return '${values.take(2).join(', ')} +${values.length - 2}';
  }

  List<Widget> _buildFilterChips() {
    if (!_filters.hasAny) {
      return const <Widget>[];
    }

    final statusOptions = _buildStatusFilterOptions();
    final attendantOptions = _buildAttendantFilterOptions();
    final departmentOptions = _buildDepartmentFilterOptions();
    final tagOptions = _buildTagFilterOptions();
    final connectionOptions = _buildConnectionFilterOptions();

    final statusLabels = _resolveSelectedLabels(_filters.statusIds, statusOptions)
        .map((label) {
          final normalized = _statusLabelFromValue(label);
          return normalized.isNotEmpty ? normalized : label;
        })
        .toList();
    final attendantLabels =
        _resolveSelectedLabels(_filters.attendantIds, attendantOptions);
    final departmentLabels =
        _resolveSelectedLabels(_filters.departments, departmentOptions);
    final tagLabels = _resolveSelectedLabels(_filters.tags, tagOptions);
    final connectionLabels =
        _resolveSelectedLabels(_filters.connectionIds, connectionOptions);

    final chips = <Widget>[];
    final search = _filters.search.trim();
    if (search.isNotEmpty) {
      chips.add(
        Chip(
          label: Text(
            'Busca: $search',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          backgroundColor: const Color(0xFF1E2733),
          side: const BorderSide(color: Colors.white24),
        ),
      );
    }
    if (_filters.searchAllMessages) {
      chips.add(
        const Chip(
          label: Text(
            'Todas mensagens',
            style: TextStyle(color: Colors.white, fontSize: 11),
          ),
          backgroundColor: Color(0xFF1E2733),
          side: BorderSide(color: Colors.white24),
        ),
      );
    }
    if (_filters.statusIds.isNotEmpty) {
      chips.add(
        Chip(
          label: Text(
            'Status: ${_compactFilterValues(statusLabels)}',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          backgroundColor: const Color(0xFF1E2733),
          side: const BorderSide(color: Colors.white24),
        ),
      );
    }
    if (_filters.attendantIds.isNotEmpty) {
      chips.add(
        Chip(
          label: Text(
            'Responsavel: ${_compactFilterValues(attendantLabels)}',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          backgroundColor: const Color(0xFF1E2733),
          side: const BorderSide(color: Colors.white24),
        ),
      );
    }
    if (_filters.departments.isNotEmpty) {
      chips.add(
        Chip(
          label: Text(
            'Departamento: ${_compactFilterValues(departmentLabels)}',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          backgroundColor: const Color(0xFF1E2733),
          side: const BorderSide(color: Colors.white24),
        ),
      );
    }
    if (_filters.tags.isNotEmpty) {
      chips.add(
        Chip(
          label: Text(
            'Tags: ${_compactFilterValues(tagLabels)}',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          backgroundColor: const Color(0xFF1E2733),
          side: const BorderSide(color: Colors.white24),
        ),
      );
    }
    if (_filters.connectionIds.isNotEmpty) {
      chips.add(
        Chip(
          label: Text(
            'Conexao: ${_compactFilterValues(connectionLabels)}',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          backgroundColor: const Color(0xFF1E2733),
          side: const BorderSide(color: Colors.white24),
        ),
      );
    }
    if (_filters.dateFrom != null) {
      chips.add(
        Chip(
          label: Text(
            'De: ${_formatDateForLabel(_filters.dateFrom!)}',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          backgroundColor: const Color(0xFF1E2733),
          side: const BorderSide(color: Colors.white24),
        ),
      );
    }
    if (_filters.dateTo != null) {
      chips.add(
        Chip(
          label: Text(
            'Ate: ${_formatDateForLabel(_filters.dateTo!)}',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          backgroundColor: const Color(0xFF1E2733),
          side: const BorderSide(color: Colors.white24),
        ),
      );
    }

    return chips;
  }

  List<dynamic> _extractRawChats(dynamic payload) {
    if (payload is List) {
      return payload;
    }

    if (payload is! Map) {
      return const <dynamic>[];
    }

    if (payload['chats'] is List) {
      return payload['chats'] as List<dynamic>;
    }
    if (payload['tickets'] is List) {
      return payload['tickets'] as List<dynamic>;
    }

    final nested = payload['data'];
    if (nested is Map) {
      if (nested['chats'] is List) {
        return nested['chats'] as List<dynamic>;
      }
      if (nested['tickets'] is List) {
        return nested['tickets'] as List<dynamic>;
      }
    }

    return const <dynamic>[];
  }

  int? _extractOptionalCount(dynamic payload, List<String> keys) {
    if (payload is! Map) {
      return null;
    }

    dynamic value;
    for (final key in keys) {
      if (payload.containsKey(key) && payload[key] != null) {
        value = payload[key];
        break;
      }
    }

    if (value == null && payload['meta'] is Map) {
      final meta = payload['meta'] as Map;
      for (final key in keys) {
        if (meta.containsKey(key) && meta[key] != null) {
          value = meta[key];
          break;
        }
      }
    }

    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }

  Map<String, int?> _extractApiCounts(dynamic payload) {
    if (payload is! Map) {
      return <String, int?>{
        'ai': null,
        'ativos': null,
        'grupos': null,
        'arquivados': null,
      };
    }

    final countsRaw = payload['counts'] ??
        payload['tabs'] ??
        payload['totals'] ??
        payload['summary'] ??
        (payload['meta'] is Map ? (payload['meta'] as Map)['counts'] : null);
    final counts = countsRaw is Map ? countsRaw : payload;

    return <String, int?>{
      'ai': _extractOptionalCount(counts, const [
        'ai',
        'pending',
        'pendentes',
      ]),
      'ativos': _extractOptionalCount(counts, const [
        'active',
        'ativos',
        'open',
      ]),
      'grupos': _extractOptionalCount(counts, const [
        'groups',
        'grupos',
        'department',
        'departments',
        'departmentCount',
        'departmentsCount',
        'departamento',
      ]),
      'arquivados': _extractOptionalCount(counts, const [
        'archived',
        'arquivados',
        'closed',
      ]),
    };
  }

  String _extractNextCursor(dynamic payload) {
    if (payload is! Map) {
      return '';
    }

    final dynamic pagination =
        payload['pagination'] ??
        payload['meta'] ??
        payload['pageInfo'] ??
        payload['page_info'];

    return _asString(
      payload['nextCursor'] ??
          payload['next_cursor'] ??
          payload['cursor'] ??
          (pagination is Map
              ? (pagination['nextCursor'] ??
                  pagination['next_cursor'] ??
                  pagination['cursor'])
              : null),
    ).trim();
  }

  bool? _extractHasMoreFromPayload(dynamic payload, {required String nextCursor}) {
    if (payload is! Map) {
      return null;
    }

    bool? directHasMore;
    final dynamic pagination =
        payload['pagination'] ??
        payload['meta'] ??
        payload['pageInfo'] ??
        payload['page_info'];
    if (pagination is Map && pagination['hasMore'] is bool) {
      directHasMore = pagination['hasMore'] as bool;
    } else if (pagination is Map && pagination['hasNextPage'] is bool) {
      directHasMore = pagination['hasNextPage'] as bool;
    } else if (payload['hasMore'] is bool) {
      directHasMore = payload['hasMore'] as bool;
    } else if (payload['hasNextPage'] is bool) {
      directHasMore = payload['hasNextPage'] as bool;
    }
    if (directHasMore != null) {
      return directHasMore;
    }
    if (nextCursor.isNotEmpty) {
      return true;
    }

    return null;
  }

  int _mergeChatsPage(List<Map<String, dynamic>> incomingChats) {
    var addedCount = 0;
    for (final incoming in incomingChats) {
      final id = _asString(incoming['id']);
      if (id.isEmpty) {
        continue;
      }

      final existingIndex =
          _chats.indexWhere((chat) => _asString(chat['id']) == id);
      if (existingIndex >= 0) {
        _chats[existingIndex] = <String, dynamic>{
          ..._chats[existingIndex],
          ...incoming,
        };
        continue;
      }

      _chats.add(incoming);
      addedCount++;
    }
    return addedCount;
  }
  Future<void> _carregarChats({bool loadMore = false}) async {
    if (loadMore) {
      if (_isLoading || _isLoadingMoreChats || !_hasMoreChats) {
        return;
      }
      if ((_nextCursor ?? '').trim().isEmpty) {
        setState(() {
          _hasMoreChats = false;
        });
        return;
      }
    }

    if (mounted) {
      setState(() {
        if (loadMore) {
          _isLoadingMoreChats = true;
        } else {
          _isLoading = true;
          _errorMessage = '';
          _hasMoreChats = true;
          _nextCursor = null;
          _didShowPaginationHint = false;
        }
      });
    }

    try {
      final token = await _storage.read(key: 'session_token');
      final chatsUri = _buildChatsUri(loadMore: loadMore);
      debugPrint('[ChatList] GET $chatsUri');
      final response = await http.get(
        chatsUri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);
        final counts = _extractApiCounts(data);
        final nextCursor = _extractNextCursor(data);
        final hasMoreFromApi = _extractHasMoreFromPayload(
          data,
          nextCursor: nextCursor,
        );
        final List<dynamic> rawChats = _extractRawChats(data);
        final chats = rawChats
            .whereType<Map>()
            .map((chat) => _normalizeChat(Map<String, dynamic>.from(chat)))
            .toList();

        if (!mounted) {
          return;
        }

        var addedCount = 0;

        setState(() {
          addedCount = loadMore ? _mergeChatsPage(chats) : chats.length;

          if (!loadMore) {
            _chats = chats;
          }

          _apiAiCount = counts['ai'] ?? _apiAiCount;
          _apiAtivosCount = counts['ativos'] ?? _apiAtivosCount;
          _apiGruposCount = counts['grupos'] ?? _apiGruposCount;
          _apiArquivadosCount = counts['arquivados'] ?? _apiArquivadosCount;
          _nextCursor = nextCursor.isNotEmpty ? nextCursor : null;

          if (hasMoreFromApi != null) {
            _hasMoreChats = hasMoreFromApi;
          } else {
            _hasMoreChats = loadMore ? addedCount > 0 : chats.isNotEmpty;
          }

          if (loadMore && addedCount == 0 && _nextCursor == null) {
            _hasMoreChats = false;
          }

          _isLoading = false;
          _isLoadingMoreChats = false;
        });

        if (loadMore && addedCount == 0 && !_didShowPaginationHint && mounted) {
          _didShowPaginationHint = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'O servidor nao retornou novas conversas para o cursor informado.',
              ),
              duration: Duration(seconds: 3),
            ),
          );
        }

        _hydrateChatsContactMeta();
      } else {
        if (!mounted) {
          return;
        }
        setState(() {
          if (!loadMore) {
            _errorMessage =
                'Erro ao carregar conversas. (Codigo: ${response.statusCode})';
            _apiAiCount = null;
            _apiAtivosCount = null;
            _apiGruposCount = null;
            _apiArquivadosCount = null;
          }
          if (loadMore) {
            _hasMoreChats = false;
          }
          _isLoading = false;
          _isLoadingMoreChats = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar chats: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        if (!loadMore) {
          _errorMessage = 'Erro de conexao. Verifica a tua internet.';
          _apiAiCount = null;
          _apiAtivosCount = null;
          _apiGruposCount = null;
          _apiArquivadosCount = null;
        }
        _isLoading = false;
        _isLoadingMoreChats = false;
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
    final detailsByChatId = <String, Map<String, dynamic>>{};
    final missingDetailsFor = <String>[];

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
      }

      final missingDepartment = _asString(chat['department']).trim().isEmpty;
      final missingAttendant = _asString(chat['attendantId']).trim().isEmpty;
      final missingStatus = _asString(chat['statusId']).trim().isEmpty &&
          _asString(chat['ticketStatus']).trim().isEmpty;
      final needsDetails = contactId.isEmpty ||
          knownConnectionId.isEmpty ||
          missingDepartment ||
          missingAttendant ||
          missingStatus;
      if (needsDetails) {
        missingDetailsFor.add(chatId);
      }
    }

    if (missingDetailsFor.isNotEmpty) {
      // Busca os detalhes em lotes para não abrir dezenas de conexões HTTP de
      // uma só vez. Cada requisição é isolada: uma falha de rede vira `null` e
      // não derruba as demais (um `Future.wait` cru rejeitaria tudo se uma
      // única `http.get` lançasse exceção). A ordem é preservada para manter o
      // alinhamento com `missingDetailsFor[i]` no loop abaixo.
      const batchSize = 6;
      final responses = <http.Response?>[];
      for (var start = 0;
          start < missingDetailsFor.length;
          start += batchSize) {
        final batch = missingDetailsFor.skip(start).take(batchSize);
        final batchResponses = await Future.wait(
          batch.map((chatId) async {
            try {
              return await http.get(
                Uri.parse('$baseUrl/api/chats/$chatId'),
                headers: headers,
              );
            } catch (_) {
              return null;
            }
          }),
        );
        responses.addAll(batchResponses);
      }

      for (var i = 0; i < responses.length; i++) {
        final resp = responses[i];
        if (resp == null || resp.statusCode != 200) {
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
          detailsByChatId[missingDetailsFor[i]] = details;
          final contactId = _asString(details['contactId']);
          final connectionId = _asString(details['connectionId']);
          final ticketConnection = _extractConnectionLabel(details);

          if (contactId.isNotEmpty) {
            contactIdByChatId[missingDetailsFor[i]] = contactId;
          }
          if (connectionId.isNotEmpty) {
            connectionIdByChatId[missingDetailsFor[i]] = connectionId;
          }
          if (ticketConnection.isNotEmpty) {
            connectionLabelByChatId[missingDetailsFor[i]] = ticketConnection;
          }
        } catch (_) {}
      }
    }

    if (contactIdByChatId.isEmpty &&
        connectionIdByChatId.isEmpty &&
        detailsByChatId.isEmpty) {
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
        final details = detailsByChatId[chatId] ?? const <String, dynamic>{};
        final mergedChat = {
          ...chat,
          ...details,
        };
        final contactId =
            contactIdByChatId[chatId] ?? _asString(mergedChat['contactId']);
        final connectionId =
            connectionIdByChatId[chatId] ?? _asString(mergedChat['connectionId']);
        final connectionLabel = _firstNonEmpty([
          _extractConnectionLabel(mergedChat),
          connectionLabelByChatId[chatId] ?? '',
        ]);

        final baseChat = {
          ...mergedChat,
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
    return status == 'pending';
  }

  bool _isAtivoChat(Map<String, dynamic> chat) {
    final status = _asString(chat['ticketStatus']).toLowerCase();
    return status == 'open';
  }

  bool _isArchivedChat(Map<String, dynamic> chat) {
    final status = _asString(chat['ticketStatus']).toLowerCase();
    return status == 'closed';
  }

  bool _isGrupoChat(Map<String, dynamic> chat) {
    final status = _asString(chat['ticketStatus']).toLowerCase();
    final department = _asString(chat['department']).trim();
    final departmentId = _asString(chat['departmentId']).trim();
    return (department.isNotEmpty || departmentId.isNotEmpty) &&
        status != 'closed';
  }

  int _resolveTabCount(int? apiCount, int localCount) {
    if (apiCount == null) {
      return localCount;
    }
    return apiCount < localCount ? localCount : apiCount;
  }

  List<Map<String, dynamic>> _visibleChats() {
    if (_activeTab == _ChatListTab.ai) {
      return _chats.where(_isAiChat).where(_matchesClientFilters).toList();
    }
    if (_activeTab == _ChatListTab.ativos) {
      return _chats.where(_isAtivoChat).where(_matchesClientFilters).toList();
    }
    return _chats.where(_isGrupoChat).where(_matchesClientFilters).toList();
  }

  String _asString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.toInt();
    }
    return int.tryParse(_asString(value)) ?? fallback;
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

  String _normalizeTicketStatus(String rawStatus) {
    final status = rawStatus.trim().toLowerCase();
    if (status.isEmpty) {
      return '';
    }
    if (status == 'open' || status == 'aberto' || status == 'ativo') {
      return 'open';
    }
    if (status == 'pending' || status == 'pendente') {
      return 'pending';
    }
    if (status == 'closed' || status == 'arquivado' || status == 'archived') {
      return 'closed';
    }
    return status;
  }

  Map<String, dynamic> _normalizeChat(Map<String, dynamic> chat) {
    final normalized = Map<String, dynamic>.from(chat);
    final ticketRaw = chat['ticket'];
    final ticket =
        ticketRaw is Map ? Map<String, dynamic>.from(ticketRaw) : <String, dynamic>{};
    final contactRaw = chat['contact'];
    final contact = contactRaw is Map
        ? Map<String, dynamic>.from(contactRaw)
        : <String, dynamic>{};

    final chatId = _firstNonEmpty([
      _asString(chat['id']),
      _asString(chat['ticketId']),
      _asString(chat['ticket_id']),
      _asString(ticket['id']),
    ]);
    if (chatId.isNotEmpty) {
      normalized['id'] = chatId;
    }

    final name = _firstNonEmpty([
      _asString(chat['name']),
      _asString(chat['contactName']),
      _asString(chat['contact_name']),
      _asString(contact['name']),
    ]);
    if (name.isNotEmpty) {
      normalized['name'] = name;
    }

    final lastMessage = _firstNonEmpty([
      _asString(chat['lastMessage']),
      _asString(chat['last_message']),
      _asString(chat['message']),
      _asString(ticket['lastMessage']),
    ], fallback: 'Sem mensagens');
    normalized['lastMessage'] = lastMessage;

    final unreadCount = _asInt(
      chat['unreadCount'],
      fallback: _asInt(
        chat['unreadMessages'],
        fallback: _asInt(ticket['unreadMessages']),
      ),
    );
    normalized['unreadCount'] = unreadCount;

    final rawTicketStatus = _firstNonEmpty([
      _asString(chat['ticketStatus']),
      _asString(chat['ticket_status']),
      _asString(chat['status']),
      _asString(ticket['status']),
    ]);
    final normalizedStatus = _normalizeTicketStatus(rawTicketStatus);
    if (normalizedStatus.isNotEmpty) {
      normalized['ticketStatus'] = normalizedStatus;
    }

    final isGroup = chat['isGroup'] == true ||
        chat['is_group'] == true ||
        chat['group'] == true ||
        ticket['isGroup'] == true;
    normalized['isGroup'] = isGroup;

    final chatDepartmentRaw = chat['department'];
    final contactDepartmentRaw = contact['department'];
    final ticketDepartmentRaw = ticket['department'];
    final chatDepartmentMap = chatDepartmentRaw is Map
        ? Map<String, dynamic>.from(chatDepartmentRaw)
        : <String, dynamic>{};
    final contactDepartmentMap = contactDepartmentRaw is Map
        ? Map<String, dynamic>.from(contactDepartmentRaw)
        : <String, dynamic>{};
    final ticketDepartmentMap = ticketDepartmentRaw is Map
        ? Map<String, dynamic>.from(ticketDepartmentRaw)
        : <String, dynamic>{};

    final department = _firstNonEmpty([
      _asString(chat['department']),
      _asString(chat['departmentName']),
      _asString(chat['department_name']),
      _asString(chatDepartmentMap['name']),
      _asString(chatDepartmentMap['label']),
      _asString(contact['department']),
      _asString(contactDepartmentMap['name']),
      _asString(contactDepartmentMap['label']),
      _asString(ticket['department']),
      _asString(ticketDepartmentMap['name']),
      _asString(ticketDepartmentMap['label']),
    ]);
    if (department.isNotEmpty) {
      normalized['department'] = department;
    }

    final departmentId = _firstNonEmpty([
      _asString(chat['departmentId']),
      _asString(chat['department_id']),
      _asString(ticket['departmentId']),
      _asString(ticket['department_id']),
    ]);
    if (departmentId.isNotEmpty) {
      normalized['departmentId'] = departmentId;
    }

    final rawTime = _firstNonEmpty([
      _asString(chat['time']),
      _asString(chat['updatedAt']),
      _asString(chat['lastSendMessageAt']),
      _asString(ticket['updatedAt']),
    ]);
    if (rawTime.isNotEmpty) {
      normalized['updatedAtRaw'] = rawTime;
      normalized['time'] = _formatRelativeTime(rawTime);
    }

    final avatar = _firstNonEmpty([
      _asString(chat['avatar']),
      _asString(contact['avatar']),
      _asString(contact['photo']),
    ]);
    if (avatar.isNotEmpty) {
      normalized['avatar'] = avatar;
    }

    final activeAgentRaw = chat['activeAgent'];
    final activeAgent = activeAgentRaw is Map
        ? Map<String, dynamic>.from(activeAgentRaw)
        : <String, dynamic>{};
    final agent = _firstNonEmpty([
      _asString(chat['agent']),
      _asString(chat['agentName']),
      _asString(chat['attendantName']),
      _asString(activeAgent['name']),
    ]);
    if (agent.isNotEmpty) {
      normalized['agent'] = agent;
    }

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

  void _clearFilters() {
    if (!_filters.hasAny) {
      return;
    }
    setState(() {
      _filters = const _ChatListFilters();
    });
    _carregarChats();
  }

  Future<void> _openFiltersSheet() async {
    final statusOptions = _buildStatusFilterOptions();
    final attendantOptions = _buildAttendantFilterOptions();
    final departmentOptions = _buildDepartmentFilterOptions();
    final tagOptions = _buildTagFilterOptions();
    final connectionOptions = _buildConnectionFilterOptions();

    final searchController = TextEditingController(text: _filters.search);
    var searchAllMessages = _filters.searchAllMessages;
    DateTime? dateFrom = _filters.dateFrom;
    DateTime? dateTo = _filters.dateTo;
    final selectedStatusValues = <String>{..._filters.statusIds};
    final selectedAttendantValues = <String>{..._filters.attendantIds};
    final selectedDepartmentValues = <String>{..._filters.departments};
    final selectedTagValues = <String>{..._filters.tags};
    final selectedConnectionValues = <String>{..._filters.connectionIds};

    final selectedFilters = await showModalBottomSheet<_ChatListFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F1722),
      builder: (modalContext) {
        Future<void> pickDate({
          required bool isFrom,
          required void Function(void Function()) updateModalState,
        }) async {
          final initialDate =
              isFrom ? (dateFrom ?? DateTime.now()) : (dateTo ?? DateTime.now());
          final pickedDate = await showDatePicker(
            context: modalContext,
            initialDate: initialDate,
            firstDate: DateTime(2000),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (pickedDate == null) {
            return;
          }
          updateModalState(() {
            if (isFrom) {
              dateFrom = pickedDate;
              if (dateTo != null && dateTo!.isBefore(pickedDate)) {
                dateTo = pickedDate;
              }
            } else {
              dateTo = pickedDate;
              if (dateFrom != null && dateFrom!.isAfter(pickedDate)) {
                dateFrom = pickedDate;
              }
            }
          });
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            final insets = MediaQuery.of(context).viewInsets.bottom;
            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 14, 16, insets + 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Filtrar Conversas',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              searchController.clear();
                              searchAllMessages = false;
                              dateFrom = null;
                              dateTo = null;
                              selectedStatusValues.clear();
                              selectedAttendantValues.clear();
                              selectedDepartmentValues.clear();
                              selectedTagValues.clear();
                              selectedConnectionValues.clear();
                            });
                          },
                          child: const Text('Limpar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildFilterInput(
                      controller: searchController,
                      label: 'Busca',
                      hint: 'Nome, mensagem, agente...',
                    ),
                    SwitchListTile.adaptive(
                      value: searchAllMessages,
                      onChanged: (value) {
                        setModalState(() {
                          searchAllMessages = value;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                      activeColor: Colors.blueAccent,
                      title: const Text(
                        'Buscar em todas as mensagens',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                    _buildFilterSelectSection(
                      icon: Icons.flag_outlined,
                      title: 'Status',
                      options: statusOptions,
                      selectedValues: selectedStatusValues,
                      emptyLabel: 'Nenhum status encontrado nas conversas.',
                      onToggle: (value) {
                        setModalState(() {
                          if (selectedStatusValues.contains(value)) {
                            selectedStatusValues.remove(value);
                          } else {
                            selectedStatusValues.add(value);
                          }
                        });
                      },
                    ),
                    _buildFilterSelectSection(
                      icon: Icons.support_agent_outlined,
                      title: 'Responsavel',
                      options: attendantOptions,
                      selectedValues: selectedAttendantValues,
                      emptyLabel: 'Nenhum responsavel encontrado nas conversas.',
                      onToggle: (value) {
                        setModalState(() {
                          if (selectedAttendantValues.contains(value)) {
                            selectedAttendantValues.remove(value);
                          } else {
                            selectedAttendantValues.add(value);
                          }
                        });
                      },
                    ),
                    _buildFilterSelectSection(
                      icon: Icons.apartment,
                      title: 'Departamento',
                      options: departmentOptions,
                      selectedValues: selectedDepartmentValues,
                      emptyLabel: 'Nenhum departamento encontrado nas conversas.',
                      onToggle: (value) {
                        setModalState(() {
                          if (selectedDepartmentValues.contains(value)) {
                            selectedDepartmentValues.remove(value);
                          } else {
                            selectedDepartmentValues.add(value);
                          }
                        });
                      },
                    ),
                    _buildFilterSelectSection(
                      icon: Icons.label_outline,
                      title: 'Tags',
                      options: tagOptions,
                      selectedValues: selectedTagValues,
                      emptyLabel: 'Nenhuma tag encontrada nas conversas.',
                      onToggle: (value) {
                        setModalState(() {
                          if (selectedTagValues.contains(value)) {
                            selectedTagValues.remove(value);
                          } else {
                            selectedTagValues.add(value);
                          }
                        });
                      },
                    ),
                    _buildFilterSelectSection(
                      icon: Icons.call_outlined,
                      title: 'Conexao',
                      options: connectionOptions,
                      selectedValues: selectedConnectionValues,
                      emptyLabel: 'Nenhuma conexao encontrada nas conversas.',
                      onToggle: (value) {
                        setModalState(() {
                          if (selectedConnectionValues.contains(value)) {
                            selectedConnectionValues.remove(value);
                          } else {
                            selectedConnectionValues.add(value);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Periodo',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickDate(
                              isFrom: true,
                              updateModalState: setModalState,
                            ),
                            icon: const Icon(Icons.date_range, size: 16),
                            label: Text(
                              dateFrom == null
                                  ? 'Data inicial'
                                  : _formatDateForLabel(dateFrom!),
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickDate(
                              isFrom: false,
                              updateModalState: setModalState,
                            ),
                            icon: const Icon(Icons.event, size: 16),
                            label: Text(
                              dateTo == null
                                  ? 'Data final'
                                  : _formatDateForLabel(dateTo!),
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              dateFrom = null;
                              dateTo = null;
                            });
                          },
                          child: const Text('Limpar datas'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                            ),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(
                                context,
                                () {
                                  final normalizedSearch =
                                      searchController.text.trim();
                                  final shouldSearchAll =
                                      normalizedSearch.isNotEmpty &&
                                      searchAllMessages;
                                  return _ChatListFilters(
                                    search: normalizedSearch,
                                    searchAllMessages: shouldSearchAll,
                                    statusIds: selectedStatusValues.toList(),
                                    attendantIds: selectedAttendantValues.toList(),
                                    departments: selectedDepartmentValues.toList(),
                                    tags: selectedTagValues.toList(),
                                    connectionIds: selectedConnectionValues.toList(),
                                    dateFrom: dateFrom,
                                    dateTo: dateTo,
                                  );
                                }(),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Aplicar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    searchController.dispose();

    if (selectedFilters == null || !mounted) {
      return;
    }

    setState(() {
      _filters = selectedFilters;
    });
    _carregarChats();
  }

  Widget _buildFilterSelectSection({
    required IconData icon,
    required String title,
    required List<_FilterOption> options,
    required Set<String> selectedValues,
    required String emptyLabel,
    required ValueChanged<String> onToggle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: Colors.white70),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              if (selectedValues.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
                  ),
                  child: Text(
                    selectedValues.length.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (options.isEmpty)
            Text(
              emptyLabel,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: options
                  .map(
                    (option) => FilterChip(
                      label: Text(
                        option.label,
                        style: TextStyle(
                          color: selectedValues.contains(option.value)
                              ? Colors.white
                              : Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      selected: selectedValues.contains(option.value),
                      onSelected: (_) => onToggle(option.value),
                      selectedColor: const Color(0xFF1D4ED8),
                      checkmarkColor: Colors.white,
                      backgroundColor: const Color(0xFF182335),
                      side: BorderSide(
                        color: selectedValues.contains(option.value)
                            ? const Color(0xFF60A5FA)
                            : Colors.white24,
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterInput({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: const Color(0xFF151F2B),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.blueAccent),
          ),
        ),
      ),
    );
  }

  Widget _buildChatBadge({
    required IconData icon,
    required String text,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
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
    IconData? icon,
    Color accent = AppColors.primary,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
          decoration: BoxDecoration(
            color: active ? accent : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? accent : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 15,
                    color: active ? Colors.white : accent),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: active ? FontWeight.bold : FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: active ? Colors.white : AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterButton(int appliedFiltersCount) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _openFiltersSheet,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderStrong),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            const Icon(Icons.tune, color: AppColors.textPrimary, size: 20),
            if (appliedFiltersCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    appliedFiltersCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ticketsStreamSubscription?.cancel();
    _chatListScrollController.removeListener(_handleChatListScroll);
    _chatListScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localAiCount = _chats.where(_isAiChat).length;
    final localAtivosCount = _chats.where(_isAtivoChat).length;
    final localGruposCount = _chats.where(_isGrupoChat).length;
    final localArchivedCount = _chats.where(_isArchivedChat).length;

    final aiCount = _resolveTabCount(_apiAiCount, localAiCount);
    final ativosCount = _resolveTabCount(_apiAtivosCount, localAtivosCount);
    final gruposCount = _resolveTabCount(_apiGruposCount, localGruposCount);
    final archivedCount =
        _resolveTabCount(_apiArquivadosCount, localArchivedCount);
    var visibleChats = _visibleChats();
    if (_quickSearch.trim().isNotEmpty) {
      final q = _quickSearch.trim().toLowerCase();
      visibleChats = visibleChats
          .where((c) =>
              _asString(c['name']).toLowerCase().contains(q) ||
              _asString(c['lastMessage']).toLowerCase().contains(q))
          .toList();
    }
    final appliedFiltersCount = _filters.appliedCount;
    final filterChips = _buildFilterChips();

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nova conversa estará disponível em breve.'),
              backgroundColor: AppColors.surface,
            ),
          );
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_comment_outlined),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          children: [
            AppLogo(),
            SizedBox(width: 10),
            Text('RapidHub',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
          ],
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: AppColors.primary),
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
                      color: AppColors.background,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (v) =>
                                  setState(() => _quickSearch = v),
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 14),
                              decoration: AppTheme.inputDecoration(
                                hint: 'Buscar conversas, contatos...',
                                prefixIcon: Icons.search,
                                suffixIcon: _quickSearch.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.close,
                                            size: 18,
                                            color: AppColors.textSecondary),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _quickSearch = '');
                                        },
                                      ),
                              ).copyWith(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _buildFilterButton(appliedFiltersCount),
                        ],
                      ),
                    ),
                    Container(
                      color: AppColors.background,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildTab(
                              label: 'IA',
                              count: aiCount,
                              icon: Icons.auto_awesome,
                              accent: AppColors.ai,
                              active: _activeTab == _ChatListTab.ai,
                              onTap: () {
                                setState(() => _activeTab = _ChatListTab.ai);
                              },
                            ),
                            _buildTab(
                              label: 'Ativos',
                              count: ativosCount,
                              accent: AppColors.primary,
                              active: _activeTab == _ChatListTab.ativos,
                              onTap: () {
                                setState(() => _activeTab = _ChatListTab.ativos);
                              },
                            ),
                            _buildTab(
                              label: 'Grupos',
                              count: gruposCount,
                              icon: Icons.groups_outlined,
                              accent: AppColors.success,
                              active: _activeTab == _ChatListTab.grupos,
                              onTap: () {
                                setState(() => _activeTab = _ChatListTab.grupos);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (filterChips.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        color: const Color(0xFF161B22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Filtros ativos',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: _clearFilters,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    minimumSize: const Size(0, 0),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Limpar',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: filterChips,
                            ),
                          ],
                        ),
                      ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF161B22),
                        border: Border(
                          top: BorderSide(color: Colors.white10),
                          bottom: BorderSide(color: Colors.white10),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.inventory_2_outlined,
                            color: Colors.white60,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'ARQUIVADOS',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              archivedCount.toString(),
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
                                        : 'Nenhum departamento encontrado.',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              controller: _chatListScrollController,
                              itemCount:
                                  visibleChats.length +
                                  ((_isLoadingMoreChats || _hasMoreChats) ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= visibleChats.length) {
                                  if (_isLoadingMoreChats) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 18),
                                      child: Center(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white54,
                                              ),
                                            ),
                                            SizedBox(width: 10),
                                            Text(
                                              'Carregando mais conversas...',
                                              style: TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }

                                  if (_hasMoreChats) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      _carregarChats(loadMore: true);
                                    });
                                    return const SizedBox(height: 14);
                                  }

                                  return const Padding(
                                    padding: EdgeInsets.only(bottom: 8),
                                    child: SizedBox.shrink(),
                                  );
                                }

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
                                final department = _asString(chat['department']).trim();
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

                                final isAi = ticketStatus == 'pending';
                                final isOnline = ticketStatus == 'open';

                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 0, 16, 10),
                                  child: Material(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ChatScreen(
                                              chatId: chatId,
                                              initialTicketStatus: ticketStatus,
                                              initialChatName:
                                                  _asString(chat['name']),
                                              initialConnectionLabel:
                                                  rawConnection,
                                              initialContactTags: contactTags,
                                            ),
                                          ),
                                        );
                                        _carregarChats();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                            color: unreadCount > 0
                                                ? AppColors.primary
                                                    .withValues(alpha: 0.5)
                                                : AppColors.border,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Stack(
                                              children: [
                                                CircleAvatar(
                                                  radius: 24,
                                                  backgroundColor:
                                                      AppColors.surfaceAlt,
                                                  backgroundImage:
                                                      avatarUrl != null
                                                          ? NetworkImage(
                                                              avatarUrl)
                                                          : null,
                                                  child: avatarUrl == null
                                                      ? const Icon(Icons.person,
                                                          color: AppColors
                                                              .textSecondary)
                                                      : null,
                                                ),
                                                if (isOnline)
                                                  Positioned(
                                                    right: 0,
                                                    bottom: 0,
                                                    child: Container(
                                                      width: 13,
                                                      height: 13,
                                                      decoration: BoxDecoration(
                                                        color:
                                                            AppColors.success,
                                                        shape: BoxShape.circle,
                                                        border: Border.all(
                                                            color: AppColors
                                                                .surface,
                                                            width: 2),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          nomeContato,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color: AppColors
                                                                .textPrimary,
                                                            fontSize: 15,
                                                            fontWeight: unreadCount >
                                                                    0
                                                                ? FontWeight.bold
                                                                : FontWeight
                                                                    .w600,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        tempo,
                                                        style: TextStyle(
                                                          color: unreadCount > 0
                                                              ? AppColors.primary
                                                              : AppColors
                                                                  .textSecondary,
                                                          fontSize: 12,
                                                          fontWeight: unreadCount >
                                                                  0
                                                              ? FontWeight.w600
                                                              : FontWeight
                                                                  .normal,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      if (isAi) ...[
                                                        const Icon(
                                                            Icons.auto_awesome,
                                                            size: 13,
                                                            color:
                                                                AppColors.ai),
                                                        const SizedBox(
                                                            width: 4),
                                                      ],
                                                      Expanded(
                                                        child: Text(
                                                          ultimaMensagem,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color: isAi
                                                                ? AppColors.ai
                                                                : (unreadCount >
                                                                        0
                                                                    ? AppColors
                                                                        .textPrimary
                                                                    : AppColors
                                                                        .textSecondary),
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      ),
                                                      if (unreadCount > 0) ...[
                                                        const SizedBox(
                                                            width: 8),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 7,
                                                            vertical: 2,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: AppColors
                                                                .primary,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        999),
                                                          ),
                                                          child: Text(
                                                            unreadCount
                                                                .toString(),
                                                            style:
                                                                const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  if (connection.isNotEmpty ||
                                                      agent.isNotEmpty ||
                                                      department.isNotEmpty ||
                                                      contactTags
                                                          .isNotEmpty) ...[
                                                    const SizedBox(height: 8),
                                                    Wrap(
                                                      spacing: 6,
                                                      runSpacing: 4,
                                                      children: [
                                                        if (isAi)
                                                          _buildChatBadge(
                                                            icon: Icons
                                                                .auto_awesome,
                                                            text: 'IA',
                                                            accentColor:
                                                                AppColors.ai,
                                                          ),
                                                        if (department
                                                            .isNotEmpty)
                                                          _buildChatBadge(
                                                            icon:
                                                                Icons.apartment,
                                                            text: department,
                                                            accentColor:
                                                                AppColors
                                                                    .primary,
                                                          ),
                                                        if (agent.isNotEmpty)
                                                          _buildChatBadge(
                                                            icon: Icons.person,
                                                            text: agent,
                                                            accentColor:
                                                                const Color(
                                                                    0xFF93C5FD),
                                                          ),
                                                        if (connection
                                                            .isNotEmpty)
                                                          _buildChatBadge(
                                                            icon: Icons
                                                                .phone_enabled,
                                                            text: connection,
                                                            accentColor:
                                                                AppColors
                                                                    .success,
                                                          ),
                                                        ...contactTags
                                                            .take(2)
                                                            .map(
                                                              (tag) =>
                                                                  _buildChatBadge(
                                                                icon: Icons
                                                                    .local_offer,
                                                                text: tag,
                                                                accentColor:
                                                                    const Color(
                                                                        0xFFD8B4FE),
                                                              ),
                                                            ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

