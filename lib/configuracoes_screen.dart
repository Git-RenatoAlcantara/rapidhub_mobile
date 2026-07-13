import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'printing/printer_settings_screen.dart';
import 'settings/settings_api.dart';
import 'theme/app_theme.dart';
import 'widgets/app_bottom_nav.dart';

class ConfiguracoesScreen extends StatefulWidget {
  const ConfiguracoesScreen({super.key, SettingsApi? api})
      : _injectedApi = api;

  /// Permite injetar um [SettingsApi] falso nos testes. Em produção fica `null`.
  final SettingsApi? _injectedApi;

  @override
  State<ConfiguracoesScreen> createState() => _ConfiguracoesScreenState();
}

class _ConfiguracoesScreenState extends State<ConfiguracoesScreen> {
  late final SettingsApi _api = widget._injectedApi ?? SettingsApi();
  final _minutesController = TextEditingController();
  final _templateController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  DailyReportSettings _daily = const DailyReportSettings(
    enabled: false,
    hour: 20,
    minute: 0,
    aiInsights: false,
    whatsappReady: false,
  );

  String _savedDailySig = '';
  String _savedReminderSig = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _minutesController.dispose();
    _templateController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _api.fetchDailyReport(),
        _api.fetchReminder(),
      ]);
      if (!mounted) return;
      final daily = results[0] as DailyReportSettings;
      final reminder = results[1] as ReminderSettings;
      setState(() {
        _daily = daily;
        _minutesController.text = '${reminder.minutesBefore}';
        _templateController.text = reminder.template;
        _savedDailySig = daily.signature;
        _savedReminderSig = reminder.signature;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Não foi possível carregar as configurações.';
        _loading = false;
      });
    }
  }

  int get _minutesBefore =>
      int.tryParse(_minutesController.text.trim()) ?? 120;

  String get _reminderSig => '$_minutesBefore|${_templateController.text}';

  bool get _dailyDirty => !_loading && _daily.signature != _savedDailySig;
  bool get _reminderDirty => !_loading && _reminderSig != _savedReminderSig;
  bool get _dirty => _dailyDirty || _reminderDirty;

  Future<void> _save() async {
    // Validações espelham as regras do backend (evita 400 desnecessário).
    final minutes = _minutesBefore;
    if (minutes < 5 || minutes > 1440) {
      _snack('O aviso deve ficar entre 5 e 1440 minutos.');
      return;
    }
    final template = _templateController.text.trim();
    if (_reminderDirty && template.length < 10) {
      _snack('O modelo do lembrete deve ter ao menos 10 caracteres.');
      return;
    }

    setState(() => _saving = true);
    try {
      if (_dailyDirty) {
        await _api.saveDailyReport(
          enabled: _daily.enabled,
          hour: _daily.hour,
          minute: _daily.minute,
          aiInsights: _daily.aiInsights,
        );
      }
      if (_reminderDirty) {
        await _api.saveReminder(minutesBefore: minutes, template: template);
      }
      if (!mounted) return;
      setState(() {
        _savedDailySig = _daily.signature;
        _savedReminderSig = _reminderSig;
        _saving = false;
      });
      _snack('Configurações salvas!');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e.toString();
      _snack(msg.startsWith('Exception: ')
          ? msg.substring('Exception: '.length)
          : 'Erro ao salvar as configurações.');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _daily.hour, minute: _daily.minute),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() =>
        _daily = _daily.copyWith(hour: picked.hour, minute: picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        titleSpacing: 16,
        title: const Text('Configurações',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 20)),
        actions: [_buildSaveAction()],
      ),
      body: SafeArea(top: false, child: _buildBody()),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }

  Widget _buildSaveAction() {
    if (_loading || _loadError != null || !_dirty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton(
        onPressed: _saving ? null : _save,
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2),
              )
            : const Text('Salvar',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_loadError != null) return _buildLoadError();

    final timeLabel =
        '${_daily.hour.toString().padLeft(2, '0')}:${_daily.minute.toString().padLeft(2, '0')}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _sectionTitle('Relatório diário'),
        _card(
          child: Column(
            children: [
              _switchRow(
                icon: Icons.summarize_outlined,
                title: 'Enviar relatório diário',
                subtitle: 'Resumo do dia no WhatsApp da equipe',
                value: _daily.enabled,
                onChanged: (v) =>
                    setState(() => _daily = _daily.copyWith(enabled: v)),
              ),
              if (_daily.enabled) ...[
                const Divider(height: 1, color: AppColors.border),
                _tapRow(
                  icon: Icons.schedule_outlined,
                  title: 'Horário de envio',
                  trailing: timeLabel,
                  onTap: _pickTime,
                ),
                const Divider(height: 1, color: AppColors.border),
                _switchRow(
                  icon: Icons.auto_awesome_outlined,
                  title: 'Insights com IA',
                  subtitle: 'Comentários automáticos sobre o desempenho',
                  value: _daily.aiInsights,
                  onChanged: (v) =>
                      setState(() => _daily = _daily.copyWith(aiInsights: v)),
                ),
              ],
            ],
          ),
        ),
        if (_daily.enabled && !_daily.whatsappReady)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              '⚠️ A integração do WhatsApp ainda não está configurada; o '
              'relatório só será enviado após conectá-la no painel web.',
              style: TextStyle(color: Color(0xFFD29922), fontSize: 12),
            ),
          ),
        const SizedBox(height: 20),
        _sectionTitle('Lembretes de agendamento'),
        _card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Avisar o cliente antes (minutos)',
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: _minutesController,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: AppTheme.inputDecoration(
                    hint: '120',
                    prefixIcon: Icons.notifications_active_outlined,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Modelo da mensagem',
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: _templateController,
                  onChanged: (_) => setState(() {}),
                  maxLines: 4,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: AppTheme.inputDecoration(
                    hint: 'Olá {contato}! Lembrete: ...',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Variáveis: {contato}, {titulo}, {data}, {horario}.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle('Impressão'),
        _card(
          child: _tapRow(
            icon: Icons.print_outlined,
            title: 'Impressora térmica',
            trailing: 'Configurar',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PrinterSettingsScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle('Sobre'),
        _card(
          child: _tapRow(
            icon: Icons.info_outline,
            title: 'Versão',
            trailing: '1.0.0',
          ),
        ),
      ],
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 48),
            const SizedBox(height: 16),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Tentar novamente'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers de UI ──────────────────────────────────────────────────────

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

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 14)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primaryDim,
          ),
        ],
      ),
    );
  }

  Widget _tapRow({
    required IconData icon,
    required String title,
    String? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: AppColors.textSecondary, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 14)),
              ),
              if (trailing != null) ...[
                Text(trailing,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
                if (onTap != null) const SizedBox(width: 6),
              ],
              if (onTap != null)
                const Icon(Icons.chevron_right,
                    color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
