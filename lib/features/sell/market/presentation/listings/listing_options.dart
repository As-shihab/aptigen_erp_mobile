import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../widgets/market_ui.dart';
import 'listing_common.dart';

// Color / size options for a market listing (OData `market_listing_variants`,
// sent as `variants: [...]` on the market_listings POST/PUT) — mobile port of
// erp/desktop's forms/market/ListingVariantsEditor.tsx.

class VariantColor {
  String name;
  String hex; // #RRGGBB
  VariantColor(this.name, this.hex);
}

const variantColorPresets = <(String, String)>[
  ('Black', '#1F2937'),
  ('White', '#F9FAFB'),
  ('Red', '#DC2626'),
  ('Blue', '#2563EB'),
  ('Green', '#16A34A'),
  ('Yellow', '#EAB308'),
  ('Grey', '#9CA3AF'),
  ('Brown', '#92400E'),
  ('Navy', '#1E3A8A'),
  ('Pink', '#EC4899'),
  ('Orange', '#EA580C'),
  ('Purple', '#7C3AED'),
  ('Beige', '#D6C7A1'),
];

/// Swatches offered for a custom color (and for changing a color's swatch).
const variantSwatches = <String>[
  '#1F2937', '#F9FAFB', '#9CA3AF', '#DC2626', '#EA580C', '#EAB308', '#16A34A', '#0D9488',
  '#0EA5E9', '#2563EB', '#1E3A8A', '#7C3AED', '#EC4899', '#92400E', '#D6C7A1', '#800020',
];

const variantSizePresets = <(String, List<String>)>[
  ('XS–XXL', ['XS', 'S', 'M', 'L', 'XL', 'XXL']),
  ('36–44', ['36', '38', '40', '42', '44']),
];

const _fallbackHex = '#9CA3AF';

Color hexToColor(String? hex) {
  final h = (hex ?? '').replaceFirst('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : '', radix: 16);
  return Color(v ?? 0xFF9CA3AF);
}

String _keyOf(String color, String size) => '${color.trim().toLowerCase()}|${size.trim().toLowerCase()}';

class VariantRow {
  int? id;
  String color;
  String colorHex;
  String size;
  final TextEditingController price;
  final TextEditingController stock;
  final TextEditingController sku;
  String? imageUrl;
  bool isActive;

  VariantRow({this.id, required this.color, required this.colorHex, required this.size, String price = '', String stock = '0', String sku = '', this.imageUrl, this.isActive = true})
      : price = TextEditingController(text: price),
        stock = TextEditingController(text: stock),
        sku = TextEditingController(text: sku);

  String get key => _keyOf(color, size);
  String get label => [color, size].where((s) => s.trim().isNotEmpty).join(' / ');
  int get stockQty => math.max(0, int.tryParse(stock.text.trim()) ?? 0);

  void dispose() {
    price.dispose();
    stock.dispose();
    sku.dispose();
  }
}

/// Form state for the options step. [known] is true when the form knows the
/// listing's full option set (new listing, or an edit loaded with `variants`
/// expanded) — only then (or once options are switched on) is `variants` sent.
class ListingOptions {
  bool enabled = false;
  bool known = true;
  final List<VariantColor> colors = [];
  final List<String> sizes = [];
  final List<VariantRow> rows = [];

  ListingOptions();

  factory ListingOptions.fromApi(dynamic list) {
    final o = ListingOptions();
    if (list is! List) {
      o.known = false;
      return o;
    }
    final items = list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      ..sort((a, b) => toInt(a['position']).compareTo(toInt(b['position'])));
    for (final v in items) {
      String s(String k) => '${v[k] ?? ''}'.trim();
      final row = VariantRow(
        id: v['id'] == null ? null : toInt(v['id']),
        color: s('color'),
        colorHex: s('color_hex'),
        size: s('size'),
        price: v['price'] == null ? '' : _numText(v['price']),
        stock: '${toInt(v['stock_qty'])}',
        sku: s('sku'),
        imageUrl: s('image_url').isEmpty ? null : s('image_url'),
        isActive: v['is_active'] != false,
      );
      o.rows.add(row);
      if (row.color.isNotEmpty && !o.colors.any((c) => c.name.toLowerCase() == row.color.toLowerCase())) {
        o.colors.add(VariantColor(row.color, row.colorHex.isEmpty ? _fallbackHex : row.colorHex));
      }
      if (row.size.isNotEmpty && !o.sizes.any((x) => x.toLowerCase() == row.size.toLowerCase())) o.sizes.add(row.size);
    }
    o.enabled = o.rows.isNotEmpty;
    return o;
  }

  static String _numText(dynamic v) {
    final d = toDouble(v);
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }

  int get totalStock => rows.where((r) => r.isActive).fold(0, (n, r) => n + r.stockQty);

  bool get hasBadPrice => rows.any((r) {
        final t = r.price.text.trim();
        if (t.isEmpty) return false;
        final d = double.tryParse(t);
        return d == null || d < 0;
      });

  /// Rebuilds the combinations from colors × sizes, keeping each existing
  /// row (id, price, stock, sku, photo) matched by lowercase color|size.
  void regenerate() {
    final byKey = {for (final r in rows) r.key: r};
    final next = <VariantRow>[];
    if (colors.isNotEmpty || sizes.isNotEmpty) {
      final cs = colors.isEmpty ? <VariantColor?>[null] : colors;
      final ss = sizes.isEmpty ? <String?>[null] : sizes;
      for (final c in cs) {
        for (final s in ss) {
          final color = c?.name ?? '';
          final size = s ?? '';
          final existing = byKey.remove(_keyOf(color, size));
          if (existing != null) {
            existing
              ..color = color
              ..size = size
              ..colorHex = c?.hex ?? '';
            next.add(existing);
          } else {
            next.add(VariantRow(color: color, colorHex: c?.hex ?? '', size: size));
          }
        }
      }
    }
    rows
      ..clear()
      ..addAll(next);
    final dropped = byKey.values.toList();
    // Their text fields are still mounted this frame — dispose afterwards.
    if (dropped.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final r in dropped) {
          r.dispose();
        }
      });
    }
  }

  /// The complete desired option set. [imageUrls] are the listing's photo
  /// URLs — an option photo must be one of them (the server nulls others).
  List<Map<String, dynamic>> payload(List<String> imageUrls) {
    if (!enabled) return [];
    return [
      for (final r in rows)
        {
          'id': ?r.id,
          'color': r.color.isEmpty ? null : r.color,
          'color_hex': r.color.isEmpty || r.colorHex.isEmpty ? null : r.colorHex,
          'size': r.size.isEmpty ? null : r.size,
          'sku': r.sku.text.trim().isEmpty ? null : r.sku.text.trim(),
          'price': r.price.text.trim().isEmpty ? null : double.tryParse(r.price.text.trim()),
          'stock_qty': r.stockQty,
          'image_url': r.imageUrl != null && imageUrls.contains(r.imageUrl) ? r.imageUrl : null,
          'is_active': r.isActive,
        },
    ];
  }

  void dispose() {
    for (final r in rows) {
      r.dispose();
    }
  }
}

/// The "Options" wizard step. Mutates [options] in place and calls
/// [onChanged] so the parent form rebuilds (review summary, stock total).
class ListingOptionsStep extends StatefulWidget {
  final ListingOptions options;
  final VoidCallback onChanged;
  final String priceHint;
  final String currencySymbol;
  final List<String> imageUrls;
  final String? error;
  final InputDecoration Function({String? hint, String? prefixText, Widget? suffix}) decoration;

  const ListingOptionsStep({
    super.key,
    required this.options,
    required this.onChanged,
    required this.priceHint,
    required this.currencySymbol,
    required this.imageUrls,
    required this.decoration,
    this.error,
  });

  @override
  State<ListingOptionsStep> createState() => _ListingOptionsStepState();
}

class _ListingOptionsStepState extends State<ListingOptionsStep> {
  final _colorName = TextEditingController();
  final _sizeInput = TextEditingController();
  final _bulkStock = TextEditingController();
  final _bulkPrice = TextEditingController();
  String _customHex = '#2563EB';

  ListingOptions get _o => widget.options;

  @override
  void dispose() {
    for (final c in [_colorName, _sizeInput, _bulkStock, _bulkPrice]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  void _addColor(String name, String hex) {
    final n = name.trim();
    if (n.isEmpty) return;
    if (_o.colors.any((c) => c.name.toLowerCase() == n.toLowerCase())) {
      marketToast(context, '$n is already added');
      return;
    }
    _changed(() {
      _o.colors.add(VariantColor(n, hex));
      _o.regenerate();
    });
  }

  void _addSizes(Iterable<String> raw) {
    final parts = raw.expand((s) => s.split(',')).map((s) => s.trim()).where((s) => s.isNotEmpty);
    _changed(() {
      for (final s in parts) {
        if (!_o.sizes.any((x) => x.toLowerCase() == s.toLowerCase())) _o.sizes.add(s);
      }
      _o.regenerate();
    });
  }

  Future<String?> _pickSwatch(String current) => showMarketSheet<String>(context, builder: (ctx) => _SwatchSheet(selected: current));

  Future<void> _pickPhoto(VariantRow r) async {
    final picked = await showMarketSheet<Object>(context, builder: (ctx) => _PhotoSheet(urls: widget.imageUrls, selected: r.imageUrl));
    if (picked == null || !mounted) return;
    _changed(() => r.imageUrl = picked is String ? picked : null);
  }

  void _applyAll(TextEditingController src, bool stock) {
    final t = src.text.trim();
    if (stock) {
      final q = int.tryParse(t);
      if (q == null || q < 0) {
        marketToast(context, 'Enter a whole number', error: true);
        return;
      }
      _changed(() {
        for (final r in _o.rows) {
          r.stock.text = '$q';
        }
      });
    } else {
      final d = t.isEmpty ? 0.0 : double.tryParse(t);
      if (d == null || d < 0) {
        marketToast(context, 'Enter a valid price', error: true);
        return;
      }
      _changed(() {
        for (final r in _o.rows) {
          r.price.text = t;
        }
      });
    }
    FocusScope.of(context).unfocus();
    src.clear();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const SectionHeader('Options', subtitle: 'Let buyers pick a color or size, with stock per option'),
        MarketCard(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          borderColor: widget.error != null ? p.error : null,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _o.enabled,
            onChanged: (v) => _changed(() => _o.enabled = v),
            title: Text('This listing has color or size options', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
            subtitle: Text(
              _o.enabled ? 'Available quantity is the total of the options on sale' : 'Off — the quantity from pricing and stock is used',
              style: TextStyle(fontSize: 11.5, color: p.label),
            ),
          ),
        ),
        if (widget.error != null)
          Padding(padding: const EdgeInsets.only(top: 6, left: 2), child: Text(widget.error!, style: TextStyle(fontSize: 12, color: p.error))),
        if (_o.enabled) ...[
          ..._colorsSection(p),
          ..._sizesSection(p),
          ..._combinationsSection(p),
        ],
      ],
    );
  }

  // ── Colors ──────────────────────────────────────────────────────────

  List<Widget> _colorsSection(MarketPalette p) {
    final presets = variantColorPresets.where((c) => !_o.colors.any((x) => x.name.toLowerCase() == c.$1.toLowerCase())).toList();
    return [
      const SectionHeader('Colors', subtitle: 'Tap a color to change its swatch'),
      if (_o.colors.isNotEmpty) ...[
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in _o.colors)
            InputChip(
              avatar: _Swatch(hex: c.hex, size: 16),
              label: Text(c.name, style: TextStyle(fontSize: 12, color: p.text)),
              backgroundColor: p.surface,
              side: BorderSide(color: p.line),
              onPressed: () async {
                final hex = await _pickSwatch(c.hex);
                if (hex != null && mounted) {
                  _changed(() {
                    c.hex = hex;
                    _o.regenerate();
                  });
                }
              },
              onDeleted: () => _changed(() {
                _o.colors.remove(c);
                _o.regenerate();
              }),
            ),
        ]),
        const SizedBox(height: 10),
      ],
      TextField(
        controller: _colorName,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (v) {
          _addColor(v, _customHex);
          _colorName.clear();
        },
        decoration: widget.decoration(
          hint: 'Custom color name, e.g. Olive',
          suffix: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Swatch',
              onPressed: () async {
                final hex = await _pickSwatch(_customHex);
                if (hex != null && mounted) setState(() => _customHex = hex);
              },
              icon: _Swatch(hex: _customHex, size: 20),
            ),
            IconButton(
              tooltip: 'Add color',
              icon: const Icon(Icons.add),
              onPressed: () {
                _addColor(_colorName.text, _customHex);
                _colorName.clear();
              },
            ),
          ]),
        ),
      ),
      if (presets.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in presets)
            ActionChip(
              avatar: _Swatch(hex: c.$2, size: 14),
              label: Text(c.$1, style: TextStyle(fontSize: 12, color: p.text)),
              backgroundColor: p.card,
              side: BorderSide(color: p.line),
              onPressed: () => _addColor(c.$1, c.$2),
            ),
        ]),
      ],
    ];
  }

  // ── Sizes ───────────────────────────────────────────────────────────

  List<Widget> _sizesSection(MarketPalette p) => [
        const SectionHeader('Sizes'),
        if (_o.sizes.isNotEmpty) ...[
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in _o.sizes)
              InputChip(
                label: Text(s, style: TextStyle(fontSize: 12, color: p.text)),
                backgroundColor: p.surface,
                side: BorderSide(color: p.line),
                onDeleted: () => _changed(() {
                  _o.sizes.remove(s);
                  _o.regenerate();
                }),
              ),
          ]),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _sizeInput,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) {
            _addSizes([v]);
            _sizeInput.clear();
          },
          decoration: widget.decoration(
            hint: 'Type a size and press enter',
            suffix: IconButton(
              tooltip: 'Add size',
              icon: const Icon(Icons.add),
              onPressed: () {
                _addSizes([_sizeInput.text]);
                _sizeInput.clear();
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final preset in variantSizePresets)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => _addSizes(preset.$2),
              icon: const Icon(Icons.add, size: 16),
              label: Text(preset.$1),
            ),
        ]),
      ];

  // ── Combinations ────────────────────────────────────────────────────

  List<Widget> _combinationsSection(MarketPalette p) {
    final rows = _o.rows;
    return [
      SectionHeader(
        'Combinations',
        subtitle: rows.isEmpty ? null : '${rows.length} option${rows.length == 1 ? '' : 's'} · ${_o.totalStock} units on sale',
      ),
      if (rows.isEmpty)
        const MarketEmpty(icon: Icons.palette_outlined, title: 'No options yet', message: 'Add at least one color or size above.')
      else ...[
        MarketCard(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            _bulkRow(p, _bulkStock, 'Set stock for all', null, true),
            const SizedBox(height: 8),
            _bulkRow(p, _bulkPrice, 'Set price for all', '${widget.currencySymbol} ', false),
          ]),
        ),
        const SizedBox(height: 10),
        for (final r in rows) Padding(key: ObjectKey(r), padding: const EdgeInsets.only(bottom: 8), child: _rowCard(p, r)),
      ],
    ];
  }

  Widget _bulkRow(MarketPalette p, TextEditingController c, String label, String? prefix, bool stock) => Row(children: [
        Expanded(
          child: TextField(
            controller: c,
            keyboardType: stock ? TextInputType.number : const TextInputType.numberWithOptions(decimal: true),
            decoration: widget.decoration(hint: label, prefixText: prefix),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: () => _applyAll(c, stock), child: const Text('Apply')),
      ]);

  Widget _rowCard(MarketPalette p, VariantRow r) {
    final img = r.imageUrl != null && widget.imageUrls.contains(r.imageUrl) ? r.imageUrl : null;
    return MarketCard(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
      color: r.isActive ? null : p.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (r.color.isNotEmpty) ...[_Swatch(hex: r.colorHex, size: 14), const SizedBox(width: 8)],
          Expanded(
            child: Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
          ),
          Text(r.isActive ? 'On sale' : 'Hidden', style: TextStyle(fontSize: 11.5, color: p.label)),
          Switch(value: r.isActive, onChanged: (v) => _changed(() => r.isActive = v)),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _pickPhoto(r),
              child: Container(
                width: 48,
                height: 48,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.line)),
                child: img != null ? MarketNetImage(img, iconSize: 18) : Icon(Icons.add_photo_alternate_outlined, size: 20, color: p.label),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: r.price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => widget.onChanged(),
                decoration: widget.decoration(hint: widget.priceHint, prefixText: '${widget.currencySymbol} '),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 84,
              child: TextField(
                controller: r.stock,
                keyboardType: TextInputType.number,
                onChanged: (_) => _changed(() {}),
                decoration: widget.decoration(hint: 'Stock'),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: TextField(controller: r.sku, decoration: widget.decoration(hint: 'SKU (optional)')),
        ),
      ]),
    );
  }
}

class _Swatch extends StatelessWidget {
  final String hex;
  final double size;
  const _Swatch({required this.hex, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: hexToColor(hex), shape: BoxShape.circle, border: Border.all(color: MarketPalette.of(context).line)),
      );
}

class _SwatchSheet extends StatelessWidget {
  final String selected;
  const _SwatchSheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Swatch color', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
        const SizedBox(height: 14),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final hex in variantSwatches)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.pop(context, hex),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hexToColor(hex),
                  shape: BoxShape.circle,
                  border: Border.all(color: hex.toUpperCase() == selected.toUpperCase() ? p.brand : p.line, width: hex.toUpperCase() == selected.toUpperCase() ? 2.5 : 1),
                ),
                child: hex.toUpperCase() == selected.toUpperCase()
                    ? Icon(Icons.check, size: 18, color: hexToColor(hex).computeLuminance() > 0.5 ? Colors.black87 : Colors.white)
                    : null,
              ),
            ),
        ]),
      ]),
    );
  }
}

/// Picks one of the listing's photos for an option. Pops the URL, or
/// `false` for "no photo".
class _PhotoSheet extends StatelessWidget {
  final List<String> urls;
  final String? selected;
  const _PhotoSheet({required this.urls, required this.selected});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Option photo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text))),
          if (selected != null) TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No photo')),
        ]),
        const SizedBox(height: 4),
        Text('Choose from this listing\'s photos', style: TextStyle(fontSize: 12, color: p.label)),
        const SizedBox(height: 12),
        if (urls.isEmpty)
          const MarketEmpty(icon: Icons.photo_library_outlined, title: 'No photos yet', message: 'Add photos in the media step first.')
        else
          Flexible(
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final u in urls)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.pop(context, u),
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: u == selected ? p.brand : p.line, width: u == selected ? 2.5 : 1),
                      ),
                      child: MarketNetImage(u, iconSize: 18),
                    ),
                  ),
              ],
            ),
          ),
      ]),
    );
  }
}
