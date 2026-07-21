import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import 'campaign_editor_screen.dart';
import 'campaigns_api.dart';
import 'coupon_editor_screen.dart';

/// Campanhas e cupons: reengaja clientes pelo WhatsApp com ofertas e mensagens
/// personalizadas. Espelha `components/campaigns/CampaignsManager.tsx` do
/// webapp. Gateada pelo módulo `campaigns`.
class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key, CampaignsApi? api}) : _injectedApi = api;

  /// Permite injetar uma [CampaignsApi] falsa nos testes de widget.
  final CampaignsApi? _injectedApi;

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen>
    with SingleTickerProviderStateMixin {
  late final CampaignsApi _api = widget._injectedApi ?? CampaignsApi();
  late final TabController _tabs = TabController(length: 2, vsync: this);

  List<Campaign> _campaigns = const [];
  List<Coupon> _coupons = const [];
  List<CampaignConnection> _connections = const [];

  bool _loading = true;
  bool _moduleDisabled = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    // O rótulo do FAB muda com a aba ("Nova campanha"/"Novo cupom").
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _moduleDisabled = false;
    });
    try {
      final campaigns = await _api.fetchCampaigns();
      final coupons = await _api.fetchCoupons();
      // A lista de conexões não é gateada pelo módulo; se falhar, o resto da
      // tela ainda serve — só não dá para criar campanha nova.
      List<CampaignConnection> connections;
      try {
        connections = await _api.fetchConnections();
      } catch (_) {
        connections = const [];
      }
      if (!mounted) return;
      setState(() {
        _campaigns = campaigns;
        _coupons = coupons;
        _connections = connections;
        _loading = false;
      });
    } on CampaignsModuleDisabled {
      if (!mounted) return;
      setState(() {
        _moduleDisabled = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Não foi possível carregar as campanhas.';
        _loading = false;
      });
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.danger : AppColors.surface,
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
      ),
    );
  }

  String _friendlyError(Object e, String fallback) {
    if (e is CampaignsForbidden) return e.message;
    final message = e.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : fallback;
  }

  // ── Ações de campanha ────────────────────────────────────────────────────

  Future<void> _openCampaignEditor([Campaign? campaign]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CampaignEditorScreen(
          api: _api,
          coupons: _coupons,
          connections: _connections,
          campaign: campaign,
        ),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _send(Campaign campaign) async {
    final confirmed = await _confirm(
      title: 'Disparar "${campaign.name}" agora?',
      message: 'Isso envia mensagens de WhatsApp aos clientes do segmento.',
      action: 'Disparar',
    );
    if (confirmed != true) return;
    try {
      final total = await _api.sendCampaign(campaign.id);
      _snack('Campanha disparada para $total cliente(s).');
      await _load();
    } catch (e) {
      _snack(_friendlyError(e, 'Falha ao disparar.'), error: true);
    }
  }

  /// Reenviar duplica em rascunho em vez de redisparar: os contadores da
  /// original ficam intactos e o operador ainda precisa clicar em Disparar,
  /// então um envio em massa nunca sai de um clique só.
  Future<void> _resend(Campaign campaign) async {
    final confirmed = await _confirm(
      title: 'Reenviar campanha?',
      message:
          'Cria um rascunho novo com a mesma configuração de "${campaign.name}".',
      action: 'Criar rascunho',
    );
    if (confirmed != true) return;
    try {
      await _api.duplicateCampaign(campaign.id);
      _snack('Rascunho criado. Revise e clique em Disparar.');
      await _load();
    } catch (e) {
      _snack(_friendlyError(e, 'Falha ao reenviar.'), error: true);
    }
  }

  Future<void> _deleteCampaign(Campaign campaign) async {
    final confirmed = await _confirm(
      title: 'Excluir campanha?',
      message: '"${campaign.name}" e o histórico de envio dela serão apagados.',
      action: 'Excluir',
      danger: true,
    );
    if (confirmed != true) return;
    try {
      await _api.deleteCampaign(campaign.id);
      await _load();
    } catch (e) {
      _snack(_friendlyError(e, 'Falha ao excluir.'), error: true);
    }
  }

  // ── Ações de cupom ───────────────────────────────────────────────────────

  Future<void> _openCouponEditor([Coupon? coupon]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CouponEditorScreen(api: _api, coupon: coupon),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _deleteCoupon(Coupon coupon) async {
    final confirmed = await _confirm(
      title: 'Excluir cupom?',
      message: 'O código ${coupon.code} deixa de existir para os clientes.',
      action: 'Excluir',
      danger: true,
    );
    if (confirmed != true) return;
    try {
      await _api.deleteCoupon(coupon.id);
      await _load();
    } catch (e) {
      _snack(_friendlyError(e, 'Falha ao excluir o cupom.'), error: true);
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String action,
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: Text(message,
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action,
                style: TextStyle(
                    color: danger ? AppColors.danger : AppColors.primary)),
          ),
        ],
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showTabs = !_loading && !_moduleDisabled && _loadError == null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 16,
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Row(
          children: [
            AppLogo(),
            SizedBox(width: 10),
            Text('Campanhas',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
          ],
        ),
        bottom: showTabs
            ? TabBar(
                controller: _tabs,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                tabs: const [
                  Tab(text: 'Campanhas'),
                  Tab(text: 'Cupons'),
                ],
              )
            : null,
      ),
      floatingActionButton: showTabs
          ? FloatingActionButton.extended(
              heroTag: 'campaigns_fab',
              backgroundColor: AppColors.primary,
              onPressed: () => _tabs.index == 0
                  ? _openCampaignEditor()
                  : _openCouponEditor(),
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(_tabs.index == 0 ? 'Nova campanha' : 'Novo cupom',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            )
          : null,
      body: SafeArea(top: false, child: _buildBody(showTabs)),
    );
  }

  Widget _buildBody(bool showTabs) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_moduleDisabled) return _buildModuleDisabled();
    if (_loadError != null) return _buildLoadError();

    return TabBarView(
      controller: _tabs,
      children: [
        RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          child: _buildCampaignsList(),
        ),
        RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          child: _buildCouponsList(),
        ),
      ],
    );
  }

  Widget _buildCampaignsList() {
    if (_campaigns.isEmpty) {
      return _emptyList(
        icon: Icons.campaign_outlined,
        title: 'Nenhuma campanha ainda',
        message: 'Crie uma campanha para reengajar clientes pelo WhatsApp.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: _campaigns.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _campaignCard(_campaigns[i]),
    );
  }

  Widget _campaignCard(Campaign campaign) {
    final sent = campaign.status == 'sent' ||
        campaign.status == 'sending' ||
        campaign.status == 'scheduled';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  campaign.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(campaign.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            campaignSegmentLabel(campaign.segmentType),
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12.5),
          ),
          if (sent) ...[
            const SizedBox(height: 8),
            Text(
              '${campaign.sentCount}/${campaign.totalRecipients} enviadas'
              '${campaign.failedCount > 0 ? ' · ${campaign.failedCount} falhas' : ''}'
              '${campaign.optOutSkipped > 0 ? ' · ${campaign.optOutSkipped} opt-out' : ''}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (campaign.isDraft) ...[
                _cardAction(
                  icon: Icons.edit_outlined,
                  label: 'Editar',
                  onTap: () => _openCampaignEditor(campaign),
                ),
                const SizedBox(width: 4),
                _cardAction(
                  icon: Icons.send_outlined,
                  label: 'Disparar',
                  onTap: () => _send(campaign),
                ),
              ] else
                _cardAction(
                  icon: Icons.copy_all_outlined,
                  label: 'Reenviar',
                  onTap: () => _resend(campaign),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Excluir',
                onPressed: () => _deleteCampaign(campaign),
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.textSecondary, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCouponsList() {
    if (_coupons.isEmpty) {
      return _emptyList(
        icon: Icons.confirmation_number_outlined,
        title: 'Nenhum cupom ainda',
        message:
            'Crie um cupom para anexar a campanhas ou à recuperação de abandono.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: _coupons.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _couponCard(_coupons[i]),
    );
  }

  Widget _couponCard(Coupon coupon) {
    final uses = coupon.maxUses == null
        ? '${coupon.usedCount} uso(s)'
        : '${coupon.usedCount}/${coupon.maxUses} usos';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        coupon.code,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _pill(
                      coupon.isActive ? 'Ativo' : 'Inativo',
                      coupon.isActive ? AppColors.success : AppColors.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${coupon.discountLabel} · $uses'
                  '${coupon.isPersonalized ? ' · exclusivo por cliente' : ''}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Editar',
            onPressed: () => _openCouponEditor(coupon),
            icon: const Icon(Icons.edit_outlined,
                color: AppColors.textSecondary, size: 20),
          ),
          IconButton(
            tooltip: 'Excluir',
            onPressed: () => _deleteCoupon(coupon),
            icon: const Icon(Icons.delete_outline,
                color: AppColors.textSecondary, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = switch (status) {
      'sent' => AppColors.success,
      'sending' || 'scheduled' => AppColors.primary,
      'canceled' => AppColors.danger,
      _ => AppColors.textSecondary,
    };
    return _pill(campaignStatusLabel(status), color);
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  Widget _cardAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    );
  }

  Widget _emptyList({
    required IconData icon,
    required String title,
    required String message,
  }) {
    // ListView (e não Center) para o pull-to-refresh continuar funcionando.
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 80, 32, 24),
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 56),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildModuleDisabled() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_outlined,
                color: AppColors.textSecondary, size: 56),
            SizedBox(height: 16),
            Text(
              'Campanhas indisponível',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'O módulo de Campanhas não está habilitado para esta empresa. '
              'Ative-o para criar campanhas e cupons.',
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
}
