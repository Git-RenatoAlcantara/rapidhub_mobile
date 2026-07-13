import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'menu_api.dart';

/// CRUD das categorias do cardápio.
///
/// Devolve `true` ao fechar se algo mudou, para a tela de Cardápio recarregar.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, required this.api});

  final MenuApi api;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<MenuCategory> _categories = const [];
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
      final categories = await widget.api.fetchCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
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
        : 'Não foi possível carregar as categorias.';
  }

  /// Executa a ação, mostra o erro na barra e recarrega em caso de sucesso.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _changed = true;
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(_friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }

  Future<String?> _promptName({String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(initial.isEmpty ? 'Nova categoria' : 'Renomear categoria',
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: AppTheme.inputDecoration(hint: 'Ex.: Bebidas'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Salvar',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    controller.dispose();
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<void> _create() async {
    final name = await _promptName();
    if (name == null) return;
    await _run(() => widget.api.createCategory(name: name));
  }

  Future<void> _rename(MenuCategory category) async {
    final name = await _promptName(initial: category.name);
    if (name == null || name == category.name) return;
    await _run(() => widget.api.updateCategory(category.id, name: name));
  }

  Future<void> _delete(MenuCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Excluir categoria',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          category.productCount > 0
              ? 'Excluir "${category.name}"? Os ${category.productCount} '
                  'produtos dela continuam no cardápio, mas ficam sem categoria.'
              : 'Excluir "${category.name}"?',
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
    await _run(() => widget.api.deleteCategory(category.id));
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
          title: const Text('Categorias',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _busy ? null : _create,
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
    if (_categories.isEmpty) {
      return const Center(
        child: Text('Nenhuma categoria ainda.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      itemCount: _categories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final category = _categories[i];
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: ListTile(
            title: Text(category.name,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            subtitle: Text(
              category.productCount == 1
                  ? '1 produto'
                  : '${category.productCount} produtos',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Renomear',
                  onPressed: _busy ? null : () => _rename(category),
                  icon: const Icon(Icons.edit_outlined,
                      color: AppColors.textSecondary, size: 20),
                ),
                IconButton(
                  tooltip: 'Excluir',
                  onPressed: _busy ? null : () => _delete(category),
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.danger, size: 20),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
