import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/network/http_client.dart';
import '../../data/market_seller_service.dart';
import '../widgets/market_ui.dart';
import 'flash_sale_widgets.dart';

class _ItemRow {
  final int listingId;
  Map<String, dynamic>? listing;
  final int soldCount;
  final TextEditingController price;
  final TextEditingController stock;
  final TextEditingController perOrder;
  _ItemRow({required this.listingId, this.listing, this.soldCount = 0, String price = '', String stock = '', String perOrder = ''})
      : price = TextEditingController(text: price),
        stock = TextEditingController(text: stock),
        perOrder = TextEditingController(text: perOrder);

  double get listPrice => toDouble(listing?['price']);

  void dispose() {
    price.dispose();
    stock.dispose();
    perOrder.dispose();
  }
}

String _numText(dynamic v) {
  if (v == null || '$v'.isEmpty) return '';
  final d = toDouble(v);
  return d == d.roundToDouble() ? d.toInt().toString() : '$d';
}

/// Full-screen create / edit form for a flash sale. Pops `true` after a
/// save or delete so the list reloads.
class FlashSaleEditorPage extends StatefulWidget {
  final Map<String, dynamic>? sale;
  const FlashSaleEditorPage({super.key, this.sale});

  @override
  State<FlashSaleEditorPage> createState() => _FlashSaleEditorPageState();
}

class _FlashSaleEditorPageState extends State<FlashSaleEditorPage> {
  final _api = MarketSellerService();
  late final _name = TextEditingController(text: '${widget.sale?['name'] ?? ''}');
  late final _desc = TextEditingController(text: '${widget.sale?['description'] ?? ''}');
  late bool _active = widget.sale == null ? true : widget.sale!['is_active'] == true;
  late DateTime? _starts = parseDate(widget.sale?['starts_at']);
  late DateTime? _ends = parseDate(widget.sale?['ends_at']);
  final List<_ItemRow> _items = [];

  List<Map<String, dynamic>> _listings = [];
  bool _loadingListings = true;
  bool _saving = false;
  bool _tried = false;

  bool get _isEdit => widget.sale?['id'] != null;

  @override
  void initState() {
    super.initState();
    final items = widget.sale?['items'];
    if (items is List) {
      for (final raw in items.whereType<Map>()) {
        final i = Map<String, dynamic>.from(raw);
        _items.add(_ItemRow(
          listingId: toInt(i['listing_id']),
          listing: i['listing'] is Map ? Map<String, dynamic>.from(i['listing'] as Map) : null,
          soldCount: toInt(i['sold_count']),
          price: _numText(i['sale_price']),
          stock: _numText(i['stock_limit']),
          perOrder: _numText(i['per_order_limit']),
        ));
      }
    }
    _loadListings();
  }

  Future<void> _loadListings() async {
    try {
      final list = await _api.listings();
      if (!mounted) return;
      final byId = {for (final l in list) toInt(l['id']): l};
      setState(() {
        _listings = list;
        for (final r in _items) {
          final fresh = byId[r.listingId];
          if (fresh != null) r.listing = {...?r.listing, ...fresh};
        }
      });
    } on ApiException catch (e) {
      if (mounted) marketToast(context, e.message, error: true);
    } catch (_) {
      if (mounted) marketToast(context, 'Could not load your listings', error: true);
    } finally {
      if (mounted) setState(() => _loadingListings = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    for (final r in _items) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _addListings() async {
    if (_loadingListings) {
      marketToast(context, 'Loading your listings…');
      return;
    }
    final existing = _items.map((r) => r.listingId).toSet();
    final picked = await pickListingsSheet(context, listings: _listings, locked: existing, title: 'Add listings', confirmLabel: 'Add');
    if (picked == null || !mounted) return;
    final byId = {for (final l in _listings) toInt(l['id']): l};
    setState(() {
      for (final id in picked.difference(existing)) {
        _items.add(_ItemRow(listingId: id, listing: byId[id]));
      }
    });
  }

  void _remove(_ItemRow r) {
    setState(() => _items.remove(r));
    r.dispose();
  }

  String? _priceError(_ItemRow r) {
    final t = r.price.text.trim();
    if (t.isEmpty) return _tried ? 'Enter a sale price' : null;
    final v = double.tryParse(t);
    if (v == null || v <= 0) return 'Enter a price above zero';
    if (r.listPrice > 0 && v >= r.listPrice) return 'Must be below ${money(r.listPrice)}';
    return null;
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Name is required';
    if (_starts == null || _ends == null) return 'Pick a start and end time';
    if (!_ends!.isAfter(_starts!)) return 'End time must be after the start time';
    if (_items.isEmpty) return 'Add at least one listing';
    for (final r in _items) {
      final title = '${r.listing?['title'] ?? 'every listing'}';
      final v = double.tryParse(r.price.text.trim());
      if (v == null || v <= 0) return 'Enter a sale price for $title';
      if (r.listPrice > 0 && v >= r.listPrice) return 'The sale price for $title must be below its price';
    }
    return null;
  }

  int? _intOrNull(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _tried = true);
    final err = _validate();
    if (err != null) {
      marketToast(context, err, error: true);
      return;
    }
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'starts_at': _starts!.toUtc().toIso8601String(),
      'ends_at': _ends!.toUtc().toIso8601String(),
      'is_active': _active,
      'items': [
        for (final r in _items)
          {
            'listing_id': r.listingId,
            'sale_price': double.parse(r.price.text.trim()),
            'stock_limit': _intOrNull(r.stock),
            'per_order_limit': _intOrNull(r.perOrder),
          },
      ],
    };
    setState(() => _saving = true);
    try {
      await _api.saveFlashSale(body, id: _isEdit ? toInt(widget.sale!['id']) : null);
      if (!mounted) return;
      marketToast(context, _isEdit ? 'Flash sale updated' : 'Flash sale created');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) marketToast(context, e.message, error: true);
    } catch (_) {
      if (mounted) marketToast(context, 'Could not save flash sale', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmMarket(context,
        title: 'Delete flash sale', message: 'Delete "${widget.sale?['name'] ?? ''}"? Its sale prices stop applying right away.');
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await _api.deleteFlashSale(toInt(widget.sale!['id']));
      if (!mounted) return;
      marketToast(context, 'Flash sale deleted');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) marketToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final endsErr = _tried && _starts != null && _ends != null && !_ends!.isAfter(_starts!) ? 'Must be after the start' : null;
    return MarketScaffold(
      title: _isEdit ? 'Edit flash sale' : 'New flash sale',
      actions: [
        if (_isEdit) IconButton(tooltip: 'Delete', icon: Icon(Icons.delete_outline, color: p.error), onPressed: _saving ? null : _delete),
      ],
      bottom: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel'))),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _saving
                      ? const SizedBox(key: ValueKey('s'), width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_isEdit ? 'Save changes' : 'Create sale', key: const ValueKey('t')),
                ),
              ),
            ),
          ]),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          FadeSlideIn(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SectionHeader('Details'),
              MarketCard(
                child: Column(children: [
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      hintText: 'e.g. Weekend deals',
                      errorText: _tried && _name.text.trim().isEmpty ? 'Name is required' : null,
                    ),
                    onChanged: (_) => _tried ? setState(() {}) : null,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _desc,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Description (optional)'),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                    title: Text('Active', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                    subtitle: Text('Turn off to pause the sale without deleting it', style: TextStyle(fontSize: 12, color: p.label)),
                  ),
                ]),
              ),
            ]),
          ),
          FadeSlideIn(
            index: 1,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SectionHeader('Schedule'),
              MarketCard(
                child: Column(children: [
                  DateTimeField(
                    label: 'Starts',
                    value: _starts,
                    errorText: _tried && _starts == null ? 'Pick a start time' : null,
                    onChanged: (v) => setState(() => _starts = v),
                  ),
                  const SizedBox(height: 12),
                  DateTimeField(
                    label: 'Ends',
                    value: _ends,
                    errorText: _tried && _ends == null ? 'Pick an end time' : endsErr,
                    onChanged: (v) => setState(() => _ends = v),
                  ),
                ]),
              ),
            ]),
          ),
          FadeSlideIn(
            index: 2,
            child: SectionHeader(
              'Items',
              subtitle: _items.isEmpty ? 'Add the listings this sale discounts' : '${_items.length} listing${_items.length == 1 ? '' : 's'}',
              trailing: TextButton.icon(onPressed: _addListings, icon: const Icon(Icons.add, size: 18), label: const Text('Add')),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _items.isEmpty
                ? MarketCard(
                    onTap: _addListings,
                    borderColor: _tried ? p.error : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Column(children: [
                        Icon(Icons.add_shopping_cart_outlined, color: p.brand, size: 28),
                        const SizedBox(height: 8),
                        Text('Add listings', style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
                        const SizedBox(height: 2),
                        Text('Pick from your market listings', style: TextStyle(fontSize: 12, color: p.label)),
                      ]),
                    ),
                  )
                : Column(children: [
                    for (var i = 0; i < _items.length; i++)
                      Padding(
                        key: ObjectKey(_items[i]),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: FadeSlideIn(index: i, child: _itemCard(_items[i])),
                      ),
                  ]),
          ),
        ],
      ),
    );
  }

  Widget _itemCard(_ItemRow r) {
    final p = MarketPalette.of(context);
    final err = _priceError(r);
    final v = double.tryParse(r.price.text.trim());
    final off = v != null && r.listPrice > 0 && v > 0 && v < r.listPrice ? ((1 - v / r.listPrice) * 100).round() : null;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return MarketCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      child: Column(children: [
        Row(children: [
          MarketThumb(url: listingThumb(r.listing), size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r.listing?['title'] ?? 'Listing #${r.listingId}'}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
              const SizedBox(height: 2),
              Text(
                [
                  'List price ${r.listing == null ? '—' : money(r.listPrice)}',
                  if (r.soldCount > 0) '${r.soldCount} sold',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: p.label),
              ),
            ]),
          ),
          IconButton(tooltip: 'Remove', icon: Icon(Icons.close, size: 20, color: p.label), onPressed: () => _remove(r)),
        ]),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(children: [
            TextField(
              controller: r.price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Sale price',
                isDense: true,
                errorText: err,
                suffixIcon: off == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Center(widthFactor: 1, child: StatusPill('$off% off', tone: MarketTone.ok)),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: r.stock,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  decoration: const InputDecoration(labelText: 'Stock limit', hintText: 'No limit', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: r.perOrder,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  decoration: const InputDecoration(labelText: 'Per order', hintText: 'No limit', isDense: true),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
