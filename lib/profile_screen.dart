import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';
import 'connections/new_connection_screen.dart';
import 'login_screen.dart';
import 'org_selection_screen.dart';
import 'store_dashboard_screen.dart';
import 'store_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_logo.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _storage = const FlutterSecureStorage();
  String _email = '';

  @override
  void initState() {
    super.initState();
    _loadEmail();
  }

  Future<void> _loadEmail() async {
    final email = await _storage.read(key: 'user_email');
    if (!mounted) return;
    setState(() => _email = email ?? '');
  }

  Future<void> _logout() async {
    final token = await _storage.read(key: 'session_token');
    await _storage.delete(key: 'session_token');
    try {
      await http.post(
        Uri.parse('$baseUrl/api/auth/sign-out'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Terminar sessão',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('Tens a certeza que queres sair da tua conta?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            child: const Text('Sair',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final initial = _email.isNotEmpty ? _email[0].toUpperCase() : '?';

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
            Text('Perfil',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 4),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Cartão do usuário.
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.surfaceAlt,
                  child: Text(initial,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _email.isNotEmpty
                            ? _email.split('@').first
                            : 'Usuário',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _email.isNotEmpty ? _email : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text('Online',
                            style: TextStyle(
                                color: AppColors.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Conta'),
          _buildTile(
            icon: Icons.swap_horiz,
            title: 'Trocar organização',
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => const OrgSelectionScreen()),
              );
            },
          ),
          _buildTile(
            icon: Icons.person_outline,
            title: 'Editar perfil',
            onTap: _showEmBreve,
          ),
          _buildTile(
            icon: Icons.notifications_none,
            title: 'Notificações',
            onTap: _showEmBreve,
          ),
          const SizedBox(height: 16),
          _sectionTitle('Conexões'),
          _buildTile(
            icon: Icons.add_link,
            title: 'Nova conexão (WhatsApp)',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const NewConnectionScreen()),
              );
            },
          ),
          const SizedBox(height: 16),
          _sectionTitle('Loja'),
          _buildTile(
            icon: Icons.insights_outlined,
            title: 'Painel da Loja',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const StoreDashboardScreen()),
              );
            },
          ),
          _buildTile(
            icon: Icons.storefront_outlined,
            title: 'Configurações da Loja',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const StoreScreen()),
              );
            },
          ),
          const SizedBox(height: 16),
          _sectionTitle('Preferências'),
          _buildTile(
            icon: Icons.dark_mode_outlined,
            title: 'Tema',
            trailingText: 'Escuro',
            onTap: _showEmBreve,
          ),
          _buildTile(
            icon: Icons.language,
            title: 'Idioma',
            trailingText: 'Português',
            onTap: _showEmBreve,
          ),
          _buildTile(
            icon: Icons.help_outline,
            title: 'Ajuda e suporte',
            onTap: _showEmBreve,
          ),
          const SizedBox(height: 24),
          // Botão sair.
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _confirmLogout,
              icon: const Icon(Icons.logout, color: AppColors.danger, size: 20),
              label: const Text('Terminar sessão',
                  style: TextStyle(
                      color: AppColors.danger,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text('RapidHub • v1.0.0',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
      child: Text(text.toUpperCase(),
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5)),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? trailingText,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.textSecondary, size: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14)),
                ),
                if (trailingText != null) ...[
                  Text(trailingText,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(width: 6),
                ],
                const Icon(Icons.chevron_right,
                    color: AppColors.textSecondary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
