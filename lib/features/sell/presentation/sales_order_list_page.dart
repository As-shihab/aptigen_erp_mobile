import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../data/sales_order_model.dart';
import '../data/sales_order_service.dart';
import 'sales_order_detail_page.dart';
import 'widgets/sell_ui.dart';

/// One list over `sales_orders`, reused for Sales orders (all statuses, with
/// a status filter), Invoices (`COMPLETED`) and Returns (`REFUNDED`) —
/// mirrors desktop's SalesOrderList/InvoiceList/ReturnList.tsx, which are
/// thin wrappers around the same query. Read-only: sales are only created
/// through the POS; void / print live on the detail page.
class SalesOrderListPage extends StatefulWidget {
  final String? statusFilter;
  final String title;
  final bool isPharma;
  const SalesOrderListPage({super.key, this.statusFilter, required this.title, this.isPharma = false});

  @override
  State<SalesOrderListPage> createState() => _SalesOrderListPageState();
}

class _SalesOrderListPageState extends State<SalesOrderListPage> {
  late final _service = SalesOrderService(ApiClient());
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<SalesOrder> _rows = [];
  // Only used when the page isn't pinned to one status by [statusFilter].
  String _status = 'ALL';

  static const _statuses = ['ALL', 'COMPLETED', 'PARKED', 'REFUNDED', 'CANCELLED'];

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
      final result = await _service.list(statusFilter: widget.statusFilter, isPharma: widget.isPharma);
      if (!mounted) return;
      setState(() => _rows = result);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load sales.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<SalesOrder> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _rows.where((o) {
      if (widget.statusFilter == null && _status != 'ALL' && o.status != _status) return false;
      if (q.isEmpty) return true;
      return o.displayNo.toLowerCase().contains(q) ||
          o.invoiceNo.toLowerCase().contains(q) ||
          (o.clientName ?? 'walk-in').toLowerCase().contains(q) ||
          (o.clientPhone ?? '').contains(q);
    }).toList();
  }

  bool get _isReturns => widget.statusFilter == 'REFUNDED';

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final visible = _visible;
    final total = visible.fold<double>(0, (s, o) => s + o.total);
    final due = visible.fold<double>(0, (s, o) => s + (o.status == 'COMPLETED' ? o.due : 0));

    return MarketScaffold(
      title: widget.title,
      subtitle: _loading && _rows.isEmpty ? 'Loading…' : '${visible.length} of ${_rows.length}',
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: KpiTile(
                      icon: _isReturns ? Icons.assignment_return_outlined : Icons.payments_outlined,
                      label: _isReturns ? 'Refunded' : 'Total',
                      value: total,
                      format: (v) => money(v),
                      tone: _isReturns ? MarketTone.error : MarketTone.ok,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _isReturns
                        ? KpiTile(icon: Icons.receipt_long_outlined, label: 'Returns', value: visible.length, tone: MarketTone.neutral)
                        : KpiTile(icon: Icons.account_balance_wallet_outlined, label: 'Due', value: due, format: (v) => money(v), tone: MarketTone.warn),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search number, client or phone',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    fillColor: p.card,
                    suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
                  ),
                ),
                if (widget.statusFilter == null) ...[
                  const SizedBox(height: 10),
                  MarketSegmented<String>(
                    value: _status,
                    onChanged: (v) => setState(() => _status = v),
                    options: [
                      for (final s in _statuses)
                        (
                          id: s,
                          label: s == 'ALL' ? 'All' : saleStatusLabel(s),
                          count: s == 'ALL' ? _rows.length : _rows.where((o) => o.status == s).length,
                        ),
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

  List<Widget> _listSlivers(MarketPalette p, List<SalesOrder> visible) {
    if (_loading && _rows.isEmpty) {
      return const [SliverFillRemaining(hasScrollBody: false, child: SkeletonList(count: 6, itemHeight: 70))];
    }
    if (_error != null) {
      return [SliverFillRemaining(hasScrollBody: false, child: MarketEmpty(icon: Icons.cloud_off_outlined, title: _error!, actionLabel: 'Try again', onAction: _load))];
    }
    if (visible.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: MarketEmpty(
            icon: _isReturns ? Icons.assignment_return_outlined : Icons.receipt_long_outlined,
            title: _rows.isEmpty ? (_isReturns ? 'No returns' : 'No sales yet') : 'Nothing matches',
            message: _rows.isEmpty ? 'Sales made in the POS show up here.' : 'Try another search or status.',
          ),
        ),
      ];
    }

    // Group rows under day headers (Today / Yesterday / date).
    final items = <Object>[];
    String? lastDay;
    for (final o in visible) {
      final d = parseLocal(o.completedAt ?? o.createdAt);
      final label = d == null ? 'Undated' : dayLabel(d);
      if (label != lastDay) {
        items.add(label);
        lastDay = label;
      }
      items.add(o);
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
              child: FadeSlideIn(index: i, child: _row(p, item as SalesOrder)),
            );
          },
        ),
      ),
    ];
  }

  Widget _row(MarketPalette p, SalesOrder o) {
    final when = parseLocal(o.completedAt ?? o.createdAt);
    final tone = saleStatusTone(o.status);
    return MarketCard(
      padding: const EdgeInsets.all(12),
      onTap: () async {
        await Navigator.of(context).push(marketRoute(SalesOrderDetailPage(saleId: o.id)));
        if (mounted) _load();
      },
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: p.tone(tone).bg, borderRadius: BorderRadius.circular(10)),
          child: Icon(o.clientName == null ? Icons.person_outline : Icons.person, size: 20, color: p.tone(tone).fg),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(o.clientName ?? 'Walk-in', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(height: 2),
            Text('${o.displayNo}${when == null ? '' : ' · ${timeLabel(when)}'}', style: TextStyle(fontSize: 11.5, color: p.label)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(money(o.total), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (o.status == 'COMPLETED' && o.due > 0) ...[
              StatusPill('Due ${money(o.due)}', tone: MarketTone.warn),
              const SizedBox(width: 4),
            ],
            StatusPill(saleStatusLabel(o.status), tone: tone),
          ]),
        ]),
      ]),
    );
  }
}
