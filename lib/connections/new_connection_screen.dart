import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import 'connection_api.dart';

/// Etapas do fluxo de conexão não oficial por código de verificação (sem QR):
/// preencher telefone → exibir código + instruções (com polling) → conectado.
enum _Stage { form, code, connected }

/// Nova conexão WhatsApp (API Não Oficial) usando **código de verificação**
/// em vez de QR Code. Espelha o fluxo `rapidhub-wpp` da web, mas focado apenas
/// no pareamento por número (WhatsApp › Aparelhos conectados › Conectar com
/// número de telefone).
class NewConnectionScreen extends StatefulWidget {
  const NewConnectionScreen({super.key, ConnectionApi? api})
      : _injectedApi = api;

  final ConnectionApi? _injectedApi;

  @override
  State<NewConnectionScreen> createState() => _NewConnectionScreenState();
}

class _NewConnectionScreenState extends State<NewConnectionScreen> {
  late final ConnectionApi _api = widget._injectedApi ?? ConnectionApi();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  _Stage _stage = _Stage.form;
  bool _busy = false;
  String? _error;

  String? _connectionId;
  String? _pairingCode;

  Timer? _pollTimer;
  Timer? _pollTimeout;

  @override
  void dispose() {
    _stopPolling();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollTimeout?.cancel();
    _pollTimeout = null;
  }

  /// Cria a conexão (se necessário) e gera o código de verificação.
  Future<void> _generateCode() async {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) {
      setState(() => _error =
          'Informa o telefone com DDI e DDD (só números). Ex.: 5511999999999');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // Cria a Connection e inicia a sessão só uma vez; ao "gerar outro código"
      // reaproveitamos o mesmo connectionId.
      _connectionId ??= (await _api.init(name: _nameController.text)).connectionId;

      final code = await _api.requestPairingCode(_connectionId!, digits);
      if (!mounted) return;
      setState(() {
        _pairingCode = code;
        _stage = _Stage.code;
        _busy = false;
      });
      _startPolling();
    } on ConnectionApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível gerar o código. Tenta novamente.';
        _busy = false;
      });
    }
  }

  /// Gera um novo código para a mesma conexão (o anterior expirou/errou).
  Future<void> _regenerateCode() async {
    if (_connectionId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
      final code = await _api.requestPairingCode(_connectionId!, digits);
      if (!mounted) return;
      setState(() {
        _pairingCode = code;
        _busy = false;
      });
    } on ConnectionApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível gerar outro código.';
        _busy = false;
      });
    }
  }

  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    // Encerra o polling após 5 min para não rodar indefinidamente.
    _pollTimeout = Timer(const Duration(minutes: 5), _stopPolling);
  }

  Future<void> _poll() async {
    final id = _connectionId;
    if (id == null) return;
    try {
      final status = await _api.fetchStatus(id);
      if (!mounted) return;
      if (status.connected) {
        _stopPolling();
        setState(() => _stage = _Stage.connected);
        return;
      }
      if (status.instanceMissing) {
        _stopPolling();
        setState(() => _error =
            'A sessão foi removida no servidor. Inicia uma nova conexão.');
      }
    } catch (_) {
      // Falha pontual — o próximo tick tenta de novo.
    }
  }

  /// Código formatado para leitura: "ABCD1234" → "ABCD-1234".
  String get _formattedCode {
    final code = _pairingCode ?? '';
    if (code.contains('-')) return code;
    if (code.length == 8) return '${code.substring(0, 4)}-${code.substring(4)}';
    return code;
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
            Text('Nova conexão',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: switch (_stage) {
          _Stage.form => _buildForm(),
          _Stage.code => _buildCode(),
          _Stage.connected => _buildConnected(),
        },
      ),
    );
  }

  // ── Etapa 1: telefone ──────────────────────────────────────────────────────
  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.dialpad, color: AppColors.success),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'API Não Oficial',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Conecta o WhatsApp por código de verificação, sem precisar ler o QR '
          'Code. Informa o número do WhatsApp e digita o código gerado no '
          'aparelho.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        const Text(
          'Nome da conexão (opcional)',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          enabled: !_busy,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: AppTheme.inputDecoration(
            hint: 'Ex.: Atendimento',
            prefixIcon: Icons.badge_outlined,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Telefone do WhatsApp (com DDI e DDD)',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          enabled: !_busy,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: AppTheme.inputDecoration(
            hint: 'Ex.: 5511999999999',
            prefixIcon: Icons.phone_outlined,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          _errorBox(_error!),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _generateCode,
            icon: _busy
                ? const SizedBox.shrink()
                : const Icon(Icons.dialpad, size: 20),
            label: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Gerar código de verificação',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Etapa 2: código + instruções ───────────────────────────────────────────
  Widget _buildCode() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Text(
          'Digita este código no WhatsApp',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3),
        ),
        const SizedBox(height: 20),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.4)),
            ),
            child: Text(
              _formattedCode,
              style: const TextStyle(
                color: AppColors.success,
                fontSize: 34,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Indicador de que estamos aguardando o pareamento.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text('Aguardando você conectar no WhatsApp...',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.info_outline,
                      color: AppColors.success, size: 18),
                  SizedBox(width: 8),
                  Text('Como conectar por código:',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 14),
              _step(1, 'Abre o WhatsApp no teu celular'),
              _step(2, 'Toca em "Aparelhos conectados"'),
              _step(
                  3,
                  'Toca em "Conectar um aparelho" e depois em '
                  '"Conectar com número de telefone"'),
              _step(4, 'Digita o código acima', last: true),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          _errorBox(_error!),
        ],
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _busy ? null : _regenerateCode,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 18),
          label: const Text('Gerar outro código'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  // ── Etapa 3: conectado ──────────────────────────────────────────────────────
  Widget _buildConnected() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle,
                  color: AppColors.success, size: 52),
            ),
            const SizedBox(height: 20),
            const Text('Conectado com sucesso!',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'A tua conexão de WhatsApp já está ativa e pronta para receber '
              'e enviar mensagens.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Concluir',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(int n, String text, {bool last = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
            child: Text('$n',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(text,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
