import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/utils/currency.dart';
import '../../../sell/market/presentation/banners/form_kit.dart' show marketInput;
import '../../data/document_models.dart';
import '../../data/store_lookup_service.dart';
import '../../data/store_product_model.dart';
import '../../data/store_util.dart' show toNum;
import 'product_picker_sheet.dart';
import 'store_ui.dart';

/// Which optional per-line fields this document uses — MRR shows unit price
/// + batch, SPR shows estimated price, Returns show a reason, etc. (see
/// `DocumentLine`'s shared-shape comment).
class LineFieldsConfig {
  final bool showUnitPrice;
  final bool showEstimatedPrice;
  final bool showBatch;
  final bool showReason;
  final bool showRemarks;
  const LineFieldsConfig({
    this.showUnitPrice = false,
    this.showEstimatedPrice = false,
    this.showBatch = false,
    this.showReason = false,
    this.showRemarks = false,
  });
}

/// The other POS-friendly centerpiece: a product-line list with big quantity
/// steppers, swipe-to-delete rows, a searchable image-tile product picker
/// ("Add item"), and an inline barcode-scan button that resolves a scanned
/// code against the preloaded product/packaging list and adds-or-increments
/// a line — entirely self-contained on mobile, no desktop socket relay
/// needed (unlike the legacy `MrrScannerPage` remote-relay flow).
class LineItemsEditor extends StatefulWidget {
  final List<DocumentLine> lines;
  final ValueChanged<List<DocumentLine>> onChanged;
  final List<StoreProduct> products;
  final List<StorePackaging> packagings;
  final List<Map<String, dynamic>> batchRows; // raw store_product_batches rows, filtered per product
  final LineFieldsConfig fieldsConfig;

  const LineItemsEditor({
    super.key,
    required this.lines,
    required this.onChanged,
    required this.products,
    this.packagings = const [],
    this.batchRows = const [],
    this.fieldsConfig = const LineFieldsConfig(),
  });

  @override
  State<LineItemsEditor> createState() => _LineItemsEditorState();
}

class _LineItemsEditorState extends State<LineItemsEditor> {
  void _emit() => widget.onChanged(widget.lines);

  Future<void> _addFromPicker() async {
    final product = await showProductPickerSheet(context, products: widget.products);
    if (product == null) return;
    _addOrIncrement(product.id, product.name, defaultUnitPrice: product.costPrice ?? product.price);
  }

  void _addOrIncrement(int productId, String productName, {double? defaultUnitPrice}) {
    final existing = widget.lines.where((l) => l.productId == productId && l.batchId == null).toList();
    if (existing.isNotEmpty) {
      setState(() => existing.first.quantity += 1);
    } else {
      setState(() => widget.lines.add(DocumentLine(
            productId: productId,
            productName: productName,
            quantity: 1,
            unitPrice: widget.fieldsConfig.showUnitPrice ? defaultUnitPrice : null,
            estimatedPrice: widget.fieldsConfig.showEstimatedPrice ? defaultUnitPrice : null,
          )));
    }
    _emit();
  }

  Future<void> _scanBarcode() async {
    final controller = MobileScannerController();
    var handled = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      clipBehavior: Clip.antiAlias,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.7,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: controller,
              onDetect: (capture) {
                if (handled) return;
                final code = capture.barcodes.firstOrNull?.rawValue;
                if (code == null || code.isEmpty) return;
                handled = true;
                Navigator.of(sheetContext).pop();
                _resolveScannedCode(code);
              },
            ),
            // Camera overlay — plain white on translucent black over the feed.
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
                  child: const Text('Point the camera at a barcode', style: TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.45)),
                icon: const Icon(Icons.close, color: Colors.white),
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
    final packaging = widget.packagings.where((p) => p.barcode == code).toList();
    if (packaging.isNotEmpty) {
      final product = widget.products.where((p) => p.id == packaging.first.productId).toList();
      final name = product.isNotEmpty ? product.first.name : 'Product #${packaging.first.productId}';
      _addOrIncrement(packaging.first.productId, name, defaultUnitPrice: product.isNotEmpty ? (product.first.costPrice ?? product.first.price) : null);
      return;
    }
    final product = widget.products.where((p) => p.barcode == code).toList();
    if (product.isNotEmpty) {
      _addOrIncrement(product.first.id, product.first.name, defaultUnitPrice: product.first.costPrice ?? product.first.price);
      return;
    }
    if (mounted) marketToast(context, 'No product matches barcode "$code".', error: true);
  }

  void _removeAt(int index) {
    setState(() => widget.lines.removeAt(index));
    _emit();
  }

  void _updateQuantity(DocumentLine line, double next) {
    if (next <= 0) return;
    setState(() => line.quantity = next);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final cfg = widget.fieldsConfig;
    final showsPrice = cfg.showUnitPrice || cfg.showEstimatedPrice;
    final total = widget.lines.fold<double>(0, (s, l) => s + l.quantity * ((cfg.showUnitPrice ? l.unitPrice : l.estimatedPrice) ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.brand,
                    backgroundColor: p.card,
                    side: BorderSide(color: p.brand.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _addFromPicker,
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add item'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: p.brandSoft,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _scanBarcode,
                icon: Icon(Icons.qr_code_scanner, color: p.brand),
                tooltip: 'Scan barcode',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (widget.lines.isEmpty)
          MarketCard(
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
            child: Column(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: p.brandSoft, shape: BoxShape.circle),
                child: Icon(Icons.inventory_2_outlined, size: 22, color: p.brand),
              ),
              const SizedBox(height: 10),
              Text('No items yet', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
              const SizedBox(height: 3),
              Text('Add a product or scan a barcode.', style: TextStyle(fontSize: 12.5, color: p.label)),
            ]),
          )
        else ...[
          for (var index = 0; index < widget.lines.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LineRow(
                key: ValueKey(identityHashCode(widget.lines[index])),
                index: index,
                line: widget.lines[index],
                fieldsConfig: cfg,
                batchOptions: cfg.showBatch
                    ? toOptions(widget.batchRows.where((b) => toNum(b['product_id']) == widget.lines[index].productId).toList(), labelField: 'batch_no')
                    : const [],
                onIncrement: () => _updateQuantity(widget.lines[index], widget.lines[index].quantity + 1),
                onDecrement: () => _updateQuantity(widget.lines[index], widget.lines[index].quantity - 1),
                onQuantityText: (v) => _updateQuantity(widget.lines[index], double.tryParse(v) ?? widget.lines[index].quantity),
                onRemove: () => _removeAt(index),
                onFieldChanged: () => setState(_emit),
                onBatchSelected: (option) => setState(() {
                  widget.lines[index].batchId = option?.id;
                  widget.lines[index].batchLabel = option?.label;
                  _emit();
                }),
              ),
            ),
          if (showsPrice)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(children: [
                Expanded(child: Text(cfg.showUnitPrice ? 'Total value' : 'Estimated total', style: TextStyle(fontSize: 12.5, color: p.label))),
                Text(money(total), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
              ]),
            ),
        ],
      ],
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _LineRow extends StatelessWidget {
  final int index;
  final DocumentLine line;
  final LineFieldsConfig fieldsConfig;
  final List<LookupOption> batchOptions;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final ValueChanged<String> onQuantityText;
  final VoidCallback onRemove;
  final VoidCallback onFieldChanged;
  final ValueChanged<LookupOption?> onBatchSelected;

  const _LineRow({
    super.key,
    required this.index,
    required this.line,
    required this.fieldsConfig,
    required this.batchOptions,
    required this.onIncrement,
    required this.onDecrement,
    required this.onQuantityText,
    required this.onRemove,
    required this.onFieldChanged,
    required this.onBatchSelected,
  });

  Widget _priceField(BuildContext context, MarketPalette p, {required String hint, required double? value, required ValueChanged<double?> onValue}) =>
      TextFormField(
        initialValue: value?.toString() ?? '',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(fontSize: 13.5, color: p.text),
        decoration: marketInput(context, hint: hint, prefixText: '${currencySymbol()} '),
        onChanged: (v) {
          onValue(double.tryParse(v));
          onFieldChanged();
        },
      );

  Widget _textField(BuildContext context, MarketPalette p,
          {required String hint, required IconData icon, required String? value, required ValueChanged<String?> onValue}) =>
      TextFormField(
        initialValue: value ?? '',
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(fontSize: 13.5, color: p.text),
        decoration: marketInput(context, hint: hint, prefixIcon: Icon(icon, size: 18, color: p.label)),
        onChanged: (v) {
          onValue(v.trim().isEmpty ? null : v.trim());
          onFieldChanged();
        },
      );

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final cfg = fieldsConfig;
    final price = cfg.showUnitPrice ? line.unitPrice : (cfg.showEstimatedPrice ? line.estimatedPrice : null);

    return Dismissible(
      key: key!,
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: p.errorBg, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('Remove', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.error)),
          const SizedBox(width: 6),
          Icon(Icons.delete_outline, color: p.error),
        ]),
      ),
      onDismissed: (_) => onRemove(),
      child: MarketCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.only(top: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(7)),
                  child: Text('${index + 1}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.brand)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(line.productName,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: p.text)),
                    if (price != null) ...[
                      const SizedBox(height: 2),
                      Text('${money(price)} each · ${money(price * line.quantity)}', style: TextStyle(fontSize: 11.5, color: p.label)),
                    ],
                  ]),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove',
                  onPressed: onRemove,
                  icon: Icon(Icons.close, size: 18, color: p.label),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                children: [
                  _QuantityStepper(quantity: line.quantity, onIncrement: onIncrement, onDecrement: onDecrement, onText: onQuantityText),
                  if (cfg.showUnitPrice || cfg.showEstimatedPrice) const SizedBox(width: 10),
                  if (cfg.showUnitPrice)
                    Expanded(child: _priceField(context, p, hint: 'Unit price', value: line.unitPrice, onValue: (v) => line.unitPrice = v)),
                  if (cfg.showEstimatedPrice)
                    Expanded(child: _priceField(context, p, hint: 'Est. price', value: line.estimatedPrice, onValue: (v) => line.estimatedPrice = v)),
                ],
              ),
            ),
            if (cfg.showBatch) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: DropdownButtonFormField<int>(
                  initialValue: batchOptions.any((o) => o.id == line.batchId) ? line.batchId : null,
                  isExpanded: true,
                  dropdownColor: p.card,
                  style: TextStyle(fontSize: 13.5, color: p.text),
                  icon: Icon(Icons.expand_more, color: p.label),
                  decoration: marketInput(
                    context,
                    hint: batchOptions.isEmpty ? 'No batches for this product' : 'Batch',
                    prefixIcon: Icon(Icons.qr_code_2, size: 18, color: p.label),
                  ),
                  items: batchOptions.map((o) => DropdownMenuItem(value: o.id, child: Text(o.label, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => onBatchSelected(v == null ? null : batchOptions.firstWhere((o) => o.id == v)),
                ),
              ),
            ],
            if (cfg.showReason) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _textField(context, p, hint: 'Reason', icon: Icons.help_outline, value: line.reason, onValue: (v) => line.reason = v),
              ),
            ],
            if (cfg.showRemarks) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _textField(context, p, hint: 'Remarks', icon: Icons.notes_outlined, value: line.remarks, onValue: (v) => line.remarks = v),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  final double quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final ValueChanged<String> onText;
  const _QuantityStepper({required this.quantity, required this.onIncrement, required this.onDecrement, required this.onText});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final display = quantity == quantity.roundToDouble() ? quantity.round().toString() : quantity.toStringAsFixed(2);
    final canDecrement = quantity - 1 > 0;
    return Container(
      height: 44,
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepButton(p, Icons.remove, canDecrement ? onDecrement : null),
          InkWell(
            onTap: () => _editQuantity(context, display),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              constraints: const BoxConstraints(minWidth: 40),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: Text(display, key: ValueKey(display), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: p.text)),
              ),
            ),
          ),
          _stepButton(p, Icons.add, onIncrement),
        ],
      ),
    );
  }

  Future<void> _editQuantity(BuildContext context, String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quantity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: marketInput(dialogContext, hint: 'Quantity'),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text), child: const Text('Set')),
        ],
      ),
    );
    if (result != null) onText(result);
  }

  Widget _stepButton(MarketPalette p, IconData icon, VoidCallback? onTap) => SizedBox(
        width: 40,
        height: 42,
        child: IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
          icon: Icon(icon, size: 18, color: onTap == null ? p.line : p.brand),
        ),
      );
}
