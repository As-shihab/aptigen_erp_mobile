import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/network/http_client.dart';
import '../../data/market_seller_service.dart';
import '../flash_sales/flash_sale_widgets.dart';
import '../widgets/market_ui.dart';
import 'promotion_utils.dart';

String _numText(dynamic v) {
  if (v == null || '$v'.isEmpty) return '';
  final d = toDouble(v);
  return d == d.roundToDouble() ? d.toInt().toString() : '$d';
}

/// Full-screen create / edit form for a coupon code or automatic discount.
/// Pops `true` after a save.
class PromotionEditorPage extends StatefulWidget {
  final Map<String, dynamic>? promotion;
  const PromotionEditorPage({super.key, this.promotion});

  @override
  State<PromotionEditorPage> createState() => _PromotionEditorPageState();
}

class _PromotionEditorPageState extends State<PromotionEditorPage> {
  final _api = MarketSellerService();
  Map<String, dynamic> get _src => widget.promotion ?? const {};
  bool get _isEdit => _src['id'] != null;

  late String _kind = _isEdit ? (isCoupon(_src) ? 'coupon' : 'automatic') : 'coupon';
  late final _name = TextEditingController(text: '${_src['name'] ?? ''}');
  late final _code = TextEditingController(text: _isEdit ? '${_src['code'] ?? ''}' : generateCouponCode());
  late final _desc = TextEditingController(text: '${_src['description'] ?? ''}');
  late String _discountType = '${_src['discount_type'] ?? 'percent'}';
  late final _value = TextEditingController(text: _numText(_src['value']));
  late final _maxDiscount = TextEditingController(text: _numText(_src['max_discount']));
  late final _minOrder = TextEditingController(text: toDouble(_src['min_order']) > 0 ? _numText(_src['min_order']) : '');
  late String _appliesTo = _src['applies_to'] == 'listings' ? 'listings' : 'all';
  late Set<int> _listingIds = parseListingIds(_src['listing_ids']).toSet();
  late final _usageLimit = TextEditingController(text: _numText(_src['usage_limit']));
  late final _perUser = TextEditingController(text: _numText(_src['per_user_limit']));
  late DateTime? _starts = parseDate(_src['starts_at']);
  late DateTime? _ends = parseDate(_src['ends_at']);
  late bool _active = _isEdit ? _src['is_active'] == true : true;

  List<Map<String, dynamic>> _listings = [];
  bool _loadingListings = true;
  bool _saving = false;
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    if (_discountType != 'percent' && _discountType != 'fixed' && _discountType != 'free_shipping') _discountType = 'percent';
    _loadListings();
  }

  Future<void> _loadListings() async {
    try {
      final list = await _api.listings();
      if (mounted) setState(() => _listings = list);
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
    for (final c in [_name, _code, _desc, _value, _maxDiscount, _minOrder, _usageLimit, _perUser]) {
      c.dispose();
    }
    super.dispose();
  }

  num? _numOrNull(TextEditingController c) => c.text.trim().isEmpty ? null : num.tryParse(c.text.trim());

  String? get _valueError {
    if (_discountType == 'free_shipping') return null;
    final t = _value.text.trim();
    if (t.isEmpty) return _tried ? 'Enter a value' : null;
    final v = double.tryParse(t);
    if (v == null || v <= 0) return 'Enter a value above zero';
    if (_discountType == 'percent' && v > 100) return 'Cannot be above 100';
    return null;
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Name is required';
    if (_kind == 'coupon' && _code.text.trim().isEmpty) return 'Enter a coupon code or generate one';
    if (_discountType != 'free_shipping') {
      final v = double.tryParse(_value.text.trim());
      if (v == null || v <= 0) return 'Enter a discount value above zero';
      if (_discountType == 'percent' && v > 100) return 'A percentage discount cannot be above 100';
    }
    if (_appliesTo == 'listings' && _listingIds.isEmpty) return 'Pick at least one listing';
    if (_starts != null && _ends != null && !_ends!.isAfter(_starts!)) return 'End time must be after the start time';
    return null;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _tried = true);
    final err = _validate();
    if (err != null) {
      marketToast(context, err, error: true);
      return;
    }
    final code = _code.text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'code': _kind == 'coupon' ? code : null,
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'discount_type': _discountType,
      'value': _discountType == 'free_shipping' ? 0 : num.parse(_value.text.trim()),
      'max_discount': _discountType == 'percent' ? _numOrNull(_maxDiscount) : null,
      'min_order': _numOrNull(_minOrder) ?? 0,
      'applies_to': _appliesTo,
      'listing_ids': _appliesTo == 'listings' ? jsonEncode(_listingIds.toList()..sort()) : null,
      'usage_limit': _numOrNull(_usageLimit)?.toInt(),
      'per_user_limit': _numOrNull(_perUser)?.toInt(),
      'starts_at': _starts?.toUtc().toIso8601String(),
      'ends_at': _ends?.toUtc().toIso8601String(),
      'is_active': _active,
    };
    setState(() => _saving = true);
    try {
      await _api.savePromotion(body, id: _isEdit ? toInt(_src['id']) : null);
      if (!mounted) return;
      marketToast(context, _isEdit ? 'Promotion updated' : 'Promotion created');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      final dup = RegExp(r'unique|already exists|already in use|duplicate', caseSensitive: false).hasMatch(e.message);
      marketToast(context, dup ? 'That coupon code is already in use' : e.message, error: true);
    } catch (_) {
      if (mounted) marketToast(context, 'Could not save promotion', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseListings() async {
    if (_loadingListings) {
      marketToast(context, 'Loading your listings…');
      return;
    }
    final picked = await pickListingsSheet(context, listings: _listings, selected: _listingIds, title: 'Applies to listings');
    if (picked != null && mounted) setState(() => _listingIds = picked);
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final decimals = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final byId = {for (final l in _listings) toInt(l['id']): l};

    Widget section(int i, String title, Widget child, {String? subtitle}) => FadeSlideIn(
          index: i,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeader(title, subtitle: subtitle),
            MarketCard(child: child),
          ]),
        );

    return MarketScaffold(
      title: _isEdit ? 'Edit promotion' : 'New promotion',
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
                      : Text(_isEdit ? 'Save changes' : 'Create promotion', key: const ValueKey('t')),
                ),
              ),
            ),
          ]),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          section(
            0,
            'Type',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MarketSegmented<String>(
                value: _kind,
                onChanged: (v) => setState(() => _kind = v),
                options: const [
                  (id: 'coupon', label: 'Coupon code', count: null),
                  (id: 'automatic', label: 'Automatic', count: null),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _kind == 'coupon'
                    ? 'Buyers enter the code at checkout.'
                    : 'Applied automatically to eligible carts. Buyers get the single best offer from your store.',
                style: TextStyle(fontSize: 12, color: p.label, height: 1.4),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _kind != 'coupon'
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            child: TextField(
                              controller: _code,
                              inputFormatters: [CouponCodeFormatter(), LengthLimitingTextInputFormatter(40)],
                              textCapitalization: TextCapitalization.characters,
                              autocorrect: false,
                              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700),
                              onChanged: (_) => _tried ? setState(() {}) : null,
                              decoration: InputDecoration(
                                labelText: 'Code',
                                errorText: _tried && _code.text.trim().isEmpty ? 'Enter a code' : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: OutlinedButton.icon(
                              onPressed: () => setState(() => _code.text = generateCouponCode()),
                              icon: const Icon(Icons.casino_outlined, size: 18),
                              label: const Text('Generate'),
                            ),
                          ),
                        ]),
                      ),
              ),
            ]),
          ),
          section(
            1,
            'Details',
            Column(children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => _tried ? setState(() {}) : null,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Eid offer',
                  errorText: _tried && _name.text.trim().isEmpty ? 'Name is required' : null,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _desc,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
              ),
            ]),
          ),
          section(
            2,
            'Discount',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MarketSegmented<String>(
                value: _discountType,
                onChanged: (v) => setState(() => _discountType = v),
                options: const [
                  (id: 'percent', label: 'Percentage', count: null),
                  (id: 'fixed', label: 'Fixed amount', count: null),
                  (id: 'free_shipping', label: 'Free shipping', count: null),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _discountType == 'free_shipping'
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: Text('Shipping is waived on eligible orders from your store.', style: TextStyle(fontSize: 12, color: p.label)),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            child: TextField(
                              controller: _value,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: decimals,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: _discountType == 'percent' ? 'Percent off' : 'Amount off',
                                suffixText: _discountType == 'percent' ? '%' : null,
                                errorText: _valueError,
                              ),
                            ),
                          ),
                          if (_discountType == 'percent') ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _maxDiscount,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: decimals,
                                decoration: const InputDecoration(labelText: 'Max discount', hintText: 'No cap'),
                              ),
                            ),
                          ],
                        ]),
                      ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _minOrder,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: decimals,
                decoration: const InputDecoration(labelText: 'Minimum order', hintText: 'None'),
              ),
            ]),
          ),
          section(
            3,
            'Applies to',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MarketSegmented<String>(
                value: _appliesTo,
                onChanged: (v) => setState(() => _appliesTo = v),
                options: const [
                  (id: 'all', label: 'All listings', count: null),
                  (id: 'listings', label: 'Selected listings', count: null),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _appliesTo != 'listings'
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          OutlinedButton.icon(
                            style: _tried && _listingIds.isEmpty ? OutlinedButton.styleFrom(foregroundColor: p.error, side: BorderSide(color: p.error)) : null,
                            onPressed: _chooseListings,
                            icon: const Icon(Icons.checklist, size: 18),
                            label: Text(_listingIds.isEmpty ? 'Choose listings' : '${_listingIds.length} selected · change'),
                          ),
                          if (_listingIds.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(spacing: 6, runSpacing: 6, children: [
                              for (final id in _listingIds)
                                InputChip(
                                  label: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 200),
                                    child: Text('${byId[id]?['title'] ?? 'Listing #$id'}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                  avatar: byId[id] == null ? null : MarketThumb(url: listingThumb(byId[id]), size: 22),
                                  onDeleted: () => setState(() => _listingIds = {..._listingIds}..remove(id)),
                                ),
                            ]),
                          ],
                        ]),
                      ),
              ),
            ]),
          ),
          section(
            4,
            'Limits',
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _usageLimit,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  decoration: const InputDecoration(labelText: 'Usage limit', hintText: 'Unlimited'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _perUser,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  decoration: const InputDecoration(labelText: 'Per customer', hintText: 'Unlimited'),
                ),
              ),
            ]),
          ),
          section(
            5,
            'Schedule',
            subtitle: 'Leave empty to run any time',
            Column(children: [
              DateTimeField(label: 'Starts (optional)', value: _starts, clearable: true, onChanged: (v) => setState(() => _starts = v)),
              const SizedBox(height: 12),
              DateTimeField(
                label: 'Ends (optional)',
                value: _ends,
                clearable: true,
                errorText: _starts != null && _ends != null && !_ends!.isAfter(_starts!) ? 'Must be after the start' : null,
                onChanged: (v) => setState(() => _ends = v),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: Text('Active', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                subtitle: Text('Inactive promotions never apply', style: TextStyle(fontSize: 12, color: p.label)),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
