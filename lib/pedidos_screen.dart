import 'dart:async';

import 'package:flutter/material.dart';

import 'menu/menu_api.dart' show formatBrl;
import 'orders/orders_api.dart';
import 'orders/orders_stream.dart';
import 'printing/printer_settings.dart';
import 'printing/thermal_printer.dart';
import 'theme/app_theme.dart';
import 'widgets/app_bottom_nav.dart';

class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key, OrdersApi? api, OrdersStream? stream})
      : _injectedApi = api,
        _injectedStream = stream;

  /// Permite injetar um [OrdersApi] falso nos testes. Em produção fica `null`.
  final OrdersApi? _injectedApi;

  /// Idem para o stream SSE dos pedidos.
  final OrdersStream? _injectedStream;

  @override
  State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  late final OrdersApi _api = widget._injectedApi ?? OrdersApi();
  late final OrdersStream _stream = widget._injectedStream ?? OrdersStream();
  final PrinterSettingsStore _printerStore = PrinterSettingsStore();

  StreamSubscription<OrderEvent>? _eventsSub;

  PrinterSettings _printer = const PrinterSettings();

  /// Pedidos já enviados à impressora nesta sessão — evita reimprimir a cada
  /// atualização da lista quando a impressão automática está ligada.
  final Set<String> _printed = <String>{};

  bool _loading = true;
  bool _moduleDisabled = false;
  String? _loadError;
  int _filter = 0;

  /// (rótulo, status enviado à API — `null` = todos os pedidos). Segue a ordem
  /// do fluxo; "Saiu p/ entrega" e "Aguardando retirada" são as etapas paralelas
  /// de entrega e retirada.
  static const List<(String, String?)> _filters = [
    ('Todos', null),
    ('Recebidos', 'received'),
    ('Em preparo', 'preparing'),
    ('Prontos', 'ready'),
    ('Saiu p/ entrega', 'out_for_delivery'),
    ('Aguardando retirada', 'awaiting_pickup'),
    ('Concluídos', 'completed'),
    ('Cancelados', 'canceled'),
  ];

  /// Pedidos do painel (sem filtro) — base para os cartões de estatística.
  List<Order> _panel = const [];

  /// Lista visível conforme o filtro selecionado.
  List<Order> _orders = const [];

  @override
  void initState() {
    super.initState();
    _loadPrinter();
    _load();
    _listenToOrders();
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _stream.dispose();
    super.dispose();
  }

  Future<void> _loadPrinter() async {
    final p = await _printerStore.load();
    if (!mounted) return;
    setState(() => _printer = p);
  }

  /// Pedidos em tempo real: entram na lista assim que o servidor avisa, sem
  /// esperar o próximo refresh.
  Future<void> _listenToOrders() async {
    _eventsSub = _stream.events.listen(_onOrderEvent);
    await _stream.connect();
  }

  void _onOrderEvent(OrderEvent event) {
    if (!mounted) return;
    setState(() => _applyIncoming(event.order));

    // Pedido novo já sai na impressora — é o ponto do stream.
    if (event.type == OrderEventType.created) {
      unawaited(_autoPrint(event.order));
    }
  }

  /// Insere ou atualiza o pedido nas duas listas, respeitando o filtro ativo.
  void _applyIncoming(Order order) {
    List<Order> upsert(List<Order> list) {
      final index = list.indexWhere((o) => o.id == order.id);
      if (index == -1) return [order, ...list];
      final copy = [...list];
      copy[index] = order;
      return copy;
    }

    _panel = upsert(_panel);

    final status = _filters[_filter].$2;
    if (status == null) {
      _orders = _panel;
    } else if (OrderStatus.parse(status) == order.status) {
      _orders = upsert(_orders);
    } else {
      // Mudou de status e saiu do filtro visível.
      _orders = _orders.where((o) => o.id != order.id).toList();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _moduleDisabled = false;
    });
    try {
      final status = _filters[_filter].$2;
      final results = await Future.wait([
        _api.fetchOrders(),
        if (status != null) _api.fetchOrders(status: status),
      ]);
      if (!mounted) return;
      setState(() {
        _panel = results[0];
        _orders = status == null ? results[0] : results[1];
        _loading = false;
      });
      unawaited(_autoPrintNewOrders());
    } on OrdersModuleDisabled {
      if (!mounted) return;
      setState(() {
        _moduleDisabled = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Não foi possível carregar os pedidos.';
        _loading = false;
      });
    }
  }

  Future<void> _selectFilter(int index) async {
    if (index == _filter) return;
    setState(() => _filter = index);
    await _load();
  }

  int _countStatus(OrderStatus status) =>
      _panel.where((o) => o.status == status).length;

  int get _activeCount =>
      _panel.where((o) => !o.status.isTerminal).length;

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.received:
        return AppColors.ai;
      case OrderStatus.preparing:
        return AppColors.primary;
      case OrderStatus.ready:
        return AppColors.primaryDim;
      case OrderStatus.outForDelivery:
        return AppColors.primaryDim;
      case OrderStatus.awaitingPickup:
        return AppColors.primaryDim;
      case OrderStatus.completed:
        return AppColors.success;
      case OrderStatus.canceled:
        return AppColors.danger;
      case OrderStatus.unknown:
        return AppColors.textSecondary;
    }
  }

  Future<void> _advance(Order order) async {
    Navigator.of(context).maybePop();
    try {
      final updated = await _api.advance(order.id);
      if (!mounted) return;
      _applyUpdate(order.id, updated);
      _snack('Pedido #${order.orderNumber} avançado para '
          '${updated?.status.label ?? '—'}.');
    } catch (e) {
      if (!mounted) return;
      _snack(_errorText(e));
    }
  }

  Future<void> _cancel(Order order) async {
    Navigator.of(context).maybePop();
    try {
      final updated = await _api.cancel(order.id);
      if (!mounted) return;
      _applyUpdate(order.id, updated);
      _snack('Pedido #${order.orderNumber} cancelado.');
    } catch (e) {
      if (!mounted) return;
      _snack(_errorText(e));
    }
  }

  /// Substitui o pedido nas duas listas após uma mudança de status.
  void _applyUpdate(String id, Order? updated) {
    if (updated == null) {
      _load();
      return;
    }
    List<Order> replace(List<Order> list) =>
        list.map((o) => o.id == id ? updated : o).toList();
    setState(() {
      _panel = replace(_panel);
      // Se a lista visível está filtrada por status e o pedido saiu do filtro,
      // some dele; caso contrário, atualiza no lugar.
      final status = _filters[_filter].$2;
      if (status != null &&
          OrderStatus.parse(status) != updated.status) {
        _orders = _orders.where((o) => o.id != id).toList();
      } else {
        _orders = replace(_orders);
      }
    });
  }

  /// Imprime o cupom sob demanda (item do menu de ações).
  Future<void> _print(Order order) async {
    Navigator.of(context).maybePop();
    if (!_printer.isConfigured) {
      _snack('Configure a impressora em Configurações > Impressora térmica.');
      return;
    }
    try {
      await ThermalPrinter(_printer).printOrder(order);
      if (!mounted) return;
      _printed.add(order.id);
      _snack('Cupom do pedido #${order.orderNumber} enviado.');
    } on PrinterException catch (e) {
      if (!mounted) return;
      _snack(e.message);
    }
  }

  /// Imprime um pedido recebido, uma única vez. Falhas são silenciosas: a
  /// impressora pode estar fora do ar e o operador ainda imprime manualmente.
  ///
  /// Devolve `false` quando a impressora não respondeu, para o chamador em lote
  /// parar de insistir.
  Future<bool> _autoPrint(Order order) async {
    if (!_printer.autoPrint || !_printer.isConfigured) return true;
    if (order.status != OrderStatus.received) return true;
    if (!_printed.add(order.id)) return true; // já saiu na impressora

    try {
      await ThermalPrinter(_printer).printOrder(order);
      return true;
    } on PrinterException {
      // Libera para uma nova tentativa no próximo evento ou refresh.
      _printed.remove(order.id);
      return false;
    }
  }

  /// Rede de segurança do SSE: ao atualizar a lista, imprime os recebidos que
  /// ainda não saíram (por exemplo, os que chegaram com o app fechado).
  Future<void> _autoPrintNewOrders() async {
    if (!_printer.autoPrint || !_printer.isConfigured) return;
    for (final order
        in _panel.where((o) => o.status == OrderStatus.received)) {
      final ok = await _autoPrint(order);
      if (!ok) return; // impressora indisponível: tenta no próximo refresh
    }
  }

  String _errorText(Object e) {
    final msg = e.toString();
    return msg.startsWith('Exception: ')
        ? msg.substring('Exception: '.length)
        : 'Erro ao atualizar o pedido.';
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

  /// Linha de detalhe do pedido no menu de ações (ícone + texto).
  Widget _detailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Sequência de etapas conforme o tipo de pedido. Entrega passa por "Saiu para
  /// entrega"; retirada por "Aguardando retirada". As duas convergem em Concluído.
  List<OrderStatus> _statusFlow(Order order) {
    return [
      OrderStatus.received,
      OrderStatus.preparing,
      OrderStatus.ready,
      order.isPickup ? OrderStatus.awaitingPickup : OrderStatus.outForDelivery,
      OrderStatus.completed,
    ];
  }

  IconData _statusIcon(OrderStatus s) {
    switch (s) {
      case OrderStatus.received:
        return Icons.receipt_long_outlined;
      case OrderStatus.preparing:
        return Icons.soup_kitchen_outlined;
      case OrderStatus.ready:
        return Icons.check_circle_outline;
      case OrderStatus.outForDelivery:
        return Icons.local_shipping_outlined;
      case OrderStatus.awaitingPickup:
        return Icons.storefront_outlined;
      case OrderStatus.completed:
        return Icons.task_alt;
      case OrderStatus.canceled:
        return Icons.cancel_outlined;
      case OrderStatus.unknown:
        return Icons.help_outline;
    }
  }

  /// "15/07 14:32" — hora curta para os nós da timeline. Só temos horário real
  /// da criação e da última mudança de status.
  String? _shortTime(DateTime? dt) {
    if (dt == null) return null;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  /// Linha do tempo das etapas do pedido. Marca as já percorridas, a atual e as
  /// pendentes. Cancelado é terminal: mostra Recebido + o nó de cancelamento.
  Widget _statusTimeline(Order order) {
    if (order.status == OrderStatus.canceled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _timelineRow(
            icon: _statusIcon(OrderStatus.received),
            label: OrderStatus.received.label,
            time: _shortTime(order.createdAt),
            state: _StepState.done,
            isLast: false,
          ),
          _timelineRow(
            icon: Icons.cancel_outlined,
            label: 'Cancelado',
            time: _shortTime(order.updatedAt),
            state: _StepState.canceled,
            isLast: true,
          ),
        ],
      );
    }

    final flow = _statusFlow(order);
    final currentIndex = flow.indexOf(order.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < flow.length; i++)
          _timelineRow(
            icon: _statusIcon(flow[i]),
            label: flow[i].label,
            time: i == 0
                ? _shortTime(order.createdAt)
                : (i == currentIndex ? _shortTime(order.updatedAt) : null),
            state: currentIndex < 0
                ? _StepState.pending
                : i < currentIndex
                    ? _StepState.done
                    : i == currentIndex
                        ? _StepState.current
                        : _StepState.pending,
            isLast: i == flow.length - 1,
          ),
      ],
    );
  }

  Widget _timelineRow({
    required IconData icon,
    required String label,
    String? time,
    required _StepState state,
    required bool isLast,
  }) {
    final Color color = switch (state) {
      _StepState.done || _StepState.current => AppColors.primary,
      _StepState.canceled => AppColors.danger,
      _StepState.pending => AppColors.borderStrong,
    };
    final bool filled = state != _StepState.pending;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color:
                      filled ? color.withValues(alpha: 0.15) : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: color.withValues(alpha: 0.4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Padding(
            padding: EdgeInsets.only(top: 3, bottom: isLast ? 0 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: state == _StepState.pending
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: state == _StepState.current
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                if (time != null)
                  Text(
                    time,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openActions(Order order) async {
    // Recarrega a config da impressora: no layout desktop esta tela fica viva no
    // IndexedStack e o IP pode ter sido salvo depois do initState.
    await _loadPrinter();
    if (!mounted) return;
    // Pedidos encerrados ainda abrem o menu: dá para tirar a 2ª via do cupom.
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pedido #${order.orderNumber} • ${order.customerName}',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  _detailRow(Icons.local_shipping_outlined,
                      order.fulfillmentLabel),
                  if (!order.isPickup && order.address != null)
                    _detailRow(Icons.location_on_outlined, order.address!),
                  if (order.customerPhone != null)
                    _detailRow(Icons.phone_outlined, order.customerPhone!),
                  _detailRow(
                    Icons.payments_outlined,
                    order.paymentMethod == 'cash' && order.changeFor != null
                        ? '${order.paymentLabel} • troco para '
                            '${formatBrl(order.changeFor!)}'
                        : order.paymentLabel,
                  ),
                  if (order.notes != null)
                    _detailRow(Icons.sticky_note_2_outlined, order.notes!),
                  const SizedBox(height: 14),
                  const Text(
                    'ETAPAS',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _statusTimeline(order),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading:
                  const Icon(Icons.print_outlined, color: AppColors.primary),
              title: const Text('Imprimir cupom',
                  style: TextStyle(color: AppColors.textPrimary)),
              subtitle: Text(
                _printer.isConfigured
                    ? 'Impressora ${_printer.host}'
                    : 'Impressora não configurada',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              onTap: () => _print(order),
            ),
            if (!order.status.isTerminal) ...[
              ListTile(
                leading:
                    const Icon(Icons.arrow_forward, color: AppColors.primary),
                title: const Text('Avançar status',
                    style: TextStyle(color: AppColors.textPrimary)),
                subtitle: const Text('Avisa o cliente no WhatsApp',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                onTap: () => _advance(order),
              ),
              ListTile(
                leading: const Icon(Icons.close, color: AppColors.danger),
                title: const Text('Cancelar pedido',
                    style: TextStyle(color: AppColors.danger)),
                onTap: () => _cancel(order),
              ),
            ],
            const SizedBox(height: 8),
          ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        titleSpacing: 16,
        title: const Text('Pedidos',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 20)),
      ),
      body: SafeArea(top: false, child: _buildBody()),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
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

    final stats = [
      _Stat('Ativos', '$_activeCount'),
      _Stat('Em preparo', '${_countStatus(OrderStatus.preparing)}'),
      _Stat('Concluídos', '${_countStatus(OrderStatus.completed)}'),
      _Stat('Cancelados', '${_countStatus(OrderStatus.canceled)}'),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < _filters.length; i++)
                  Padding(
                    padding:
                        EdgeInsets.only(right: i < _filters.length - 1 ? 8 : 0),
                    child: FilterChip(
                      label: Text(_filters[i].$1),
                      selected: _filter == i,
                      onSelected: (_) => _selectFilter(i),
                      selectedColor: AppColors.primary.withValues(alpha: 0.2),
                      backgroundColor: AppColors.surface,
                      labelStyle: TextStyle(
                        color: _filter == i
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      side: BorderSide(
                        color: _filter == i
                            ? AppColors.primary
                            : AppColors.border,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final s in stats) Expanded(child: _StatCard(stat: s)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            onRefresh: _load,
            child: _orders.isEmpty
                ? _buildEmpty()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemBuilder: (context, index) {
                      final order = _orders[index];
                      return _OrderTile(
                        order: order,
                        statusColor: _statusColor(order.status),
                        onTap: () => _openActions(order),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemCount: _orders.length,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_outlined,
                      color: AppColors.textSecondary, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'Nenhum pedido por aqui.',
                    style: TextStyle(
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
            Icon(Icons.receipt_long_outlined,
                color: AppColors.textSecondary, size: 56),
            SizedBox(height: 16),
            Text(
              'Pedidos indisponíveis',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'O módulo de Cardápio não está habilitado para esta empresa. '
              'Ative-o para receber pedidos.',
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

class _Stat {
  final String label;
  final String value;
  const _Stat(this.label, this.value);
}

/// Estado de um nó da linha do tempo do pedido.
enum _StepState { done, current, pending, canceled }

class _StatCard extends StatelessWidget {
  final _Stat stat;
  const _StatCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stat.value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(stat.label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final Order order;
  final Color statusColor;
  final VoidCallback onTap;
  const _OrderTile({
    required this.order,
    required this.statusColor,
    required this.onTap,
  });

  String _time(DateTime? dt) {
    if (dt == null) return '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long,
                    color: AppColors.textSecondary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '#${order.orderNumber} • ${order.customerName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(order.status.label,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              )),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(order.itemsSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(_time(order.createdAt),
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 11)),
                        const Spacer(),
                        Text(formatBrl(order.total),
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
