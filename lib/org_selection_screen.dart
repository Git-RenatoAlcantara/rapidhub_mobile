import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'chat_list_screen.dart';
import 'login_screen.dart';
import 'config.dart';
import 'theme/app_theme.dart';

class OrgSelectionScreen extends StatefulWidget {
  const OrgSelectionScreen({super.key});

  @override
  State<OrgSelectionScreen> createState() => _OrgSelectionScreenState();
}

class _OrgSelectionScreenState extends State<OrgSelectionScreen> {
  final _storage = const FlutterSecureStorage();
  List<dynamic> _orgs = [];
  bool _isLoading = true;
  bool _isSelecting = false;
  String _errorMessage = '';
  String _search = '';
  String? _selectedOrgId;
  String _userEmail = '';

  @override
  void initState() {
    super.initState();
    _loadUserEmail();
    _loadOrganizations();
  }

  Future<void> _loadUserEmail() async {
    final email = await _storage.read(key: 'user_email');
    if (!mounted) return;
    setState(() => _userEmail = email ?? '');
  }

  Future<void> _loadOrganizations() async {
    try {
      final token = await _storage.read(key: 'session_token');
      final resp = await http.get(
        Uri.parse('$baseUrl/api/auth/organization/list'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print("Org list status: ${resp.statusCode}");
      print("Org list body: ${resp.body}");

      if (resp.statusCode == 200) {
        final orgs = jsonDecode(resp.body) as List;
        setState(() {
          _orgs = orgs;
          _selectedOrgId = orgs.isNotEmpty ? orgs.first['id']?.toString() : null;
          _isLoading = false;
        });
      } else if (resp.statusCode == 401) {
        await _logoutAndGoToLogin();
      } else {
        setState(() {
          _errorMessage = 'Erro ao carregar organizações.';
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Erro ao carregar orgs: $e");
      setState(() {
        _errorMessage = 'Erro de conexão.';
        _isLoading = false;
      });
    }
  }

  Future<void> _logoutAndGoToLogin() async {
    // Token inválido/expirado (ou de outro domínio): limpa tudo e volta ao login
    await _storage.deleteAll();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  Future<void> _selectOrg(String orgId) async {
    setState(() => _isSelecting = true);

    try {
      final token = await _storage.read(key: 'session_token');
      final resp = await http.post(
        Uri.parse('$baseUrl/api/auth/organization/set-active'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'organizationId': orgId}),
      );

      print("Set active org status: ${resp.statusCode}");

      if (resp.statusCode == 200) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ChatListScreen()),
        );
      } else {
        setState(() {
          _errorMessage = 'Erro ao selecionar organização.';
          _isSelecting = false;
        });
      }
    } catch (e) {
      print("Erro ao selecionar org: $e");
      setState(() {
        _errorMessage = 'Erro de conexão.';
        _isSelecting = false;
      });
    }
  }

  List<dynamic> get _filteredOrgs {
    if (_search.trim().isEmpty) return _orgs;
    final q = _search.trim().toLowerCase();
    return _orgs.where((org) {
      final name = (org['name'] ?? '').toString().toLowerCase();
      final slug = (org['slug'] ?? '').toString().toLowerCase();
      return name.contains(q) || slug.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : Column(
                children: [
                  _buildTopBar(),
                  Expanded(child: _buildBody()),
                  if (_orgs.isNotEmpty) _buildContinueBar(),
                ],
              ),
      ),
    );
  }

  Widget _buildTopBar() {
    final initial =
        _userEmail.isNotEmpty ? _userEmail[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.surfaceAlt,
            child: Text(initial,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sua conta',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                if (_userEmail.isNotEmpty)
                  Text(_userEmail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: _logoutAndGoToLogin,
            icon: const Icon(Icons.logout, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_errorMessage.isNotEmpty && _orgs.isEmpty) {
      return Center(
        child: Text(_errorMessage,
            style: const TextStyle(color: AppColors.danger)),
      );
    }
    if (_orgs.isEmpty) {
      return const Center(
        child: Text('Nenhuma organização encontrada.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final orgs = _filteredOrgs;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        const Text(
          'Selecione uma organização',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5),
        ),
        const SizedBox(height: 6),
        const Text(
          'Escolha o workspace para continuar o atendimento',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 18),
        TextField(
          style: const TextStyle(color: AppColors.textPrimary),
          onChanged: (v) => setState(() => _search = v),
          decoration: AppTheme.inputDecoration(
            hint: 'Buscar organização...',
            prefixIcon: Icons.search,
          ),
        ),
        const SizedBox(height: 16),
        ...orgs.map(_buildOrgCard),
        const SizedBox(height: 8),
        _buildCreateCard(),
      ],
    );
  }

  Widget _buildOrgCard(dynamic org) {
    final name = (org['name'] ?? 'Sem nome').toString();
    final slug = (org['slug'] ?? '').toString();
    final id = org['id']?.toString();
    final selected = id != null && id == _selectedOrgId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: id == null ? null : () => setState(() => _selectedOrgId = id),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.borderStrong,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.ai],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      if (slug.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(slug,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                selected
                    ? const Icon(Icons.check_circle,
                        color: AppColors.primary, size: 24)
                    : const Icon(Icons.arrow_forward_ios,
                        color: AppColors.textSecondary, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreateCard() {
    return DottedBorderBox(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Criação de organização estará disponível em breve.'),
            backgroundColor: AppColors.surface,
          ),
        );
      },
    );
  }

  Widget _buildContinueBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: (_selectedOrgId == null || _isSelecting)
              ? null
              : () => _selectOrg(_selectedOrgId!),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isSelecting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Continuar',
                        style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Card de "Criar nova organização" com borda pontilhada.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedRectPainter(),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add,
                    color: AppColors.textPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Criar nova organização',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.borderStrong
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    const radius = Radius.circular(16);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.7, 0.7, size.width - 1.4, size.height - 1.4),
      radius,
    );

    final path = Path()..addRRect(rrect);
    const dashWidth = 6.0;
    const dashSpace = 5.0;

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
