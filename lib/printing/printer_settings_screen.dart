import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'printer_settings.dart';
import 'thermal_printer.dart';

/// Configuração da impressora térmica de rede (ESC/POS na porta 9100).
class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key, PrinterSettingsStore? store})
      : _injectedStore = store;

  final PrinterSettingsStore? _injectedStore;

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  late final PrinterSettingsStore _store =
      widget._injectedStore ?? PrinterSettingsStore();

  final _storeNameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _copiesController = TextEditingController();

  PrinterSettings _settings = const PrinterSettings();
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _copiesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await _store.load();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _storeNameController.text = s.storeName;
      _hostController.text = s.host;
      _portController.text = s.port.toString();
      _copiesController.text = s.copies.toString();
      _loading = false;
    });
  }

  /// Junta os campos de texto ao estado dos toggles.
  PrinterSettings get _current => _settings.copyWith(
        storeName: _storeNameController.text,
        host: _hostController.text,
        port: int.tryParse(_portController.text) ?? 9100,
        copies: int.tryParse(_copiesController.text) ?? 1,
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    await _persist();
    if (!mounted) return;
    setState(() => _saving = false);
    _toast('Configuração salva.');
  }

  /// Grava a configuração atual sem tocar na UI. Usado tanto pelo botão Salvar
  /// quanto pelo auto-save ao sair da tela.
  Future<void> _persist() async {
    final s = _current;
    await _store.save(s);
    if (!mounted) return;
    _settings = s;
  }

  Future<void> _test() async {
    final s = _current;
    if (!s.isConfigured) {
      _toast('Informe o IP da impressora.', error: true);
      return;
    }
    setState(() => _testing = true);
    try {
      await ThermalPrinter(s).printTest();
      if (!mounted) return;
      _toast('Cupom de teste enviado.');
    } on PrinterException catch (e) {
      if (!mounted) return;
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.danger : AppColors.surfaceAlt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Sair da tela salva sozinho: o operador digita o IP e volta sem precisar
    // lembrar de tocar em "Salvar".
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        await _persist();
        navigator.pop();
      },
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text('Impressora térmica',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 20)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _saving || _loading ? null : _save,
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2),
                    )
                  : const Text('Salvar',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      body: SafeArea(top: false, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _sectionTitle('Conexão'),
        _card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Endereço IP da impressora',
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: _hostController,
                  keyboardType: TextInputType.text,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: AppTheme.inputDecoration(
                    hint: '192.168.0.100',
                    prefixIcon: Icons.print_outlined,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Porta',
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: AppTheme.inputDecoration(
                    hint: '9100',
                    prefixIcon: Icons.lan_outlined,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Impressoras térmicas de rede usam a porta RAW 9100. '
                  'O IP precisa ser fixo — reserve-o no roteador.',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle('Cupom'),
        _card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nome no cabeçalho',
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: _storeNameController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: AppTheme.inputDecoration(
                    hint: 'Nome do estabelecimento',
                    prefixIcon: Icons.storefront_outlined,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Largura do papel',
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                const SizedBox(height: 8),
                SegmentedButton<PaperWidth>(
                  segments: [
                    for (final w in PaperWidth.values)
                      ButtonSegment(
                        value: w,
                        label: Text('${w.label} (${w.columns} col.)'),
                      ),
                  ],
                  selected: {_settings.paperWidth},
                  onSelectionChanged: (v) => setState(
                    () => _settings = _settings.copyWith(paperWidth: v.first),
                  ),
                  style: SegmentedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    selectedForegroundColor: Colors.white,
                    selectedBackgroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.borderStrong),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Vias por pedido',
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: _copiesController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: AppTheme.inputDecoration(
                    hint: '1',
                    prefixIcon: Icons.copy_all_outlined,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle('Automação'),
        _card(
          child: SwitchListTile(
            value: _settings.autoPrint,
            onChanged: (v) =>
                setState(() => _settings = _settings.copyWith(autoPrint: v)),
            activeThumbColor: AppColors.primary,
            secondary:
                const Icon(Icons.bolt_outlined, color: AppColors.textSecondary),
            title: const Text('Imprimir pedidos novos',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            subtitle: const Text(
              'Ao atualizar a lista, imprime sozinho os pedidos recebidos '
              'que ainda não saíram na impressora.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _testing ? null : _test,
          icon: _testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 2),
                )
              : const Icon(Icons.receipt_long_outlined),
          label: Text(_testing ? 'Enviando…' : 'Imprimir cupom de teste'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.borderStrong),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(
          title,
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6),
        ),
      );

  Widget _card({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}
