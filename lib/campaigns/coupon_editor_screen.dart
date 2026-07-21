import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'campaign_editor_screen.dart' show CampaignDropdown;
import 'campaigns_api.dart';

/// Cria ou edita um cupom de desconto. Devolve `true` ao fechar quando algo foi
/// salvo.
///
/// Código e "exclusivo por cliente" só existem na criação: o servidor não
/// aceita mudar nenhum dos dois depois, porque códigos já entregues ao cliente
/// não podem mudar de sentido.
class CouponEditorScreen extends StatefulWidget {
  const CouponEditorScreen({super.key, required this.api, this.coupon});

  final CampaignsApi api;

  /// `null` = criar um cupom novo.
  final Coupon? coupon;

  @override
  State<CouponEditorScreen> createState() => _CouponEditorScreenState();
}

class _CouponEditorScreenState extends State<CouponEditorScreen> {
  final _code = TextEditingController();
  final _value = TextEditingController();
  final _minOrder = TextEditingController();
  final _maxUses = TextEditingController();
  final _perContactLimit = TextEditingController(text: '1');

  String _discountType = 'percent';
  bool _isActive = true;
  bool _isPersonalized = false;
  String _validUntil = '';

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.coupon != null;

  @override
  void initState() {
    super.initState();
    final coupon = widget.coupon;
    if (coupon != null) {
      _code.text = coupon.code;
      _discountType = coupon.discountType;
      _value.text = _numberText(coupon.discountValue);
      if (coupon.minOrder != null) {
        _minOrder.text = _numberText(coupon.minOrder!);
      }
      if (coupon.maxUses != null) _maxUses.text = '${coupon.maxUses}';
      _perContactLimit.text = '${coupon.perContactLimit ?? 1}';
      _isActive = coupon.isActive;
      _isPersonalized = coupon.isPersonalized;
      final until = coupon.validUntil;
      if (until != null && until.length >= 10) {
        _validUntil = until.substring(0, 10);
      }
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _minOrder.dispose();
    _maxUses.dispose();
    _perContactLimit.dispose();
    super.dispose();
  }

  static String _numberText(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(2).replaceAll('.', ',');

  /// Aceita vírgula ou ponto — o operador digita "9,90".
  double? _parseNumber(String raw) {
    final text = raw.trim().replaceAll('.', '').replaceAll(',', '.');
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    return (value == null || value < 0) ? null : value;
  }

  Future<void> _save() async {
    final code = _code.text.trim().toUpperCase();
    final value = _parseNumber(_value.text);

    if (!_isEditing && code.isEmpty) {
      setState(() => _error = 'Informe o código do cupom.');
      return;
    }
    if (value == null || value <= 0) {
      setState(() => _error = 'Informe um valor de desconto válido.');
      return;
    }
    if (_discountType == 'percent' && value > 100) {
      setState(() => _error = 'Desconto percentual não pode passar de 100%.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final minOrder = _parseNumber(_minOrder.text);
      final maxUses = int.tryParse(_maxUses.text.trim());
      final perContact = int.tryParse(_perContactLimit.text.trim());

      if (_isEditing) {
        await widget.api.updateCoupon(
          widget.coupon!.id,
          discountType: _discountType,
          discountValue: value,
          minOrder: minOrder,
          maxUses: maxUses,
          perContactLimit: (perContact != null && perContact > 0)
              ? perContact
              : 1,
          validUntil: _validUntil.isEmpty ? null : _validUntil,
          clearValidUntil: _validUntil.isEmpty,
          isActive: _isActive,
        );
      } else {
        await widget.api.createCoupon(
          code: code,
          discountType: _discountType,
          discountValue: value,
          minOrder: minOrder,
          maxUses: maxUses,
          perContactLimit: (perContact != null && perContact > 0)
              ? perContact
              : 1,
          validUntil: _validUntil.isEmpty ? null : _validUntil,
          isActive: _isActive,
          isPersonalized: _isPersonalized,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object e) {
    if (e is CampaignsForbidden) return e.message;
    final message = e.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : 'Não foi possível salvar o cupom.';
  }

  Future<void> _pickValidUntil() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
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
      _validUntil = '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(_isEditing ? 'Editar cupom' : 'Novo cupom',
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
      ),
      body: SafeArea(top: false, child: _buildForm()),
      bottomNavigationBar: _buildSaveBar(),
    );
  }

  Widget _buildForm() {
    final code = _code.text.trim().toUpperCase();

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
        _label('Código'),
        TextField(
          controller: _code,
          enabled: !_saving && !_isEditing,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: AppTheme.inputDecoration(
            hint: 'VOLTA10',
            prefixIcon: Icons.confirmation_number_outlined,
          ),
        ),
        if (_isEditing) ...[
          const SizedBox(height: 6),
          const Text(
            'O código não muda depois de criado — clientes já podem tê-lo.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
        const SizedBox(height: 16),
        _label('Tipo de desconto'),
        CampaignDropdown<String>(
          value: _discountType,
          enabled: !_saving,
          items: const [
            DropdownMenuItem(value: 'percent', child: Text('Percentual (%)')),
            DropdownMenuItem(value: 'fixed', child: Text('Valor fixo (R\$)')),
          ],
          onChanged: (v) => setState(() => _discountType = v ?? 'percent'),
        ),
        const SizedBox(height: 16),
        _label(_discountType == 'percent' ? 'Desconto (%)' : 'Desconto (R\$)'),
        TextField(
          controller: _value,
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: AppTheme.inputDecoration(
            hint: _discountType == 'percent' ? '10' : '5,00',
          ),
        ),
        const SizedBox(height: 16),
        _label('Pedido mínimo (R\$)'),
        TextField(
          controller: _minOrder,
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: AppTheme.inputDecoration(hint: 'Vazio = sem mínimo'),
        ),
        const SizedBox(height: 16),
        _label('Limite total de usos'),
        TextField(
          controller: _maxUses,
          enabled: !_saving,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: AppTheme.inputDecoration(hint: 'Vazio = ilimitado'),
        ),
        const SizedBox(height: 16),
        _label('Usos por cliente'),
        TextField(
          controller: _perContactLimit,
          enabled: !_saving,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: AppTheme.inputDecoration(hint: '1'),
        ),
        const SizedBox(height: 16),
        _label('Validade'),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _pickValidUntil,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(_validUntil.isEmpty
                    ? 'Sem data de validade'
                    : 'Vale até ${_formatDate(_validUntil)}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.borderStrong),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            if (_validUntil.isNotEmpty)
              IconButton(
                tooltip: 'Limpar validade',
                onPressed: _saving ? null : () => setState(() => _validUntil = ''),
                icon: const Icon(Icons.close,
                    color: AppColors.textSecondary, size: 18),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _card(
          child: SwitchListTile(
            value: _isActive,
            onChanged: _saving ? null : (v) => setState(() => _isActive = v),
            activeThumbColor: AppColors.primary,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: const Text('Ativo',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            subtitle: const Text(
              'Desligado, o cupom deixa de valer em novos pedidos.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ),
        if (!_isEditing) ...[
          const SizedBox(height: 12),
          _card(
            child: SwitchListTile(
              value: _isPersonalized,
              onChanged:
                  _saving ? null : (v) => setState(() => _isPersonalized = v),
              activeThumbColor: AppColors.primary,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: const Text('Código exclusivo por cliente',
                  style:
                      TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: Text(
                _isPersonalized
                    ? 'Cada cliente recebe um código próprio, tipo '
                        '${code.isEmpty ? 'VOLTA10' : code}-A3F9. Não dá para repassar.'
                    : 'Todos recebem o mesmo código.',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// `2026-07-13` → `13/07/2026`.
  String _formatDate(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length != 3) return dateKey;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
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
                : Text(_isEditing ? 'Salvar alterações' : 'Criar cupom',
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
