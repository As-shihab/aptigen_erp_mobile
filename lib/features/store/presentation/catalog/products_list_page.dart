import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../data/store_lookup_service.dart';
import '../../data/store_product_model.dart';
import '../../data/store_product_service.dart';
import '../widgets/store_ui.dart';
import 'product_form_page.dart';

enum _ProductFilter { all, inStock, low, out, inactive }

/// Products list — search, stock segmented filter, category chips and SAP
/// Horizon product rows (thumbnail, stock pill, price). FAB creates, tap
/// edits, trailing action deletes.
class ProductsListPage extends StatefulWidget {
  final String? title;
  final String? filter;
  const ProductsListPage({super.key, this.title, this.filter});

  @override
  State<ProductsListPage> createState() => _ProductsListPageState();
}

class _ProductsListPageState extends State<ProductsListPage> {
  final _service = StoreProductService(ApiClient());
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<StoreProduct> _products = [];
  List<Map<String, dynamic>> _categories = [];
  int? _categoryFilter;
  _ProductFilter _filter = _ProductFilter.all;
  final Set<int> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.list(filter: widget.filter),
        StoreLookupService(ApiClient()).loadAll(),
      ]);
      if (!mounted) return;
      setState(() {
        _products = results[0] as List<StoreProduct>;
        _categories = (results[1] as Map<String, List<Map<String, dynamic>>>)['categories'] ?? [];
      });
    } catch (_) {
      // leave whatever's already loaded on failure
      if (mounted && _products.isEmpty) setState(() => _error = 'Could not load products.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isOut(StoreProduct p) => p.trackStock && p.stockQty <= 0;
  bool _isLow(StoreProduct p) => p.trackStock && p.stockQty > 0 && p.stockQty <= p.lowStockAt;

  bool _matchesFilter(StoreProduct p, _ProductFilter f) => switch (f) {
        _ProductFilter.all => true,
        _ProductFilter.inStock => p.isActive && !_isOut(p) && !_isLow(p),
        _ProductFilter.low => p.isActive && _isLow(p),
        _ProductFilter.out => p.isActive && _isOut(p),
        _ProductFilter.inactive => !p.isActive,
      };

  List<StoreProduct> get _visible {
    var list = _products.where((p) => _matchesFilter(p, _filter)).toList();
    if (_categoryFilter != null) list = list.where((p) => p.categoryId == _categoryFilter).toList();
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((p) => p.name.toLowerCase().contains(query) || (p.sku ?? '').toLowerCase().contains(query) || (p.barcode ?? '').toLowerCase().contains(query)).toList();
    }
    return list;
  }

  Future<void> _createOrEdit({StoreProduct? existing}) async {
    final saved = await Navigator.of(context).push<bool>(marketRoute<bool>(ProductFormPage(existing: existing)));
    if (saved == true) _load();
  }

  Future<void> _delete(StoreProduct product) async {
    final confirmed = await confirmMarket(context, title: 'Delete product', message: 'Delete "${product.name}"? This can\'t be undone.');
    if (!confirmed) return;
    setState(() => _busyIds.add(product.id));
    try {
      await _service.delete(product.id);
      if (!mounted) return;
      setState(() => _products.removeWhere((p) => p.id == product.id));
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Could not delete this product.', error: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(product.id));
    }
  }

  int _count(_ProductFilter f) => _products.where((p) => _matchesFilter(p, f)).length;

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final visible = _visible;
    return MarketScaffold(
      title: widget.title ?? 'Products',
      subtitle: _loading && _products.isEmpty ? 'Loading…' : '${visible.length} of ${_products.length}',
      fab: FloatingActionButton.extended(onPressed: () => _createOrEdit(), icon: const Icon(Icons.add), label: const Text('New product')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search name, SKU or barcode',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      fillColor: p.card,
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_searchController.clear)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  MarketSegmented<_ProductFilter>(
                    value: _filter,
                    onChanged: (v) => setState(() => _filter = v),
                    options: [
                      (id: _ProductFilter.all, label: 'All', count: _products.length),
                      (id: _ProductFilter.inStock, label: 'In stock', count: null),
                      (id: _ProductFilter.low, label: 'Low', count: _count(_ProductFilter.low)),
                      (id: _ProductFilter.out, label: 'Out', count: _count(_ProductFilter.out)),
                      (id: _ProductFilter.inactive, label: 'Inactive', count: _count(_ProductFilter.inactive)),
                    ],
                  ),
                  if (_categories.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _categoryChip(p, null, 'All categories'),
                          ..._categories.map((c) => _categoryChip(p, (c['id'] as num).toInt(), (c['name'] ?? '').toString())),
                        ],
                      ),
                    ),
                  ],
                ]),
              ),
            ),
            ..._listSlivers(p, visible),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip(MarketPalette p, int? id, String label) {
    final selected = _categoryFilter == id;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _categoryFilter = selected ? null : id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? p.brandSoft : p.card,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: selected ? p.brand : p.line),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? p.brand : p.text)),
        ),
      ),
    );
  }

  List<Widget> _listSlivers(MarketPalette p, List<StoreProduct> visible) {
    if (_loading && _products.isEmpty) {
      return const [SliverFillRemaining(hasScrollBody: false, child: SkeletonList(count: 6, itemHeight: 72))];
    }
    if (_error != null && _products.isEmpty) {
      return [SliverFillRemaining(hasScrollBody: false, child: MarketEmpty(icon: Icons.cloud_off_outlined, title: _error!, actionLabel: 'Try again', onAction: _load))];
    }
    if (visible.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _products.isEmpty
              ? MarketEmpty(
                  icon: Icons.inventory_2_outlined,
                  title: 'No products yet',
                  message: 'Add your first product to start tracking stock and prices.',
                  actionLabel: 'New product',
                  onAction: () => _createOrEdit(),
                )
              : const MarketEmpty(icon: Icons.search_off_outlined, title: 'Nothing matches', message: 'Try another search, filter or category.'),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        sliver: SliverList.separated(
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => FadeSlideIn(index: i, child: _productRow(p, visible[i])),
        ),
      ),
    ];
  }

  Widget _productRow(MarketPalette p, StoreProduct prod) {
    final busy = _busyIds.contains(prod.id);
    final (label, tone) = stockPill(trackStock: prod.trackStock, qty: prod.stockQty, lowAt: prod.lowStockAt);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: busy ? 0.5 : 1,
      child: MarketCard(
        padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
        onTap: busy ? null : () => _createOrEdit(existing: prod),
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
                      placeholder: (_, _) => Container(color: p.surface),
                      errorWidget: (_, _, _) => Icon(Icons.image_not_supported_outlined, color: p.label),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(prod.name,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                ),
                if (prod.isFeatured) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.star_rounded, size: 16, color: p.warn),
                ],
              ]),
              const SizedBox(height: 3),
              Text(prod.sku == null || prod.sku!.isEmpty ? 'No SKU' : 'SKU ${prod.sku}', style: TextStyle(fontSize: 11.5, color: p.label)),
              const SizedBox(height: 5),
              Wrap(spacing: 4, runSpacing: 4, children: [
                StatusPill(label, tone: tone),
                if (!prod.isActive) const StatusPill('Inactive', tone: MarketTone.neutral),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(money(prod.price), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline, size: 20, color: p.error),
              onPressed: busy ? null : () => _delete(prod),
            ),
          ]),
        ]),
      ),
    );
  }
}
