import 'dart:convert';

import 'package:flutter/material.dart';

import 'campaigns/campaigns_api.dart';
import 'theme/app_theme.dart';
import 'widgets/app_logo.dart';
import 'store/store_api.dart';
import 'store/store_models.dart';
import 'store/kitchen_group_editor.dart';
import 'store/menu_mode_editor.dart';
import 'store/operating_hours_editor.dart';
import 'store/delivery_zones_editor.dart';
import 'store/pickup_time_editor.dart';
import 'store/pre_order_editor.dart';

/// Configurações da Loja (nível de organização): grupo da cozinha, horário de
/// funcionamento, frete e tempo de retirada. Salvas em
/// `Organization.metadata.store` via `/api/store`. Gateadas pelo módulo `menu`.
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key, StoreApi? api}) : _injectedApi = api;

  /// Permite injetar um [StoreApi] falso nos testes de widget. Em produção
  /// fica `null` e a tela cria a instância real.
  final StoreApi? _injectedApi;

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  late final StoreApi _api = widget._injectedApi ?? StoreApi();
  late final CampaignsApi _campaignsApi = CampaignsApi();

  bool _loading = true;
  bool _saving = false;
  bool _moduleDisabled = false;
  String? _loadError;

  MenuMode _menuMode = MenuMode.regular;
  KitchenGroup? _kitchenGroup;
  OperatingHours _operatingHours = OperatingHours.initial();
  DeliveryZones _deliveryZones = DeliveryZones.initial();
  PickupTime _pickupTime = PickupTime.initial();
  PreOrder _preOrder = PreOrder.initial();
  String _abandonmentStage = kDefaultAbandonmentStage;
  String _abandonmentCouponId = '';
  String _halfPriceRule = '';

  /// Cupons ativos para o seletor da recuperação. Fica vazio quando o módulo de
  /// Campanhas está desligado — o resto da tela continua funcionando.
  List<CouponChoice> _coupons = const [];

  String _savedSignature = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Assinatura estável do estado atual para dirty-tracking (espelha o webapp).
  String _signature() {
    return jsonEncode({
      'menuMode': _menuMode.value,
      'kitchenGroup': _kitchenGroup == null
          ? ''
          : '${_kitchenGroup!.connectionId}:${_kitchenGroup!.groupId}',
      'operatingHours': _operatingHours.signature,
      'deliveryZones': _deliveryZones.signature,
      'pickupTime': _pickupTime.signature,
      'preOrder': _preOrder.signature,
      'abandonmentTriggerStage': _abandonmentStage,
      'abandonmentCouponId': _abandonmentCouponId,
      'halfPriceRule': _halfPriceRule,
    });
  }

  bool get _dirty => !_loading && _signature() != _savedSignature;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _moduleDisabled = false;
    });
    try {
      final store = await _api.fetchStore();
      if (!mounted) return;
      setState(() {
        _menuMode = MenuMode.parse(store['menuMode']);
        _kitchenGroup = KitchenGroup.fromJson(store['kitchenGroup']);
        _operatingHours = OperatingHours.fromMetadata(store);
        _deliveryZones = DeliveryZones.fromMetadata(store);
        _pickupTime = PickupTime.fromMetadata(store);
        _preOrder = PreOrder.fromMetadata(store);
        _abandonmentStage =
            parseAbandonmentStage(store['abandonmentTriggerStage']);
        _abandonmentCouponId = (store['abandonmentCouponId'] ?? '').toString();
        _halfPriceRule = parseHalfPriceRule(store['halfPriceRule']);
        _savedSignature = _signature();
        _loading = false;
      });
      await _loadCoupons();
    } on StoreModuleDisabled {
      if (!mounted) return;
      setState(() {
        _moduleDisabled = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Não foi possível carregar as configurações da loja.';
        _loading = false;
      });
    }
  }

  /// Cupons ativos do módulo de Campanhas. Falhar aqui não é erro de tela: a
  /// loja pode nem ter o módulo ligado, e aí o seletor só não aparece.
  Future<void> _loadCoupons() async {
    try {
      final coupons = await _campaignsApi.fetchCoupons();
      if (!mounted) return;
      setState(() {
        _coupons = [
          for (final c in coupons.where((c) => c.isActive))
            CouponChoice(
              id: c.id,
              label: c.isPersonalized
                  ? '${c.label} · exclusivo por cliente'
                  : c.label,
            ),
        ];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _coupons = const []);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final store = {
        'menuMode': _menuMode.value,
        'kitchenGroup': _kitchenGroup?.toJson(),
        'operatingHours': _operatingHours.toMetadata(),
        'deliveryZones': _deliveryZones.toMetadata(),
        'pickupTime': _pickupTime.toMetadata(),
        'preOrder': _preOrder.toMetadata(),
        'abandonmentTriggerStage': _abandonmentStage,
        // '' = sem cupom / meio a meio desligado; grava null para limpar.
        'abandonmentCouponId':
            _abandonmentCouponId.isEmpty ? null : _abandonmentCouponId,
        'halfPriceRule': _halfPriceRule.isEmpty ? null : _halfPriceRule,
      };
      await _api.saveStore(store);
      if (!mounted) return;
      setState(() {
        _savedSignature = _signature();
        _saving = false;
      });
      _snack('Configurações da loja salvas!');
    } on StoreModuleDisabled {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _moduleDisabled = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Erro ao salvar as configurações da loja.');
    }
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
            Text('Loja',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
          ],
        ),
      ),
      body: SafeArea(top: false, child: _buildBody()),
      bottomNavigationBar: _buildSaveBar(),
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Text(
          'Configurações da Loja',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.4),
        ),
        const SizedBox(height: 6),
        const Text(
          'Grupo da cozinha, horário de funcionamento e frete. Valem para '
          'todos os agentes desta loja.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        MenuModeEditor(
          value: _menuMode,
          disabled: _saving,
          onChanged: (m) => setState(() => _menuMode = m),
        ),
        const SizedBox(height: 24),
        KitchenGroupEditor(
          value: _kitchenGroup,
          api: _api,
          disabled: _saving,
          onChanged: (kg) => setState(() => _kitchenGroup = kg),
        ),
        const SizedBox(height: 24),
        OperatingHoursEditor(
          value: _operatingHours,
          disabled: _saving,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 24),
        DeliveryZonesEditor(
          value: _deliveryZones,
          disabled: _saving,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 24),
        PickupTimeEditor(
          value: _pickupTime,
          disabled: _saving,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 24),
        PreOrderEditor(
          value: _preOrder,
          disabled: _saving,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 24),
        AbandonmentStageEditor(
          value: _abandonmentStage,
          disabled: _saving,
          onChanged: (v) => setState(() => _abandonmentStage = v),
        ),
        const SizedBox(height: 24),
        AbandonmentCouponEditor(
          value: _abandonmentCouponId,
          coupons: _coupons,
          disabled: _saving,
          onChanged: (v) => setState(() => _abandonmentCouponId = v),
        ),
        const SizedBox(height: 24),
        HalfPriceRuleEditor(
          value: _halfPriceRule,
          disabled: _saving,
          onChanged: (v) => setState(() => _halfPriceRule = v),
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
            Icon(Icons.storefront_outlined,
                color: AppColors.textSecondary, size: 56),
            SizedBox(height: 16),
            Text(
              'Loja indisponível',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'O módulo de Cardápio não está habilitado para esta empresa. '
              'Ative-o para configurar a loja.',
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
            const Icon(Icons.error_outline,
                color: AppColors.danger, size: 48),
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

  Widget? _buildSaveBar() {
    if (_loading || _moduleDisabled || _loadError != null) return null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_dirty)
              const Expanded(
                child: Text(
                  'Alterações não salvas',
                  style: TextStyle(color: Color(0xFFD29922), fontSize: 13),
                ),
              )
            else
              const Spacer(),
            const SizedBox(width: 12),
            SizedBox(
              height: 46,
              child: ElevatedButton(
                onPressed: (!_dirty || _saving) ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.4),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
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
                    : const Text('Salvar',
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
