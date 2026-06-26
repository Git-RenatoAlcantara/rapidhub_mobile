import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';
import 'theme/app_theme.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_logo.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _storage = const FlutterSecureStorage();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _contacts = <Map<String, dynamic>>[];
  bool _isLoading = true;
  String _errorMessage = '';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _asString(dynamic v) => v?.toString() ?? '';

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final token = await _storage.read(key: 'session_token');
      final resp = await http.get(
        Uri.parse('$baseUrl/api/contacts'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        final raw = decoded is Map && decoded['contacts'] is List
            ? decoded['contacts'] as List
            : (decoded is List ? decoded : const <dynamic>[]);
        final contacts = raw
            .whereType<Map>()
            .map((c) => Map<String, dynamic>.from(c))
            .toList();
        contacts.sort((a, b) => _asString(a['name'])
            .toLowerCase()
            .compareTo(_asString(b['name']).toLowerCase()));
        if (!mounted) return;
        setState(() {
          _contacts = contacts;
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'Erro ao carregar contatos. (Código: ${resp.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erro de conexão. Verifica a tua internet.';
        _isLoading = false;
      });
    }
  }

  String _phoneOf(Map<String, dynamic> c) {
    return _firstNonEmpty([
      _asString(c['phone']),
      _asString(c['number']),
      _asString(c['whatsapp']),
      _asString(c['email']),
    ]);
  }

  List<String> _tagsOf(Map<String, dynamic> c) {
    final raw = c['tags'];
    if (raw is! List) return const <String>[];
    return raw
        .map((t) => _asString(t).trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  String _firstNonEmpty(List<String> values) {
    for (final v in values) {
      if (v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.trim().isEmpty) return _contacts;
    final q = _search.trim().toLowerCase();
    return _contacts.where((c) {
      return _asString(c['name']).toLowerCase().contains(q) ||
          _phoneOf(c).toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 16,
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Row(
          children: [
            AppLogo(),
            SizedBox(width: 10),
            Text('Contatos',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Adicionar contato',
            icon: const Icon(Icons.person_add_alt, color: AppColors.primary),
            onPressed: _showEmBreve,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showEmBreve,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: AppTheme.inputDecoration(
                hint: 'Buscar contatos...',
                prefixIcon: Icons.search,
              ).copyWith(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage,
                style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loadContacts,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    final contacts = _filtered;
    if (contacts.isEmpty) {
      return const Center(
        child: Text('Nenhum contato encontrado.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    // Agrupa por letra inicial.
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final c in contacts) {
      final name = _asString(c['name']).trim();
      final letter =
          name.isNotEmpty ? name[0].toUpperCase() : '#';
      groups.putIfAbsent(letter, () => []).add(c);
    }
    final letters = groups.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _loadContacts,
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: letters.length,
        itemBuilder: (context, index) {
          final letter = letters[index];
          final items = groups[letter]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 0, 8),
                child: Text(letter,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
              ...items.map(_buildContactTile),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContactTile(Map<String, dynamic> c) {
    final name = _asString(c['name']).trim().isEmpty
        ? 'Sem nome'
        : _asString(c['name']).trim();
    final phone = _phoneOf(c);
    final tags = _tagsOf(c);
    final avatar = _firstNonEmpty([
      _asString(c['avatar']),
      _asString(c['photo']),
    ]);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.surfaceAlt,
              backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
              child: avatar.isEmpty
                  ? Text(initial,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(phone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ],
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: tags
                          .take(3)
                          .map((t) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.ai.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                      color: AppColors.ai
                                          .withValues(alpha: 0.4)),
                                ),
                                child: Text(t,
                                    style: const TextStyle(
                                        color: AppColors.ai,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600)),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Abrir conversa',
              icon: const Icon(Icons.chat_bubble_outline,
                  color: AppColors.primary, size: 20),
              onPressed: _showEmBreve,
            ),
          ],
        ),
      ),
    );
  }

  void _showEmBreve() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Funcionalidade estará disponível em breve.'),
        backgroundColor: AppColors.surface,
      ),
    );
  }
}
