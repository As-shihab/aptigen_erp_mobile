import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../store/data/store_product_model.dart';
import '../../store/data/store_product_service.dart';
import 'widgets/sell_ui.dart';

enum _StockFilter { all, inStock, low, out }

/// Sellable catalogue — view-only, same as desktop's sell/products
/// ProductList.tsx (products are created and edited in the Store module).
class SellProductsPage extends StatefulWidget {
  const SellProductsPage({super.key});

  @override
  State<SellProductsPage> createState() => _SellProductsPageState();
}

class _SellProductsPageState extends State<SellProductsPage> {
  final _service = StoreProductService(ApiClient());
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<StoreProduct> _rows = [];
  _StockFilter _filter = _StockFilter.all;

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
      final rows = await _service.list(filter: 'is_pharma eq false');
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load products.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isOut(StoreProduct p) => p.trackStock && p.stockQty <= 0;
  bool _isLow(StoreProduct p) => p.trackStock && p.stockQty > 0 && p.stockQty <= p.lowStockAt;

  List<StoreProduct> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _rows.where((p) {
      if (!p.isActive) return false;
      final matchesStock = switch (_filter) {
        _StockFilter.all => true,
        _StockFilter.inStock => !_isOut(p) && !_isLow(p),
        _StockFilter.low => _isLow(p),
        _StockFilter.out => _isOut(p),
      };
      if (!matchesStock) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) || (p.sku ?? '').toLowerCase().contains(q) || (p.barcode ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final active = _rows.where((r) => r.isActive).toList();
    final visible = _visible;
    return MarketScaffold(
      title: 'Products',
      subtitle: '${active.length} sellable · managed in Store',
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search name, SKU or barcode',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    fillColor: p.card,
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
                  ),
                ),
                const SizedBox(height: 10),
                MarketSegmented<_StockFilter>(
                  value: _filter,
                  onChanged: (v) => setState(() => _filter = v),
                  options: [
                    (id: _StockFilter.all, label: 'All', count: active.length),
                    (id: _StockFilter.inStock, label: 'In stock', count: null),
                    (id: _StockFilter.low, label: 'Low', count: active.where(_isLow).length),
                    (id: _StockFilter.out, label: 'Out', count: active.where(_isOut).length),
                  ],
                ),
              ]),
            ),
          ),
          if (_loading && _rows.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: SkeletonList(count: 6, itemHeight: 72))
          else if (_error != null)
            SliverFillRemaining(hasScrollBody: false, child: MarketEmpty(icon: Icons.cloud_off_outlined, title: _error!, actionLabel: 'Try again', onAction: _load))
          else if (visible.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: MarketEmpty(icon: Icons.inventory_2_outlined, title: 'No products', message: 'Nothing matches this search or filter.'),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList.separated(
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => FadeSlideIn(index: i, child: _productRow(p, visible[i])),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _productRow(MarketPalette p, StoreProduct prod) {
    final (label, tone) = !prod.trackStock
        ? ('Not tracked', MarketTone.neutral)
        : _isOut(prod)
            ? ('Out of stock', MarketTone.error)
            : _isLow(prod)
                ? ('Low · ${_qty(prod.stockQty)}', MarketTone.warn)
                : ('${_qty(prod.stockQty)} in stock', MarketTone.ok);
    return MarketCard(
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 52,
            height: 52,
            color: p.surface,
            child: prod.thumbnailUrl == null
                ? Icon(Icons.inventory_2_outlined, color: p.label)
                : CachedNetworkImage(
                    imageUrl: prod.thumbnailUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => Icon(Icons.image_not_supported_outlined, color: p.label),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(prod.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(height: 3),
            Text(prod.sku == null || prod.sku!.isEmpty ? 'No SKU' : 'SKU ${prod.sku}', style: TextStyle(fontSize: 11.5, color: p.label)),
            const SizedBox(height: 5),
            StatusPill(label, tone: tone),
          ]),
        ),
        const SizedBox(width: 8),
        Text(money(prod.price), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
      ]),
    );
  }

  String _qty(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
