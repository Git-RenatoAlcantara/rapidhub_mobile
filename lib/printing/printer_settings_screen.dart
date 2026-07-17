import 'dart:io';

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'printer_settings.dart';
import 'thermal_printer.dart';
import 'windows_raw_printer.dart';

/// Roda `EnumPrinters` fora da thread de UI (via `compute`). O parâmetro é
/// ignorado — `compute` exige uma função de um argumento.
List<String> _enumPrintersIsolate(void _) => WindowsRawPrinter.listPrinters();

/// Configuração da impressora térmica (ESC/POS), por rede ou USB.
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

  /// USB só existe no desktop Windows (spool RAW via winspool).
  bool get _usbSupported => !kIsWeb && Platform.isWindows;

  /// Impressoras instaladas no Windows, para o dropdown do modo USB.
  List<String> _usbPrinters = const [];
  bool _loadingUsb = false;

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
    if (_usbSupported) _refreshUsbPrinters();
  }

  /// Lê as impressoras instaladas no Windows. Roda fora da thread de UI porque
  /// EnumPrinters pode demorar se houver impressoras de rede offline.
  Future<void> _refreshUsbPrinters() async {
    setState(() => _loadingUsb = true);
    final list = await compute(_enumPrintersIsolate, null);
    if (!mounted) return;
    setState(() {
      _usbPrinters = list;
      _loadingUsb = false;
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
      _toast(
        s.connection == PrinterConnection.network
            ? 'Informe o IP da impressora.'
            : 'Selecione a impressora do Windows.',
        error: true,
      );
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
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: error ? AppColors.danger : AppColors.success,
        behavior: SnackBarBehavior.floating,
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
                const Text('Tipo de conexão',
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                const SizedBox(height: 8),
                SegmentedButton<PrinterConnection>(
                  segments: [
                    for (final c in PrinterConnection.values)
                      ButtonSegment(value: c, label: Text(c.label)),
                  ],
                  selected: {_settings.connection},
                  onSelectionChanged: (v) => setState(
                    () => _settings =
                        _settings.copyWith(connection: v.first),
                  ),
                  style: SegmentedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    selectedForegroundColor: Colors.white,
                    selectedBackgroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.borderStrong),
                  ),
                ),
                const SizedBox(height: 16),
                if (_settings.connection == PrinterConnection.network)
                  ..._networkFields()
                else
                  ..._usbFields(),
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

  List<Widget> _networkFields() => [
        const Text('Endereço IP da impressora',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
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
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
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
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ];

  List<Widget> _usbFields() {
    if (!_usbSupported) {
      return const [
        Text(
          'A impressão USB só funciona no app desktop do Windows. '
          'Neste dispositivo use uma impressora de rede.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ];
    }

    final selected = _settings.usbPrinterName.trim();
    // Mantém na lista uma impressora salva que não apareceu no enum (ex.: USB
    // desconectada no momento), para o operador não perder a escolha.
    final items = <String>[
      ..._usbPrinters,
      if (selected.isNotEmpty && !_usbPrinters.contains(selected)) selected,
    ];

    return [
      Row(
        children: [
          const Expanded(
            child: Text('Impressora do Windows',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
          ),
          TextButton.icon(
            onPressed: _loadingUsb ? null : _refreshUsbPrinters,
            icon: _loadingUsb
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
            label: const Text('Atualizar'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (items.isEmpty)
        const Text(
          'Nenhuma impressora instalada encontrada. Instale o driver da '
          'impressora USB no Windows e toque em Atualizar.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        )
      else
        DropdownButtonFormField<String>(
          initialValue: selected.isEmpty ? null : selected,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: AppTheme.inputDecoration(
            hint: 'Selecione a impressora',
            prefixIcon: Icons.usb,
          ),
          items: [
            for (final name in items)
              DropdownMenuItem(value: name, child: Text(name)),
          ],
          onChanged: (v) => setState(
            () => _settings =
                _settings.copyWith(usbPrinterName: v ?? ''),
          ),
        ),
      const SizedBox(height: 8),
      const Text(
        'Escolha a impressora térmica instalada no Windows. Os cupons vão '
        'crus (ESC/POS), sem passar pela renderização do driver.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    ];
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
