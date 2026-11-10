import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/utils/currency.dart' show currencySymbol;
import '../../../../shared/widgets/media_library_dialog.dart';
import '../../../sell/market/presentation/banners/form_kit.dart' show FieldBlock, MarketTextField, SwitchRow, marketInput;
import '../../data/store_lookup_service.dart';
import '../../data/store_product_model.dart';
import '../../data/store_product_service.dart';
import '../widgets/store_ui.dart';

/// Create/edit a `store_products` row — one scrolling form grouped into SAP
/// Horizon section cards (details, classification, pricing, stock, media,
/// visibility) with a sticky save bar. Category -> sub-category cascade
/// mirrors desktop's `ProductForm.tsx` (`handleCategorySelect` clears
/// sub_category whenever category changes).
class ProductFormPage extends StatefulWidget {
  final StoreProduct? existing;
  const ProductFormPage({super.key, this.existing});

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  final _service = StoreProductService(ApiClient());

  bool get _isEdit => widget.existing != null;

  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late final _skuController = TextEditingController(text: widget.existing?.sku ?? '');
  late final _barcodeController = TextEditingController(text: widget.existing?.barcode ?? '');
  late final _shortDescController = TextEditingController(text: widget.existing?.shortDesc ?? '');
  late final _priceController = TextEditingController(text: widget.existing != null ? widget.existing!.price.toStringAsFixed(2) : '');
  late final _comparePriceController = TextEditingController(text: widget.existing?.comparePrice?.toStringAsFixed(2) ?? '');
  late final _costPriceController = TextEditingController(text: widget.existing?.costPrice?.toStringAsFixed(2) ?? '');
  late final _stockQtyController = TextEditingController(text: widget.existing != null ? widget.existing!.stockQty.toStringAsFixed(0) : '0');
  late final _lowStockAtController = TextEditingController(text: widget.existing != null ? widget.existing!.lowStockAt.toStringAsFixed(0) : '5');

  late int? _categoryId = widget.existing?.categoryId;
  late int? _subCategoryId = widget.existing?.subCategoryId;
  late int? _uomId = widget.existing?.uomId;
  late bool _isActive = widget.existing?.isActive ?? true;
  late bool _isFeatured = widget.existing?.isFeatured ?? false;
  late bool _trackStock = widget.existing?.trackStock ?? true;
  late String? _thumbnailUrl = widget.existing?.thumbnailUrl;

  bool _lookupsLoading = true;
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _subCategories = [];
  List<Map<String, dynamic>> _uoms = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _shortDescController.dispose();
    _priceController.dispose();
    _comparePriceController.dispose();
    _costPriceController.dispose();
    _stockQtyController.dispose();
    _lowStockAtController.dispose();
    _pageScroll.dispose();
    super.dispose();
  }

  Future<void> _loadLookups() async {
    try {
      final all = await StoreLookupService(ApiClient()).loadAll();
      if (!mounted) return;
      setState(() {
        _categories = all['categories'] ?? [];
        _subCategories = all['subCategories'] ?? [];
        _uoms = all['uoms'] ?? [];
      });
    } catch (_) {
      // form still usable without lookups
    } finally {
      if (mounted) setState(() => _lookupsLoading = false);
    }
  }

  List<Map<String, dynamic>> get _visibleSubCategories {
    if (_categoryId == null) return _subCategories;
    return _subCategories.where((sc) => (sc['category_id'] as num?)?.toInt() == _categoryId).toList();
  }

  Future<void> _pickThumbnail() async {
    final picked = await showMediaLibraryDialog(context, title: 'Select thumbnail', defaultCategoryName: 'Products');
    if (picked == null || picked.isEmpty) return;
    setState(() => _thumbnailUrl = picked.first.fileUrl);
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      marketToast(context, 'Please enter a product name.', error: true);
      return;
    }
    final price = double.tryParse(_priceController.text.trim());
    if (price == null) {
      marketToast(context, 'Please enter a valid price.', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final payload = {
        'name': name,
        'sku': _skuController.text.trim().isEmpty ? null : _skuController.text.trim(),
        'barcode': _barcodeController.text.trim().isEmpty ? null : _barcodeController.text.trim(),
        'short_desc': _shortDescController.text.trim().isEmpty ? null : _shortDescController.text.trim(),
        'category_id': _categoryId,
        'sub_category_id': _subCategoryId,
        'uom_id': _uomId,
        'price': price,
        'compare_price': double.tryParse(_comparePriceController.text.trim()),
        'cost_price': double.tryParse(_costPriceController.text.trim()),
        'stock_qty': int.tryParse(_stockQtyController.text.trim()) ?? 0,
        'low_stock_at': int.tryParse(_lowStockAtController.text.trim()) ?? 5,
        'track_stock': _trackStock,
        'is_active': _isActive,
        'is_featured': _isFeatured,
        'thumbnail_url': _thumbnailUrl,
      };
      if (_isEdit) {
        await _service.update(widget.existing!.id, payload);
      } else {
        await _service.create(payload);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Could not save this product.', error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Step wizard ────────────────────────────────────────────────────────
  // Details → Pricing (classification + prices) → Stock & media → Review.
  // A name is required to leave step 1 and a valid price to leave step 2;
  // earlier steps can always be reopened from the step header.

  static const _steps = [
    (label: 'Details', icon: Icons.edit_note_outlined),
    (label: 'Pricing', icon: Icons.sell_outlined),
    (label: 'Stock', icon: Icons.inventory_outlined),
    (label: 'Review', icon: Icons.fact_check_outlined),
  ];

  int _step = 0;
  final _pageScroll = ScrollController();

  String? _stepError(int step) {
    if (step == 0 && _nameController.text.trim().isEmpty) return 'Please enter a product name.';
    if (step == 1 && double.tryParse(_priceController.text.trim()) == null) return 'Please enter a valid price.';
    return null;
  }

  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    if (step > _step) {
      for (var s = _step; s < step; s++) {
        final error = _stepError(s);
        if (error != null) {
          setState(() => _step = s);
          marketToast(context, error, error: true);
          return;
        }
      }
    }
    setState(() => _step = step);
    if (_pageScroll.hasClients) _pageScroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    var section = 0;
    Widget block(Widget child) => FadeSlideIn(index: section++, child: child);
    const decimal = TextInputType.numberWithOptions(decimal: true);
    final symbol = '${currencySymbol()} ';

    final stepBodies = <List<Widget> Function()>[
      () => [
            block(const SectionHeader('Details', subtitle: 'Name and codes used on documents and labels')),
            block(_card([
              FieldBlock(
                label: 'Product name',
                required: true,
                child: MarketTextField(controller: _nameController, hint: 'e.g. Basmati rice 5 kg', icon: Icons.inventory_2_outlined),
              ),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: FieldBlock(label: 'SKU', child: MarketTextField(controller: _skuController, hint: 'SKU', capitalization: TextCapitalization.characters))),
                const SizedBox(width: 10),
                Expanded(
                  child: FieldBlock(
                    label: 'Barcode',
                    child: MarketTextField(controller: _barcodeController, hint: 'Barcode', icon: Icons.qr_code_2_outlined, capitalization: TextCapitalization.none),
                  ),
                ),
              ]),
              FieldBlock(label: 'Short description', child: MarketTextField(controller: _shortDescController, hint: 'A line or two about this product', maxLines: 3)),
            ])),
          ],
      () => [
            block(const SectionHeader('Classification')),
            block(_card(_lookupsLoading
                ? const [
                    Padding(padding: EdgeInsets.only(bottom: 14), child: SkeletonBox(height: 44, radius: 10)),
                    Padding(padding: EdgeInsets.only(bottom: 14), child: SkeletonBox(height: 44, radius: 10)),
                    Padding(padding: EdgeInsets.only(bottom: 14), child: SkeletonBox(height: 44, radius: 10)),
                  ]
                : [
                    FieldBlock(
                      label: 'Category',
                      child: _dropdown(
                        p,
                        rows: _categories,
                        value: _categoryId,
                        hint: _categories.isEmpty ? 'No categories yet' : 'Choose a category',
                        icon: Icons.category_outlined,
                        onChanged: (v) => setState(() {
                          _categoryId = v;
                          _subCategoryId = null;
                        }),
                      ),
                    ),
                    FieldBlock(
                      label: 'Sub-category',
                      child: _dropdown(
                        p,
                        key: ValueKey('sub-category-$_categoryId'),
                        rows: _visibleSubCategories,
                        value: _subCategoryId,
                        hint: _visibleSubCategories.isEmpty ? 'No sub-categories' : 'Choose a sub-category',
                        icon: Icons.account_tree_outlined,
                        onChanged: (v) => setState(() => _subCategoryId = v),
                      ),
                    ),
                    FieldBlock(
                      label: 'Unit of measure',
                      child: _dropdown(
                        p,
                        rows: _uoms,
                        value: _uomId,
                        hint: _uoms.isEmpty ? 'No units yet' : 'Choose a unit',
                        icon: Icons.straighten_outlined,
                        onChanged: (v) => setState(() => _uomId = v),
                      ),
                    ),
                  ])),
            block(const SectionHeader('Pricing')),
            block(_card([
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: FieldBlock(
                    label: 'Price',
                    required: true,
                    child: MarketTextField(controller: _priceController, hint: '0.00', keyboardType: decimal, prefixText: symbol),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FieldBlock(
                    label: 'Compare-at price',
                    child: MarketTextField(controller: _comparePriceController, hint: '0.00', keyboardType: decimal, prefixText: symbol),
                  ),
                ),
              ]),
              FieldBlock(
                label: 'Cost price',
                help: 'Used for margins and stock value',
                child: MarketTextField(controller: _costPriceController, hint: '0.00', keyboardType: decimal, prefixText: symbol),
              ),
            ])),
          ],
      () => [
            block(const SectionHeader('Stock')),
            block(_card([
              SwitchRow(
                title: 'Track stock',
                subtitle: _trackStock ? 'Quantity changes with receipts and sales' : 'Stock is not counted for this product',
                value: _trackStock,
                onChanged: (v) => setState(() => _trackStock = v),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _trackStock
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: FieldBlock(
                            label: 'Stock quantity',
                            child: MarketTextField(controller: _stockQtyController, hint: '0', keyboardType: TextInputType.number),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FieldBlock(
                            label: 'Low-stock at',
                            child: MarketTextField(controller: _lowStockAtController, hint: '5', keyboardType: TextInputType.number),
                          ),
                        ),
                      ])
                    : const SizedBox(width: double.infinity),
              ),
            ])),
            block(const SectionHeader('Media')),
            block(_card([_mediaBlock(p)])),
          ],
      () => [
            block(const SectionHeader('Review')),
            block(_reviewCard(p)),
            block(const SectionHeader('Visibility')),
            block(_card([
              SwitchRow(
                title: 'Active',
                subtitle: _isActive ? 'Available on documents and in sales' : 'Hidden from new documents',
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              SwitchRow(
                title: 'Featured',
                subtitle: 'Highlighted in the catalogue',
                value: _isFeatured,
                onChanged: (v) => setState(() => _isFeatured = v),
              ),
            ])),
          ],
    ];

    return MarketScaffold(
      title: _isEdit ? 'Edit product' : 'New product',
      subtitle: _isEdit ? widget.existing!.name : 'Item you can stock, buy and sell',
      bottom: _saveBar(p),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(children: [
          _stepper(p),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: ListView(
                key: ValueKey(_step),
                controller: _pageScroll,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: stepBodies[_step](),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _stepper(MarketPalette p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(color: p.card, border: Border(bottom: BorderSide(color: p.line))),
      child: Row(children: [
        for (var i = 0; i < _steps.length; i++) ...[
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _submitting ? null : () => _goTo(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _step ? p.okBg : (i == _step ? p.brand : p.card),
                    border: Border.all(color: i < _step ? p.ok : (i == _step ? p.brand : p.line), width: 2),
                  ),
                  alignment: Alignment.center,
                  child: i < _step
                      ? Icon(Icons.check, size: 16, color: p.ok)
                      : Icon(_steps[i].icon, size: 15, color: i == _step ? Colors.white : p.label),
                ),
                const SizedBox(height: 4),
                Text(_steps[i].label,
                    style: TextStyle(fontSize: 11, fontWeight: i == _step ? FontWeight.w700 : FontWeight.w500, color: i == _step ? p.brand : p.label)),
              ]),
            ),
          ),
          if (i < _steps.length - 1)
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(left: 4, right: 4, bottom: 18),
                height: 2,
                color: i < _step ? p.ok : p.line,
              ),
            ),
        ],
      ]),
    );
  }

  Widget _reviewCard(MarketPalette p) {
    String nameOf(List<Map<String, dynamic>> rows, int? id) =>
        id == null ? '—' : (rows.firstWhere((r) => (r['id'] as num?)?.toInt() == id, orElse: () => const <String, dynamic>{})['name'] ?? '—').toString();
    String orDash(String v) => v.trim().isEmpty ? '—' : v.trim();
    final symbol = '${currencySymbol()} ';
    final rows = <(String, String, int)>[
      ('Name', orDash(_nameController.text), 0),
      ('SKU', orDash(_skuController.text), 0),
      ('Barcode', orDash(_barcodeController.text), 0),
      ('Category', nameOf(_categories, _categoryId), 1),
      ('Sub-category', nameOf(_subCategories, _subCategoryId), 1),
      ('Unit', nameOf(_uoms, _uomId), 1),
      ('Price', _priceController.text.trim().isEmpty ? '—' : '$symbol${_priceController.text.trim()}', 1),
      ('Cost price', _costPriceController.text.trim().isEmpty ? '—' : '$symbol${_costPriceController.text.trim()}', 1),
      ('Stock', _trackStock ? '${orDash(_stockQtyController.text)} (low at ${orDash(_lowStockAtController.text)})' : 'Not tracked', 2),
      ('Thumbnail', _thumbnailUrl != null ? 'Selected' : 'None', 2),
    ];
    return MarketCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, color: p.line),
          InkWell(
            onTap: () => _goTo(rows[i].$3),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(children: [
                SizedBox(width: 104, child: Text(rows[i].$1, style: TextStyle(fontSize: 12.5, color: p.label))),
                Expanded(
                  child: Text(rows[i].$2,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                ),
                Icon(Icons.chevron_right, size: 18, color: p.label),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _card(List<Widget> children) => MarketCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _dropdown(
    MarketPalette p, {
    Key? key,
    required List<Map<String, dynamic>> rows,
    required int? value,
    required String hint,
    required IconData icon,
    required ValueChanged<int?> onChanged,
  }) {
    return DropdownButtonFormField<int>(
      key: key,
      initialValue: rows.any((c) => (c['id'] as num).toInt() == value) ? value : null,
      isExpanded: true,
      dropdownColor: p.card,
      style: TextStyle(fontSize: 14, color: p.text),
      decoration: marketInput(context, hint: hint, prefixIcon: Icon(icon, size: 18, color: p.label)),
      items: rows.map((c) => DropdownMenuItem(value: (c['id'] as num).toInt(), child: Text((c['name'] ?? '').toString(), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _mediaBlock(MarketPalette p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line)),
            child: _thumbnailUrl != null
                ? CachedNetworkImage(
                    imageUrl: _thumbnailUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(color: p.surface),
                    errorWidget: (_, _, _) => Icon(Icons.image_not_supported_outlined, color: p.label),
                  )
                : Icon(Icons.image_outlined, size: 32, color: p.label),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Thumbnail', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(height: 2),
            Text(_thumbnailUrl != null ? 'Thumbnail selected' : 'No thumbnail selected', style: TextStyle(fontSize: 11.5, color: p.label)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, side: BorderSide(color: p.line)),
                onPressed: _pickThumbnail,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(_thumbnailUrl != null ? 'Change' : 'Browse'),
              ),
              if (_thumbnailUrl != null)
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: p.error),
                  onPressed: () => setState(() => _thumbnailUrl = null),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Remove'),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _saveBar(MarketPalette p) {
    final last = _step == _steps.length - 1;
    return Container(
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            if (_step > 0) ...[
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: _submitting ? null : () => _goTo(_step - 1),
                    child: const Text('Back'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: _submitting ? null : (last ? _submit : () => _goTo(_step + 1)),
                  icon: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(last ? (_isEdit ? Icons.check : Icons.add) : Icons.arrow_forward, size: 20),
                  label: Text(last ? (_isEdit ? 'Save changes' : 'Create product') : 'Next'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
