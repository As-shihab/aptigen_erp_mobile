import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../data/stock_movement_model.dart';
import '../../data/stock_movement_service.dart';
import '../widgets/store_ui.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Read-only view over the full, unfiltered `store_stock_movements` ledger —
/// deliberately dumber than Stock Adjustment's page, matches desktop's
/// `StoreStockLedger.tsx` (no dialog, no create/edit/delete).
class StockLedgerPage extends StatefulWidget {
  const StockLedgerPage({super.key});

  @override
  State<StockLedgerPage> createState() => _StockLedgerPageState();
}

class _StockLedgerPageState extends State<StockLedgerPage> {
  final _service = StockMovementService(ApiClient());
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<StockMovementRow> _rows = [];
  String _type = 'ALL';

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
      final result = await _service.list();
      if (!mounted) return;
      setState(() => _rows = result);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the stock ledger.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _sign(String type) => switch (type) { 'OUT' => '-', 'ADJUST' => '±', _ => '+' };

  List<StockMovementRow> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _rows.where((r) {
      if (_type != 'ALL' && r.type != _type) return false;
      if (q.isEmpty) return true;
      return r.productName.toLowerCase().contains(q) ||
          r.locationPath.toLowerCase().contains(q) ||
          (r.batchNo ?? '').toLowerCase().contains(q) ||
          (r.remarks ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final visible = _visible;
    return MarketScaffold(
      title: 'Stock ledger',
      subtitle: _loading && _rows.isEmpty ? 'Loading…' : '${visible.length} of ${_rows.length} movements',
      body: RefreshIndicator(
        onRefresh: _load,
        color: p.brand,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search product, location or batch',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    fillColor: p.card,
                    suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
                  ),
                ),
                const SizedBox(height: 10),
                MarketSegmented<String>(
                  value: _type,
                  onChanged: (v) => setState(() => _type = v),
                  options: [
                    (id: 'ALL', label: 'All', count: _rows.length),
                    (id: 'IN', label: 'In', count: _rows.where((r) => r.type == 'IN').length),
                    (id: 'OUT', label: 'Out', count: _rows.where((r) => r.type == 'OUT').length),
                    (id: 'ADJUST', label: 'Adjust', count: _rows.where((r) => r.type == 'ADJUST').length),
                  ],
                ),
              ]),
            ),
          ),
          ..._listSlivers(p, visible),
        ]),
      ),
    );
  }

  List<Widget> _listSlivers(MarketPalette p, List<StockMovementRow> visible) {
    if (_loading && _rows.isEmpty) {
      return const [SliverFillRemaining(hasScrollBody: false, child: SkeletonList(count: 7, itemHeight: 66))];
    }
    if (_error != null) {
      return [SliverFillRemaining(hasScrollBody: false, child: MarketEmpty(icon: Icons.cloud_off_outlined, title: _error!, actionLabel: 'Try again', onAction: _load))];
    }
    if (visible.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: MarketEmpty(
            icon: Icons.history_outlined,
            title: _rows.isEmpty ? 'No movements yet' : 'Nothing matches',
            message: _rows.isEmpty ? 'Receipts, issues and adjustments show up here.' : 'Try another search or movement type.',
          ),
        ),
      ];
    }

    // Group rows under day headers (Today / Yesterday / date).
    final items = <Object>[];
    String? lastDay;
    for (final r in visible) {
      final d = _parse(r.createdAt);
      final label = d == null ? 'Undated' : _dayLabel(d);
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
              child: FadeSlideIn(index: i, child: _row(p, item as StockMovementRow)),
            );
          },
        ),
      ),
    ];
  }

  Widget _row(MarketPalette p, StockMovementRow row) {
    final tone = movementTone(row.type);
    final c = p.tone(tone);
    final d = _parse(row.createdAt);
    final meta = [
      row.locationPath,
      if (row.batchNo != null) 'Batch ${row.batchNo}',
      if (d != null) _time(d),
    ].join(' · ');
    return MarketCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10)),
          child: Icon(movementIcon(row.type), size: 19, color: c.fg),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.productName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(height: 2),
            Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
            if (row.remarks != null) ...[
              const SizedBox(height: 2),
              Text(row.remarks!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label, fontStyle: FontStyle.italic)),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${_sign(row.type)}${row.quantity.toStringAsFixed(0)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.fg)),
          const SizedBox(height: 4),
          StatusPill(movementLabel(row.type), tone: tone),
          if (row.balanceAfter != null) ...[
            const SizedBox(height: 3),
            Text('Balance ${row.balanceAfter!.toStringAsFixed(0)}', style: TextStyle(fontSize: 10.5, color: p.label)),
          ],
        ]),
      ]),
    );
  }
}

/// Stock movement type → sentence-case label / tone / icon. Shared with the
/// stock adjustment page.
String movementLabel(String type) => switch (type) { 'IN' => 'Received', 'OUT' => 'Issued', 'ADJUST' => 'Adjusted', _ => storeStatusLabel(type) };

MarketTone movementTone(String type) => switch (type) { 'IN' => MarketTone.ok, 'OUT' => MarketTone.error, _ => MarketTone.warn };

IconData movementIcon(String type) => switch (type) { 'IN' => Icons.south_west, 'OUT' => Icons.north_east, _ => Icons.tune };

DateTime? _parse(String iso) => iso.isEmpty ? null : DateTime.tryParse(iso)?.toLocal();

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  final diff = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

String _time(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
