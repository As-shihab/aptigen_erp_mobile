import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../data/stock_movement_model.dart';
import '../../data/stock_movement_service.dart';
import '../../data/store_lookup_service.dart';
import '../../data/store_product_model.dart';
import '../../data/store_product_service.dart';
import '../../data/store_util.dart';
import '../widgets/product_picker_sheet.dart';
import '../widgets/store_ui.dart' hide toDouble, toInt;
import 'stock_ledger_page.dart' show movementLabel, movementTone, movementIcon;

/// Manual IN/OUT/ADJUST postings — create-only list (the ledger is
/// append-only, no edit/delete, matches desktop's `StoreStockAdjustment.tsx`
/// and the schema's lack of an `updated_at` on `store_stock_movements`).
class StockAdjustmentPage extends StatefulWidget {
  const StockAdjustmentPage({super.key});

  @override
  State<StockAdjustmentPage> createState() => _StockAdjustmentPageState();
}

class _StockAdjustmentPageState extends State<StockAdjustmentPage> {
  final _client = ApiClient();
  late final _movementService = StockMovementService(_client);
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
      final result = await _movementService.listAdjustments();
      if (!mounted) return;
      setState(() => _rows = result);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load adjustments.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _sign(String type) => switch (type) { 'OUT' => '-', 'ADJUST' => '±', _ => '+' };

  Future<void> _openCreate() async {
    final saved = await Navigator.of(context).push<bool>(marketRoute(const _NewMovementPage()));
    if (saved == true) {
      if (mounted) marketToast(context, 'Stock movement recorded.');
      _load();
    }
  }

  List<StockMovementRow> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _rows.where((r) {
      if (_type != 'ALL' && r.type != _type) return false;
      if (q.isEmpty) return true;
      return r.productName.toLowerCase().contains(q) || r.locationPath.toLowerCase().contains(q) || (r.remarks ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final visible = _visible;
    return MarketScaffold(
      title: 'Stock adjustment',
      subtitle: _loading && _rows.isEmpty ? 'Loading…' : 'Manual receipts, issues and counts',
      fab: FloatingActionButton.extended(
        backgroundColor: p.brand,
        foregroundColor: Colors.white,
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('New adjustment'),
      ),
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
                    hintText: 'Search product, location or remarks',
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
                    (id: 'IN', label: 'Received', count: _rows.where((r) => r.type == 'IN').length),
                    (id: 'OUT', label: 'Issued', count: _rows.where((r) => r.type == 'OUT').length),
                    (id: 'ADJUST', label: 'Counted', count: _rows.where((r) => r.type == 'ADJUST').length),
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
      return const [SliverFillRemaining(hasScrollBody: false, child: SkeletonList(count: 6, itemHeight: 64))];
    }
    if (_error != null) {
      return [SliverFillRemaining(hasScrollBody: false, child: MarketEmpty(icon: Icons.cloud_off_outlined, title: _error!, actionLabel: 'Try again', onAction: _load))];
    }
    if (visible.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: MarketEmpty(
            icon: Icons.tune,
            title: _rows.isEmpty ? 'No adjustments yet' : 'Nothing matches',
            message: _rows.isEmpty ? 'Record a receipt, an issue or a stock count to correct on-hand quantities.' : 'Try another search or type.',
            actionLabel: _rows.isEmpty ? 'New adjustment' : null,
            onAction: _rows.isEmpty ? _openCreate : null,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        sliver: SliverList.separated(
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) => FadeSlideIn(index: i, child: _row(p, visible[i])),
        ),
      ),
    ];
  }

  Widget _row(MarketPalette p, StockMovementRow row) {
    final tone = movementTone(row.type);
    final c = p.tone(tone);
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
            Text('${row.locationPath} · ${displayDate(row.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
            if (row.remarks != null)
              Text(row.remarks!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label, fontStyle: FontStyle.italic)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${_sign(row.type)}${row.quantity.toStringAsFixed(0)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.fg)),
          const SizedBox(height: 4),
          StatusPill(movementLabel(row.type), tone: tone),
        ]),
      ]),
    );
  }
}

const _movementTypes = ['IN', 'OUT', 'ADJUST'];

class _NewMovementPage extends StatefulWidget {
  const _NewMovementPage();

  @override
  State<_NewMovementPage> createState() => _NewMovementPageState();
}

class _NewMovementPageState extends State<_NewMovementPage> {
  final _client = ApiClient();

  String _type = 'IN';
  StoreProduct? _product;
  int? _warehouseId;
  int? _corridorId;
  int? _rackId;
  int? _binId;
  int? _batchId;
  final _quantityController = TextEditingController();
  final _remarksController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  List<StoreProduct> _products = [];
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _corridors = [];
  List<Map<String, dynamic>> _racks = [];
  List<Map<String, dynamic>> _bins = [];
  List<Map<String, dynamic>> _batches = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final lookups = await StoreLookupService(_client).loadAll();
      final products = await StoreProductService(_client).list();
      if (!mounted) return;
      setState(() {
        _warehouses = lookups['warehouses'] ?? [];
        _corridors = lookups['corridors'] ?? [];
        _racks = lookups['racks'] ?? [];
        _bins = lookups['bins'] ?? [];
        _batches = lookups['batches'] ?? [];
        _products = products;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _visibleCorridors => _warehouseId == null ? _corridors : _corridors.where((c) => toNum(c['warehouse_id']) == _warehouseId).toList();
  List<Map<String, dynamic>> get _visibleRacks => _corridorId == null ? _racks : _racks.where((r) => toNum(r['corridor_id']) == _corridorId).toList();
  List<Map<String, dynamic>> get _visibleBins => _rackId == null ? _bins : _bins.where((b) => toNum(b['rack_id']) == _rackId).toList();
  List<Map<String, dynamic>> get _visibleBatches => _product == null ? _batches : _batches.where((b) => toNum(b['product_id']) == _product!.id).toList();

  Future<void> _pickProduct() async {
    final picked = await showProductPickerSheet(context, products: _products);
    if (picked == null) return;
    setState(() {
      _product = picked;
      _batchId = null;
    });
  }

  Future<int?> _resolveLocationId() async {
    final filterParts = ['warehouse_id eq $_warehouseId'];
    filterParts.add(_corridorId != null ? 'corridor_id eq $_corridorId' : 'corridor_id eq null');
    filterParts.add(_rackId != null ? 'rack_id eq $_rackId' : 'rack_id eq null');
    filterParts.add(_binId != null ? 'bin_id eq $_binId' : 'bin_id eq null');
    final filter = filterParts.join(' and ');
    final found = await _client.get('store_locations?\$filter=${Uri.encodeComponent(filter)}&\$top=1');
    final foundList = unwrapList(found);
    if (foundList.isNotEmpty) return toIntOrNull((foundList.first as Map)['id']);

    final warehouse = _warehouses.where((w) => toNum(w['id']) == _warehouseId).firstOrNull;
    final corridor = _corridors.where((c) => toNum(c['id']) == _corridorId).firstOrNull;
    final rack = _racks.where((r) => toNum(r['id']) == _rackId).firstOrNull;
    final bin = _bins.where((b) => toNum(b['id']) == _binId).firstOrNull;
    final path = [warehouse?['code'], corridor?['code'], rack?['code'], bin?['code']].where((c) => c != null).join(' / ');

    final created = await _client.post('store_locations', {'warehouse_id': _warehouseId, 'corridor_id': _corridorId, 'rack_id': _rackId, 'bin_id': _binId, 'path': path}, isV8: true);
    final row = (created is Map && created['value'] is Map) ? created['value'] : created;
    return toIntOrNull((row as Map?)?['id']);
  }

  Future<void> _submit() async {
    final enteredQty = double.tryParse(_quantityController.text.trim());
    if (_product == null || _warehouseId == null || enteredQty == null || enteredQty < 0 || (_type != 'ADJUST' && enteredQty <= 0)) {
      marketToast(context, 'Please select a product, warehouse and a valid quantity.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final locationId = await _resolveLocationId();
      if (locationId == null) {
        if (!mounted) return;
        marketToast(context, 'Failed to resolve warehouse location', error: true);
        return;
      }

      final balanceRes = await _client.get('store_stock_movements?\$select=balance_after&\$filter=product_id eq ${_product!.id} and location_id eq $locationId&\$orderby=id desc&\$top=1');
      final balanceList = unwrapList(balanceRes);
      final previousBalance = balanceList.isEmpty ? 0.0 : toDouble((balanceList.first as Map)['balance_after']);

      double movementQty;
      double newBalance;
      double delta;

      if (_type == 'IN') {
        movementQty = enteredQty;
        delta = enteredQty;
        newBalance = previousBalance + enteredQty;
      } else if (_type == 'OUT') {
        if (enteredQty > previousBalance) {
          if (!mounted) return;
          marketToast(context, 'Only $previousBalance available at this location', error: true);
          return;
        }
        movementQty = enteredQty;
        delta = -enteredQty;
        newBalance = previousBalance - enteredQty;
      } else {
        delta = enteredQty - previousBalance;
        if (delta == 0) {
          if (!mounted) return;
          marketToast(context, 'Counted quantity matches current balance — nothing to adjust');
          return;
        }
        movementQty = delta.abs();
        newBalance = enteredQty;
      }

      await _client.post('store_stock_movements', {
        'product_id': _product!.id,
        'location_id': locationId,
        'batch_id': _batchId,
        'type': _type,
        'quantity': movementQty,
        'balance_after': newBalance,
        'reference_type': 'ADJUSTMENT',
        'reference_id': null,
        'remarks': _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
      }, isV8: true);

      final productRes = await _client.get('store_products?\$select=id,stock_qty&\$filter=id eq ${_product!.id}&\$top=1');
      final productList = unwrapList(productRes);
      final currentStock = productList.isEmpty ? 0.0 : toDouble((productList.first as Map)['stock_qty']);
      await _client.put('store_products', _product!.id, {'stock_qty': currentStock + delta});

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Failed to record stock movement', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _typeOption(String t) => switch (t) { 'IN' => 'Receive', 'OUT' => 'Issue', _ => 'Count' };

  String _typeHelp(String t) => switch (t) {
        'IN' => 'Adds the quantity to the selected location.',
        'OUT' => 'Takes the quantity out of the selected location.',
        _ => 'Enter the freshly counted on-hand quantity — the ledger records the difference.',
      };

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final quantityLabel = _type == 'ADJUST' ? 'Counted quantity' : 'Quantity';
    final tone = movementTone(_type);
    return MarketScaffold(
      title: 'New stock movement',
      subtitle: movementLabel(_type),
      body: _loading
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                SkeletonBox(height: 16, width: 120),
                SizedBox(height: 12),
                SkeletonBox(height: 110, radius: 12),
                SizedBox(height: 24),
                SkeletonBox(height: 16, width: 100),
                SizedBox(height: 12),
                SkeletonBox(height: 180, radius: 12),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                FadeSlideIn(
                  child: _section(p, title: 'Movement', subtitle: 'What kind of change this is', children: [
                    MarketSegmented<String>(
                      value: _type,
                      onChanged: (v) => setState(() => _type = v),
                      options: [for (final t in _movementTypes) (id: t, label: _typeOption(t), count: null)],
                    ),
                    const SizedBox(height: 10),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(movementIcon(_type), size: 16, color: p.tone(tone).fg),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_typeHelp(_type), style: TextStyle(fontSize: 12, color: p.label, height: 1.4))),
                    ]),
                  ]),
                ),
                FadeSlideIn(
                  index: 1,
                  child: _section(p, title: 'Product', children: [
                    MarketCard(
                      color: p.surface,
                      padding: const EdgeInsets.all(12),
                      onTap: _pickProduct,
                      child: Row(children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(9)),
                          child: Icon(Icons.inventory_2_outlined, size: 18, color: p.brand),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_product?.name ?? 'Select product',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _product == null ? p.label : p.text)),
                            if (_product != null) ...[
                              const SizedBox(height: 2),
                              Text('SKU ${_product!.sku ?? '—'}', style: TextStyle(fontSize: 11.5, color: p.label)),
                            ],
                          ]),
                        ),
                        if (_product != null) ...[
                          Builder(builder: (_) {
                            final (label, t) = stockPill(trackStock: _product!.trackStock, qty: _product!.stockQty, lowAt: _product!.lowStockAt);
                            return StatusPill(label, tone: t);
                          }),
                          const SizedBox(width: 4),
                        ],
                        Icon(Icons.search, size: 18, color: p.label),
                      ]),
                    ),
                  ]),
                ),
                FadeSlideIn(
                  index: 2,
                  child: _section(p, title: 'Location', subtitle: 'Where the stock sits', children: [
                    DropdownButtonFormField<int>(
                      initialValue: _warehouses.any((w) => toNum(w['id']) == _warehouseId) ? _warehouseId : null,
                      decoration: _dec(p, 'Warehouse *'),
                      items: _warehouses.map((w) => DropdownMenuItem(value: toNum(w['id']), child: Text((w['name'] ?? '').toString()))).toList(),
                      onChanged: (v) => setState(() {
                        _warehouseId = v;
                        _corridorId = null;
                        _rackId = null;
                        _binId = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _visibleCorridors.any((c) => toNum(c['id']) == _corridorId) ? _corridorId : null,
                            decoration: _dec(p, 'Corridor'),
                            isExpanded: true,
                            items: _visibleCorridors.map((c) => DropdownMenuItem(value: toNum(c['id']), child: Text(codeLabel(c), overflow: TextOverflow.ellipsis))).toList(),
                            onChanged: (v) => setState(() {
                              _corridorId = v;
                              _rackId = null;
                              _binId = null;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _visibleRacks.any((r) => toNum(r['id']) == _rackId) ? _rackId : null,
                            decoration: _dec(p, 'Rack'),
                            isExpanded: true,
                            items: _visibleRacks.map((r) => DropdownMenuItem(value: toNum(r['id']), child: Text(codeLabel(r), overflow: TextOverflow.ellipsis))).toList(),
                            onChanged: (v) => setState(() {
                              _rackId = v;
                              _binId = null;
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _visibleBins.any((b) => toNum(b['id']) == _binId) ? _binId : null,
                      decoration: _dec(p, 'Bin'),
                      isExpanded: true,
                      items: _visibleBins.map((b) => DropdownMenuItem(value: toNum(b['id']), child: Text(codeLabel(b), overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) => setState(() => _binId = v),
                    ),
                  ]),
                ),
                FadeSlideIn(
                  index: 3,
                  child: _section(p, title: 'Quantity', children: [
                    DropdownButtonFormField<int>(
                      initialValue: _visibleBatches.any((b) => toNum(b['id']) == _batchId) ? _batchId : null,
                      decoration: _dec(p, 'Batch (optional)'),
                      isExpanded: true,
                      items: _visibleBatches.map((b) => DropdownMenuItem(value: toNum(b['id']), child: Text((b['batch_no'] ?? '').toString()))).toList(),
                      onChanged: (v) => setState(() => _batchId = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _quantityController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _dec(p, quantityLabel),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _remarksController,
                      maxLines: 3,
                      minLines: 2,
                      decoration: _dec(p, 'Remarks').copyWith(alignLabelWithHint: true),
                    ),
                  ]),
                ),
              ],
            ),
      bottom: Container(
        decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(children: [
              Expanded(
                child: _product == null
                    ? Text('Pick a product to continue', style: TextStyle(fontSize: 12.5, color: p.label))
                    : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_product!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
                        Text(movementLabel(_type), style: TextStyle(fontSize: 11.5, color: p.tone(tone).fg)),
                      ]),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: p.brand, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 22)),
                  onPressed: _saving || _loading ? null : _submit,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, size: 18),
                  label: const Text('Record'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(MarketPalette p, String label) => InputDecoration(labelText: label, isDense: true, fillColor: p.card);

  Widget _section(MarketPalette p, {required String title, String? subtitle, required List<Widget> children}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(title, subtitle: subtitle),
      MarketCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    ]);
  }
}

extension _FirstOrNullMap on Iterable<Map<String, dynamic>> {
  Map<String, dynamic>? get firstOrNull => isEmpty ? null : first;
}
