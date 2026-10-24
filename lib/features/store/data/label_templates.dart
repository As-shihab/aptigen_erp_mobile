import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'label_model.dart';

// Built-in starter labels + the user's own templates (device-local JSON in
// shared_preferences), plus the auto-saved working draft of the designer.

LabelElement _e(LabelElementType type, double x, double y, double w, double h) => LabelElement(id: newLabelId(), type: type, x: x, y: y, w: w, h: h);

LabelDesign _simpleBarcode() => LabelDesign(id: 'builtin_simple', name: 'Simple barcode', presetId: '50x30', widthMm: 50, heightMm: 30, elements: [
      _e(LabelElementType.text, 3, 2.2, 44, 5)
        ..content = '{name}'
        ..fontSize = 9
        ..bold = true
        ..align = 'center'
        ..maxLines = 1,
      _e(LabelElementType.barcode, 4, 8, 42, 19)
        ..content = '{barcode}'
        ..humanTextSize = 8,
    ]);

LabelDesign _priceTag() => LabelDesign(id: 'builtin_price_tag', name: 'Price tag', presetId: '40x30', widthMm: 40, heightMm: 30, elements: [
      _e(LabelElementType.text, 2, 1.8, 36, 7)
        ..content = '{name}'
        ..fontSize = 7.5
        ..bold = true
        ..align = 'center'
        ..maxLines = 2,
      _e(LabelElementType.price, 2, 9, 36, 4)
        ..priceField = 'mrp'
        ..fontSize = 7
        ..strike = true
        ..align = 'center'
        ..maxLines = 1,
      _e(LabelElementType.price, 2, 13, 36, 7)
        ..fontSize = 16
        ..bold = true
        ..align = 'center'
        ..autoFit = true
        ..maxLines = 1,
      _e(LabelElementType.barcode, 3, 20.5, 34, 8)
        ..content = '{barcode}'
        ..humanTextSize = 5.5,
    ]);

LabelDesign _shelfLabel() => LabelDesign(id: 'builtin_shelf', name: 'Shelf label, big price', presetId: '100x50', widthMm: 100, heightMm: 50, border: true, cornerRadiusMm: 2, elements: [
      _e(LabelElementType.text, 4, 4, 52, 12)
        ..content = '{name}'
        ..fontSize = 12
        ..bold = true
        ..maxLines = 2,
      _e(LabelElementType.text, 4, 17, 52, 5)
        ..content = 'Per {unit}'
        ..fontSize = 8
        ..maxLines = 1,
      _e(LabelElementType.price, 58, 4, 38, 4.5)
        ..priceField = 'mrp'
        ..fontSize = 9
        ..strike = true
        ..align = 'right'
        ..maxLines = 1,
      _e(LabelElementType.price, 56, 9, 40, 20)
        ..fontSize = 36
        ..bold = true
        ..align = 'right'
        ..autoFit = true
        ..maxLines = 1,
      _e(LabelElementType.line, 4, 31, 92, 1)..stroke = 0.3,
      _e(LabelElementType.barcode, 4, 33.5, 50, 13)
        ..content = '{barcode}'
        ..humanTextSize = 7,
      _e(LabelElementType.text, 58, 35, 38, 4.5)
        ..content = 'SKU {sku}'
        ..fontSize = 7.5
        ..align = 'right'
        ..maxLines = 1,
      _e(LabelElementType.date, 58, 41, 38, 4.5)
        ..content = 'Updated '
        ..dateFormat = 'd MMM yyyy'
        ..fontSize = 6.5
        ..align = 'right'
        ..maxLines = 1,
    ]);

LabelDesign _assetTag() => LabelDesign(id: 'builtin_asset', name: 'QR asset tag', presetId: '50x25', widthMm: 50, heightMm: 25, border: true, cornerRadiusMm: 2, elements: [
      _e(LabelElementType.qr, 2.5, 2.5, 20, 20)
        ..content = '{barcode}'
        ..symbology = LabelSymbology.qrCode
        ..showHumanText = false
        ..ecLevel = 'M',
      _e(LabelElementType.text, 24.5, 3, 23, 4.5)
        ..content = '{company}'
        ..fontSize = 6.5
        ..invert = true
        ..align = 'center'
        ..maxLines = 1,
      _e(LabelElementType.text, 24.5, 9, 23, 8)
        ..content = '{name}'
        ..fontSize = 7.5
        ..bold = true
        ..maxLines = 2,
      _e(LabelElementType.text, 24.5, 17.5, 23, 4.5)
        ..content = '{barcode}'
        ..fontSize = 6.5
        ..maxLines = 1,
    ]);

LabelDesign _shipping() => LabelDesign(id: 'builtin_shipping', name: 'Shipping label 100 × 150', presetId: '100x150', widthMm: 100, heightMm: 150, border: true, cornerRadiusMm: 0, elements: [
      _e(LabelElementType.text, 0, 0, 100, 12)
        ..content = '{company}'
        ..fontSize = 16
        ..bold = true
        ..invert = true
        ..align = 'center'
        ..maxLines = 1,
      _e(LabelElementType.text, 5, 15, 40, 5)
        ..content = 'Ship to'
        ..fontSize = 9
        ..bold = true,
      _e(LabelElementType.rect, 5, 21, 90, 36)
        ..stroke = 0.5
        ..radius = 1.5,
      _e(LabelElementType.text, 8, 24, 84, 30)
        ..content = 'Customer name\nStreet address\nCity, postcode\nPhone'
        ..fontSize = 12
        ..maxLines = 5,
      _e(LabelElementType.line, 5, 60, 90, 1)..stroke = 0.5,
      _e(LabelElementType.text, 5, 63, 60, 5)
        ..content = 'Order {sku}'
        ..fontSize = 10
        ..bold = true
        ..maxLines = 1,
      _e(LabelElementType.date, 55, 63, 40, 5)
        ..content = ''
        ..dateFormat = 'd MMM yyyy'
        ..fontSize = 9
        ..align = 'right'
        ..maxLines = 1,
      _e(LabelElementType.barcode, 8, 72, 84, 32)
        ..content = '{barcode}'
        ..humanTextSize = 11,
      _e(LabelElementType.line, 5, 108, 90, 1)..stroke = 0.5,
      _e(LabelElementType.qr, 5, 112, 32, 32)
        ..content = '{barcode}'
        ..symbology = LabelSymbology.qrCode
        ..showHumanText = false,
      _e(LabelElementType.text, 42, 114, 53, 28)
        ..content = 'From\n{company}'
        ..fontSize = 10
        ..maxLines = 4,
    ]);

LabelDesign _logoLabel() => LabelDesign(id: 'builtin_logo', name: 'Product label with logo', presetId: '50x30', widthMm: 50, heightMm: 30, elements: [
      _e(LabelElementType.image, 2, 2, 9, 9)..fit = 'contain',
      _e(LabelElementType.text, 12.5, 2, 35.5, 4)
        ..content = '{company}'
        ..fontSize = 6.5
        ..bold = true
        ..maxLines = 1,
      _e(LabelElementType.text, 12.5, 6, 35.5, 5)
        ..content = '{name}'
        ..fontSize = 7
        ..maxLines = 1,
      _e(LabelElementType.barcode, 2, 12.5, 30, 15.5)
        ..content = '{barcode}'
        ..humanTextSize = 6,
      _e(LabelElementType.price, 33, 15, 15, 7)
        ..fontSize = 10
        ..bold = true
        ..align = 'right'
        ..autoFit = true
        ..maxLines = 1,
      _e(LabelElementType.text, 33, 22, 15, 4)
        ..content = '{batch}'
        ..fontSize = 5.5
        ..align = 'right'
        ..maxLines = 1,
    ]);

/// Fresh copies of the built-in starters (callers may mutate them).
List<LabelDesign> builtInLabelTemplates() => [_simpleBarcode(), _priceTag(), _shelfLabel(), _assetTag(), _shipping(), _logoLabel()];

bool isBuiltInTemplate(String id) => id.startsWith('builtin_');

class LabelTemplateStore {
  static const _templatesKey = 'store_label_templates_v1';
  static const _defaultKey = 'store_label_default_template_v1';
  static const _draftKey = 'store_label_draft_v1';

  static Future<List<LabelDesign>> loadUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_templatesKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final t in decoded)
          if (t is Map) LabelDesign.fromJson(t),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveAll(List<LabelDesign> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_templatesKey, jsonEncode([for (final t in all) t.toJson()]));
  }

  /// Insert or replace by id.
  static Future<void> upsert(LabelDesign design) async {
    final all = await loadUser();
    final i = all.indexWhere((t) => t.id == design.id);
    final copy = design.clone();
    if (i == -1) {
      all.add(copy);
    } else {
      all[i] = copy;
    }
    await _saveAll(all);
  }

  static Future<void> delete(String id) async {
    final all = await loadUser();
    all.removeWhere((t) => t.id == id);
    await _saveAll(all);
    if (await getDefaultId() == id) await setDefaultId(null);
  }

  static Future<String?> getDefaultId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultKey);
  }

  static Future<void> setDefaultId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_defaultKey);
    } else {
      await prefs.setString(_defaultKey, id);
    }
  }

  /// The default template (user or built-in), or the simple barcode starter.
  static Future<LabelDesign> loadDefault() async {
    final id = await getDefaultId();
    if (id != null) {
      if (isBuiltInTemplate(id)) {
        final match = builtInLabelTemplates().where((t) => t.id == id);
        if (match.isNotEmpty) return match.first;
      } else {
        final match = (await loadUser()).where((t) => t.id == id);
        if (match.isNotEmpty) return match.first;
      }
    }
    return builtInLabelTemplates().first;
  }

  static Future<({LabelDesign design, String? templateId})?> loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['design'] is! Map) return null;
      return (design: LabelDesign.fromJson(decoded['design'] as Map), templateId: decoded['templateId'] as String?);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveDraft(LabelDesign design, String? templateId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey, jsonEncode({'design': design.toJson(), 'templateId': templateId}));
  }
}
