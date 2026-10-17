import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../data/store_analytics_service.dart';
import '../data/store_lookup_service.dart';
import '../data/store_settings_service.dart';
import 'analytics/store_analytics_page.dart';
import 'catalog/barcode_lab_page.dart';
import 'catalog/products_list_page.dart';
import 'configs/entity_configs.dart';
import 'documents/mrr_form_page.dart';
import 'documents/mrr_list_page.dart';
import 'documents/mrr_return_list_page.dart';
import 'documents/purchase_order_list_page.dart';
import 'documents/purchase_requisition_form_page.dart';
import 'documents/purchase_requisition_list_page.dart';
import 'documents/requisition_list_page.dart';
import 'documents/return_list_page.dart';
import 'settings/store_settings_page.dart';
import 'stock/low_stock_page.dart';
import 'stock/sales_dispatch_page.dart';
import 'stock/stock_adjustment_page.dart';
import 'stock/stock_expiry_page.dart';
import 'stock/stock_ledger_page.dart';
import 'widgets/field_spec.dart';
import 'widgets/store_ui.dart';

typedef _Area = (IconData icon, String title, String? subtitle, VoidCallback onTap);

/// Store module home — stock value, alert KPIs, quick actions and every Store
/// area grouped like desktop's store.nav.ts. Same SAP Horizon look as the
/// Sales home (sales_hub_page.dart).
class StoreHomePage extends StatefulWidget {
  const StoreHomePage({super.key});

  @override
  State<StoreHomePage> createState() => _StoreHomePageState();
}

class _StoreHomePageState extends State<StoreHomePage> {
  final _client = ApiClient();
  bool _loading = true;
  StoreAnalyticsSnapshot? _snapshot;
  Map<String, List<Map<String, dynamic>>> _lookups = {};
  StoreFeatureToggles _toggles = const StoreFeatureToggles();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Independent reads — each failure only blanks its own part.
    final results = await Future.wait<Object?>([
      StoreAnalyticsService(_client).load().then<Object?>((v) => v).catchError((_) => null),
      StoreLookupService(_client).loadAll().then<Object?>((v) => v).catchError((_) => null),
      StoreSettingsService(_client).load().then<Object?>((v) => v).catchError((_) => null),
    ]);
    if (!mounted) return;
    setState(() {
      _snapshot = results[0] as StoreAnalyticsSnapshot?;
      _lookups = (results[1] as Map<String, List<Map<String, dynamic>>>?) ?? _lookups;
      _toggles = (results[2] as StoreFeatureToggles?) ?? _toggles;
      _loading = false;
    });
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(marketRoute(page));
    if (mounted) _load();
  }

  void _openSimple(SimpleCrudConfig config) => _open(SimpleEntityListPage(config: config));

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketScaffold(
      title: 'Store',
      subtitle: 'Catalogue, stock and warehouse',
      actions: [
        IconButton(tooltip: 'Store settings', icon: const Icon(Icons.settings_outlined), onPressed: () => _open(const StoreSettingsPage())),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _valueCard(p),
            const SizedBox(height: 12),
            _kpis(),
            _quickActions(p),
            ..._sections(p),
          ],
        ),
      ),
    );
  }

  Widget _valueCard(MarketPalette p) {
    final s = _snapshot;
    return FadeSlideIn(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Stock value', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
          const SizedBox(height: 6),
          _loading && s == null
              ? const SizedBox(height: 30, child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 120, child: LinearProgressIndicator(color: Colors.white, backgroundColor: Colors.white24))))
              : CountUp(
                  value: s?.stockValue ?? 0,
                  format: (v) => money(v),
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.1),
                ),
          const SizedBox(height: 12),
          Row(children: [
            _valueStat('Received', '${s?.movementTypeCounts['IN'] ?? 0}'),
            _valueStat('Issued', '${s?.movementTypeCounts['OUT'] ?? 0}'),
            _valueStat('Adjusted', '${s?.movementTypeCounts['ADJUST'] ?? 0}'),
          ]),
          const SizedBox(height: 2),
          const Text('Stock movements', style: TextStyle(color: Colors.white60, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _valueStat(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
        ]),
      );

  Widget _kpis() {
    final s = _snapshot;
    final tiles = [
      KpiTile(icon: Icons.warning_amber_outlined, label: 'Low stock', value: s?.lowStockCount ?? 0,
          tone: (s?.lowStockCount ?? 0) > 0 ? MarketTone.error : MarketTone.ok, onTap: () => _open(const LowStockPage())),
      KpiTile(icon: Icons.event_busy_outlined, label: 'Expiring ≤ 30d', value: s?.expiringBatchCount ?? 0,
          tone: (s?.expiringBatchCount ?? 0) > 0 ? MarketTone.warn : MarketTone.ok, onTap: () => _open(const StockExpiryPage())),
      if (_toggles.hasSpr)
        KpiTile(icon: Icons.request_page_outlined, label: 'Pending SPR', value: s?.pendingSprCount ?? 0, tone: MarketTone.warn,
            onTap: () => _open(const PurchaseRequisitionListPage())),
      if (_toggles.hasSr)
        KpiTile(icon: Icons.description_outlined, label: 'Pending SR', value: s?.pendingSrCount ?? 0, tone: MarketTone.warn,
            onTap: () => _open(const RequisitionListPage())),
      KpiTile(icon: Icons.shopping_cart_outlined, label: 'Pending POs', value: s?.pendingPoCount ?? 0, tone: MarketTone.info,
          onTap: () => _open(const PurchaseOrderListPage())),
      KpiTile(icon: Icons.insights_outlined, label: 'Analytics', value: s?.categoryProductCounts.length ?? 0, sub: 'categories', tone: MarketTone.brand,
          onTap: () => _open(const StoreAnalyticsPage())),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.35,
      children: [for (var i = 0; i < tiles.length; i++) FadeSlideIn(index: i + 1, child: tiles[i])],
    );
  }

  Widget _quickActions(MarketPalette p) {
    final actions = <(IconData, String, VoidCallback)>[
      (Icons.move_to_inbox_outlined, 'Receive', () => _open(const MrrFormPage(type: 'LOCAL'))),
      (Icons.tune, 'Adjust', () => _open(const StockAdjustmentPage())),
      if (_toggles.hasSpr) (Icons.add_shopping_cart_outlined, 'New SPR', () => _open(const PurchaseRequisitionFormPage())),
      (Icons.qr_code_scanner_outlined, 'Barcodes', () => _open(const BarcodeLabPage())),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(children: [
        for (final a in actions)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: a.$3,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: p.card, shape: BoxShape.circle, border: Border.all(color: p.line)),
                    child: Icon(a.$1, color: p.brand, size: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(a.$2, style: TextStyle(fontSize: 12, color: p.text, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  List<Widget> _sections(MarketPalette p) {
    final sections = <(String, List<_Area>)>[
      ('Catalogue', [
        (Icons.inventory_2_outlined, 'Products', 'Items, prices and stock levels', () => _open(const ProductsListPage())),
        (Icons.category_outlined, 'Categories', null, () => _openSimple(categoriesConfig())),
        (Icons.account_tree_outlined, 'Sub-categories', null, () => _openSimple(subCategoriesConfig(_lookups))),
        (Icons.straighten_outlined, 'Units of measure', null, () => _openSimple(uomsConfig())),
        (Icons.qr_code_2_outlined, 'Packaging and barcodes', null, () => _openSimple(packagingsConfig(_lookups))),
        (Icons.qr_code_scanner_outlined, 'Barcode lab', 'Preview and print any code', () => _open(const BarcodeLabPage())),
      ]),
      ('Inward', [
        (Icons.shopping_cart_outlined, 'Purchase orders', 'Read-only, feeds MRR receiving', () => _open(const PurchaseOrderListPage())),
        (Icons.move_to_inbox_outlined, 'MRR, local', 'Goods received from local suppliers', () => _open(const MrrListPage(type: 'LOCAL'))),
        (Icons.flight_land_outlined, 'MRR, imported', 'Goods received from imports', () => _open(const MrrListPage(type: 'IMPORTED'))),
        if (_toggles.hasRepairMrr) (Icons.build_outlined, 'MRR, repair', 'Items back from repair', () => _open(const MrrListPage(type: 'REPAIR'))),
      ]),
      ('Outward', [
        (Icons.assignment_return_outlined, 'Returns', 'Reverses a store requisition', () => _open(const ReturnListPage())),
        (Icons.undo_outlined, 'Return MRR', 'Sends goods back to the supplier', () => _open(const MrrReturnListPage())),
        (Icons.point_of_sale_outlined, 'Sales dispatch', 'Read-only, stock out via POS', () => _open(const SalesDispatchPage())),
      ]),
      ('Requisitions', [
        if (_toggles.hasSpr) (Icons.request_page_outlined, 'Purchase requisitions (SPR)', 'Sent for approval, then to purchasing', () => _open(const PurchaseRequisitionListPage())),
        if (_toggles.hasSr) (Icons.description_outlined, 'Store requisitions (SR)', 'Internal issue requests', () => _open(const RequisitionListPage())),
        (Icons.inventory_outlined, 'Product batches', 'Lots and expiry dates', () => _openSimple(batchesConfig(_lookups))),
      ]),
      ('Stock', [
        (Icons.tune, 'Stock adjustment', 'Correct counts and write-offs', () => _open(const StockAdjustmentPage())),
        (Icons.history_outlined, 'Stock ledger', 'Full movement history', () => _open(const StockLedgerPage())),
        (Icons.warning_amber_outlined, 'Low stock', 'At or below the reorder level', () => _open(const LowStockPage())),
        (Icons.event_busy_outlined, 'Stock expiry', 'FIFO / LIFO pick order', () => _open(const StockExpiryPage())),
      ]),
      ('Warehouse', [
        (Icons.warehouse_outlined, 'Warehouses', null, () => _openSimple(warehousesConfig())),
        (Icons.turn_slight_right_outlined, 'Corridors', null, () => _openSimple(corridorsConfig(_lookups))),
        (Icons.grid_view_outlined, 'Racks', null, () => _openSimple(racksConfig(_lookups))),
        (Icons.inbox_outlined, 'Bins', null, () => _openSimple(binsConfig(_lookups))),
      ]),
    ];

    return [
      for (final (title, areas) in sections)
        if (areas.isNotEmpty) ...[
          SectionHeader(title),
          MarketCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (var i = 0; i < areas.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 62, color: p.line),
                ListTile(
                  onTap: areas[i].$4,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(9)),
                    child: Icon(areas[i].$1, size: 19, color: p.brand),
                  ),
                  title: Text(areas[i].$2, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                  subtitle: areas[i].$3 == null ? null : Text(areas[i].$3!, style: TextStyle(fontSize: 12, color: p.label)),
                  trailing: Icon(Icons.chevron_right, color: p.label),
                ),
              ],
            ]),
          ),
        ],
    ];
  }
}
