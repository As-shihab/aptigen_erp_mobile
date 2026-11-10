import 'package:flutter/material.dart';
import '../data/market_seller_service.dart';
import 'orders/order_common.dart';
import 'refunds/refund_common.dart';
import 'refunds/refund_detail_sheet.dart';
import 'widgets/market_ui.dart';

/// Refund requests buyers raised on this store's order items —
/// GET /api/market/seller-refunds (loaded once, filtered locally), resolved
/// from the detail sheet via PATCH /api/market/seller-refunds/:id.
class MarketRefundsPage extends StatefulWidget {
  const MarketRefundsPage({super.key});

  @override
  State<MarketRefundsPage> createState() => _MarketRefundsPageState();
}

class _MarketRefundsPageState extends State<MarketRefundsPage> {
  final _service = MarketSellerService();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _filter = 'requested';

  static const _filters = [
    ('requested', 'Requested'),
    ('approved', 'Approved'),
    ('refunded', 'Refunded'),
    ('rejected', 'Rejected'),
    ('all', 'All'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final rows = await _service.refunds();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (_rows.isEmpty) setState(() => _error = errorText(e, 'Could not load refunds'));
      marketToast(context, errorText(e, 'Could not load refunds'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, int> get _counts {
    final c = <String, int>{'all': _rows.length};
    for (final r in _rows) {
      final s = '${r['status']}';
      c[s] = (c[s] ?? 0) + 1;
    }
    return c;
  }

  Future<void> _open(Map<String, dynamic> r) async {
    final done = await showRefundDetailSheet(context, refund: r, service: _service);
    if (done == null || !mounted) return;
    marketToast(context, done);
    _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final counts = _counts;
    final visible = _filter == 'all' ? _rows : _rows.where((r) => r['status'] == _filter).toList();

    return MarketScaffold(
      title: 'Refunds',
      subtitle: _loading && _rows.isEmpty ? null : '${counts['requested'] ?? 0} awaiting a decision',
      actions: [
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : () => _load(), icon: const Icon(Icons.refresh)),
      ],
      body: Column(children: [
        Container(
          width: double.infinity,
          color: p.card,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: MarketSegmented<String>(
              value: _filter,
              options: [
                for (final f in _filters) (id: f.$1, label: f.$2, count: f.$1 == 'requested' ? (counts['requested'] ?? 0) : null),
              ],
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        ),
        Divider(height: 1, color: p.line),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(silent: true),
            child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: _body(visible)),
          ),
        ),
      ]),
    );
  }

  Widget _body(List<Map<String, dynamic>> visible) {
    if (_loading && _rows.isEmpty) return const SkeletonList(key: ValueKey('loading'), itemHeight: 112);
    if (_error != null && _rows.isEmpty) {
      return ListView(key: const ValueKey('error'), children: [
        MarketEmpty(icon: Icons.cloud_off_outlined, title: 'Could not load refunds', message: _error, actionLabel: 'Try again', onAction: _load),
      ]);
    }
    if (visible.isEmpty) {
      return ListView(key: ValueKey('empty-$_filter'), children: [
        MarketEmpty(
          icon: Icons.assignment_return_outlined,
          title: _filter == 'requested' ? 'No open refund requests' : 'No refunds here',
          message: 'Refund requests buyers raise on your orders show up here.',
        ),
      ]);
    }
    return ListView.separated(
      key: ValueKey('list-$_filter'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => FadeSlideIn(
        key: ValueKey('r-${visible[i]['id']}'),
        index: i,
        child: _RefundCard(refund: visible[i], onTap: () => _open(visible[i])),
      ),
    );
  }
}

class _RefundCard extends StatelessWidget {
  final Map<String, dynamic> refund;
  final VoidCallback onTap;
  const _RefundCard({required this.refund, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final status = '${refund['status']}';
    final item = asMap(refund['order_item']);
    final order = asMap(refund['order']);
    final reason = str(refund['reason']);
    final qty = toInt(refund['quantity']);

    return MarketCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(str(item['title']) ?? 'Item',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
          ),
          const SizedBox(width: 8),
          StatusPill(refundStatusLabel[status] ?? status, tone: refundStatusTone(status)),
        ]),
        if (str(item['variant_label']) != null) ...[
          const SizedBox(height: 2),
          Text(str(item['variant_label'])!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
        ],
        const SizedBox(height: 4),
        Text('Order ${str(order['order_no']) ?? '#${refund['order_id']}'} · ${fmtDate(refund['created_at'])}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.person_outline, size: 16, color: p.label),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${refundBuyerName(refund)} · qty $qty',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.text)),
          ),
          const SizedBox(width: 8),
          Text(money(toDouble(refund['amount'])), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text)),
        ]),
        if (reason != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8)),
            child: Text(reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.label, height: 1.35)),
          ),
        ],
      ]),
    );
  }
}
