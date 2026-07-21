import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'widgets/app_logo.dart';
import 'orders/orders_api.dart';
import 'store/store_api.dart';
import 'store/store_models.dart';
import 'pedidos_screen.dart';
import 'store_screen.dart';

/// Recorte de tempo do painel — mesmas opções do webapp.
enum DashboardPeriod {
  today('Hoje'),
  yesterday('Ontem'),
  last7('7 dias'),
  last30('30 dias');

  const DashboardPeriod(this.label);

  final String label;

  /// Intervalo `[from, to]` no fuso local, sempre em dias inteiros.
  DateRange range(DateTime now) {
    switch (this) {
      case DashboardPeriod.today:
        return DateRange(_startOfDay(now), _endOfDay(now));
      case DashboardPeriod.yesterday:
        final y = now.subtract(const Duration(days: 1));
        return DateRange(_startOfDay(y), _endOfDay(y));
      case DashboardPeriod.last7:
        return DateRange(
            _startOfDay(now.subtract(const Duration(days: 6))), _endOfDay(now));
      case DashboardPeriod.last30:
        return DateRange(_startOfDay(now.subtract(const Duration(days: 29))),
            _endOfDay(now));
    }
  }

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
}

class DateRange {
  const DateRange(this.from, this.to);

  final DateTime from;
  final DateTime to;
}

/// Painel operacional da loja (análogo mobile de `/store/dashboard` no webapp).
///
/// Reúne, numa só tela, o pulso da operação: se a loja está aberta agora
/// (segundo o horário de funcionamento), quantos pedidos estão em andamento
/// por etapa e o resultado do dia (concluídos e faturamento). Consome as
/// mesmas rotas de [StoreApi] e [OrdersApi] usadas nos demais ecrãs.
class StoreDashboardScreen extends StatefulWidget {
  const StoreDashboardScreen({super.key, StoreApi? storeApi, OrdersApi? ordersApi})
      : _injectedStoreApi = storeApi,
        _injectedOrdersApi = ordersApi;

  /// Permite injetar APIs falsas nos testes de widget. Em produção ficam
  /// `null` e a tela cria as instâncias reais.
  final StoreApi? _injectedStoreApi;
  final OrdersApi? _injectedOrdersApi;

  @override
  State<StoreDashboardScreen> createState() => _StoreDashboardScreenState();
}

class _StoreDashboardScreenState extends State<StoreDashboardScreen> {
  late final StoreApi _storeApi = widget._injectedStoreApi ?? StoreApi();
  late final OrdersApi _ordersApi = widget._injectedOrdersApi ?? OrdersApi();

  bool _loading = true;
  bool _moduleDisabled = false;
  String? _loadError;

  OperatingHours _hours = OperatingHours.initial();
  List<Order> _orders = const [];
  DashboardPeriod _period = DashboardPeriod.today;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _selectPeriod(DashboardPeriod period) async {
    if (period == _period) return;
    setState(() => _period = period);
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _moduleDisabled = false;
    });
    try {
      final range = _period.range(DateTime.now());
      // As duas rotas dependem do módulo Cardápio; buscar em paralelo.
      final results = await Future.wait([
        _storeApi.fetchStore(),
        _ordersApi.fetchOrders(from: range.from, to: range.to),
      ]);
      if (!mounted) return;
      final store = results[0] as Map<String, dynamic>;
      final orders = results[1] as List<Order>;
      setState(() {
        _hours = OperatingHours.fromMetadata(store);
        _orders = orders;
        _loading = false;
      });
    } on StoreModuleDisabled {
      _onModuleDisabled();
    } on OrdersModuleDisabled {
      _onModuleDisabled();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Não foi possível carregar o painel da loja.';
        _loading = false;
      });
    }
  }

  void _onModuleDisabled() {
    if (!mounted) return;
    setState(() {
      _moduleDisabled = true;
      _loading = false;
    });
  }

  // ── Métricas operacionais ────────────────────────────────────────────────

  List<Order> get _active =>
      _orders.where((o) => !o.status.isTerminal).toList();

  int _countByStatus(OrderStatus status) =>
      _orders.where((o) => o.status == status).length;

  /// Vendas = todos os pedidos do período **menos os cancelados** — não só os
  /// concluídos, senão o total do dia fica zerado enquanto os pedidos ainda
  /// estão em preparo ou saíram para entrega. Mesma regra do webapp.
  double get _revenue => _orders
      .where((o) => o.status != OrderStatus.canceled)
      .fold<double>(0, (sum, o) => sum + o.total);

  /// Tempo médio entre a criação do pedido e a última mudança de status, para
  /// os pedidos que já saíram da cozinha. `null` quando não há amostra.
  int? get _avgPrepMinutes {
    final done = _orders.where((o) =>
        o.status == OrderStatus.completed ||
        o.status == OrderStatus.outForDelivery ||
        o.status == OrderStatus.awaitingPickup);
    final sample = done
        .where((o) => o.createdAt != null && o.updatedAt != null)
        .toList();
    if (sample.isEmpty) return null;
    final totalMs = sample.fold<int>(
      0,
      (acc, o) =>
          acc + o.updatedAt!.difference(o.createdAt!).inMilliseconds,
    );
    return (totalMs / sample.length / 60000).round();
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
            Text('Painel da Loja',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
          ],
        ),
        actions: [
          if (!_loading && !_moduleDisabled && _loadError == null)
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _load,
              icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
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
    if (_moduleDisabled) return _buildModuleDisabled();
    if (_loadError != null) return _buildLoadError();

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildStatusCard(),
          const SizedBox(height: 20),
          _buildPeriodChips(),
          const SizedBox(height: 16),
          _sectionTitle('Resultado — ${_period.label.toLowerCase()}'),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  icon: Icons.receipt_long_outlined,
                  label: 'Pedidos',
                  value: '${_orders.length}',
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statTile(
                  icon: Icons.payments_outlined,
                  label: 'Vendas',
                  value: _brl(_revenue),
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statTile(
                  icon: Icons.timer_outlined,
                  label: 'Preparo médio',
                  value: _avgPrepMinutes == null
                      ? '—'
                      : '$_avgPrepMinutes min',
                  color: AppColors.ai,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _sectionTitle('Pedidos em andamento (${_active.length})'),
          _buildPipelineCard(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PedidosScreen()),
                );
              },
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Ver todos os pedidos'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Filtro de período ────────────────────────────────────────────────────

  Widget _buildPeriodChips() {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: DashboardPeriod.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final period = DashboardPeriod.values[i];
          final active = period == _period;
          return GestureDetector(
            onTap: () => _selectPeriod(period),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: active ? AppColors.primary : AppColors.border),
              ),
              child: Text(
                period.label,
                style: TextStyle(
                  color: active ? Colors.white : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Status da loja (aberta/fechada agora) ────────────────────────────────

  Widget _buildStatusCard() {
    final now = DateTime.now();
    final _StoreStatus status = _resolveStatus(now);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: status.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(status.icon, color: status.color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status.title,
                    style: TextStyle(
                        color: status.color,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(status.subtitle,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Resolve o estado atual da loja a partir do horário de funcionamento.
  ///
  /// O backend guarda os slots por `weekday` no padrão JS (`0` = domingo). O
  /// Dart usa `DateTime.weekday` com segunda=1…domingo=7, então `weekday % 7`
  /// converte para o padrão do servidor. Janelas que cruzam a meia-noite
  /// (fim ≤ início) são tratadas como virada de dia.
  _StoreStatus _resolveStatus(DateTime now) {
    if (!_hours.enabled) {
      return const _StoreStatus(
        title: 'Horário não configurado',
        subtitle: 'Defina o horário de funcionamento nas configurações.',
        icon: Icons.schedule_outlined,
        color: AppColors.textSecondary,
      );
    }

    final jsWeekday = now.weekday % 7; // 0 = domingo
    final nowMin = now.hour * 60 + now.minute;
    final today = _hours.days[jsWeekday];

    if (today.active) {
      final from = hhmmToMinutes(today.from);
      final to = hhmmToMinutes(today.to);
      final open = to <= from
          ? (nowMin >= from || nowMin < to) // cruza a meia-noite
          : (nowMin >= from && nowMin < to);
      if (open) {
        return _StoreStatus(
          title: 'Loja aberta',
          subtitle: 'Aberta hoje das ${today.from} às ${today.to}.',
          icon: Icons.storefront,
          color: AppColors.success,
        );
      }
      if (nowMin < from) {
        return _StoreStatus(
          title: 'Loja fechada',
          subtitle: 'Abre hoje às ${today.from}.',
          icon: Icons.storefront_outlined,
          color: AppColors.danger,
        );
      }
    }

    return const _StoreStatus(
      title: 'Loja fechada',
      subtitle: 'Fora do horário de funcionamento.',
      icon: Icons.storefront_outlined,
      color: AppColors.danger,
    );
  }

  // ── Pipeline de pedidos por etapa ────────────────────────────────────────

  Widget _buildPipelineCard() {
    // A pré-venda só ocupa espaço quando há pedido agendado — loja que não usa
    // o recurso não ganha uma linha morta no painel.
    final stages = <OrderStatus>[
      if (_countByStatus(OrderStatus.scheduled) > 0) OrderStatus.scheduled,
      OrderStatus.received,
      OrderStatus.preparing,
      OrderStatus.ready,
      OrderStatus.outForDelivery,
      OrderStatus.awaitingPickup,
    ];

    if (_active.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: Text('Nenhum pedido em andamento.',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < stages.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            _pipelineRow(stages[i], _countByStatus(stages[i])),
          ],
        ],
      ),
    );
  }

  Widget _pipelineRow(OrderStatus status, int count) {
    final dim = count == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Icon(_statusIcon(status),
              size: 20,
              color: dim ? AppColors.textSecondary : AppColors.textPrimary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(status.label,
                style: TextStyle(
                    color: dim ? AppColors.textSecondary : AppColors.textPrimary,
                    fontSize: 14)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: dim
                  ? AppColors.surfaceAlt
                  : AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$count',
                style: TextStyle(
                    color: dim ? AppColors.textSecondary : AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.scheduled:
        return Icons.schedule;
      case OrderStatus.received:
        return Icons.inbox_outlined;
      case OrderStatus.preparing:
        return Icons.soup_kitchen_outlined;
      case OrderStatus.ready:
        return Icons.check_circle_outline;
      case OrderStatus.outForDelivery:
        return Icons.delivery_dining_outlined;
      case OrderStatus.awaitingPickup:
        return Icons.shopping_bag_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  // ── Estados de exceção ───────────────────────────────────────────────────

  Widget _buildModuleDisabled() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront_outlined,
                color: AppColors.textSecondary, size: 56),
            const SizedBox(height: 16),
            const Text('Painel indisponível',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'O módulo de Cardápio não está habilitado para esta empresa. '
              'Ative-o para acompanhar a operação da loja.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StoreScreen()),
                );
              },
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Configurações da Loja'),
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
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
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

  // ── Helpers de UI ────────────────────────────────────────────────────────

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
      child: Text(text.toUpperCase(),
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5)),
    );
  }

  Widget _statTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 12),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.4)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  /// Formata um valor em reais no padrão pt-BR (R$ 1.234,56).
  String _brl(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final buffer = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write('.');
      buffer.write(intPart[i]);
    }
    return 'R\$ ${buffer.toString()},${parts[1]}';
  }
}

/// Estado apresentável da loja (aberta/fechada/sem horário).
class _StoreStatus {
  const _StoreStatus({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}
