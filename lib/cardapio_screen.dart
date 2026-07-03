import 'package:flutter/material.dart';

import 'menu/menu_api.dart';
import 'theme/app_theme.dart';
import 'widgets/app_bottom_nav.dart';

class CardapioScreen extends StatefulWidget {
  const CardapioScreen({super.key, MenuApi? api}) : _injectedApi = api;

  /// Permite injetar um [MenuApi] falso nos testes. Em produção fica `null`.
  final MenuApi? _injectedApi;

  @override
  State<CardapioScreen> createState() => _CardapioScreenState();
}

class _CardapioScreenState extends State<CardapioScreen> {
  late final MenuApi _api = widget._injectedApi ?? MenuApi();
  final _searchController = TextEditingController();

  bool _loading = true;
  bool _moduleDisabled = false;
  String? _loadError;

  List<MenuCategory> _categories = const [];
  List<MenuProduct> _products = const [];

  /// `null` = categoria "Todos".
  String? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _moduleDisabled = false;
    });
    try {
      final results = await Future.wait([
        _api.fetchCategories(),
        _api.fetchProducts(),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<MenuCategory>;
        _products = results[1] as List<MenuProduct>;
        _loading = false;
      });
    } on MenuModuleDisabled {
      if (!mounted) return;
      setState(() {
        _moduleDisabled = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Não foi possível carregar o cardápio.';
        _loading = false;
      });
    }
  }

  List<MenuProduct> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    return _products.where((item) {
      final matchesQuery = query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.description.toLowerCase().contains(query);
      final matchesCategory =
          _selectedCategoryId == null || item.categoryId == _selectedCategoryId;
      return matchesQuery && matchesCategory;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        titleSpacing: 16,
        title: const Text('Cardápio',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 20)),
      ),
      body: SafeArea(top: false, child: _buildBody()),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_moduleDisabled) return _buildModuleDisabled();
    if (_loadError != null) return _buildLoadError();

    final filtered = _filtered;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: AppTheme.inputDecoration(
              hint: 'Buscar item...',
              prefixIcon: Icons.search,
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              // index 0 = "Todos"; demais = categorias reais.
              final isAll = index == 0;
              final category = isAll ? null : _categories[index - 1];
              final active = _selectedCategoryId == category?.id;
              final label = isAll ? 'Todos' : category!.name;
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedCategoryId = category?.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: active ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: Center(
                    child: Text(label,
                        style: TextStyle(
                          color:
                              active ? Colors.white : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.normal,
                        )),
                  ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemCount: _categories.length + 1,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: filtered.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemBuilder: (context, index) =>
                        _MenuTile(item: filtered[index]),
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemCount: filtered.length,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    final hasFilter =
        _searchController.text.trim().isNotEmpty || _selectedCategoryId != null;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.restaurant_menu_outlined,
                      color: AppColors.textSecondary, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    hasFilter
                        ? 'Nenhum item encontrado.'
                        : 'Nenhum item no cardápio ainda.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModuleDisabled() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu_outlined,
                color: AppColors.textSecondary, size: 56),
            SizedBox(height: 16),
            Text(
              'Cardápio indisponível',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'O módulo de Cardápio não está habilitado para esta empresa. '
              'Ative-o para gerenciar os itens.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
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
}

class _MenuTile extends StatelessWidget {
  final MenuProduct item;
  const _MenuTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 56,
              height: 56,
              color: AppColors.surfaceAlt,
              child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                  ? Image.network(
                      item.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.restaurant_menu,
                          color: AppColors.textSecondary,
                          size: 28),
                    )
                  : const Icon(Icons.restaurant_menu,
                      color: AppColors.textSecondary, size: 28),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item.name,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ),
                    Text(formatBrl(item.price),
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: item.isAvailable ? AppColors.success : AppColors.danger,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
