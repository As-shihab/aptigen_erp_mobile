import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../data/store_util.dart';
import '../widgets/store_ui.dart' hide toDouble, toInt;

enum _PickOrder { fifo, lifo }

enum _Window { all, expired, soon, later }

class _ExpiryRow {
  final int id;
  final String productName;
  final String batchNo;
  final double quantity;
  final String? manufactureDate;
  final String expiryDate;
  final int pickOrder;
  final int daysToExpiry;
  const _ExpiryRow({
    required this.id,
    required this.productName,
    required this.batchNo,
    required this.quantity,
    this.manufactureDate,
    required this.expiryDate,
    required this.pickOrder,
    required this.daysToExpiry,
  });
}

/// Every ACTIVE, in-stock batch with an expiry_date, re-ranked client-side
/// into a per-product FIFO/LIFO pick order — same client-side-filter
/// reasoning as Low Stock, and the same grouping algorithm as desktop's
/// `StoreStockExpiry.tsx` `buildRows` (rank within each product, then
/// flatten sorted by product name).
class StockExpiryPage extends StatefulWidget {
  const StockExpiryPage({super.key});

  @override
  State<StockExpiryPage> createState() => _StockExpiryPageState();
}

class _StockExpiryPageState extends State<StockExpiryPage> {
  final _client = ApiClient();
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  _PickOrder _order = _PickOrder.fifo;
  _Window _window = _Window.all;
  List<Map<String, dynamic>> _raw = [];

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
      final res = await _client.get(
        "store_product_batches?\$select=id,product_id,batch_no,manufacture_date,expiry_date,quantity,status&\$filter=status eq 'ACTIVE' and quantity gt 0 and is_pharma eq false&\$expand=product&\$top=2000",
      );
      final rows = unwrapList(res).cast<Map<String, dynamic>>().where((b) => toStringOrNull(b['expiry_date']) != null).toList();
      if (!mounted) return;
      setState(() => _raw = rows);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load batches.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _daysUntil(String dateStr) {
    final target = DateTime.tryParse(dateStr);
    if (target == null) return 0;
    final now = DateTime.now();
    return daysBetween(DateTime(now.year, now.month, now.day), DateTime(target.year, target.month, target.day));
  }

  List<_ExpiryRow> get _rows {
    final byProduct = <int, List<Map<String, dynamic>>>{};
    for (final row in _raw) {
      final productId = toNum(row['product_id']);
      (byProduct[productId] ??= []).add(row);
    }
    final result = <_ExpiryRow>[];
    for (final batches in byProduct.values) {
      final sorted = [...batches];
      sorted.sort((a, b) {
        final aKey = (a['manufacture_date'] ?? a['expiry_date']).toString();
        final bKey = (b['manufacture_date'] ?? b['expiry_date']).toString();
        return _order == _PickOrder.fifo ? aKey.compareTo(bKey) : bKey.compareTo(aKey);
      });
      for (var i = 0; i < sorted.length; i++) {
        final b = sorted[i];
        result.add(_ExpiryRow(
          id: toNum(b['id']),
          productName: ((b['product'] as Map?)?['name'] ?? '—').toString(),
          batchNo: (b['batch_no'] ?? '').toString(),
          quantity: toDouble(b['quantity']),
          manufactureDate: toStringOrNull(b['manufacture_date']),
          expiryDate: (b['expiry_date'] ?? '').toString(),
          pickOrder: i + 1,
          daysToExpiry: _daysUntil((b['expiry_date'] ?? '').toString()),
        ));
      }
    }
    result.sort((a, b) {
      final nameCompare = a.productName.compareTo(b.productName);
      return nameCompare != 0 ? nameCompare : a.pickOrder.compareTo(b.pickOrder);
    });
    return result;
  }

  ({String label, MarketTone tone}) _tone(int days) {
    if (days < 0) return (label: 'Expired', tone: MarketTone.error);
    if (days <= 7) return (label: 'Critical', tone: MarketTone.error);
    if (days <= 30) return (label: 'Expiring soon', tone: MarketTone.warn);
    return (label: 'Fresh', tone: MarketTone.ok);
  }

  bool _inWindow(_ExpiryRow r, _Window w) => switch (w) {
        _Window.all => true,
        _Window.expired => r.daysToExpiry < 0,
        _Window.soon => r.daysToExpiry >= 0 && r.daysToExpiry <= 30,
        _Window.later => r.daysToExpiry > 30,
      };

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final rows = _rows;
    final expired = rows.where((r) => r.daysToExpiry < 0).length;
    final expiringSoon = rows.where((r) => r.daysToExpiry >= 0 && r.daysToExpiry <= 30).length;
    final later = rows.length - expired - expiringSoon;
    final q = _search.text.trim().toLowerCase();
    final visible = rows.where((r) => _inWindow(r, _window) && (q.isEmpty || r.productName.toLowerCase().contains(q) || r.batchNo.toLowerCase().contains(q))).toList();

    return MarketScaffold(
      title: 'Stock expiry',
      subtitle: _loading && _raw.isEmpty ? 'Loading…' : '${rows.length} batches tracked',
      body: RefreshIndicator(
        onRefresh: _load,
        color: p.brand,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: KpiTile(icon: Icons.dangerous_outlined, label: 'Expired', value: expired, tone: MarketTone.error)),
                  const SizedBox(width: 10),
                  Expanded(child: KpiTile(icon: Icons.event_busy_outlined, label: 'Within 30 days', value: expiringSoon, tone: MarketTone.warn)),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search product or batch',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    fillColor: p.card,
                    suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
                  ),
                ),
                const SizedBox(height: 10),
                MarketSegmented<_Window>(
                  value: _window,
                  onChanged: (v) => setState(() => _window = v),
                  options: [
                    (id: _Window.all, label: 'All', count: rows.length),
                    (id: _Window.expired, label: 'Expired', count: expired),
                    (id: _Window.soon, label: '≤ 30d', count: expiringSoon),
                    (id: _Window.later, label: 'Later', count: later),
                  ],
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Text('Pick order', style: TextStyle(fontSize: 12.5, color: p.label)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MarketSegmented<_PickOrder>(
                      value: _order,
                      onChanged: (v) => setState(() => _order = v),
                      options: const [
                        (id: _PickOrder.fifo, label: 'First in, first out', count: null),
                        (id: _PickOrder.lifo, label: 'Last in, first out', count: null),
                      ],
                    ),
                  ),
                ]),
              ]),
            ),
          ),
          ..._listSlivers(p, visible),
        ]),
      ),
    );
  }

  List<Widget> _listSlivers(MarketPalette p, List<_ExpiryRow> visible) {
    if (_loading && _raw.isEmpty) {
      return const [SliverFillRemaining(hasScrollBody: false, child: SkeletonList(count: 6, itemHeight: 66))];
    }
    if (_error != null) {
      return [SliverFillRemaining(hasScrollBody: false, child: MarketEmpty(icon: Icons.cloud_off_outlined, title: _error!, actionLabel: 'Try again', onAction: _load))];
    }
    if (visible.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: MarketEmpty(
            icon: Icons.event_available_outlined,
            title: _raw.isEmpty ? 'No batches with an expiry date' : 'Nothing matches',
            message: _raw.isEmpty ? 'In-stock batches with an expiry date show up here.' : 'Try another search or window.',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        sliver: SliverList.separated(
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) => FadeSlideIn(index: i, child: _row(p, visible[i])),
        ),
      ),
    ];
  }

  Widget _row(MarketPalette p, _ExpiryRow row) {
    final t = _tone(row.daysToExpiry);
    final c = p.tone(t.tone);
    final days = row.daysToExpiry;
    final dayText = days < 0
        ? '${days.abs()}d overdue'
        : days == 0
            ? 'Today'
            : '${days}d left';
    return MarketCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('#${row.pickOrder}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c.fg, height: 1.1)),
            Text('pick', style: TextStyle(fontSize: 9, color: c.fg)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.productName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(height: 2),
            Text('Batch ${row.batchNo.isEmpty ? '—' : row.batchNo} · Qty ${row.quantity.toStringAsFixed(0)}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
            Text('Expires ${displayDate(row.expiryDate)}', style: TextStyle(fontSize: 11.5, color: p.label)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(dayText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c.fg)),
          const SizedBox(height: 4),
          StatusPill(t.label, tone: t.tone),
        ]),
      ]),
    );
  }
}
