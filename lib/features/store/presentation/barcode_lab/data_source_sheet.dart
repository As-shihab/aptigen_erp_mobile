import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/label_model.dart';
import '../../data/store_product_model.dart';
import '../../data/store_product_service.dart';
import '../widgets/product_picker_sheet.dart';
import 'lab_widgets.dart';

enum LabDataMode { manual, product, batch }

class LabBatchEntry {
  final StoreProduct product;
  StorePackaging? packaging;
  int copies;
  LabBatchEntry(this.product, {this.packaging, this.copies = 1});
}

/// Merge-field values for one product (and optional packaging).
Map<String, String> productLabelData(StoreProduct product, [StorePackaging? packaging]) {
  String num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  final barcode = (packaging?.barcode ?? '').isNotEmpty ? packaging!.barcode! : ((product.barcode ?? '').isNotEmpty ? product.barcode! : (product.sku ?? ''));
  return {
    'name': packaging == null ? product.name : '${product.name} · ${packaging.name}',
    'sku': product.sku ?? '',
    'barcode': barcode,
    'price': num(product.price * (packaging?.unitQty ?? 1)),
    'mrp': product.comparePrice == null ? '' : num(product.comparePrice! * (packaging?.unitQty ?? 1)),
    'unit': packaging?.name ?? '',
  };
}

/// Where merge-field values come from: typed values, one product, or a
/// batch of products with a copy count each.
class LabDataSource {
  LabDataMode mode = LabDataMode.manual;
  final Map<String, String> manual = {};
  StoreProduct? product;
  StorePackaging? packaging;
  final List<LabBatchEntry> batch = [];

  bool get hasAny =>
      manual.values.any((v) => v.trim().isNotEmpty) || (mode == LabDataMode.product && product != null) || (mode == LabDataMode.batch && batch.isNotEmpty);

  Map<String, String> _manualClean() => {
        for (final e in manual.entries)
          if (e.value.trim().isNotEmpty) e.key: e.value,
      };

  Map<String, String> dataFor(StoreProduct? p, StorePackaging? pk, String company) => {
        if (company.isNotEmpty) 'company': company,
        if (p != null) ...productLabelData(p, pk),
        ..._manualClean(),
      };

  /// What the designer canvas shows — real values, or samples when nothing
  /// has been chosen yet so the layout never looks empty.
  Map<String, String> previewData(String company) {
    if (!hasAny) return sampleLabelData(company: company);
    return switch (mode) {
      LabDataMode.product => dataFor(product, packaging, company),
      LabDataMode.batch when batch.isNotEmpty => dataFor(batch.first.product, batch.first.packaging, company),
      _ => dataFor(null, null, company),
    };
  }

  /// Labels to print: (data, copies, title).
  List<({Map<String, String> data, int copies, String title})> jobs(String company, int copies) {
    if (mode == LabDataMode.batch && batch.isNotEmpty) {
      return [
        for (final b in batch)
          if (b.copies > 0) (data: dataFor(b.product, b.packaging, company), copies: b.copies, title: b.packaging == null ? b.product.name : '${b.product.name} · ${b.packaging!.name}'),
      ];
    }
    final p = mode == LabDataMode.product ? product : null;
    return [(data: dataFor(p, mode == LabDataMode.product ? packaging : null, company), copies: copies, title: p?.name ?? 'Label')];
  }

  String get summary => switch (mode) {
        LabDataMode.product => product == null ? 'Choose product' : product!.name,
        LabDataMode.batch => batch.isEmpty ? 'Batch, empty' : 'Batch · ${batch.length} products',
        LabDataMode.manual => manual.values.any((v) => v.trim().isNotEmpty) ? 'Manual values' : 'Sample data',
      };
}

/// Products/packagings, fetched once per app session for the lab.
class _LabCatalog {
  static List<StoreProduct>? products;
  static List<StorePackaging>? packagings;

  static Future<void> ensure() async {
    if (products != null && packagings != null) return;
    final service = StoreProductService(ApiClient());
    final res = await Future.wait([service.list(filter: 'is_active eq true'), service.listPackagings()]);
    products = res[0] as List<StoreProduct>;
    packagings = res[1] as List<StorePackaging>;
  }

  static List<StorePackaging> forProduct(int id) => (packagings ?? const []).where((p) => p.productId == id).toList();
}

Future<void> showDataSourceSheet(BuildContext context, {required LabDataSource source, required Set<String> usedFields, required VoidCallback onChanged}) {
  return showMotionSheet<void>(context, (_) => _DataSourceSheet(source: source, usedFields: usedFields, onChanged: onChanged));
}

class _DataSourceSheet extends StatefulWidget {
  final LabDataSource source;
  final Set<String> usedFields;
  final VoidCallback onChanged;
  const _DataSourceSheet({required this.source, required this.usedFields, required this.onChanged});

  @override
  State<_DataSourceSheet> createState() => _DataSourceSheetState();
}

class _DataSourceSheetState extends State<_DataSourceSheet> {
  bool _loading = false;

  LabDataSource get s => widget.source;

  void _changed(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  Future<StoreProduct?> _pickProduct() async {
    setState(() => _loading = true);
    try {
      await _LabCatalog.ensure();
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not load products'), error: true);
      return null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return null;
    return showProductPickerSheet(context, products: _LabCatalog.products ?? const []);
  }

  Future<StorePackaging?> _pickPackaging(StoreProduct product, StorePackaging? current) async {
    final list = _LabCatalog.forProduct(product.id);
    final picked = await showPickerSheet(
      context,
      title: 'Packaging',
      selected: current?.id ?? 0,
      options: [
        const PickOption(0, 'Base unit'),
        for (final pk in list) PickOption(pk.id, pk.name, sub: [if ((pk.barcode ?? '').isNotEmpty) pk.barcode!, '× ${pk.unitQty}'].join(' · ')),
      ],
    );
    if (picked == null) return current;
    if (picked.id == 0) return null;
    return list.where((pk) => pk.id == picked.id).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final total = s.batch.fold<int>(0, (a, b) => a + b.copies);
    return FormSheet(
      title: 'Data source',
      subtitle: 'Fills the fields used on the label',
      extraAction: _loading ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))) : null,
      children: [
        LabChoice<LabDataMode>(
          value: s.mode,
          options: const [(LabDataMode.manual, 'Manual'), (LabDataMode.product, 'Product'), (LabDataMode.batch, 'Batch')],
          onChanged: (v) => _changed(() => s.mode = v),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SizeTransition(sizeFactor: a, axisAlignment: -1, child: child)),
          child: KeyedSubtree(
            key: ValueKey(s.mode),
            child: switch (s.mode) {
              LabDataMode.product => _productGroup(p),
              LabDataMode.batch => _batchGroup(p, total),
              LabDataMode.manual => const SizedBox(width: double.infinity),
            },
          ),
        ),
        LabGroup(
          title: s.mode == LabDataMode.manual ? 'Values' : 'Extra values',
          children: [
            if (s.mode != LabDataMode.manual)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('Filled values replace the product\'s own, e.g. batch and expiry.', style: TextStyle(fontSize: 12, color: p.label)),
              ),
            for (final f in kLabelMergeFields)
              if (f.key != 'date')
                FormLabel(
                  label: widget.usedFields.contains(f.key) ? '${f.label} · used' : f.label,
                  child: SyncedField(
                    key: ValueKey('mf-${f.key}'),
                    value: s.manual[f.key] ?? '',
                    hint: '{${f.key}}',
                    numeric: f.key == 'price' || f.key == 'mrp',
                    onChanged: (v) => _changed(() => s.manual[f.key] = v),
                  ),
                ),
          ],
        ),
      ],
    );
  }

  Widget _productGroup(MarketPalette p) {
    final product = s.product;
    return LabGroup(title: 'Product', children: [
      if (product != null) ...[
        InfoRow('Name', product.name, emphasize: true),
        InfoRow('SKU', product.sku ?? '—'),
        InfoRow('Barcode', productLabelData(product, s.packaging)['barcode']!.isEmpty ? '—' : productLabelData(product, s.packaging)['barcode']!),
        InfoRow('Price', money(product.price * (s.packaging?.unitQty ?? 1))),
        const SizedBox(height: 8),
        PickerField(
          value: s.packaging?.id ?? 0,
          allowClear: false,
          icon: Icons.inventory_2_outlined,
          options: [
            const PickOption(0, 'Base unit'),
            for (final pk in _LabCatalog.forProduct(product.id)) PickOption(pk.id, pk.name, sub: pk.barcode),
          ],
          onChanged: (v) => _changed(() => s.packaging = _LabCatalog.forProduct(product.id).where((pk) => pk.id == v).firstOrNull),
        ),
        const SizedBox(height: 10),
      ],
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.brand,
          side: BorderSide(color: p.line),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: _loading
            ? null
            : () async {
                final picked = await _pickProduct();
                if (picked != null) {
                  _changed(() {
                    s.product = picked;
                    s.packaging = null;
                  });
                }
              },
        icon: const Icon(Icons.search_rounded, size: 18),
        label: Text(product == null ? 'Choose product' : 'Change product'),
      ),
      const SizedBox(height: 12),
    ]);
  }

  Widget _batchGroup(MarketPalette p, int total) {
    return LabGroup(
      title: 'Batch',
      trailing: StatusPill('$total labels', tone: total > 0 ? MarketTone.brand : MarketTone.neutral),
      children: [
        if (s.batch.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Add products and set how many labels each one needs.', style: TextStyle(fontSize: 12.5, color: p.label)),
          ),
        for (var i = 0; i < s.batch.length; i++)
          FadeSlideIn(
            key: ObjectKey(s.batch[i]),
            index: i,
            offsetY: 8,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
              child: Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final entry = s.batch[i];
                      final pk = await _pickPackaging(entry.product, entry.packaging);
                      _changed(() => entry.packaging = pk);
                    },
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.batch[i].product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                      Text(s.batch[i].packaging?.name ?? 'Base unit · tap to change', style: TextStyle(fontSize: 11.5, color: p.label)),
                    ]),
                  ),
                ),
                LabStepper(value: s.batch[i].copies, min: 1, max: 999, onChanged: (v) => _changed(() => s.batch[i].copies = v)),
                IconButton(
                  tooltip: 'Remove',
                  icon: Icon(Icons.close_rounded, size: 18, color: p.error),
                  onPressed: () => _changed(() => s.batch.removeAt(i)),
                ),
              ]),
            ),
          ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: p.brand,
            side: BorderSide(color: p.line),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _loading
              ? null
              : () async {
                  final picked = await _pickProduct();
                  if (picked != null) _changed(() => s.batch.add(LabBatchEntry(picked)));
                },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add product'),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
