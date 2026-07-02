import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'store_api.dart';
import 'store_models.dart';
import 'store_widgets.dart';

/// Editor do grupo da cozinha (envio do pedido). Carrega as conexões
/// group-capable e os grupos da conexão selecionada de `/api/menu/kitchen-options`.
/// Notificame não envia para grupos — só RapidHub/Baileys aparecem.
class KitchenGroupEditor extends StatefulWidget {
  const KitchenGroupEditor({
    super.key,
    required this.value,
    required this.onChanged,
    required this.api,
    this.disabled = false,
  });

  final KitchenGroup? value;
  final ValueChanged<KitchenGroup?> onChanged;
  final StoreApi api;
  final bool disabled;

  @override
  State<KitchenGroupEditor> createState() => _KitchenGroupEditorState();
}

class _KitchenGroupEditorState extends State<KitchenGroupEditor> {
  List<KitchenConnection> _connections = [];
  List<KitchenGroupOption> _groups = [];
  bool _loadingConnections = true;
  bool _loadingGroups = false;

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    final conns = await widget.api.fetchConnections();
    if (!mounted) return;
    setState(() {
      _connections = conns;
      _loadingConnections = false;
    });
    // Carrega os grupos da conexão já salva (para exibir o nome do grupo).
    final connId = widget.value?.connectionId;
    if (connId != null && connId.isNotEmpty) _loadGroups(connId);
  }

  Future<void> _loadGroups(String connectionId) async {
    setState(() => _loadingGroups = true);
    final groups = await widget.api.fetchGroups(connectionId);
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _loadingGroups = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;

    return StoreSection(
      label: 'Grupo da cozinha',
      children: [
        const StoreHelpText(
          'Ao fechar o pedido, a comanda é enviada para este grupo de WhatsApp. '
          'Funciona apenas em conexões compatíveis (RapidHub/Baileys); '
          'Notificame não envia para grupos.',
        ),
        const SizedBox(height: 14),
        if (_loadingConnections)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            ),
          )
        else if (_connections.isEmpty)
          Text(
            'Nenhuma conexão compatível com grupos encontrada nesta empresa.',
            style: TextStyle(
              color: AppColors.danger.withValues(alpha: 0.9),
              fontSize: 13,
            ),
          )
        else ...[
          _buildConnectionDropdown(value),
          if (value != null && value.connectionId.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildGroupDropdown(value),
          ],
          if (value != null && value.groupId.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.check_circle,
                    color: AppColors.success, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pedidos serão enviados para: '
                    '${value.groupName ?? value.groupId}',
                    style: const TextStyle(
                        color: AppColors.success, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildConnectionDropdown(KitchenGroup? value) {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('Não enviar para grupo')),
      ..._connections.map(
        (c) => DropdownMenuItem(
          value: c.id,
          child: Text(
            c.connected ? c.name : '${c.name} (desconectada)',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ];

    return _dropdown(
      label: 'Conexão',
      value: value?.connectionId ?? '',
      items: items,
      onChanged: widget.disabled
          ? null
          : (connectionId) {
              setState(() => _groups = []);
              if (connectionId == null || connectionId.isEmpty) {
                widget.onChanged(null);
              } else {
                widget.onChanged(KitchenGroup(
                  connectionId: connectionId,
                  groupId: '',
                ));
                _loadGroups(connectionId);
              }
            },
    );
  }

  Widget _buildGroupDropdown(KitchenGroup value) {
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: '',
        child: Text(_loadingGroups ? 'Carregando grupos…' : 'Selecione o grupo'),
      ),
      ..._groups.map(
        (g) => DropdownMenuItem(
          value: g.id,
          child: Text(g.name, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];

    return _dropdown(
      label: 'Grupo',
      value: value.groupId,
      items: items,
      onChanged: (widget.disabled || _loadingGroups)
          ? null
          : (groupId) {
              if (groupId == null) return;
              final g = _groups.where((x) => x.id == groupId);
              widget.onChanged(value.copyWith(
                groupId: groupId,
                groupName: g.isNotEmpty ? g.first.name : null,
                clearGroupName: g.isEmpty,
              ));
            },
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?>? onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        isDense: true,
        filled: true,
        fillColor: AppColors.background,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          dropdownColor: AppColors.surfaceAlt,
          iconEnabledColor: AppColors.textSecondary,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
