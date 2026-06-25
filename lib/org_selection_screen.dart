import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'chat_list_screen.dart';
import 'login_screen.dart';
import 'config.dart';

class OrgSelectionScreen extends StatefulWidget {
  const OrgSelectionScreen({super.key});

  @override
  State<OrgSelectionScreen> createState() => _OrgSelectionScreenState();
}

class _OrgSelectionScreenState extends State<OrgSelectionScreen> {
  final _storage = const FlutterSecureStorage();
  List<dynamic> _orgs = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadOrganizations();
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
    setState(() => _isLoading = true);

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
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Erro ao selecionar org: $e");
      setState(() {
        _errorMessage = 'Erro de conexão.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text('Escolher Organização',
            style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Text(_errorMessage,
                      style: const TextStyle(color: Colors.redAccent)))
              : _orgs.isEmpty
                  ? const Center(
                      child: Text('Nenhuma organização encontrada.',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _orgs.length,
                      itemBuilder: (context, index) {
                        final org = _orgs[index];
                        final name = org['name'] ?? 'Sem nome';
                        final slug = org['slug'] ?? '';

                        return Card(
                          color: const Color(0xFF161B22),
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue[800],
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            subtitle: Text(slug,
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 13)),
                            trailing: const Icon(Icons.arrow_forward_ios,
                                color: Colors.grey, size: 16),
                            onTap: () => _selectOrg(org['id']),
                          ),
                        );
                      },
                    ),
    );
  }
}
