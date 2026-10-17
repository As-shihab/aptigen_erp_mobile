import 'package:flutter/material.dart';
import '../data/market_seller_service.dart';
import 'banners/form_kit.dart';
import 'gateways/gateway_editor_sheet.dart';
import 'gateways/gateway_methods.dart';
import 'gateways/gateway_tile.dart';
import 'widgets/market_ui.dart';

/// Payment methods this store accepts at market checkout
/// (OData market_payment_gateways) — desktop's Gateways.tsx.
class MarketGatewaysPage extends StatefulWidget {
  const MarketGatewaysPage({super.key});

  @override
  State<MarketGatewaysPage> createState() => _MarketGatewaysPageState();
}

class _MarketGatewaysPageState extends State<MarketGatewaysPage> {
  final _svc = MarketSellerService();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  final Set<int> _toggling = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _svc.gateways();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e, 'Could not load payment methods');
      });
    }
  }

  Future<void> _open({Map<String, dynamic>? row, String method = 'mobile'}) async {
    if (await showGatewayEditor(context, _svc, row: row, method: method)) await _load();
  }

  Future<void> _toggle(Map<String, dynamic> g, bool on) async {
    final id = toInt(g['id']);
    setState(() {
      _toggling.add(id);
      g['is_active'] = on;
    });
    try {
      await _svc.saveGateway(gatewayBody({...g, 'is_active': on}), id: id);
    } catch (e) {
      if (mounted) {
        setState(() => g['is_active'] = !on);
        marketToast(context, errorText(e, 'Could not update the payment method'), error: true);
      }
    } finally {
      if (mounted) setState(() => _toggling.remove(id));
    }
  }

  Future<void> _delete(Map<String, dynamic> g) async {
    final name = (g['label'] ?? g['provider'] ?? gatewayMethod(g['method']?.toString()).label).toString();
    final ok = await confirmMarket(context, title: 'Delete payment method', message: 'Remove "$name"? Buyers will no longer see it at checkout.');
    if (!ok || !mounted) return;
    try {
      await _svc.deleteGateway(toInt(g['id']));
      if (!mounted) return;
      setState(() => _rows.removeWhere((r) => r['id'] == g['id']));
      marketToast(context, 'Payment method deleted');
    } catch (e) {
      if (mounted) marketToast(context, errorText(e, 'Could not delete the payment method'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MarketScaffold(
      title: 'Payment methods',
      subtitle: 'How buyers can pay you on the market',
      fab: _loading || _error != null
          ? null
          : FloatingActionButton.extended(onPressed: () => _open(), icon: const Icon(Icons.add), label: const Text('Add method')),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: _loading
            ? const SkeletonList(key: ValueKey('s'), count: 5, itemHeight: 70)
            : _error != null
                ? Center(
                    key: const ValueKey('e'),
                    child: MarketEmpty(
                      icon: Icons.cloud_off_outlined,
                      title: 'Could not load payment methods',
                      message: _error,
                      actionLabel: 'Try again',
                      onAction: () {
                        setState(() => _loading = true);
                        _load();
                      },
                    ),
                  )
                : RefreshIndicator(key: const ValueKey('l'), onRefresh: _load, child: _list(context)),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final p = MarketPalette.of(context);
    final noRows = _rows.isEmpty;
    final accepted = noRows
        ? gatewayMethods.where((m) => m.id != 'bank').toList()
        : gatewayMethods.where((m) => _rows.any((r) => r['method'] == m.id && r['is_active'] == true)).toList();

    var i = 0;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        FadeSlideIn(
          index: i++,
          child: MarketCard(
            color: p.infoBg,
            borderColor: p.info.withValues(alpha: 0.25),
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 18, color: p.info),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'With no methods set, buyers can pay by cash, card or mobile wallet. Once you add any, only the active ones are accepted.',
                  style: TextStyle(fontSize: 12.5, color: p.text, height: 1.4),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        FadeSlideIn(index: i++, child: _acceptedStrip(context, accepted, noRows)),
        for (final m in gatewayMethods) ...[
          SectionHeader(
            m.label,
            subtitle: m.hint,
            trailing: TextButton.icon(
              onPressed: () => _open(method: m.id),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ),
          ..._group(context, m, i),
        ],
      ],
    );
  }

  List<Widget> _group(BuildContext context, GatewayMethod m, int base) {
    final p = MarketPalette.of(context);
    final items = _rows.where((r) => r['method'] == m.id).toList()..sort((a, b) => toInt(a['sort_order']).compareTo(toInt(b['sort_order'])));
    if (items.isEmpty) {
      return [
        FadeSlideIn(
          index: base,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
            child: Row(children: [
              Icon(m.icon, size: 18, color: p.label),
              const SizedBox(width: 10),
              Expanded(child: Text('Nothing set up yet', style: TextStyle(fontSize: 12.5, color: p.label))),
            ]),
          ),
        ),
      ];
    }
    return [
      for (var j = 0; j < items.length; j++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FadeSlideIn(
            key: ValueKey('g${items[j]['id']}'),
            index: base + j,
            child: GatewayTile(
              row: items[j],
              busy: _toggling.contains(toInt(items[j]['id'])),
              onToggle: (v) => _toggle(items[j], v),
              onEdit: () => _open(row: items[j]),
              onDelete: () => _delete(items[j]),
            ),
          ),
        ),
    ];
  }

  Widget _acceptedStrip(BuildContext context, List<GatewayMethod> accepted, bool defaults) {
    final p = MarketPalette.of(context);
    final none = accepted.isEmpty;
    return MarketCard(
      padding: const EdgeInsets.all(12),
      borderColor: none ? p.warn.withValues(alpha: 0.5) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Accepted right now', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text))),
          if (defaults) const StatusPill('Default', tone: MarketTone.info),
        ]),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: none
              ? Row(
                  key: const ValueKey('none'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: p.warn),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Every method is off, so buyers can\'t check out from your store. Turn at least one on.',
                          style: TextStyle(fontSize: 12.5, color: p.warn, height: 1.4, fontWeight: FontWeight.w600)),
                    ),
                  ],
                )
              : Wrap(
                  key: ValueKey(accepted.map((m) => m.id).join()),
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final m in accepted) StatusPill(m.label, tone: MarketTone.ok, icon: m.icon)],
                ),
        ),
      ]),
    );
  }
}
