import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../store/data/store_util.dart' show toNum, toIntOrNull, toStringOrNull;
import 'widgets/sell_ui.dart';

class _PaymentRow {
  final int id;
  final int? saleId;
  final String clientName;
  final String method;
  final double amount;
  final String? reference;
  final String createdAt;
  const _PaymentRow({required this.id, this.saleId, required this.clientName, required this.method, required this.amount, this.reference, required this.createdAt});

  String get saleNo => saleId != null ? 'SO-${saleId.toString().padLeft(6, '0')}' : '—';
}

const _methodLabels = {'CASH': 'Cash', 'CARD': 'Card', 'MOBILE_BANKING': 'Mobile banking'};

/// Sentence-case label for a payment method code (unknown codes too).
String _methodLabel(String m) =>
    _methodLabels[m] ?? (m.isEmpty ? '—' : m[0] + m.substring(1).toLowerCase().replaceAll('_', ' '));

IconData _methodIcon(String method) => switch (method) {
      'CASH' => Icons.payments_outlined,
      'CARD' => Icons.credit_card,
      'MOBILE_BANKING' => Icons.phone_iphone,
      _ => Icons.account_balance_wallet_outlined,
    };

MarketTone _methodTone(String method) => switch (method) {
      'CASH' => MarketTone.ok,
      'CARD' => MarketTone.info,
      'MOBILE_BANKING' => MarketTone.brand,
      _ => MarketTone.neutral,
    };

/// Read-only, flattened `order_payments` across every sale — mirrors
/// desktop's PaymentList.tsx.
class PaymentsListPage extends StatefulWidget {
  const PaymentsListPage({super.key});

  @override
  State<PaymentsListPage> createState() => _PaymentsListPageState();
}

class _PaymentsListPageState extends State<PaymentsListPage> {
  final _client = ApiClient();
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<_PaymentRow> _rows = [];
  String _method = 'ALL';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _client.get(r'order_payments?$expand=sale($expand=client)&$filter=sale/is_pharma eq false&$orderby=id desc&$top=1000');
      final rows = unwrapList(res).cast<Map<String, dynamic>>().map((row) {
        final sale = row['sale'] as Map?;
        final client = sale?['client'] as Map?;
        return _PaymentRow(
          id: toNum(row['id']),
          saleId: toIntOrNull(sale?['id']),
          clientName: (client?['name'] ?? 'Walk-in').toString(),
          method: (row['method'] ?? '').toString(),
          amount: toDouble(row['amount']),
          reference: toStringOrNull(row['reference']),
          createdAt: (row['created_at'] ?? '').toString(),
        );
      }).toList();
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load payments.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_PaymentRow> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _rows.where((r) {
      if (_method != 'ALL' && r.method != _method) return false;
      if (q.isEmpty) return true;
      return r.saleNo.toLowerCase().contains(q) || r.clientName.toLowerCase().contains(q) || (r.reference ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final visible = _visible;
    final total = visible.fold<double>(0, (s, r) => s + r.amount);
    // Methods actually present, in a stable order, so the filter never shows empty tabs.
    final methods = [
      ..._methodLabels.keys.where((m) => _rows.any((r) => r.method == m)),
      ..._rows.map((r) => r.method).where((m) => !_methodLabels.containsKey(m)).toSet(),
    ];

    return MarketScaffold(
      title: 'Payments',
      subtitle: _loading && _rows.isEmpty ? 'Loading…' : '${visible.length} of ${_rows.length}',
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: KpiTile(icon: Icons.payments_outlined, label: 'Collected', value: total, format: (v) => money(v), tone: MarketTone.ok)),
                  const SizedBox(width: 10),
                  Expanded(child: KpiTile(icon: Icons.receipt_long_outlined, label: 'Payments', value: visible.length, tone: MarketTone.info)),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search sale number, client or reference',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    fillColor: p.card,
                    suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
                  ),
                ),
                if (methods.length > 1) ...[
                  const SizedBox(height: 10),
                  MarketSegmented<String>(
                    value: _method,
                    onChanged: (v) => setState(() => _method = v),
                    options: [
                      (id: 'ALL', label: 'All', count: _rows.length),
                      for (final m in methods) (id: m, label: _methodLabel(m), count: _rows.where((r) => r.method == m).length),
                    ],
                  ),
                ],
              ]),
            ),
          ),
          ..._listSlivers(p, visible),
        ]),
      ),
    );
  }

  List<Widget> _listSlivers(MarketPalette p, List<_PaymentRow> visible) {
    if (_loading && _rows.isEmpty) {
      return const [SliverFillRemaining(hasScrollBody: false, child: SkeletonList(count: 6, itemHeight: 64))];
    }
    if (_error != null) {
      return [SliverFillRemaining(hasScrollBody: false, child: MarketEmpty(icon: Icons.cloud_off_outlined, title: _error!, actionLabel: 'Try again', onAction: _load))];
    }
    if (visible.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: MarketEmpty(
            icon: Icons.payments_outlined,
            title: _rows.isEmpty ? 'No payments recorded yet' : 'Nothing matches',
            message: _rows.isEmpty ? 'Payments taken in the POS show up here.' : 'Try another search or method.',
          ),
        ),
      ];
    }

    // Group rows under day headers (Today / Yesterday / date).
    final items = <Object>[];
    String? lastDay;
    for (final r in visible) {
      final d = parseLocal(r.createdAt);
      final label = d == null ? 'Undated' : dayLabel(d);
      if (label != lastDay) {
        items.add(label);
        lastDay = label;
      }
      items.add(r);
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        sliver: SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            if (item is String) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
                child: Text(item, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.label)),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FadeSlideIn(index: i, child: _row(p, item as _PaymentRow)),
            );
          },
        ),
      ),
    ];
  }

  Widget _row(MarketPalette p, _PaymentRow r) {
    final c = p.tone(_methodTone(r.method));
    final when = parseLocal(r.createdAt);
    return MarketCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10)),
          child: Icon(_methodIcon(r.method), size: 20, color: c.fg),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.clientName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(height: 2),
            Text(
              [r.saleNo, if ((r.reference ?? '').isNotEmpty) r.reference!, if (when != null) timeLabel(when)].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: p.label),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(money(r.amount), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
          const SizedBox(height: 4),
          StatusPill(_methodLabel(r.method), tone: _methodTone(r.method)),
        ]),
      ]),
    );
  }
}
