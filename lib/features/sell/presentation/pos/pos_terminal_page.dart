import '../../market/presentation/market_hub_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/utils/currency.dart';
import '../../../store/data/store_lookup_service.dart';
import '../../../store/data/store_product_model.dart';
import '../../../store/data/store_product_service.dart';
import '../../../store/data/store_util.dart';
import '../../../store/presentation/catalog/products_list_page.dart';
import '../../../store/presentation/widgets/field_spec.dart';
import '../../data/cart_models.dart';
import '../../data/client_model.dart';
import '../../data/client_service.dart';
import '../../data/order_settings_service.dart';
import '../../data/pos_local_prefs.dart';
import '../clients_list_page.dart';
import '../configs/sell_entity_configs.dart';
import '../held_bills_list_page.dart';
import '../payments_list_page.dart';
import '../sales_order_list_page.dart';
import '../sales_report_page.dart';
import '../sell_analytics_page.dart';
import '../sell_products_page.dart';
import '../sell_settings_page.dart';
import '../widgets/sell_ui.dart' show MarketPalette, MarketCard, MarketTone, StatusPill, MarketEmpty, SkeletonBox, showMarketSheet, marketToast;
import 'cart_page.dart';
import 'pos_receipt_page.dart';
import 'widgets/held_bills_sheet.dart';
import 'widgets/pos_settings_sheet.dart';

/// Sales' default landing (mirrors desktop's `index.tsx` redirecting
/// straight to `/sell/pos`, not an orders list) — pushed directly for the
/// 'sell' module tile. Everything else in the module (Sales Orders,
/// Invoices, Payments, Returns, Held Bills, Reports, Clients, Client
/// Groups, Analytics, Settings) lives behind the app bar's menu icon,
/// same set as desktop's `sell.layout.tsx` nav, just tucked behind a menu
/// instead of a permanent sidebar so POS keeps the whole screen.
class PosTerminalPage extends StatefulWidget {
  /// POS-first pharma mode: pharma-flagged products/checkout/held bills,
  /// "Pharma POS" branding, and a menu trimmed down to Inventory + Sales
  /// only. Full desktop parity (purchases/suppliers/customers/expenses/
  /// reports/catalog as separate screens) is out of scope for this pass.
  final bool isPharma;
  const PosTerminalPage({super.key, this.isPharma = false});

  @override
  State<PosTerminalPage> createState() => _PosTerminalPageState();
}

class _PosTerminalPageState extends State<PosTerminalPage> {
  final _client = ApiClient();
  late final _productService = StoreProductService(_client);
  late final _clientService = ClientService(_client);
  late final _orderSettingsService = OrderSettingsService(_client);

  bool _loading = true;
  List<StoreProduct> _products = [];
  List<StorePackaging> _packagings = [];
  List<Client> _clients = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _warehouses = [];
  OrderSettings _orderSettings = const OrderSettings();

  final List<CartTab> _carts = [CartTab(label: 'Sale 1')];
  int _activeIndex = 0;
  int _nextCartNumber = 2;

  final _searchController = TextEditingController();
  int? _categoryFilter;

  CartTab get _activeCart => _carts[_activeIndex];

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
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _productService.list(filter: 'is_active eq true and is_salable eq true and is_pharma eq ${widget.isPharma}'),
        _productService.listPackagings(isPharma: widget.isPharma),
        _clientService.list(isPharma: widget.isPharma),
        StoreLookupService(_client).loadAll(),
        _orderSettingsService.load(),
      ]);
      if (!mounted) return;
      final lookups = results[3] as Map<String, List<Map<String, dynamic>>>;
      final orderSettings = results[4] as OrderSettings;
      setState(() {
        _products = results[0] as List<StoreProduct>;
        _packagings = results[1] as List<StorePackaging>;
        _clients = results[2] as List<Client>;
        _categories = lookups['categories'] ?? [];
        _warehouses = lookups['warehouses'] ?? [];
        _orderSettings = orderSettings;
        for (final cart in _carts) {
          if (cart.taxRate == 0) cart.taxRate = orderSettings.defaultTaxRate;
        }
      });
    } catch (_) {
      if (mounted) marketToast(context, 'Could not load POS reference data.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<StoreProduct> get _visibleProducts {
    var list = _products;
    if (_categoryFilter != null) list = list.where((p) => p.categoryId == _categoryFilter).toList();
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((p) => p.name.toLowerCase().contains(query) || (p.sku ?? '').toLowerCase().contains(query)).toList();
    }
    return list;
  }

  void _addToCart(StoreProduct product) {
    final cart = _activeCart;
    final existing = cart.lines.where((l) => l.productId == product.id).toList();
    final maxStock = (product.trackStock) ? product.stockQty : null;
    if (existing.isNotEmpty) {
      final line = existing.first;
      if (maxStock != null && line.quantity + 1 > maxStock) {
        marketToast(context, 'Only ${maxStock.toStringAsFixed(0)} in stock.', error: true);
        return;
      }
      setState(() => line.quantity += 1);
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.selectionClick();
    } else {
      if (maxStock != null && maxStock < 1) {
        marketToast(context, 'Out of stock.', error: true);
        return;
      }
      setState(() => cart.lines.add(CartLine(productId: product.id, name: product.name, unitPrice: product.price, quantity: 1, maxStock: maxStock)));
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.selectionClick();
    }
  }

  Future<void> _scanBarcode() async {
    final controller = MobileScannerController();
    var handled = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.7,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: controller,
              onDetect: (capture) {
                if (handled) return;
                final barcodes = capture.barcodes;
                if (barcodes.isEmpty) return;
                final code = barcodes.first.rawValue;
                if (code == null || code.isEmpty) return;
                handled = true;
                Navigator.of(sheetContext).pop();
                _resolveScannedCode(code);
              },
            ),
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 240,
                  height: 160,
                  decoration: BoxDecoration(border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2), borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 28,
              child: IgnorePointer(
                child: Text('Point the camera at a barcode', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13, fontWeight: FontWeight.w500)),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.45)),
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Close scanner',
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  void _resolveScannedCode(String code) {
    final packagingMatches = _packagings.where((p) => p.barcode == code).toList();
    if (packagingMatches.isNotEmpty) {
      final productMatches = _products.where((p) => p.id == packagingMatches.first.productId).toList();
      if (productMatches.isNotEmpty) {
        _addProductWithQuantity(productMatches.first, packagingMatches.first.unitQty);
        return;
      }
    }
    final productMatches = _products.where((p) => p.barcode == code).toList();
    if (productMatches.isNotEmpty) {
      _addToCart(productMatches.first);
      return;
    }
    marketToast(context, 'No product matches barcode "$code".', error: true);
  }

  void _addProductWithQuantity(StoreProduct product, double qty) {
    final cart = _activeCart;
    final existing = cart.lines.where((l) => l.productId == product.id).toList();
    if (existing.isNotEmpty) {
      setState(() => existing.first.quantity += qty.round());
    } else {
      setState(() => cart.lines.add(CartLine(productId: product.id, name: product.name, unitPrice: product.price, quantity: qty.round(), maxStock: product.trackStock ? product.stockQty : null)));
    }
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.selectionClick();
  }

  void _newCart() {
    setState(() {
      _carts.add(CartTab(label: 'Sale $_nextCartNumber', taxRate: _orderSettings.defaultTaxRate));
      _nextCartNumber++;
      _activeIndex = _carts.length - 1;
    });
  }

  void _closeCart(int index) {
    if (_carts.length == 1) return;
    setState(() {
      _carts.removeAt(index);
      if (_activeIndex >= _carts.length) _activeIndex = _carts.length - 1;
    });
  }

  Future<void> _openCart() async {
    final result = await Navigator.of(context).push<CartPageResult>(MaterialPageRoute(builder: (_) => CartPage(cart: _activeCart, clients: _clients, isPharma: widget.isPharma)));
    if (result == null || !mounted) return;
    if (result.parked) {
      setState(() {});
      return;
    }
    if (result.completedSale != null) {
      final closedTabLabel = _activeCart.label;
      setState(() => _carts[_activeIndex] = CartTab(label: closedTabLabel, taxRate: _orderSettings.defaultTaxRate));
      await _refreshStockFor(result.completedSale!.items.map((i) => i.productId).toSet());
      final showReceipt = await PosLocalPrefs.getShowReceiptAfterCheckout();
      if (!mounted || !showReceipt) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PosReceiptPage(sale: result.completedSale!, receiptFooter: _orderSettings.receiptFooter)));
    }
  }

  /// Checkout decrements `store_products.stock_qty` server-side (and stock
  /// can move from other sources — MRR, adjustments, other devices — at any
  /// time too), but the grid's `_products` list is only loaded once on
  /// entry. Re-reading just the sold products' fresh stock (one batched
  /// round trip) after a completed sale keeps their tiles/badges accurate
  /// without refetching the entire catalog.
  Future<void> _refreshStockFor(Set<int> productIds) async {
    if (productIds.isEmpty) return;
    try {
      final result = await _client.batch([
        for (final id in productIds) BatchRequest(id: '$id', method: 'GET', url: 'store_products?\$select=id,stock_qty&\$filter=id eq $id&\$top=1'),
      ]);
      if (!mounted) return;
      setState(() {
        for (final id in productIds) {
          final body = unwrapBatchBody(result, '$id');
          final rows = unwrapList(body);
          if (rows.isEmpty) continue;
          final freshStock = toDouble((rows.first as Map)['stock_qty']);
          final index = _products.indexWhere((p) => p.id == id);
          if (index != -1) _products[index] = _products[index].copyWith(stockQty: freshStock);
        }
      });
    } catch (_) {
      // Best-effort — a failed refresh just leaves the tile showing its
      // last-known stock until the next reload; the sale itself already
      // succeeded regardless.
    }
  }

  Future<void> _openHeldBills() async {
    final resumed = await showHeldBillsSheet(context, isPharma: widget.isPharma);
    if (resumed == null || !mounted) return;
    setState(() {
      _carts.add(CartTab(
        saleId: resumed.id,
        label: resumed.displayNo,
        clientId: resumed.clientId,
        clientName: resumed.clientName,
        lines: resumed.items
            .map((i) => CartLine(
                  productId: i.productId,
                  name: i.name,
                  unitPrice: i.unitPrice,
                  quantity: i.quantity,
                ))
            .toList(),
        discountType: resumed.discountType,
        discountValue: resumed.discountValue,
        taxRate: resumed.taxRate,
        note: resumed.note,
      ));
      _activeIndex = _carts.length - 1;
    });
  }

  Future<void> _openSettings() async {
    final saved = await showPosSettingsSheet(context, settings: _orderSettings, warehouses: _warehouses);
    if (saved != null && mounted) setState(() => _orderSettings = saved);
  }

  /// Pharma mode keeps this menu deliberately small — just the two POS-first
  /// destinations (Inventory, Sales). Desktop parity for pharma
  /// (purchases/suppliers/customers/expenses/reports/catalog as separate
  /// screens) is out of scope for this pass; the regular (non-pharma) POS
  /// menu below is untouched.
  void _openMenu() {
    showMarketSheet(
      context,
      builder: (sheetContext) {
        final p = MarketPalette.of(sheetContext);
        final tiles = widget.isPharma
            ? <Widget>[
                _menuTile(sheetContext, Icons.inventory_2_outlined, 'Inventory', () => const ProductsListPage(filter: 'is_pharma eq true', title: 'Pharma Inventory')),
                _menuTile(sheetContext, Icons.receipt_long_outlined, 'Sales', () => const SalesOrderListPage(isPharma: true, title: 'Pharma Sales')),
              ]
            : <Widget>[
                _menuTile(sheetContext, Icons.storefront_outlined, 'Online market', () => const MarketHubPage()),
                _menuTile(sheetContext, Icons.insights_outlined, 'Analytics', () => const SellAnalyticsPage()),
                _menuTile(sheetContext, Icons.receipt_long_outlined, 'Sales orders', () => const SalesOrderListPage(title: 'Sales orders')),
                _menuTile(sheetContext, Icons.description_outlined, 'Invoices', () => const SalesOrderListPage(title: 'Invoices', statusFilter: 'COMPLETED')),
                _menuTile(sheetContext, Icons.payments_outlined, 'Payments', () => const PaymentsListPage()),
                _menuTile(sheetContext, Icons.assignment_return_outlined, 'Sales returns', () => const SalesOrderListPage(statusFilter: 'REFUNDED', title: 'Sales returns')),
                _menuTile(sheetContext, Icons.pause_circle_outline, 'Held bills', () => const HeldBillsListPage()),
                _menuTile(sheetContext, Icons.inventory_2_outlined, 'Products', () => const SellProductsPage()),
                _menuTile(sheetContext, Icons.bar_chart_outlined, 'Sales reports', () => const SalesReportPage()),
                _menuTile(sheetContext, Icons.people_alt_outlined, 'Clients', () => const ClientsListPage()),
                _menuTile(sheetContext, Icons.groups_outlined, 'Client groups', () => SimpleEntityListPage(config: clientGroupsConfig())),
                _menuTile(sheetContext, Icons.settings_outlined, 'Sales settings', () => const SellSettingsPage()),
              ];
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.85),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2)))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(9)),
                        child: Icon(widget.isPharma ? Icons.medication_outlined : Icons.point_of_sale_outlined, size: 18, color: p.brand),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.isPharma ? 'Pharma' : 'Sales', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
                            const SizedBox(height: 2),
                            Text(widget.isPharma ? 'Inventory and sales records' : 'Everything else in the sales module', style: TextStyle(fontSize: 12, color: p.label)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Material(
                      color: p.card,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.line)),
                      child: Column(
                        children: [
                          for (var i = 0; i < tiles.length; i++) ...[
                            if (i > 0) Divider(height: 1, thickness: 1, indent: 58, color: p.line),
                            tiles[i],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _menuTile(BuildContext sheetContext, IconData icon, String label, Widget Function() pageBuilder) {
    final p = MarketPalette.of(sheetContext);
    return InkWell(
      onTap: () {
        Navigator.of(sheetContext).pop();
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => pageBuilder()));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 18, color: p.brand),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.text))),
            Icon(Icons.chevron_right, size: 18, color: p.label),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.card,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: p.line)),
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isPharma) ...[
              Icon(Icons.medication_outlined, color: p.brand, size: 20),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.isPharma ? 'Pharma POS' : 'POS terminal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
                  if (!_loading) Text('${_products.length} product${_products.length == 1 ? '' : 's'}', style: TextStyle(fontSize: 11.5, color: p.label)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.pause_circle_outline), tooltip: 'Held sales', onPressed: _openHeldBills),
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'POS settings', onPressed: _openSettings),
          IconButton(icon: const Icon(Icons.menu), tooltip: 'Sales menu', onPressed: _openMenu),
        ],
      ),
      body: _loading
          ? _loadingState(p)
          : Column(
              children: [
                Container(
                  decoration: BoxDecoration(color: p.card, border: Border(bottom: BorderSide(color: p.line))),
                  child: Column(
                    children: [
                      _cartTabsRow(p),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: TextStyle(fontSize: 14, color: p.text),
                                decoration: InputDecoration(
                                  prefixIcon: Icon(Icons.search, size: 20, color: p.label),
                                  suffixIcon: _searchController.text.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: Icon(Icons.close, size: 18, color: p.label),
                                          tooltip: 'Clear search',
                                          onPressed: () => setState(() => _searchController.clear()),
                                        ),
                                  hintText: 'Search by name or SKU',
                                  hintStyle: TextStyle(fontSize: 14, color: p.label),
                                  isDense: true,
                                  filled: true,
                                  fillColor: p.surface,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.brand, width: 1.5)),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Scan barcode',
                              child: Material(
                                color: p.brandSoft,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: _scanBarcode,
                                  child: SizedBox(width: 46, height: 46, child: Icon(Icons.qr_code_scanner, color: p.brand)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_categories.isNotEmpty)
                        SizedBox(
                          height: 44,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                            children: [
                              _categoryChip(p, null, 'All'),
                              ..._categories.map((c) => _categoryChip(p, (c['id'] as num).toInt(), (c['name'] ?? '').toString())),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(child: _productGrid(p)),
                _cartSummaryBar(p),
              ],
            ),
    );
  }

  Widget _loadingState(MarketPalette p) {
    return Column(
      children: [
        Container(
          color: p.card,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: const Column(
            children: [
              Row(children: [SkeletonBox(height: 30, width: 72), SizedBox(width: 6), SkeletonBox(height: 30, width: 72)]),
              SizedBox(height: 10),
              SkeletonBox(height: 46, radius: 10),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.76),
            itemCount: 6,
            itemBuilder: (_, _) => const SkeletonBox(height: double.infinity, radius: 12),
          ),
        ),
      ],
    );
  }

  Widget _cartTabsRow(MarketPalette p) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        children: [
          for (var i = 0; i < _carts.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _cartTab(p, i),
            ),
          Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: p.line)),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _newCart,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: p.brand),
                    const SizedBox(width: 4),
                    Text('New sale', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.brand)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartTab(MarketPalette p, int i) {
    final selected = _activeIndex == i;
    final count = _carts[i].lines.fold(0, (sum, l) => sum + l.quantity);
    return Material(
      color: selected ? p.brandSoft : p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: selected ? p.brand : p.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _activeIndex = i),
        child: Padding(
          padding: EdgeInsets.only(left: 10, right: _carts.length > 1 ? 2 : 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_outlined, size: 14, color: selected ? p.brand : p.label),
              const SizedBox(width: 6),
              Text(_carts[i].label, style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? p.brand : p.text)),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: selected ? p.brand : p.neutralBg, borderRadius: BorderRadius.circular(10)),
                  child: Text('$count', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : p.neutral)),
                ),
              ],
              if (_carts.length > 1)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _closeCart(i),
                  child: Padding(padding: const EdgeInsets.all(5), child: Icon(Icons.close, size: 14, color: p.label)),
                ),
            ],
          ),
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
            color: selected ? p.brand : p.card,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: selected ? p.brand : p.line),
          ),
          child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.white : p.text)),
        ),
      ),
    );
  }

  Widget _productGrid(MarketPalette p) {
    final products = _visibleProducts;
    if (products.isEmpty) {
      final filtering = _searchController.text.trim().isNotEmpty || _categoryFilter != null;
      return Center(
        child: SingleChildScrollView(
          child: MarketEmpty(
            icon: filtering ? Icons.search_off : Icons.inventory_2_outlined,
            title: filtering ? 'No matching products' : 'No products to sell',
            message: filtering
                ? 'Try a different name, SKU or category.'
                : 'Only active, salable${widget.isPharma ? ' pharma' : ''} products appear here.',
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.76),
      itemCount: products.length,
      itemBuilder: (context, index) => _ProductTile(product: products[index], onTap: () => _addToCart(products[index])),
    );
  }

  Widget _cartSummaryBar(MarketPalette p) {
    final cart = _activeCart;
    final itemCount = cart.lines.fold(0, (sum, l) => sum + l.quantity);
    return Container(
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: cart.isEmpty ? null : _openCart,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(10)),
                              child: Icon(Icons.shopping_cart_outlined, size: 20, color: p.brand),
                            ),
                            if (itemCount > 0)
                              Positioned(
                                right: -5,
                                top: -5,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 20),
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.card, width: 1.5)),
                                  child: Text('$itemCount', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                cart.isEmpty ? 'Cart is empty' : '$itemCount item${itemCount == 1 ? '' : 's'} · ${cart.label}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: p.label),
                              ),
                              const SizedBox(height: 1),
                              Text(formatMoney(cart.total), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: cart.isEmpty ? null : _openCart,
                  style: FilledButton.styleFrom(
                    backgroundColor: p.brand,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: p.surface,
                    disabledForegroundColor: p.label,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.point_of_sale_outlined, size: 18),
                  label: const Text('Charge', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final StoreProduct product;
  final VoidCallback onTap;
  const _ProductTile({required this.product, required this.onTap});

  String get _qtyText => product.stockQty == product.stockQty.roundToDouble() ? product.stockQty.toStringAsFixed(0) : product.stockQty.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final outOfStock = product.trackStock && product.stockQty <= 0;
    final (String, MarketTone)? stock = !product.trackStock
        ? null
        : outOfStock
            ? ('Out of stock', MarketTone.error)
            : product.isLowStock
                ? ('Low · $_qtyText', MarketTone.warn)
                : ('$_qtyText in stock', MarketTone.ok);
    return Opacity(
      opacity: outOfStock ? 0.6 : 1,
      child: MarketCard(
        padding: EdgeInsets.zero,
        onTap: outOfStock ? null : onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    product.thumbnailUrl != null
                        ? CachedNetworkImage(imageUrl: product.thumbnailUrl!, fit: BoxFit.cover, width: double.infinity, errorWidget: (_, _, _) => _placeholder(p), placeholder: (_, _) => Container(color: p.surface))
                        : _placeholder(p),
                    if (stock != null)
                      Positioned(
                        left: 8,
                        top: 8,
                        right: 8,
                        child: Align(alignment: Alignment.centerLeft, child: StatusPill(stock.$1, tone: stock.$2)),
                      ),
                  ],
                ),
              ),
            ),
            Container(height: 1, color: p.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 34,
                    child: Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.3, color: p.text)),
                  ),
                  const SizedBox(height: 4),
                  Text(formatMoney(product.price), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: p.text)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(MarketPalette p) => Container(color: p.surface, child: Icon(Icons.inventory_2_outlined, color: p.label, size: 30));
}
