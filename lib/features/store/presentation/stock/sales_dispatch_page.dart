import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../data/store_util.dart' show toNum, toDouble;
import '../widgets/store_ui.dart' hide toDouble, toInt;

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

class _DispatchRow {
  final int id;
  final String productName;
  final double quantity;
  final double unitPrice;
  final String saleNo;
  final String createdAt;
  const _DispatchRow({required this.id, required this.productName, required this.quantity, required this.unitPrice, required this.saleNo, required this.createdAt});
}

/// Read-only — "where did this product get outed from stock via a sale".
/// Not backed by a `store_*` model: reads `sell.prisma`'s `sales_items`
/// directly with a relation-path filter (`sale/status eq 'COMPLETED'`),
/// mirroring desktop's `StoreSalesDispatch.tsx` — excludes parked carts
/// (never decremented) and refunded/restored sales.
class SalesDispatchPage extends StatefulWidget {
  const SalesDispatchPage({super.key});

  @override
  State<SalesDispatchPage> createState() => _SalesDispatchPageState();
}

class _SalesDispatchPageState extends State<SalesDispatchPage> {
  final _client = ApiClient();
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<_DispatchRow> _rows = [];

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
        "sales_items?\$filter=sale/status eq 'COMPLETED' and sale/is_pharma eq false&\$expand=product,sale&\$orderby=id desc&\$top=500",
      );
      final rows = unwrapList(res).cast<Map<String, dynamic>>().map((row) {
        final sale = row['sale'] as Map?;
        return _DispatchRow(
          id: toNum(row['id']),
          productName: ((row['product'] as Map?)?['name'] ?? '—').toString(),
          quantity: toDouble(row['quantity']),
          unitPrice: toDouble(row['unit_price']),
          saleNo: (sale?['sale_no'] ?? sale?['id'] ?? '—').toString(),
          createdAt: (sale?['created_at'] ?? '').toString(),
        );
      }).toList();
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load sales dispatch.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_DispatchRow> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((r) => r.productName.toLowerCase().contains(q) || r.saleNo.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final visible = _visible;
    final units = visible.fold<double>(0, (s, r) => s + r.quantity);
    final value = visible.fold<double>(0, (s, r) => s + r.quantity * r.unitPrice);
    return MarketScaffold(
      title: 'Sales dispatch',
      subtitle: _loading && _rows.isEmpty ? 'Loading…' : 'Stock out through completed sales',
      body: RefreshIndicator(
        onRefresh: _load,
        color: p.brand,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: KpiTile(icon: Icons.outbox_outlined, label: 'Units out', value: units, tone: MarketTone.error)),
                  const SizedBox(width: 10),
                  Expanded(child: KpiTile(icon: Icons.payments_outlined, label: 'Sale value', value: value, format: (v) => money(v), tone: MarketTone.ok)),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search product or sale number',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    fillColor: p.card,
                    suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
                  ),
                ),
              ]),
            ),
          ),
          ..._listSlivers(p, visible),
        ]),
      ),
    );
  }

  List<Widget> _listSlivers(MarketPalette p, List<_DispatchRow> visible) {
    if (_loading && _rows.isEmpty) {
      return const [SliverFillRemaining(hasScrollBody: false, child: SkeletonList(count: 7, itemHeight: 64))];
    }
    if (_error != null) {
      return [SliverFillRemaining(hasScrollBody: false, child: MarketEmpty(icon: Icons.cloud_off_outlined, title: _error!, actionLabel: 'Try again', onAction: _load))];
    }
    if (visible.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: MarketEmpty(
            icon: Icons.point_of_sale_outlined,
            title: _rows.isEmpty ? 'No completed sales yet' : 'Nothing matches',
            message: _rows.isEmpty ? 'Items sold through the POS show up here.' : 'Try another search.',
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

  Widget _row(MarketPalette p, _DispatchRow row) {
    return MarketCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.point_of_sale_outlined, size: 19, color: p.brand),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.productName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(height: 2),
            Text('Sale ${row.saleNo} · ${_date(row.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('-${row.quantity.toStringAsFixed(0)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.error)),
          const SizedBox(height: 2),
          Text('at ${money(row.unitPrice)}', style: TextStyle(fontSize: 11, color: p.label)),
        ]),
      ]),
    );
  }
}

String _date(String iso) {
  final d = iso.isEmpty ? null : DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '—';
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}
