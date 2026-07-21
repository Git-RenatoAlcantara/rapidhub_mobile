import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'menu_api.dart';
import 'menu_availability.dart';
import 'option_groups_editor.dart';

/// Cria ou edita um produto do cardápio.
///
/// Devolve `true` ao fechar quando algo foi salvo — a tela de Cardápio usa isso
/// para recarregar a lista. Recarregar é obrigatório e não opcional: o
/// `PUT /api/menu/products/[id]` responde **sem** os grupos de opções, então
/// confiar no produto devolvido faria as opções sumirem da tela.
class ProductEditorScreen extends StatefulWidget {
  const ProductEditorScreen({
    super.key,
    required this.api,
    required this.categories,
    required this.menus,
    this.product,
  });

  final MenuApi api;
  final List<MenuCategory> categories;
  final List<Menu> menus;

  /// `null` = criar um produto novo.
  final MenuProduct? product;

  @override
  State<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends State<ProductEditorScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();

  String? _categoryId;
  String? _menuId;
  bool _isAvailable = true;
  bool _allowsHalf = false;
  final Set<int> _weekdays = <int>{};
  List<MenuOptionGroup> _groups = [];

  /// Estado das opções ao abrir a tela: só chamamos `PUT .../options` (que
  /// apaga e recria tudo) quando de fato mudou alguma coisa.
  String _initialGroupsSignature = '';

  List<AvailabilityOverride> _overrides = const [];
  bool _loadingOverrides = false;

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    if (product != null) {
      _name.text = product.name;
      _description.text = product.description;
      _price.text = product.price.toStringAsFixed(2).replaceAll('.', ',');
      _categoryId = product.categoryId;
      _menuId = product.menuId;
      _isAvailable = product.isAvailable;
      _allowsHalf = product.allowsHalf;
      _weekdays.addAll(product.availableWeekdays);
      _groups = product.optionGroups.map((g) => g.copy()).toList();
      _loadOverrides();
    }
    _initialGroupsSignature = _groupsSignature();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  String _groupsSignature() => jsonEncode([
        for (var i = 0; i < _groups.length; i++) _groups[i].toJson(i),
      ]);

  /// Preço aceito com vírgula ou ponto — o operador digita "28,90".
  double? get _parsedPrice {
    final raw = _price.text.trim().replaceAll('.', '').replaceAll(',', '.');
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null || value < 0) return null;
    return value;
  }

  Future<void> _loadOverrides() async {
    final product = widget.product;
    if (product == null) return;
    setState(() => _loadingOverrides = true);
    try {
      final today = DateTime.now();
      final overrides = await widget.api.fetchOverrides(
        product.id,
        from: menuDateKey(today),
        to: menuDateKey(today.add(const Duration(days: 30))),
      );
      if (!mounted) return;
      setState(() {
        _overrides = overrides;
        _loadingOverrides = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Falha aqui não impede editar o resto do produto.
      setState(() => _loadingOverrides = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = _parsedPrice;

    if (name.isEmpty) {
      setState(() => _error = 'Informe o nome do produto.');
      return;
    }
    if (price == null) {
      setState(() => _error = 'Informe um preço válido (ex.: 28,90).');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final description = _description.text.trim();
      final weekdays = _weekdays.toList()..sort();

      String productId;
      if (_isEditing) {
        productId = widget.product!.id;
        await widget.api.updateProduct(
          productId,
          name: name,
          price: price,
          description: description.isEmpty ? null : description,
          categoryId: _categoryId,
          menuId: _menuId,
          // Sem esses flags, mandar `null` seria omitido do corpo e o vínculo
          // antigo continuaria no servidor — "Sem categoria" não teria efeito.
          clearCategory: _categoryId == null,
          clearMenu: _menuId == null,
          isAvailable: _isAvailable,
          allowsHalf: _allowsHalf,
          availableWeekdays: weekdays,
        );
      } else {
        final created = await widget.api.createProduct(
          name: name,
          price: price,
          description: description.isEmpty ? null : description,
          categoryId: _categoryId,
          menuId: _menuId,
          isAvailable: _isAvailable,
          allowsHalf: _allowsHalf,
          availableWeekdays: weekdays,
        );
        productId = created.id;
      }

      // A rota de opções substitui tudo o que existe. Só a chamamos quando o
      // operador mexeu nos grupos, para não apagar/recriar à toa.
      if (_groupsSignature() != _initialGroupsSignature) {
        await widget.api.saveOptions(productId, _groups);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on MenuForbidden catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _saving = false;
      });
    }
  }

  String _friendlyError(Object e) {
    final message = e.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : 'Não foi possível salvar o produto.';
  }

  Future<void> _confirmDelete() async {
    final product = widget.product;
    if (product == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Excluir produto',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Excluir "${product.name}" do cardápio? Esta ação não pode ser '
          'desfeita.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await widget.api.deleteProduct(product.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _saving = false;
      });
    }
  }

  // ── Disponibilidade por data ─────────────────────────────────────────────

  Future<void> _addOverride() async {
    final product = widget.product;
    if (product == null) return;

    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final key = menuDateKey(date);
    final available = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Disponibilidade em ${_formatDate(key)}',
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 17)),
        content: const Text(
          'Nesta data, o produto deve ser vendido ou ficar bloqueado?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Bloquear',
                style: TextStyle(color: AppColors.danger)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Liberar',
                style: TextStyle(color: AppColors.success)),
          ),
        ],
      ),
    );
    if (available == null) return;

    try {
      await widget.api
          .setOverride(product.id, date: key, isAvailable: available);
      await _loadOverrides();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    }
  }

  Future<void> _removeOverride(AvailabilityOverride override) async {
    final product = widget.product;
    if (product == null) return;
    try {
      await widget.api.clearOverride(product.id, date: override.date);
      await _loadOverrides();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    }
  }

  /// `2026-07-13` → `13/07/2026`.
  String _formatDate(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length != 3) return dateKey;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(_isEditing ? 'Editar produto' : 'Novo produto',
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Excluir',
              onPressed: _saving ? null : _confirmDelete,
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            ),
        ],
      ),
      body: SafeArea(top: false, child: _buildForm()),
      bottomNavigationBar: _buildSaveBar(),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.danger),
            ),
            child: Text(_error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ),
          const SizedBox(height: 16),
        ],
        _label('Nome'),
        TextField(
          controller: _name,
          enabled: !_saving,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: AppTheme.inputDecoration(
            hint: 'Ex.: Smash Clássico',
            prefixIcon: Icons.fastfood_outlined,
          ),
        ),
        const SizedBox(height: 16),
        _label('Descrição'),
        TextField(
          controller: _description,
          enabled: !_saving,
          maxLines: 3,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: AppTheme.inputDecoration(
            hint: 'Pão brioche, blend 160g, queijo cheddar…',
          ),
        ),
        const SizedBox(height: 16),
        _label('Preço'),
        TextField(
          controller: _price,
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: AppTheme.inputDecoration(
            hint: '28,90',
            prefixIcon: Icons.attach_money,
          ),
        ),
        const SizedBox(height: 16),
        _label('Categoria'),
        _Dropdown<String?>(
          value: _categoryId,
          enabled: !_saving,
          items: [
            const DropdownMenuItem(value: null, child: Text('Sem categoria')),
            for (final c in widget.categories)
              DropdownMenuItem(value: c.id, child: Text(c.name)),
          ],
          onChanged: (v) => setState(() => _categoryId = v),
        ),
        const SizedBox(height: 16),
        _label('Cardápio'),
        _Dropdown<String?>(
          value: _menuId,
          enabled: !_saving,
          items: [
            const DropdownMenuItem(
                value: null, child: Text('Nenhum (sempre disponível)')),
            for (final m in widget.menus)
              DropdownMenuItem(value: m.id, child: Text(m.name)),
          ],
          onChanged: (v) => setState(() => _menuId = v),
        ),
        const SizedBox(height: 20),
        _card(
          child: SwitchListTile(
            value: _isAvailable,
            onChanged: _saving
                ? null
                : (v) => setState(() => _isAvailable = v),
            activeThumbColor: AppColors.primary,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: const Text('Disponível',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            subtitle: const Text(
              'Desligado, o item sai do cardápio em qualquer dia.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _card(
          child: SwitchListTile(
            value: _allowsHalf,
            onChanged: _saving ? null : (v) => setState(() => _allowsHalf = v),
            activeThumbColor: AppColors.primary,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: const Text('Aceita meio a meio',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            subtitle: const Text(
              'Só sabores marcados entram numa pizza de dois sabores. O preço '
              'segue a regra da loja.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _label('Dias da semana'),
        const Text(
          'Nenhum dia marcado = vendido todos os dias.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var day = 0; day < 7; day++)
              _WeekdayChip(
                label: kWeekdayShortLabels[day],
                selected: _weekdays.contains(day),
                enabled: !_saving,
                onTap: () => setState(() {
                  if (!_weekdays.remove(day)) _weekdays.add(day);
                }),
              ),
          ],
        ),
        const SizedBox(height: 24),
        OptionGroupsEditor(
          groups: _groups,
          enabled: !_saving,
          onChanged: (groups) => setState(() => _groups = groups),
        ),
        if (_isEditing) ...[
          const SizedBox(height: 24),
          _buildOverridesSection(),
        ],
      ],
    );
  }

  Widget _buildOverridesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _label('Disponibilidade por data')),
            TextButton.icon(
              onPressed: _saving ? null : _addOverride,
              icon: const Icon(Icons.event_outlined, size: 18),
              label: const Text('Adicionar'),
              style:
                  TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
        const Text(
          'Exceções para um dia específico. Elas têm prioridade sobre os dias '
          'da semana acima.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (_loadingOverrides)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2),
              ),
            ),
          )
        else if (_overrides.isEmpty)
          _card(
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Nenhuma exceção nos próximos 30 dias.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ),
          )
        else
          _card(
            child: Column(
              children: [
                for (var i = 0; i < _overrides.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: AppColors.border),
                  ListTile(
                    leading: Icon(
                      _overrides[i].isAvailable
                          ? Icons.check_circle_outline
                          : Icons.block,
                      color: _overrides[i].isAvailable
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                    title: Text(_formatDate(_overrides[i].date),
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 14)),
                    subtitle: Text(
                      _overrides[i].isAvailable
                          ? 'Liberado neste dia'
                          : 'Bloqueado neste dia',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    trailing: IconButton(
                      tooltip: 'Remover exceção',
                      onPressed: _saving
                          ? null
                          : () => _removeOverride(_overrides[i]),
                      icon: const Icon(Icons.close,
                          color: AppColors.textSecondary, size: 18),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSaveBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor:
                  AppColors.primary.withValues(alpha: 0.4),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Text(_isEditing ? 'Salvar alterações' : 'Criar produto',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
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

class _WeekdayChip extends StatelessWidget {
  const _WeekdayChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.enabled,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// Dropdown no estilo escuro do app.
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.enabled,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          icon: const Icon(Icons.expand_more, color: AppColors.textSecondary),
          style:
              const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          items: items,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}
