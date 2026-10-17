import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../data/store_product_model.dart';
import '../../data/store_product_service.dart';
import '../catalog/product_form_page.dart';
import '../widgets/store_ui.dart';

/// Every active, track_stock product where `stock_qty <= low_stock_at` —
/// client-side filtered, same reasoning as desktop's `StoreLowStock.tsx`
/// (a field-to-field comparison the generic OData `$filter` grammar can't
/// express). Tap a row to quick-edit via the shared `ProductFormPage`.
class LowStockPage extends StatefulWidget {
  const LowStockPage({super.key});

  @override
  State<LowStockPage> createState() => _LowStockPageState();
}

class _LowStockPageState extends State<LowStockPage> {
  final _service = StoreProductService(ApiClient());
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<StoreProduct> _rows = [];
  String _filter = 'ALL';

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
      final all = await _service.list(filter: 'is_active eq true and track_stock eq true');
      if (!mounted) return;
      setState(() => _rows = all.where((p) => p.isLowStock).toList()..sort((a, b) => a.stockQty.compareTo(b.stockQty)));
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load low stock items.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _quickEdit(StoreProduct product) async {
    final saved = await Navigator.of(context).push<bool>(marketRoute(ProductFormPage(existing: product)));
    if (saved == true) _load();
  }

  List<StoreProduct> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _rows.where((r) {
      if (_filter == 'OUT' && r.stockQty > 0) return false;
      if (_filter == 'LOW' && r.stockQty <= 0) return false;
      if (q.isEmpty) return true;
      return r.name.toLowerCase().contains(q) || (r.sku ?? '').toLowerCase().contains(q) || (r.barcode ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final visible = _visible;
    final outCount = _rows.where((r) => r.stockQty <= 0).length;
    return MarketScaffold(
      title: 'Low stock',
      subtitle: _loading && _rows.isEmpty ? 'Loading…' : 'At or below the reorder level',
      body: RefreshIndicator(
        onRefresh: _load,
        color: p.brand,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: KpiTile(icon: Icons.warning_amber_outlined, label: 'Running low', value: _rows.length - outCount, tone: MarketTone.warn)),
                  const SizedBox(width: 10),
                  Expanded(child: KpiTile(icon: Icons.remove_shopping_cart_outlined, label: 'Out of stock', value: outCount, tone: MarketTone.error)),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search name, SKU or barcode',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    fillColor: p.card,
                    suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
                  ),
                ),
                const SizedBox(height: 10),
                MarketSegmented<String>(
                  value: _filter,
                  onChanged: (v) => setState(() => _filter = v),
                  options: [
                    (id: 'ALL', label: 'All', count: _rows.length),
                    (id: 'LOW', label: 'Running low', count: _rows.length - outCount),
                    (id: 'OUT', label: 'Out of stock', count: outCount),
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

  List<Widget> _listSlivers(MarketPalette p, List<StoreProduct> visible) {
    if (_loading && _rows.isEmpty) {
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
            icon: _rows.isEmpty ? Icons.check_circle_outline : Icons.search_off_outlined,
            title: _rows.isEmpty ? 'Nothing is low on stock' : 'Nothing matches',
            message: _rows.isEmpty ? 'Products at or below their reorder level show up here.' : 'Try another search or filter.',
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

  Widget _row(MarketPalette p, StoreProduct product) {
    final (label, tone) = stockPill(trackStock: product.trackStock, qty: product.stockQty, lowAt: product.lowStockAt);
    final c = p.tone(tone);
    return MarketCard(
      padding: const EdgeInsets.all(12),
      onTap: () => _quickEdit(product),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10)),
          child: Icon(product.stockQty <= 0 ? Icons.remove_shopping_cart_outlined : Icons.inventory_2_outlined, size: 19, color: c.fg),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(height: 2),
            Text('SKU ${product.sku ?? '—'} · Reorder at ${product.lowStockAt.toStringAsFixed(0)}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
          ]),
        ),
        const SizedBox(width: 8),
        StatusPill(label, tone: tone),
        const SizedBox(width: 2),
        Icon(Icons.chevron_right, size: 18, color: p.label),
      ]),
    );
  }
}
