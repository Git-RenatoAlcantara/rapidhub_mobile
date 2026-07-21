import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'campaigns_api.dart';

/// Cria ou edita uma campanha (rascunho). Devolve `true` ao fechar quando algo
/// foi salvo, para a tela de Campanhas recarregar a lista.
///
/// O disparo NÃO acontece aqui: salvar só grava o rascunho. Enviar em massa é
/// um clique separado na lista, com confirmação.
class CampaignEditorScreen extends StatefulWidget {
  const CampaignEditorScreen({
    super.key,
    required this.api,
    required this.coupons,
    required this.connections,
    this.campaign,
  });

  final CampaignsApi api;
  final List<Coupon> coupons;
  final List<CampaignConnection> connections;

  /// `null` = criar uma campanha nova.
  final Campaign? campaign;

  @override
  State<CampaignEditorScreen> createState() => _CampaignEditorScreenState();
}

class _CampaignEditorScreenState extends State<CampaignEditorScreen> {
  final _name = TextEditingController();
  final _message = TextEditingController();
  final _inactiveDays = TextEditingController(text: '30');
  final _phone = TextEditingController();

  String? _connectionId;
  String _segmentType = 'all';
  String? _couponId;
  int _throttleSeconds = 8;
  String _dateFrom = '';
  String _dateTo = '';

  int? _previewCount;
  bool _previewing = false;

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.campaign != null;

  @override
  void initState() {
    super.initState();
    final campaign = widget.campaign;
    if (campaign != null) {
      _name.text = campaign.name;
      _message.text = campaign.messageText;
      _segmentType = campaign.segmentType;
      _couponId = campaign.couponId;
      _throttleSeconds = campaign.throttleSeconds;
      _connectionId = campaign.connectionId;
      final config = campaign.segmentConfig;
      final days = config['inactiveDays'];
      if (days is num) _inactiveDays.text = '${days.toInt()}';
      _dateFrom = (config['dateFrom'] ?? '').toString();
      _dateTo = (config['dateTo'] ?? '').toString();
      final phones = config['phones'];
      if (phones is List && phones.isNotEmpty) {
        _phone.text = phones.first.toString();
      }
    }
    // A conexão salva pode ter caído desde então; sem ela na lista, o dropdown
    // ficaria com um valor sem item e quebraria o build.
    final known = widget.connections.any((c) => c.id == _connectionId);
    if (!known) {
      _connectionId =
          widget.connections.isNotEmpty ? widget.connections.first.id : null;
    }
    if (_couponId != null &&
        !widget.coupons.any((c) => c.id == _couponId)) {
      _couponId = null;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _message.dispose();
    _inactiveDays.dispose();
    _phone.dispose();
    super.dispose();
  }

  Map<String, dynamic> _segmentConfig() {
    switch (_segmentType) {
      case 'inactive':
        final days = int.tryParse(_inactiveDays.text.trim());
        return {'inactiveDays': (days == null || days <= 0) ? 30 : days};
      case 'purchase_period':
        return {
          if (_dateFrom.isNotEmpty) 'dateFrom': _dateFrom,
          if (_dateTo.isNotEmpty) 'dateTo': _dateTo,
        };
      case 'specific':
        final phone = _phone.text.replaceAll(RegExp(r'\D'), '');
        return {if (phone.isNotEmpty) 'phones': [phone]};
      default:
        return const {};
    }
  }

  Future<void> _preview() async {
    setState(() {
      _previewing = true;
      _previewCount = null;
    });
    try {
      final config = _segmentConfig();
      final phones = config['phones'];
      final count = await widget.api.previewCount(
        segmentType: _segmentType,
        inactiveDays: config['inactiveDays'] as int?,
        dateFrom: config['dateFrom'] as String?,
        dateTo: config['dateTo'] as String?,
        phone: (phones is List && phones.isNotEmpty)
            ? phones.first.toString()
            : null,
      );
      if (!mounted) return;
      setState(() {
        _previewCount = count;
        _previewing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _previewing = false;
        _error = _friendlyError(e, 'Não foi possível contar os destinatários.');
      });
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final message = _message.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Dê um nome à campanha.');
      return;
    }
    if (_connectionId == null) {
      setState(() => _error =
          'Nenhuma conexão de WhatsApp conectada para disparar a campanha.');
      return;
    }
    if (message.isEmpty) {
      setState(() => _error = 'Escreva a mensagem que o cliente vai receber.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (_isEditing) {
        await widget.api.updateCampaign(
          widget.campaign!.id,
          name: name,
          connectionId: _connectionId,
          segmentType: _segmentType,
          segmentConfig: _segmentConfig(),
          messageText: message,
          couponId: _couponId,
          clearCoupon: _couponId == null,
          throttleSeconds: _throttleSeconds,
        );
      } else {
        await widget.api.createCampaign(
          name: name,
          connectionId: _connectionId!,
          segmentType: _segmentType,
          segmentConfig: _segmentConfig(),
          messageText: message,
          couponId: _couponId,
          throttleSeconds: _throttleSeconds,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(e, 'Não foi possível salvar a campanha.');
      });
    }
  }

  String _friendlyError(Object e, String fallback) {
    if (e is CampaignsForbidden) return e.message;
    final message = e.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : fallback;
  }

  Future<void> _pickDate({required bool from}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
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
    final key = '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    setState(() {
      if (from) {
        _dateFrom = key;
      } else {
        _dateTo = key;
      }
      _previewCount = null;
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
        title: Text(_isEditing ? 'Editar campanha' : 'Nova campanha',
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
            hint: 'Ex.: Volta pra gente — julho',
            prefixIcon: Icons.campaign_outlined,
          ),
        ),
        const SizedBox(height: 16),
        _label('Conexão de envio'),
        if (widget.connections.isEmpty)
          const Text(
            'Nenhuma conexão conectada. Conecte um WhatsApp para disparar.',
            style: TextStyle(color: AppColors.danger, fontSize: 12.5),
          )
        else
          CampaignDropdown<String?>(
            value: _connectionId,
            enabled: !_saving,
            items: [
              for (final c in widget.connections)
                DropdownMenuItem(value: c.id, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _connectionId = v),
          ),
        const SizedBox(height: 16),
        _label('Público'),
        CampaignDropdown<String>(
          value: _segmentType,
          enabled: !_saving,
          items: [
            for (final s in kCampaignSegments)
              DropdownMenuItem(value: s.value, child: Text(s.label)),
          ],
          onChanged: (v) => setState(() {
            _segmentType = v ?? 'all';
            _previewCount = null;
          }),
        ),
        ..._buildSegmentConfig(),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton.icon(
              onPressed: (_saving || _previewing) ? null : _preview,
              icon: const Icon(Icons.group_outlined, size: 18),
              label: const Text('Contar destinatários'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
            if (_previewing)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2),
              )
            else if (_previewCount != null)
              Text('${_previewCount!} cliente(s)',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),
        _label('Mensagem'),
        TextField(
          controller: _message,
          enabled: !_saving,
          maxLines: 6,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: AppTheme.inputDecoration(
            hint: 'Oi [primeiro_nome]! Sentimos sua falta…',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Variáveis: [nome], [primeiro_nome], [produto_favorito] e [cupom]. '
          'Sem valor, a variável some do texto.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        _label('Cupom'),
        CampaignDropdown<String?>(
          value: _couponId,
          enabled: !_saving,
          items: [
            const DropdownMenuItem(value: null, child: Text('Sem cupom')),
            for (final c in widget.coupons.where((c) => c.isActive))
              DropdownMenuItem(
                value: c.id,
                child: Text(c.isPersonalized
                    ? '${c.label} · exclusivo por cliente'
                    : c.label),
              ),
          ],
          onChanged: (v) => setState(() => _couponId = v),
        ),
        const SizedBox(height: 8),
        const Text(
          'Cada destinatário ganha uma concessão do cupom. Se ele for exclusivo '
          'por cliente, o código sai personalizado e o desconto entra sozinho '
          'na próxima compra.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        _label('Intervalo entre envios'),
        CampaignDropdown<int>(
          value: _throttleSeconds,
          enabled: !_saving,
          items: const [
            DropdownMenuItem(value: 5, child: Text('5 segundos')),
            DropdownMenuItem(value: 8, child: Text('8 segundos (padrão)')),
            DropdownMenuItem(value: 15, child: Text('15 segundos')),
            DropdownMenuItem(value: 30, child: Text('30 segundos')),
            DropdownMenuItem(value: 60, child: Text('1 minuto')),
          ],
          onChanged: (v) => setState(() => _throttleSeconds = v ?? 8),
        ),
        const SizedBox(height: 8),
        const Text(
          'Espaçar os envios reduz o risco de bloqueio do número no WhatsApp.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  List<Widget> _buildSegmentConfig() {
    switch (_segmentType) {
      case 'inactive':
        return [
          const SizedBox(height: 16),
          _label('Dias sem comprar'),
          TextField(
            controller: _inactiveDays,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() => _previewCount = null),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: AppTheme.inputDecoration(hint: '30'),
          ),
        ];
      case 'purchase_period':
        return [
          const SizedBox(height: 16),
          _label('Período da compra'),
          Row(
            children: [
              Expanded(
                child: _DateButton(
                  label: _dateFrom.isEmpty ? 'De' : _formatDate(_dateFrom),
                  enabled: !_saving,
                  onTap: () => _pickDate(from: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateButton(
                  label: _dateTo.isEmpty ? 'Até' : _formatDate(_dateTo),
                  enabled: !_saving,
                  onTap: () => _pickDate(from: false),
                ),
              ),
            ],
          ),
        ];
      case 'specific':
        return [
          const SizedBox(height: 16),
          _label('Número (com DDI)'),
          TextField(
            controller: _phone,
            enabled: !_saving,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() => _previewCount = null),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: AppTheme.inputDecoration(
              hint: '5511999999999',
              prefixIcon: Icons.phone_outlined,
            ),
          ),
        ];
      default:
        return const [];
    }
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
                : Text(_isEditing ? 'Salvar rascunho' : 'Criar rascunho',
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
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.onTap,
    required this.enabled,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: const Icon(Icons.event_outlined, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.borderStrong),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// Dropdown no estilo escuro do app, compartilhado pelas telas de campanha.
class CampaignDropdown<T> extends StatelessWidget {
  const CampaignDropdown({
    super.key,
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
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          items: items,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}
