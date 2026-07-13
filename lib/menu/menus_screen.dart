import 'package:flutter/material.dart';

import '../store/store_models.dart' show minutesToHHMM;
import '../theme/app_theme.dart';
import 'menu_api.dart';
import 'menu_availability.dart';

/// Cardápios da loja (`/api/menu/menus`): vários cardápios, cada um com suas
/// janelas de horário — almoço, jantar, fim de semana.
///
/// Devolve `true` ao fechar se algo mudou, para o Cardápio recarregar.
class MenusScreen extends StatefulWidget {
  const MenusScreen({super.key, required this.api});

  final MenuApi api;

  @override
  State<MenusScreen> createState() => _MenusScreenState();
}

class _MenusScreenState extends State<MenusScreen> {
  List<Menu> _menus = const [];
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final menus = await widget.api.fetchMenus();
      if (!mounted) return;
      setState(() {
        _menus = menus;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendly(e);
        _loading = false;
      });
    }
  }

  String _friendly(Object e) {
    if (e is MenuForbidden) return e.message;
    final message = e.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : 'Não foi possível carregar os cardápios.';
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _changed = true;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_friendly(e)), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Abre o editor e salva o que voltar dele.
  Future<void> _edit({Menu? menu}) async {
    final result = await showModalBottomSheet<_MenuDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MenuEditorSheet(menu: menu),
    );
    if (result == null) return;

    await _run(() async {
      if (menu == null) {
        await widget.api.createMenu(
          name: result.name,
          isActive: result.isActive,
          availability: result.availability,
        );
      } else {
        await widget.api.updateMenu(
          menu.id,
          name: result.name,
          isActive: result.isActive,
          availability: result.availability,
          // Só aqui a `availability` é reescrita. Sem esse flag, o servidor
          // ignora o campo e as janelas antigas ficariam intactas.
          touchAvailability: true,
        );
      }
    });
  }

  Future<void> _delete(Menu menu) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Excluir cardápio',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          menu.productCount > 0
              ? 'Excluir "${menu.name}"? Os ${menu.productCount} produtos dele '
                  'continuam no cardápio, mas ficam sem cardápio associado.'
              : 'Excluir "${menu.name}"?',
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
    await _run(() => widget.api.deleteMenu(menu.id));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          title: const Text('Cardápios',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _busy ? null : () => _edit(),
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
        body: SafeArea(top: false, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14)),
              const SizedBox(height: 16),
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
    if (_menus.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Nenhum cardápio ainda. Crie um para separar itens por horário '
            '(almoço, jantar) — produtos sem cardápio ficam sempre à venda.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      itemCount: _menus.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _MenuCard(
        menu: _menus[i],
        enabled: !_busy,
        onEdit: () => _edit(menu: _menus[i]),
        onDelete: () => _delete(_menus[i]),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.menu,
    required this.onEdit,
    required this.onDelete,
    required this.enabled,
  });

  final Menu menu;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool enabled;

  /// "Seg 11:00–15:00 • Ter 11:00–15:00" ou o motivo de não haver horário.
  String get _scheduleLabel {
    final availability = menu.availability;
    if (availability == null || !availability.enabled) {
      return 'Sem restrição de horário';
    }
    final slots = availability.slots.where((s) => s.isActive).toList();
    if (slots.isEmpty) return 'Nenhuma janela definida';
    return slots
        .map((s) =>
            '${kWeekdayShortLabels[s.weekday]} ${minutesToHHMM(s.fromMinutes)}'
            '–${minutesToHHMM(s.toMinutes)}')
        .join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(menu.name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (menu.isActive ? AppColors.success : AppColors.danger)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  menu.isActive ? 'Ativo' : 'Inativo',
                  style: TextStyle(
                    color:
                        menu.isActive ? AppColors.success : AppColors.danger,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_scheduleLabel,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            menu.productCount == 1
                ? '1 produto'
                : '${menu.productCount} produtos',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: enabled ? onEdit : null,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Editar'),
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
              TextButton.icon(
                onPressed: enabled ? onDelete : null,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Excluir'),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// O que o editor devolve para a tela salvar.
class _MenuDraft {
  const _MenuDraft({
    required this.name,
    required this.isActive,
    required this.availability,
  });

  final String name;
  final bool isActive;

  /// `null` = sem restrição de horário (o backend grava NULL).
  final MenuAvailability? availability;
}

class _MenuEditorSheet extends StatefulWidget {
  const _MenuEditorSheet({this.menu});

  final Menu? menu;

  @override
  State<_MenuEditorSheet> createState() => _MenuEditorSheetState();
}

class _MenuEditorSheetState extends State<_MenuEditorSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.menu?.name ?? '');

  late bool _isActive = widget.menu?.isActive ?? true;

  /// Horário ligado = o cardápio só vale dentro das janelas.
  late bool _scheduled = widget.menu?.availability?.enabled ?? false;

  /// Cópia das janelas: editar aqui não mexe no objeto da lista até salvar.
  late final List<MenuSlot> _slots = [
    ...?widget.menu?.availability?.slots.map((s) => s.copy()),
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickTime(MenuSlot slot, {required bool isStart}) async {
    final current = isStart ? slot.fromMinutes : slot.toMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
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
    if (picked == null) return;
    setState(() {
      final minutes = picked.hour * 60 + picked.minute;
      if (isStart) {
        slot.fromMinutes = minutes;
      } else {
        slot.toMinutes = minutes;
      }
    });
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    // Sem horário marcado, mandamos `null`: o cardápio passa a depender só do
    // toggle Ativo, que é o que o backend entende por "sem restrição".
    final availability = _scheduled
        ? MenuAvailability(enabled: true, slots: _slots)
        : null;

    Navigator.of(context).pop(_MenuDraft(
      name: name,
      isActive: _isActive,
      availability: availability,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.menu == null ? 'Novo cardápio' : 'Editar cardápio',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: AppTheme.inputDecoration(
                hint: 'Nome (ex.: Almoço)',
                prefixIcon: Icons.menu_book_outlined,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              activeThumbColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
              title: const Text('Ativo',
                  style:
                      TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: const Text('Desligado, o cardápio inteiro sai do ar.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ),
            SwitchListTile(
              value: _scheduled,
              onChanged: (v) => setState(() => _scheduled = v),
              activeThumbColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
              title: const Text('Restringir por horário',
                  style:
                      TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: const Text(
                'Sem isso, o cardápio vale o dia todo, todos os dias.',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            if (_scheduled) ...[
              const SizedBox(height: 8),
              for (var i = 0; i < _slots.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SlotRow(
                    key: ObjectKey(_slots[i]),
                    slot: _slots[i],
                    onWeekdayChanged: (v) =>
                        setState(() => _slots[i].weekday = v),
                    onPickStart: () => _pickTime(_slots[i], isStart: true),
                    onPickEnd: () => _pickTime(_slots[i], isStart: false),
                    onRemove: () => setState(() => _slots.removeAt(i)),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  // 21 é o teto do schema do servidor.
                  onPressed: _slots.length >= 21
                      ? null
                      : () => setState(() => _slots.add(MenuSlot(
                            weekday: 1,
                            fromMinutes: 11 * 60,
                            toMinutes: 15 * 60,
                          ))),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Adicionar janela'),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.primary),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Salvar',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    super.key,
    required this.slot,
    required this.onWeekdayChanged,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onRemove,
  });

  final MenuSlot slot;
  final ValueChanged<int> onWeekdayChanged;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: slot.weekday,
              dropdownColor: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              icon: const Icon(Icons.expand_more,
                  color: AppColors.textSecondary, size: 18),
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 14),
              items: [
                for (var d = 0; d < 7; d++)
                  DropdownMenuItem(
                      value: d, child: Text(kWeekdayShortLabels[d])),
              ],
              onChanged: (v) => onWeekdayChanged(v ?? 0),
            ),
          ),
          const Spacer(),
          _TimeButton(
              label: minutesToHHMM(slot.fromMinutes), onTap: onPickStart),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('–',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          _TimeButton(label: minutesToHHMM(slot.toMinutes), onTap: onPickEnd),
          IconButton(
            tooltip: 'Remover janela',
            onPressed: onRemove,
            icon: const Icon(Icons.close,
                color: AppColors.textSecondary, size: 18),
          ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderStrong),
        ),
        child: Text(label,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 13)),
      ),
    );
  }
}
