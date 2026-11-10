import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../../../core/network/http_client.dart';
import '../../../../../core/storage/app_storage.dart';
import '../../../../../core/utils/currency.dart';
import '../../data/market_seller_service.dart';
import '../widgets/market_ui.dart';
import 'listing_common.dart';
import 'listing_options.dart';

/// Full-screen listing wizard — mobile port of erp/desktop's
/// forms/market/CreateListing.tsx. Pops with the saved status
/// ('draft' | 'active') so the list reloads; null when cancelled.
class ListingFormPage extends StatefulWidget {
  /// Existing listing row (from `MarketSellerService.listings`) for edit mode.
  final Map<String, dynamic>? listing;

  /// City / country to suggest for a new listing (e.g. from the store's
  /// latest listing) — desktop geolocates instead.
  final String? cityHint;
  final String? countryHint;

  const ListingFormPage({super.key, this.listing, this.cityHint, this.countryHint});

  @override
  State<ListingFormPage> createState() => _ListingFormPageState();
}

class _MediaItem {
  final String key;
  String? url;
  String type; // image | video
  String name;
  Uint8List? bytes; // local preview while / after uploading
  bool uploading;
  String? error;
  _MediaItem({required this.key, this.url, required this.type, required this.name, this.bytes, this.uploading = false});
}

const _steps = [
  (label: 'Product', hint: 'Pick from your catalog'),
  (label: 'Details', hint: 'Title, category and condition'),
  (label: 'Pricing & stock', hint: 'Price, quantity and order limits'),
  (label: 'Media', hint: 'Photos and videos'),
  (label: 'Options', hint: 'Colors, sizes and stock per option'),
  (label: 'Review & publish', hint: 'Location and go live'),
];

class _ListingFormPageState extends State<ListingFormPage> {
  final _service = MarketSellerService();
  final _picker = ImagePicker();

  bool get _isEdit => widget.listing?['id'] != null;

  int _step = 0;
  bool _forward = true;
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  String? _savingStatus;

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _categories = [];
  int? _profileId;

  int? _productId;
  int? _categoryId;
  String _condition = 'new';
  String _listingType = 'fixed';
  String _currency = WorkplaceCurrency.code;
  bool _featured = false;
  DateTime? _expiresAt;
  final List<String> _tags = [];
  final List<_MediaItem> _media = [];
  String? _coverUrl;
  int _mediaSeq = 0;
  ListingOptions _options = ListingOptions();

  final _productQuery = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _compare = TextEditingController();
  final _qty = TextEditingController(text: '0');
  final _minOrder = TextEditingController(text: '1');
  final _maxOrder = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController();
  final _tagInput = TextEditingController();

  final Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _prefill();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_productQuery, _title, _description, _price, _compare, _qty, _minOrder, _maxOrder, _city, _country, _tagInput]) {
      c.dispose();
    }
    _options.dispose();
    super.dispose();
  }

  // ── Prefill / lookups ───────────────────────────────────────────────

  void _prefill() {
    final l = widget.listing;
    if (l == null) {
      _city.text = widget.cityHint ?? '';
      _country.text = widget.countryHint ?? '';
      if (_country.text.isEmpty) _workplaceCountry();
      return;
    }
    _productId = l['product_id'] == null ? null : toInt(l['product_id']);
    _profileId = l['creator_profile_id'] == null ? null : toInt(l['creator_profile_id']);
    _categoryId = l['category_id'] == null ? null : toInt(l['category_id']);
    _title.text = '${l['title'] ?? ''}';
    _description.text = '${l['description'] ?? ''}';
    _price.text = l['price'] == null ? '' : _numText(l['price']);
    _compare.text = l['compare_price'] == null ? '' : _numText(l['compare_price']);
    if ('${l['currency'] ?? ''}'.isNotEmpty) _currency = '${l['currency']}';
    _condition = conditionLabels.containsKey(l['condition']) ? '${l['condition']}' : 'new';
    _listingType = listingTypeLabels.containsKey(l['listing_type']) ? '${l['listing_type']}' : 'fixed';
    _qty.text = '${toInt(l['quantity'])}';
    _minOrder.text = '${l['min_order'] ?? 1}';
    _maxOrder.text = l['max_order'] == null ? '' : '${l['max_order']}';
    _featured = l['is_featured'] == true;
    _expiresAt = DateTime.tryParse('${l['expires_at'] ?? ''}')?.toLocal();
    _city.text = '${l['city'] ?? ''}';
    _country.text = '${l['country'] ?? ''}';
    _tags.addAll('${l['tags'] ?? ''}'.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty));
    for (final m in listingMedias(l)) {
      final url = '${m['url'] ?? ''}';
      if (url.isEmpty) continue;
      _media.add(_MediaItem(key: 'm${_mediaSeq++}', url: url, type: isVideoMedia(m) ? 'video' : 'image', name: '${m['name'] ?? ''}'));
    }
    // `variants` is only present when the listing was loaded with it expanded;
    // otherwise the option set is unknown and must not be overwritten.
    _options = ListingOptions.fromApi(l['variants']);
    final thumb = '${l['thumbnail_url'] ?? ''}';
    _coverUrl = thumb.isNotEmpty && _media.any((m) => m.url == thumb && m.type == 'image') ? thumb : null;
  }

  Future<void> _workplaceCountry() async {
    try {
      final user = await AppStorage.getUser();
      final wp = (user?['selectedWorkplace'] ?? user?['workplace']) as Map?;
      final c = '${wp?['country'] ?? ''}'.trim();
      if (c.isNotEmpty && mounted && _country.text.isEmpty) setState(() => _country.text = c);
    } catch (_) {}
  }

  String _numText(dynamic v) {
    final d = toDouble(v);
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final res = await _service.listingLookups();
      if (!mounted) return;
      setState(() {
        _products = res.products;
        _categories = res.categories;
        if (res.profiles.isNotEmpty) _profileId ??= toInt(res.profiles.first['id']);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load your products';
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? get _product {
    for (final p in _products) {
      if (toInt(p['id']) == _productId) return p;
    }
    final l = widget.listing;
    if (l != null && l['product'] is Map && toInt(l['product_id']) == _productId) return Map<String, dynamic>.from(l['product'] as Map);
    return null;
  }

  Map<String, dynamic>? get _category {
    for (final c in _categories) {
      if (toInt(c['id']) == _categoryId) return c;
    }
    final l = widget.listing;
    if (l != null && l['category'] is Map && toInt(l['category_id']) == _categoryId) return Map<String, dynamic>.from(l['category'] as Map);
    return null;
  }

  void _selectProduct(Map<String, dynamic> p) {
    setState(() {
      _productId = toInt(p['id']);
      _errors.remove('product');
      if (_title.text.trim().isEmpty) _title.text = '${p['name'] ?? ''}';
      if (_price.text.trim().isEmpty && p['price'] != null) _price.text = _numText(p['price']);
      if (!_isEdit) _qty.text = '${toInt(p['stock_qty'])}';
      // Store categories aren't market categories — match by name (desktop parity).
      if (_categoryId == null) {
        final name = '${(p['category'] as Map?)?['name'] ?? ''}'.trim().toLowerCase();
        if (name.isNotEmpty) {
          for (final c in _categories) {
            if ('${c['name'] ?? ''}'.trim().toLowerCase() == name) {
              _categoryId = toInt(c['id']);
              break;
            }
          }
        }
      }
    });
  }

  // ── Validation ──────────────────────────────────────────────────────

  bool _validate(int step) {
    final e = <String, String>{};
    switch (step) {
      case 0:
        if (_productId == null) e['product'] = 'Pick a product to list';
      case 1:
        if (_title.text.trim().isEmpty) e['title'] = 'Title is required';
      case 2:
        final price = double.tryParse(_price.text.trim());
        if (_price.text.trim().isEmpty) {
          e['price'] = 'Price is required';
        } else if (price == null || price < 0) {
          e['price'] = 'Enter a valid price';
        }
        final cmp = _compare.text.trim();
        if (cmp.isNotEmpty) {
          final c = double.tryParse(cmp);
          if (c == null || c < 0) {
            e['compare'] = 'Enter a valid amount';
          } else if (price != null && c <= price) {
            e['compare'] = 'Compare-at price should be above the price';
          }
        }
        final q = int.tryParse(_qty.text.trim());
        if (!_options.enabled && (q == null || q < 0)) e['qty'] = 'Enter a whole number';
        final mn = int.tryParse(_minOrder.text.trim());
        if (mn == null || mn < 1) e['min'] = 'At least 1';
        final mxText = _maxOrder.text.trim();
        if (mxText.isNotEmpty) {
          final mx = int.tryParse(mxText);
          if (mx == null || mx < 1) {
            e['max'] = 'Enter a whole number';
          } else if (mn != null && mx < mn) {
            e['max'] = 'Must be at least the min order';
          }
        }
      case 3:
        if (_media.any((m) => m.uploading)) e['media'] = 'Wait for uploads to finish';
        if (_media.any((m) => m.url == null && !m.uploading)) e['media'] = 'Remove or retry the failed uploads';
      case 4:
        if (_options.enabled && _options.rows.isEmpty) {
          e['options'] = 'Add at least one color or size, or turn options off';
        } else if (_options.enabled && _options.hasBadPrice) {
          e['options'] = 'Check the option prices';
        }
      case 5:
        if (_city.text.trim().isEmpty) e['city'] = 'City is required';
        if (_country.text.trim().isEmpty) e['country'] = 'Country is required';
    }
    setState(() {
      const keys = {
        0: ['product'],
        1: ['title'],
        2: ['price', 'compare', 'qty', 'min', 'max'],
        3: ['media'],
        4: ['options'],
        5: ['city', 'country'],
      };
      for (final k in keys[step]!) {
        _errors.remove(k);
      }
      _errors.addAll(e);
    });
    return e.isEmpty;
  }

  void _go(int i) {
    if (i == _step || i < 0 || i >= _steps.length) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _forward = i > _step;
      _step = i;
    });
  }

  void _next() {
    if (!_validate(_step)) return;
    _go(_step + 1);
  }

  // ── Media ───────────────────────────────────────────────────────────

  Future<void> _pick({bool camera = false, bool video = false}) async {
    List<XFile> files;
    try {
      if (camera) {
        final f = video ? await _picker.pickVideo(source: ImageSource.camera) : await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
        files = f == null ? [] : [f];
      } else {
        files = await _picker.pickMultipleMedia(imageQuality: 85);
      }
    } catch (_) {
      if (mounted) marketToast(context, 'Could not open the picker', error: true);
      return;
    }
    for (final f in files) {
      final bytes = await f.readAsBytes();
      final name = f.name.isNotEmpty ? f.name : f.path.split(RegExp(r'[\\/]')).last;
      final isVid = isVideoUrl(name) || (f.mimeType?.startsWith('video') ?? false);
      final item = _MediaItem(key: 'm${_mediaSeq++}', type: isVid ? 'video' : 'image', name: name, bytes: bytes, uploading: true);
      if (!mounted) return;
      setState(() {
        _media.add(item);
        _errors.remove('media');
      });
      _upload(item, bytes);
    }
  }

  Future<void> _upload(_MediaItem item, List<int> bytes) async {
    setState(() {
      item.uploading = true;
      item.error = null;
    });
    try {
      final res = await _service.uploadMedia(bytes, item.name);
      if (!mounted) return;
      setState(() {
        item.url = '${res['url']}';
        item.type = '${res['type'] ?? item.type}';
        item.uploading = false;
        if (_coverUrl == null && item.type == 'image') _coverUrl = item.url;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        item.uploading = false;
        item.error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        item.uploading = false;
        item.error = 'Upload failed';
      });
    }
  }

  void _removeMedia(_MediaItem m) => setState(() {
        _media.remove(m);
        if (_coverUrl != null && m.url == _coverUrl) _coverUrl = null;
      });

  void _move(int from, int to) {
    if (to < 0 || to >= _media.length) return;
    setState(() {
      final m = _media.removeAt(from);
      _media.insert(to, m);
    });
  }

  String? get _effectiveCover {
    final ready = _media.where((m) => m.url != null).toList();
    if (_coverUrl != null && ready.any((m) => m.url == _coverUrl && m.type == 'image')) return _coverUrl;
    for (final m in ready) {
      if (m.type == 'image') return m.url;
    }
    return null;
  }

  // ── Date-time helper ────────────────────────────────────────────────

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final initial = _expiresAt ?? now.add(const Duration(days: 30));
    final d = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (!mounted) return;
    final tt = t ?? const TimeOfDay(hour: 23, minute: 59);
    setState(() => _expiresAt = DateTime(d.year, d.month, d.day, tt.hour, tt.minute));
  }

  // ── Submit ──────────────────────────────────────────────────────────

  Future<void> _submit(String status) async {
    FocusScope.of(context).unfocus();
    for (var i = 0; i < _steps.length; i++) {
      if (!_validate(i)) {
        _go(i);
        marketToast(context, 'Check the highlighted fields', error: true);
        return;
      }
    }
    if (_profileId == null) {
      marketToast(context, 'Set up your storefront first (Market → Storefront)', error: true);
      return;
    }
    final l = widget.listing;
    final ready = _media.where((m) => m.url != null).toList();
    final payload = <String, dynamic>{
      'product_id': _productId,
      'creator_profile_id': _profileId,
      'category_id': _categoryId,
      'title': _title.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'price': double.parse(_price.text.trim()),
      'compare_price': _compare.text.trim().isEmpty ? null : double.parse(_compare.text.trim()),
      'currency': _currency,
      // Desktop sends these too; the mobile form has no UI for them, so keep
      // the listing's own values (or desktop's defaults for a new one).
      'courier_id': l?['courier_id'],
      'shipping_fee': l?['shipping_fee'] == null ? 35 : toDouble(l!['shipping_fee']),
      'tax_rate': l?['tax_rate'] == null ? 6 : toDouble(l!['tax_rate']),
      'condition': _condition,
      'listing_type': _listingType,
      'quantity': _options.enabled ? _options.totalStock : int.tryParse(_qty.text.trim()) ?? 0,
      'min_order': int.tryParse(_minOrder.text.trim()) ?? 1,
      'max_order': _maxOrder.text.trim().isEmpty ? null : int.tryParse(_maxOrder.text.trim()),
      // Cover must be a photo — product cards can't show a video.
      'thumbnail_url': _effectiveCover,
      'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
      'country': _country.text.trim().isEmpty ? null : _country.text.trim(),
      'tags': _tags.isEmpty ? null : _tags.join(', '),
      'is_featured': _featured,
      'expires_at': _expiresAt?.toUtc().toIso8601String(),
      'status': status,
      'medias': [
        for (var i = 0; i < ready.length; i++)
          {'url': ready[i].url, 'type': ready[i].type, 'name': ready[i].name.isEmpty ? null : ready[i].name, 'position': i},
      ],
      // Complete option set — only when the form actually knows it, so an
      // edit whose variants weren't loaded never wipes them.
      if (!_isEdit || _options.known || _options.enabled) 'variants': _options.payload(_imageUrls),
    };
    setState(() {
      _saving = true;
      _savingStatus = status;
    });
    try {
      await _service.saveListing(payload, id: _isEdit ? toInt(l!['id']) : null);
      if (!mounted) return;
      if (status == 'active') {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(Icons.hourglass_top_rounded, color: MarketPalette.of(ctx).warn),
            title: const Text('Sent for approval', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            content: const Text(
                'Your listing is awaiting platform approval. It shows as "Awaiting approval" in your listings and appears on the market once it is approved.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
          ),
        );
        if (!mounted) return;
      }
      Navigator.pop(context, status);
    } on ApiException catch (e) {
      if (mounted) marketToast(context, e.message, error: true);
    } catch (_) {
      if (mounted) marketToast(context, _isEdit ? 'Could not update the listing' : 'Could not save the listing', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _savingStatus = null;
        });
      }
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final isLast = _step == _steps.length - 1;
    return PopScope(
      canPop: !_saving,
      child: MarketScaffold(
        title: _isEdit ? 'Edit listing' : 'New listing',
        subtitle: 'Step ${_step + 1} of ${_steps.length} · ${_steps[_step].hint}',
        body: Column(children: [
          _StepBar(current: _step, onSelect: _saving ? null : _go),
          Expanded(
            child: _loading
                ? const SkeletonList(count: 5)
                : _loadError != null
                    ? Center(
                        child: MarketEmpty(icon: Icons.cloud_off_outlined, title: 'Could not load', message: _loadError, actionLabel: 'Retry', onAction: _load),
                      )
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) {
                          final incoming = child.key == ValueKey(_step);
                          final dx = (incoming == _forward) ? 0.06 : -0.06;
                          return FadeTransition(
                            opacity: anim,
                            child: SlideTransition(position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(anim), child: child),
                          );
                        },
                        child: KeyedSubtree(key: ValueKey(_step), child: _stepBody(context)),
                      ),
          ),
        ]),
        bottom: Container(
          decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SafeArea(
            top: false,
            child: Row(children: [
              if (_step > 0)
                OutlinedButton(onPressed: _saving ? null : () => _go(_step - 1), child: const Text('Back'))
              else
                TextButton(onPressed: _saving ? null : () => Navigator.maybePop(context), child: const Text('Cancel')),
              const Spacer(),
              if (isLast) ...[
                Flexible(
                  child: OutlinedButton(
                    onPressed: _saving || _loading ? null : () => _submit('draft'),
                    child: _savingStatus == 'draft'
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save draft', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FilledButton(
                    onPressed: _saving || _loading ? null : () => _submit('active'),
                    child: _savingStatus == 'active'
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Publish', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ] else
                FilledButton(onPressed: _loading ? null : _next, child: const Text('Next')),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _stepBody(BuildContext context) => switch (_step) {
        0 => _productStep(context),
        1 => _detailsStep(context),
        2 => _pricingStep(context),
        3 => _mediaStep(context),
        4 => _optionsStep(context),
        _ => _reviewStep(context),
      };

  Widget _scroll(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: children,
      );

  // Step 1 — product
  Widget _productStep(BuildContext context) {
    final p = MarketPalette.of(context);
    final q = _productQuery.text.trim().toLowerCase();
    final list = q.isEmpty
        ? _products
        : _products.where((x) => '${x['name'] ?? ''}'.toLowerCase().contains(q) || '${x['sku'] ?? ''}'.toLowerCase().contains(q)).toList();
    final selected = _product;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionHeader('Which product are you listing?', subtitle: 'From your sellable catalog — title, price and stock are prefilled'),
          if (selected != null && !_products.any((x) => toInt(x['id']) == _productId))
            Padding(padding: const EdgeInsets.only(bottom: 8), child: _productTile(p, selected, true, -1)),
          TextField(
            controller: _productQuery,
            onChanged: (_) => setState(() {}),
            decoration: _dec(p, hint: 'Search by name or SKU', prefix: Icons.search),
          ),
          if (_errors['product'] != null) _errorText(p, _errors['product']!),
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? MarketEmpty(
                icon: _products.isEmpty ? Icons.inventory_2_outlined : Icons.search_off,
                title: _products.isEmpty ? 'No products to list' : 'No matching products',
                message: _products.isEmpty ? 'Add active, non-pharma products in Store → Catalog first.' : 'Try another name or SKU.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => FadeSlideIn(index: i, child: _productTile(p, list[i], toInt(list[i]['id']) == _productId, i)),
              ),
      ),
    ]);
  }

  Widget _productTile(MarketPalette p, Map<String, dynamic> x, bool sel, int i) => MarketCard(
        onTap: i < 0 ? null : () => _selectProduct(x),
        padding: const EdgeInsets.all(10),
        color: sel ? p.brandSoft : null,
        borderColor: sel ? p.brand : null,
        child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 48, height: 48, child: MarketNetImage('${x['thumbnail_url'] ?? ''}', iconSize: 20))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${x['name'] ?? 'Product'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
              Text(
                [
                  if ('${x['sku'] ?? ''}'.isNotEmpty) 'SKU ${x['sku']}',
                  if (x['price'] != null) money(toDouble(x['price'])),
                  if (x['stock_qty'] != null) 'Stock ${toInt(x['stock_qty'])}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: p.label),
              ),
            ]),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: sel ? Icon(Icons.check_circle, key: const ValueKey(1), color: p.brand, size: 22) : Icon(Icons.circle_outlined, key: const ValueKey(0), color: p.line, size: 22),
          ),
        ]),
      );

  // Step 2 — details
  Widget _detailsStep(BuildContext context) {
    final p = MarketPalette.of(context);
    final cat = _category;
    return _scroll([
      const SectionHeader('Describe your listing', subtitle: 'What buyers see on the market'),
      _label(p, 'Title', required: true),
      TextField(
        controller: _title,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => _errors.containsKey('title') ? setState(() => _errors.remove('title')) : null,
        decoration: _dec(p, hint: 'e.g. Wireless earbuds with charging case', error: _errors['title']),
      ),
      const SizedBox(height: 14),
      _label(p, 'Description'),
      TextField(
        controller: _description,
        minLines: 3,
        maxLines: 8,
        textCapitalization: TextCapitalization.sentences,
        decoration: _dec(p, hint: 'Features, what is in the box, warranty…'),
      ),
      const SizedBox(height: 14),
      _label(p, 'Market category'),
      MarketCard(
        onTap: _pickCategory,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        child: Row(children: [
          Icon(Icons.sell_outlined, size: 18, color: p.label),
          const SizedBox(width: 10),
          Expanded(
            child: Text(cat == null ? 'Choose where buyers will find it' : '${cat['name']}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: cat == null ? p.label : p.text)),
          ),
          Icon(Icons.chevron_right, color: p.label),
        ]),
      ),
      const SizedBox(height: 14),
      _label(p, 'Condition'),
      MarketSegmented<String>(
        value: _condition,
        options: [for (final e in conditionLabels.entries) (id: e.key, label: e.value, count: null)],
        onChanged: (v) => setState(() => _condition = v),
      ),
      const SizedBox(height: 14),
      _label(p, 'Listing type'),
      MarketSegmented<String>(
        value: _listingType,
        options: [for (final e in listingTypeLabels.entries) (id: e.key, label: e.value, count: null)],
        onChanged: (v) => setState(() => _listingType = v),
      ),
      const SizedBox(height: 14),
      _label(p, 'Tags'),
      TextField(
        controller: _tagInput,
        textInputAction: TextInputAction.done,
        onChanged: (v) {
          if (v.contains(',')) _addTags(v);
        },
        onSubmitted: _addTags,
        decoration: _dec(p, hint: 'Type a tag and press enter', suffix: IconButton(icon: const Icon(Icons.add), onPressed: () => _addTags(_tagInput.text))),
      ),
      if (_tags.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in _tags)
            InputChip(
              label: Text(t, style: TextStyle(fontSize: 12, color: p.text)),
              backgroundColor: p.surface,
              side: BorderSide(color: p.line),
              onDeleted: () => setState(() => _tags.remove(t)),
            ),
        ]),
      ],
    ]);
  }

  void _addTags(String raw) {
    final parts = raw.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty);
    setState(() {
      for (final t in parts) {
        if (!_tags.any((x) => x.toLowerCase() == t.toLowerCase())) _tags.add(t);
      }
      _tagInput.clear();
    });
  }

  Future<void> _pickCategory() async {
    final picked = await showMarketSheet<Object>(context, builder: (ctx) => _CategorySheet(categories: _categories, selected: _categoryId));
    if (!mounted || picked == null) return;
    setState(() => _categoryId = picked is int ? picked : null);
  }

  // Step 3 — pricing & stock
  Widget _pricingStep(BuildContext context) {
    final p = MarketPalette.of(context);
    final sym = currencySymbol(_currency);
    void clear(String k) => _errors.containsKey(k) ? setState(() => _errors.remove(k)) : null;
    return _scroll([
      const SectionHeader('Pricing', subtitle: 'Shown to buyers in your store currency'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(p, 'Price', required: true),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => clear('price'),
              decoration: _dec(p, hint: '0.00', prefixText: '$sym ', error: _errors['price']),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(p, 'Compare-at price'),
            TextField(
              controller: _compare,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => clear('compare'),
              decoration: _dec(p, hint: 'Optional', prefixText: '$sym ', error: _errors['compare']),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      InfoRow('Currency', '$sym $_currency'),
      const SectionHeader('Stock and order limits'),
      _label(p, 'Available quantity', required: !_options.enabled),
      if (_options.enabled)
        MarketCard(
          onTap: () => _go(4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(children: [
            Icon(Icons.palette_outlined, size: 18, color: p.label),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_options.totalStock} units', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                Text('Total of your options — set stock per option', style: TextStyle(fontSize: 11.5, color: p.label)),
              ]),
            ),
            Icon(Icons.chevron_right, color: p.label),
          ]),
        )
      else
        TextField(
          controller: _qty,
          keyboardType: TextInputType.number,
          onChanged: (_) => clear('qty'),
          decoration: _dec(p, hint: '0', error: _errors['qty']),
        ),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(p, 'Min order'),
            TextField(
              controller: _minOrder,
              keyboardType: TextInputType.number,
              onChanged: (_) => clear('min'),
              decoration: _dec(p, hint: '1', error: _errors['min']),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(p, 'Max order'),
            TextField(
              controller: _maxOrder,
              keyboardType: TextInputType.number,
              onChanged: (_) => clear('max'),
              decoration: _dec(p, hint: 'No limit', error: _errors['max']),
            ),
          ]),
        ),
      ]),
      const SectionHeader('Visibility'),
      MarketCard(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _featured,
          onChanged: (v) => setState(() => _featured = v),
          title: Text('Featured', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
          subtitle: Text('Highlight it in your storefront', style: TextStyle(fontSize: 11.5, color: p.label)),
        ),
      ),
      const SizedBox(height: 10),
      MarketCard(
        onTap: _pickExpiry,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(children: [
          Icon(Icons.event_outlined, size: 18, color: p.label),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Expiry date', style: TextStyle(fontSize: 11.5, color: p.label)),
              Text(_expiresAt == null ? 'Never expires' : DateFormat('d MMM y, h:mm a').format(_expiresAt!),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: p.text)),
            ]),
          ),
          if (_expiresAt != null)
            IconButton(tooltip: 'Clear', icon: Icon(Icons.close, size: 18, color: p.label), onPressed: () => setState(() => _expiresAt = null))
          else
            Icon(Icons.chevron_right, color: p.label),
        ]),
      ),
    ]);
  }

  // Step 4 — media
  Widget _mediaStep(BuildContext context) {
    final p = MarketPalette.of(context);
    final cover = _effectiveCover;
    return _scroll([
      const SectionHeader('Photos and videos', subtitle: 'Long-press and drag, or use the arrows, to reorder. The cover must be a photo.'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonalIcon(onPressed: () => _pick(), icon: const Icon(Icons.photo_library_outlined, size: 18), label: const Text('Gallery')),
        OutlinedButton.icon(onPressed: () => _pick(camera: true), icon: const Icon(Icons.photo_camera_outlined, size: 18), label: const Text('Photo')),
        OutlinedButton.icon(onPressed: () => _pick(camera: true, video: true), icon: const Icon(Icons.videocam_outlined, size: 18), label: const Text('Video')),
      ]),
      if (_errors['media'] != null) _errorText(p, _errors['media']!),
      const SizedBox(height: 12),
      if (_media.isEmpty)
        MarketEmpty(icon: Icons.add_photo_alternate_outlined, title: 'No media yet', message: 'Listings with clear photos get more views. Add a few from your gallery or camera.')
      else
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _media.length,
          proxyDecorator: (child, _, _) => Material(color: Colors.transparent, elevation: 4, borderRadius: BorderRadius.circular(12), child: child),
          onReorder: (from, to) => _move(from, to > from ? to - 1 : to),
          itemBuilder: (_, i) {
            final m = _media[i];
            return ReorderableDelayedDragStartListener(
              key: ValueKey(m.key),
              index: i,
              child: Padding(padding: const EdgeInsets.only(bottom: 8), child: _mediaTile(p, m, i, m.url != null && m.url == cover)),
            );
          },
        ),
    ]);
  }

  Widget _mediaTile(MarketPalette p, _MediaItem m, int i, bool isCover) {
    Widget preview;
    if (m.type == 'video') {
      preview = Container(color: p.surface, alignment: Alignment.center, child: Icon(Icons.videocam_outlined, color: p.label));
    } else if (m.bytes != null) {
      preview = Image.memory(m.bytes!, fit: BoxFit.cover);
    } else {
      preview = MarketNetImage(m.url, iconSize: 20);
    }
    return MarketCard(
      padding: const EdgeInsets.all(8),
      borderColor: isCover ? p.brand : (m.error != null ? p.error : null),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 64,
            height: 64,
            child: Stack(fit: StackFit.expand, children: [
              preview,
              AnimatedOpacity(
                opacity: m.uploading ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  alignment: Alignment.center,
                  child: const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.name.isEmpty ? (m.type == 'video' ? 'Video' : 'Photo') : m.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: m.uploading
                  ? Column(key: const ValueKey('up'), crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Uploading…', style: TextStyle(fontSize: 11, color: p.label)),
                      const SizedBox(height: 4),
                      ClipRRect(borderRadius: BorderRadius.circular(2), child: const LinearProgressIndicator(minHeight: 3)),
                    ])
                  : m.error != null
                      ? Row(key: const ValueKey('err'), children: [
                          Flexible(child: Text(m.error!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.error))),
                          if (m.bytes != null)
                            TextButton(
                              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                              onPressed: () => _upload(m, m.bytes!),
                              child: const Text('Retry'),
                            ),
                        ])
                      : Wrap(key: const ValueKey('ok'), spacing: 4, runSpacing: 4, children: [
                          StatusPill(m.type == 'video' ? 'Video' : 'Photo', tone: m.type == 'video' ? MarketTone.info : MarketTone.neutral),
                          if (isCover)
                            const StatusPill('Cover', tone: MarketTone.brand, icon: Icons.star_rounded)
                          else if (m.type == 'image')
                            GestureDetector(
                              onTap: () => setState(() => _coverUrl = m.url),
                              child: Text('Set as cover', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.brand)),
                            ),
                        ]),
            ),
          ]),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          _tinyIcon(p, Icons.keyboard_arrow_up, i == 0 ? null : () => _move(i, i - 1), 'Move up'),
          _tinyIcon(p, Icons.keyboard_arrow_down, i == _media.length - 1 ? null : () => _move(i, i + 1), 'Move down'),
        ]),
        _tinyIcon(p, Icons.close, () => _removeMedia(m), 'Remove', color: p.error),
      ]),
    );
  }

  Widget _tinyIcon(MarketPalette p, IconData icon, VoidCallback? onTap, String tip, {Color? color}) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
        iconSize: 20,
        onPressed: onTap,
        icon: Icon(icon, color: onTap == null ? p.line : (color ?? p.label)),
      );

  List<String> get _imageUrls => [for (final m in _media) if (m.url != null && m.type == 'image') m.url!];

  // Step 5 — options (colors / sizes)
  Widget _optionsStep(BuildContext context) {
    final p = MarketPalette.of(context);
    final price = _price.text.trim();
    return ListingOptionsStep(
      options: _options,
      onChanged: () => setState(() {
        if (_errors.containsKey('options')) _errors.remove('options');
      }),
      priceHint: price.isEmpty ? 'Listing price' : price,
      currencySymbol: currencySymbol(_currency),
      imageUrls: _imageUrls,
      error: _errors['options'],
      decoration: ({String? hint, String? prefixText, Widget? suffix}) => _dec(p, hint: hint, prefixText: prefixText, suffix: suffix),
    );
  }

  // Step 6 — review & publish
  Widget _reviewStep(BuildContext context) {
    final p = MarketPalette.of(context);
    final prod = _product;
    final cat = _category;
    final ready = _media.where((m) => m.url != null).toList();
    final price = double.tryParse(_price.text.trim()) ?? 0;
    final cmp = double.tryParse(_compare.text.trim());
    void clear(String k) => _errors.containsKey(k) ? setState(() => _errors.remove(k)) : null;
    return _scroll([
      Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.infoBg, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 18, color: p.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Publishing sends this listing for a quick platform review. It shows as awaiting approval until it is approved.',
                style: TextStyle(fontSize: 12.5, color: p.text, height: 1.35)),
          ),
        ]),
      ),
      const SectionHeader('Summary'),
      MarketCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 64, height: 64, child: MarketNetImage(_effectiveCover ?? '${prod?['thumbnail_url'] ?? ''}', iconSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_title.text.trim().isEmpty ? 'Untitled listing' : _title.text.trim(),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                const SizedBox(height: 2),
                Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.end, children: [
                  Text(money(price, currency: _currency), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                  if (cmp != null && cmp > price)
                    Text(money(cmp, currency: _currency), style: TextStyle(fontSize: 11.5, color: p.label, decoration: TextDecoration.lineThrough)),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Divider(height: 1, color: p.line),
          const SizedBox(height: 4),
          _reviewRow(p, 'Product', '${prod?['name'] ?? '—'}', 0),
          _reviewRow(p, 'Category', '${cat?['name'] ?? '—'}', 1),
          _reviewRow(p, 'Condition', conditionLabels[_condition] ?? _condition, 1),
          _reviewRow(p, 'Listing type', listingTypeLabels[_listingType] ?? _listingType, 1),
          _reviewRow(p, 'Tags', _tags.isEmpty ? '—' : _tags.join(', '), 1),
          _reviewRow(p, 'Stock', _options.enabled ? '${_options.totalStock}' : (_qty.text.trim().isEmpty ? '0' : _qty.text.trim()), _options.enabled ? 4 : 2),
          _reviewRow(p, 'Order limits', 'Min ${_minOrder.text.trim().isEmpty ? '1' : _minOrder.text.trim()} · max ${_maxOrder.text.trim().isEmpty ? 'no limit' : _maxOrder.text.trim()}', 2),
          _reviewRow(p, 'Featured', _featured ? 'Yes' : 'No', 2),
          _reviewRow(p, 'Expires', _expiresAt == null ? 'Never' : DateFormat('d MMM y, h:mm a').format(_expiresAt!), 2),
          _reviewRow(p, 'Media', '${ready.where((m) => m.type == 'image').length} photos · ${ready.where((m) => m.type == 'video').length} videos', 3),
          _reviewRow(
            p,
            'Options',
            _options.enabled
                ? '${_options.rows.length} option${_options.rows.length == 1 ? '' : 's'} · ${_options.totalStock} units'
                : 'None',
            4,
          ),
        ]),
      ),
      const SectionHeader('Location', subtitle: 'Where the item ships from'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(p, 'City', required: true),
            TextField(
              controller: _city,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => clear('city'),
              decoration: _dec(p, hint: 'City', error: _errors['city']),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(p, 'Country', required: true),
            TextField(
              controller: _country,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => clear('country'),
              decoration: _dec(p, hint: 'Country', error: _errors['country']),
            ),
          ]),
        ),
      ]),
      if (_profileId == null) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.warnBg, borderRadius: BorderRadius.circular(10)),
          child: Text('Your store has no storefront profile yet. Set one up in Market → Storefront before saving.',
              style: TextStyle(fontSize: 12.5, color: p.text, height: 1.35)),
        ),
      ],
    ]);
  }

  Widget _reviewRow(MarketPalette p, String label, String value, int step) => InkWell(
        onTap: () => _go(step),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 104, child: Text(label, style: TextStyle(fontSize: 12.5, color: p.label))),
            Expanded(child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: p.text))),
            const SizedBox(width: 4),
            Icon(Icons.edit_outlined, size: 14, color: p.label),
          ]),
        ),
      );

  // ── Small form bits ─────────────────────────────────────────────────

  Widget _label(MarketPalette p, String text, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: text),
          if (required) TextSpan(text: ' *', style: TextStyle(color: p.error)),
        ]), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.label)),
      );

  Widget _errorText(MarketPalette p, String msg) => Padding(
        padding: const EdgeInsets.only(top: 6, left: 2),
        child: Text(msg, style: TextStyle(fontSize: 12, color: p.error)),
      );

  InputDecoration _dec(MarketPalette p, {String? hint, String? error, IconData? prefix, String? prefixText, Widget? suffix}) {
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: w));
    return InputDecoration(
      hintText: hint,
      errorText: error,
      isDense: true,
      filled: true,
      fillColor: p.card,
      prefixIcon: prefix == null ? null : Icon(prefix, size: 18, color: p.label),
      prefixText: prefixText,
      suffixIcon: suffix,
      hintStyle: TextStyle(fontSize: 13, color: p.label),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      enabledBorder: b(p.line),
      focusedBorder: b(p.brand, 1.5),
      errorBorder: b(p.error),
      focusedErrorBorder: b(p.error, 1.5),
    );
  }
}

/// Fiori-style wizard step indicator — numbered dots joined by a line,
/// scrollable on narrow screens.
class _StepBar extends StatelessWidget {
  final int current;
  final ValueChanged<int>? onSelect;
  const _StepBar({required this.current, this.onSelect});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      color: p.card,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          for (var i = 0; i < _steps.length; i++) ...[
            if (i > 0)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 18,
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: i <= current ? p.brand : p.line,
              ),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onSelect == null ? null : () => onSelect!(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < current ? p.brand : (i == current ? p.brandSoft : p.surface),
                      border: Border.all(color: i <= current ? p.brand : p.line, width: 1.5),
                    ),
                    child: i < current
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : Text('${i + 1}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: i == current ? p.brand : p.label)),
                  ),
                  const SizedBox(width: 6),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(fontSize: 12, fontWeight: i == current ? FontWeight.w700 : FontWeight.w500, color: i == current ? p.text : p.label),
                    child: Text(_steps[i].label),
                  ),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Searchable market category picker. Pops the chosen id, or `false` for
/// "no category".
class _CategorySheet extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final int? selected;
  const _CategorySheet({required this.categories, required this.selected});

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final list = _q.isEmpty ? widget.categories : widget.categories.where((c) => '${c['name'] ?? ''}'.toLowerCase().contains(_q)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Expanded(child: Text('Market category', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text))),
            if (widget.selected != null) TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Clear')),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            autofocus: false,
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search categories',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: list.isEmpty
              ? const MarketEmpty(icon: Icons.sell_outlined, title: 'No categories found')
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final c = list[i];
                    final sel = toInt(c['id']) == widget.selected;
                    return ListTile(
                      dense: true,
                      title: Text('${c['name'] ?? ''}', style: TextStyle(fontSize: 13.5, color: p.text, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                      trailing: sel ? Icon(Icons.check, color: p.brand) : null,
                      onTap: () => Navigator.pop(context, toInt(c['id'])),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
