import 'package:flutter/material.dart';
import '../widgets/market_ui.dart';
import 'gateway_methods.dart';

/// One configured payment method row.
class GatewayTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const GatewayTile({super.key, required this.row, required this.busy, required this.onToggle, required this.onEdit, required this.onDelete});

  String _s(String k) => (row[k] ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final m = gatewayMethod(row['method']?.toString());
    final active = row['is_active'] == true;
    final title = _s('label').isNotEmpty ? _s('label') : (_s('provider').isNotEmpty ? _s('provider') : m.label);
    final account = [_s('account_name'), _s('account_number')].where((x) => x.isNotEmpty).join(' · ');
    final tone = p.tone(active ? MarketTone.brand : MarketTone.neutral);

    return MarketCard(
      onTap: onEdit,
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(10)),
          child: Icon(m.icon, size: 19, color: tone.fg),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: active ? 1 : 0.6,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                ),
                if (!active) ...[const SizedBox(width: 6), const StatusPill('Inactive')],
              ]),
              if (_s('provider').isNotEmpty && _s('provider') != title)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(_s('provider'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
                ),
              if (account.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(account,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.text, fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              if (_s('instructions').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_s('instructions'),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label, height: 1.35)),
                ),
            ]),
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 36,
            child: busy
                ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                : Switch.adaptive(value: active, onChanged: onToggle),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(Icons.more_horiz, color: p.label, size: 20),
            onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
      ]),
    );
  }
}
