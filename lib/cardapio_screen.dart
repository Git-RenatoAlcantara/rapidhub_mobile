import 'package:flutter/material.dart';

import 'menu/categories_screen.dart';
import 'menu/menu_api.dart';
import 'menu/menus_screen.dart';
import 'menu/product_editor_screen.dart';
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
  List<Menu> _menus = const [];

  /// Ids dos produtos vendáveis hoje, segundo o próprio servidor
  /// (`/api/menu/today`) — já considera exceções por data e dias da semana.
  Set<String> _availableToday = const {};

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
        _api.fetchMenus(),
        _api.fetchAvailableTodayIds(),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<MenuCategory>;
        _products = results[1] as List<MenuProduct>;
        _menus = results[2] as List<Menu>;
        _availableToday = results[3] as Set<String>;
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

  /// Abre o editor e recarrega tudo se algo foi salvo. Recarregar é
  /// obrigatório: a resposta do PUT de produto não traz os grupos de opções.
  Future<void> _openProduct([MenuProduct? product]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductEditorScreen(
          api: _api,
          categories: _categories,
          menus: _menus,
          product: product,
        ),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _openCategories() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CategoriesScreen(api: _api)),
    );
    if (changed == true) {
      // A categoria selecionada pode ter sido excluída.
      setState(() => _selectedCategoryId = null);
      await _load();
    }
  }

  Future<void> _openMenus() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MenusScreen(api: _api)),
    );
    if (changed == true) await _load();
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
        actions: [
          if (!_moduleDisabled && _loadError == null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
              color: AppColors.surface,
              onSelected: (value) {
                if (value == 'categorias') _openCategories();
                if (value == 'cardapios') _openMenus();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'categorias',
                  child: Text('Categorias',
                      style: TextStyle(color: AppColors.textPrimary)),
                ),
                PopupMenuItem(
                  value: 'cardapios',
                  child: Text('Cardápios por horário',
                      style: TextStyle(color: AppColors.textPrimary)),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: (_loading || _moduleDisabled || _loadError != null)
          ? null
          : FloatingActionButton.extended(
              heroTag: 'fab_cardapio',
              onPressed: () => _openProduct(),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Novo item',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _MenuTile(
                        item: item,
                        // Um produto disponível pode mesmo assim estar fora do
                        // cardápio de hoje (dia da semana ou exceção de data).
                        availableToday: _availableToday.contains(item.id),
                        onTap: () => _openProduct(item),
                      );
                    },
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
  const _MenuTile({
    required this.item,
    required this.availableToday,
    required this.onTap,
  });

  final MenuProduct item;
  final bool availableToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: _buildCard(),
    );
  }

  Widget _buildCard() {
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
                if (_statusLabel != null || item.optionGroups.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (_statusLabel != null)
                        _chip(_statusLabel!, _statusColor),
                      if (item.optionGroups.isNotEmpty)
                        _chip(
                          item.optionGroups.length == 1
                              ? '1 grupo de opções'
                              : '${item.optionGroups.length} grupos de opções',
                          AppColors.textSecondary,
                        ),
                    ],
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
              color: _statusColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  /// Três estados, não dois: o item pode estar ligado e ainda assim fora do
  /// cardápio de hoje (por dia da semana ou por exceção de data).
  String? get _statusLabel {
    if (!item.isAvailable) return 'Indisponível';
    if (!availableToday) return 'Fora do cardápio hoje';
    return null;
  }

  Color get _statusColor {
    if (!item.isAvailable) return AppColors.danger;
    if (!availableToday) return const Color(0xFFD29922); // âmbar
    return AppColors.success;
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
