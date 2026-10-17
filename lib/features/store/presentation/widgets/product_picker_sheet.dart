import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../data/store_product_model.dart';
import 'store_ui.dart';

/// The POS-friendly centerpiece reused by every line-item document (MRR, SR,
/// SPR, Returns, MRR Returns, Stock Adjustment): a full-height modal sheet
/// with an autofocused search box and a grid of big tappable product tiles
/// (thumbnail, name, price, stock pill) — no per-open network round trip,
/// the caller preloads the product list once and hands it in.
Future<StoreProduct?> showProductPickerSheet(BuildContext context, {required List<StoreProduct> products}) {
  return showMarketSheet<StoreProduct>(context, builder: (_) => _ProductPickerSheet(products: products));
}

class _ProductPickerSheet extends StatefulWidget {
  final List<StoreProduct> products;
  const _ProductPickerSheet({required this.products});

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<StoreProduct> get _visible {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.products;
    return widget.products
        .where((p) =>
            p.name.toLowerCase().contains(query) ||
            (p.sku ?? '').toLowerCase().contains(query) ||
            (p.barcode ?? '').toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        final products = _visible;
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Select a product', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
                      Text('${products.length} of ${widget.products.length}', style: TextStyle(fontSize: 12, color: p.label)),
                    ]),
                  ),
                  IconButton(icon: Icon(Icons.close, color: p.label), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search name, SKU or barcode',
                  isDense: true,
                  fillColor: p.surface,
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_searchController.clear)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: p.line),
            Expanded(
              child: Container(
                color: p.bg,
                child: products.isEmpty
                    ? ListView(
                        controller: scrollController,
                        children: const [
                          MarketEmpty(icon: Icons.search_off_outlined, title: 'No matching products', message: 'Try another name, SKU or barcode.'),
                        ],
                      )
                    : GridView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.74),
                        itemCount: products.length,
                        itemBuilder: (context, index) => FadeSlideIn(
                          index: index,
                          child: _ProductTile(product: products[index], onTap: () => Navigator.of(context).pop(products[index])),
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProductTile extends StatelessWidget {
  final StoreProduct product;
  final VoidCallback onTap;
  const _ProductTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final (label, tone) = stockPill(trackStock: product.trackStock, qty: product.stockQty, lowAt: product.lowStockAt);
    return MarketCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              child: SizedBox(
                width: double.infinity,
                child: product.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: product.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => _placeholder(p),
                        placeholder: (_, _) => Container(color: p.surface),
                      )
                    : _placeholder(p),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: p.text, height: 1.25)),
                const SizedBox(height: 4),
                Text(money(product.price), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.text)),
                const SizedBox(height: 6),
                StatusPill(label, tone: tone),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(MarketPalette p) => Container(color: p.surface, child: Icon(Icons.inventory_2_outlined, color: p.label, size: 32));
}
