import 'package:barcode_widget/barcode_widget.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/currency.dart';

// Label designer data model (Barcode lab) — a label is a fixed-size canvas
// in millimetres with a z-ordered list of elements. Everything is plain JSON
// so designs can be saved as templates in shared_preferences and snapshotted
// for undo/redo.

const _uuid = Uuid();
String newLabelId() => _uuid.v4();

double _d(dynamic v, double fallback) => v is num ? v.toDouble() : double.tryParse('$v') ?? fallback;
int _i(dynamic v, int fallback) => v is num ? v.toInt() : int.tryParse('$v') ?? fallback;
bool _b(dynamic v, bool fallback) => v is bool ? v : (v == null ? fallback : '$v' == 'true');
String _s(dynamic v, String fallback) => v == null ? fallback : '$v';

// ── Symbologies ─────────────────────────────────────────────────────────

enum LabelSymbology { code128, code39, code93, ean13, ean8, upcA, upcE, itf, itf14, codabar, qrCode, dataMatrix, pdf417, aztec }

extension LabelSymbologyX on LabelSymbology {
  String get label => switch (this) {
        LabelSymbology.code128 => 'Code 128',
        LabelSymbology.code39 => 'Code 39',
        LabelSymbology.code93 => 'Code 93',
        LabelSymbology.ean13 => 'EAN-13',
        LabelSymbology.ean8 => 'EAN-8',
        LabelSymbology.upcA => 'UPC-A',
        LabelSymbology.upcE => 'UPC-E',
        LabelSymbology.itf => 'ITF (interleaved 2 of 5)',
        LabelSymbology.itf14 => 'ITF-14',
        LabelSymbology.codabar => 'Codabar',
        LabelSymbology.qrCode => 'QR code',
        LabelSymbology.dataMatrix => 'Data matrix',
        LabelSymbology.pdf417 => 'PDF417',
        LabelSymbology.aztec => 'Aztec',
      };

  String get hint => switch (this) {
        LabelSymbology.code128 => 'Any text or number',
        LabelSymbology.code39 => 'Capital letters, digits and - . \$ / + % space',
        LabelSymbology.code93 => 'Capital letters, digits and - . \$ / + % space',
        LabelSymbology.ean13 => '12 digits (check digit added) or 13 digits',
        LabelSymbology.ean8 => '7 digits (check digit added) or 8 digits',
        LabelSymbology.upcA => '11 digits (check digit added) or 12 digits',
        LabelSymbology.upcE => '6 to 8 digits',
        LabelSymbology.itf => 'Even number of digits',
        LabelSymbology.itf14 => '13 digits (check digit added) or 14 digits',
        LabelSymbology.codabar => 'Digits and - \$ : / . +',
        LabelSymbology.qrCode => 'Any text, link or number',
        LabelSymbology.dataMatrix => 'Any text or number',
        LabelSymbology.pdf417 => 'Any text or number',
        LabelSymbology.aztec => 'Any text or number',
      };

  bool get is2D => this == LabelSymbology.qrCode || this == LabelSymbology.dataMatrix || this == LabelSymbology.pdf417 || this == LabelSymbology.aztec;

  /// Square symbols — drawn as the largest square that fits the element box.
  bool get isSquare => this == LabelSymbology.qrCode || this == LabelSymbology.dataMatrix || this == LabelSymbology.aztec;

  bool get hasErrorLevel => this == LabelSymbology.qrCode || this == LabelSymbology.pdf417 || this == LabelSymbology.aztec;

  Barcode barcode({String ecLevel = 'M'}) => switch (this) {
        LabelSymbology.code128 => Barcode.code128(),
        LabelSymbology.code39 => Barcode.code39(),
        LabelSymbology.code93 => Barcode.code93(),
        LabelSymbology.ean13 => Barcode.ean13(),
        LabelSymbology.ean8 => Barcode.ean8(),
        LabelSymbology.upcA => Barcode.upcA(),
        LabelSymbology.upcE => Barcode.upcE(),
        LabelSymbology.itf => Barcode.itf(),
        LabelSymbology.itf14 => Barcode.itf14(),
        LabelSymbology.codabar => Barcode.codabar(),
        LabelSymbology.qrCode => Barcode.qrCode(
            errorCorrectLevel: switch (ecLevel) {
              'L' => BarcodeQRCorrectionLevel.low,
              'Q' => BarcodeQRCorrectionLevel.quartile,
              'H' => BarcodeQRCorrectionLevel.high,
              _ => BarcodeQRCorrectionLevel.medium,
            },
          ),
        LabelSymbology.dataMatrix => Barcode.dataMatrix(),
        LabelSymbology.pdf417 => Barcode.pdf417(
            securityLevel: switch (ecLevel) {
              'L' => Pdf417SecurityLevel.level1,
              'Q' => Pdf417SecurityLevel.level4,
              'H' => Pdf417SecurityLevel.level6,
              _ => Pdf417SecurityLevel.level2,
            },
          ),
        LabelSymbology.aztec => Barcode.aztec(
            minECCPercent: switch (ecLevel) {
              'L' => 10,
              'Q' => 36,
              'H' => 50,
              _ => 23,
            },
          ),
      };
}

const kOneDSymbologies = [
  LabelSymbology.code128,
  LabelSymbology.code39,
  LabelSymbology.code93,
  LabelSymbology.ean13,
  LabelSymbology.ean8,
  LabelSymbology.upcA,
  LabelSymbology.upcE,
  LabelSymbology.itf,
  LabelSymbology.itf14,
  LabelSymbology.codabar,
];
const kTwoDSymbologies = [LabelSymbology.qrCode, LabelSymbology.dataMatrix, LabelSymbology.pdf417, LabelSymbology.aztec];

/// Null when [data] can be encoded as [s]; otherwise a short sentence-case
/// message for the inline error. Never throws.
String? validateSymbology(LabelSymbology s, String data, {String ecLevel = 'M'}) {
  if (data.isEmpty) return 'Enter a value to encode';
  final digits = RegExp(r'^\d+$').hasMatch(data);
  String? lengthRule(List<int> lengths, String name) {
    if (!digits) return '$name accepts digits only';
    if (!lengths.contains(data.length)) return '$name needs ${lengths.join(' or ')} digits';
    return null;
  }

  final pre = switch (s) {
    LabelSymbology.ean13 => lengthRule([12, 13], 'EAN-13'),
    LabelSymbology.ean8 => lengthRule([7, 8], 'EAN-8'),
    LabelSymbology.upcA => lengthRule([11, 12], 'UPC-A'),
    LabelSymbology.upcE => lengthRule([6, 7, 8], 'UPC-E'),
    LabelSymbology.itf14 => lengthRule([13, 14], 'ITF-14'),
    LabelSymbology.itf => !digits ? 'ITF accepts digits only' : (data.length.isOdd ? 'ITF needs an even number of digits' : null),
    _ => null,
  };
  if (pre != null) return pre;
  // Full-length GS1 codes carry their own check digit — verify it rather
  // than letting the encoder silently print a different one.
  final fullLength = switch (s) {
    LabelSymbology.ean13 => 13,
    LabelSymbology.ean8 => 8,
    LabelSymbology.upcA => 12,
    LabelSymbology.itf14 => 14,
    _ => 0,
  };
  if (fullLength > 0 && data.length == fullLength && gs1CheckDigit(data.substring(0, fullLength - 1)) != int.parse(data[fullLength - 1])) {
    return 'Check digit is wrong, it should be ${gs1CheckDigit(data.substring(0, fullLength - 1))}';
  }
  try {
    s.barcode(ecLevel: ecLevel).verify(data);
    return null;
  } on BarcodeException catch (e) {
    final m = e.message.toLowerCase();
    if (m.contains('checksum') || m.contains('check digit')) {
      return 'Check digit is wrong — leave it off and it is calculated';
    }
    if (m.contains('too long') || m.contains('too much') || m.contains('capacity')) {
      return 'Too much data for ${s.label}';
    }
    return 'This value can\'t be encoded as ${s.label}';
  } catch (_) {
    return 'This value can\'t be encoded as ${s.label}';
  }
}

/// GS1 mod-10 check digit for the digits [body] (EAN, UPC, ITF-14).
int gs1CheckDigit(String body) {
  var sum = 0;
  for (var i = 0; i < body.length; i++) {
    final digit = body.codeUnitAt(body.length - 1 - i) - 48;
    sum += i.isEven ? digit * 3 : digit;
  }
  return (10 - sum % 10) % 10;
}

// ── Merge fields ────────────────────────────────────────────────────────

/// Merge fields usable as `{key}` inside text, barcode data and more.
const List<({String key, String label})> kLabelMergeFields = [
  (key: 'name', label: 'Product name'),
  (key: 'sku', label: 'SKU'),
  (key: 'barcode', label: 'Barcode'),
  (key: 'price', label: 'Price'),
  (key: 'mrp', label: 'MRP / old price'),
  (key: 'unit', label: 'Unit'),
  (key: 'batch', label: 'Batch'),
  (key: 'expiry', label: 'Expiry'),
  (key: 'date', label: 'Today'),
  (key: 'company', label: 'Company'),
];

/// Values shown on the canvas while designing with no data source chosen.
Map<String, String> sampleLabelData({String company = ''}) => {
      'name': 'Sample product 500 g',
      'sku': 'SKU-10021',
      'barcode': '890123456789',
      'price': '120',
      'mrp': '150',
      'unit': 'pcs',
      'batch': 'B-2410',
      'expiry': DateFormat('d MMM yyyy').format(DateTime.now().add(const Duration(days: 180))),
      'company': company.isEmpty ? 'Your company' : company,
    };

String _fmtMoneyMerge(String raw) {
  final v = double.tryParse(raw.replaceAll(',', '').trim());
  return v == null ? raw : formatMoney(v);
}

/// Replaces `{key}` with values from [data]; price/mrp numbers get currency
/// formatting, `{date}` defaults to today. Unknown keys stay as typed.
String resolveMerge(String template, Map<String, String> data) {
  if (!template.contains('{')) return template;
  return template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
    final key = m.group(1)!;
    final value = data[key];
    if (key == 'date' && (value == null || value.isEmpty)) return DateFormat('d MMM yyyy').format(DateTime.now());
    if (value == null) return kLabelMergeFields.any((f) => f.key == key) ? '' : m.group(0)!;
    if (key == 'price' || key == 'mrp') return _fmtMoneyMerge(value);
    return value;
  });
}

/// Raw (unformatted) barcode data — `{price}` stays numeric here.
String resolveMergeRaw(String template, Map<String, String> data) {
  if (!template.contains('{')) return template;
  return template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
    final key = m.group(1)!;
    if (key == 'date' && (data[key] ?? '').isEmpty) return DateFormat('yyyyMMdd').format(DateTime.now());
    return data[key] ?? (kLabelMergeFields.any((f) => f.key == key) ? '' : m.group(0)!);
  });
}

// ── Elements ────────────────────────────────────────────────────────────

enum LabelElementType { barcode, qr, text, price, image, line, rect, ellipse, date }

extension LabelElementTypeX on LabelElementType {
  String get label => switch (this) {
        LabelElementType.barcode => 'Barcode',
        LabelElementType.qr => 'QR / 2D code',
        LabelElementType.text => 'Text',
        LabelElementType.price => 'Price',
        LabelElementType.image => 'Image',
        LabelElementType.line => 'Line',
        LabelElementType.rect => 'Rectangle',
        LabelElementType.ellipse => 'Ellipse',
        LabelElementType.date => 'Date stamp',
      };

  bool get isCode => this == LabelElementType.barcode || this == LabelElementType.qr;
  bool get isTextual => this == LabelElementType.text || this == LabelElementType.price || this == LabelElementType.date;
}

const kDateFormats = ['d MMM yyyy', 'dd/MM/yyyy', 'MM/dd/yyyy', 'yyyy-MM-dd', 'dd-MM-yy', 'MMM yyyy', 'd MMM yyyy, HH:mm', 'HH:mm'];

/// One element on the label. Mutable on purpose — the designer edits it in
/// place and snapshots the whole design (JSON) for undo/redo.
class LabelElement {
  String id;
  LabelElementType type;

  /// Visual bounding box on the label, in mm (already rotated).
  double x, y, w, h;
  int rotation; // 0, 90, 180, 270
  bool locked;

  /// Text / barcode data / date prefix / custom price amount. May contain merge fields.
  String content;

  // Codes
  LabelSymbology symbology;
  bool showHumanText;
  double humanTextSize; // pt
  String ecLevel; // L M Q H

  // Text-like
  double fontSize; // pt
  bool bold;
  bool italic;
  String align; // left center right
  int maxLines; // 0 = unlimited
  bool autoFit;
  bool invert;

  // Price
  String priceField; // price mrp custom
  String currencyStyle; // symbol code none
  int decimals;
  bool strike;

  // Image
  String? imageB64;
  String fit; // contain cover fill
  bool grayscale;

  // Shapes
  bool vertical;
  double stroke; // mm
  bool fill;
  double radius; // mm

  // Date
  String dateFormat;
  int dateOffsetDays;

  LabelElement({
    required this.id,
    required this.type,
    this.x = 2,
    this.y = 2,
    this.w = 20,
    this.h = 8,
    this.rotation = 0,
    this.locked = false,
    this.content = '',
    this.symbology = LabelSymbology.code128,
    this.showHumanText = true,
    this.humanTextSize = 7,
    this.ecLevel = 'M',
    this.fontSize = 9,
    this.bold = false,
    this.italic = false,
    this.align = 'left',
    this.maxLines = 0,
    this.autoFit = false,
    this.invert = false,
    this.priceField = 'price',
    this.currencyStyle = 'symbol',
    this.decimals = 2,
    this.strike = false,
    this.imageB64,
    this.fit = 'contain',
    this.grayscale = true,
    this.vertical = false,
    this.stroke = 0.4,
    this.fill = false,
    this.radius = 0,
    this.dateFormat = 'd MMM yyyy',
    this.dateOffsetDays = 0,
  });

  /// A new element with sensible defaults, sized relative to a label of
  /// [labelW] × [labelH] mm and centred on it.
  factory LabelElement.create(LabelElementType type, double labelW, double labelH) {
    final e = LabelElement(id: newLabelId(), type: type);
    switch (type) {
      case LabelElementType.barcode:
        e
          ..content = '{barcode}'
          ..w = (labelW * 0.8).clamp(10, 90).toDouble()
          ..h = (labelH * 0.4).clamp(6, 40).toDouble();
      case LabelElementType.qr:
        final side = (labelH * 0.6).clamp(8, 50).toDouble();
        e
          ..content = '{barcode}'
          ..symbology = LabelSymbology.qrCode
          ..showHumanText = false
          ..w = side
          ..h = side;
      case LabelElementType.text:
        e
          ..content = '{name}'
          ..w = (labelW * 0.8).clamp(10, 90).toDouble()
          ..h = 5
          ..fontSize = 9
          ..maxLines = 1;
      case LabelElementType.price:
        e
          ..w = (labelW * 0.6).clamp(12, 80).toDouble()
          ..h = 8
          ..fontSize = 16
          ..bold = true
          ..align = 'center'
          ..maxLines = 1;
      case LabelElementType.image:
        final side = (labelH * 0.4).clamp(6, 40).toDouble();
        e
          ..w = side
          ..h = side;
      case LabelElementType.line:
        e
          ..w = (labelW * 0.8).clamp(5, 100).toDouble()
          ..h = 1.5
          ..stroke = 0.4;
      case LabelElementType.rect:
        e
          ..w = (labelW * 0.5).clamp(5, 100).toDouble()
          ..h = (labelH * 0.4).clamp(4, 100).toDouble()
          ..stroke = 0.4;
      case LabelElementType.ellipse:
        final side = (labelH * 0.4).clamp(4, 60).toDouble();
        e
          ..w = side
          ..h = side
          ..stroke = 0.4;
      case LabelElementType.date:
        e
          ..content = 'Packed: '
          ..w = (labelW * 0.6).clamp(10, 80).toDouble()
          ..h = 4.5
          ..fontSize = 7
          ..maxLines = 1;
    }
    e
      ..x = ((labelW - e.w) / 2).clamp(0, labelW).toDouble()
      ..y = ((labelH - e.h) / 2).clamp(0, labelH).toDouble();
    return e;
  }

  double get cx => x + w / 2;
  double get cy => y + h / 2;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'rotation': rotation,
        'locked': locked,
        'content': content,
        'symbology': symbology.name,
        'showHumanText': showHumanText,
        'humanTextSize': humanTextSize,
        'ecLevel': ecLevel,
        'fontSize': fontSize,
        'bold': bold,
        'italic': italic,
        'align': align,
        'maxLines': maxLines,
        'autoFit': autoFit,
        'invert': invert,
        'priceField': priceField,
        'currencyStyle': currencyStyle,
        'decimals': decimals,
        'strike': strike,
        if (imageB64 != null) 'imageB64': imageB64,
        'fit': fit,
        'grayscale': grayscale,
        'vertical': vertical,
        'stroke': stroke,
        'fill': fill,
        'radius': radius,
        'dateFormat': dateFormat,
        'dateOffsetDays': dateOffsetDays,
      };

  factory LabelElement.fromJson(Map json) => LabelElement(
        id: _s(json['id'], newLabelId()),
        type: LabelElementType.values.firstWhere((t) => t.name == json['type'], orElse: () => LabelElementType.text),
        x: _d(json['x'], 2),
        y: _d(json['y'], 2),
        w: _d(json['w'], 20).clamp(0.2, 1000).toDouble(),
        h: _d(json['h'], 8).clamp(0.2, 1000).toDouble(),
        rotation: const [0, 90, 180, 270].contains(_i(json['rotation'], 0)) ? _i(json['rotation'], 0) : 0,
        locked: _b(json['locked'], false),
        content: _s(json['content'], ''),
        symbology: LabelSymbology.values.firstWhere((t) => t.name == json['symbology'], orElse: () => LabelSymbology.code128),
        showHumanText: _b(json['showHumanText'], true),
        humanTextSize: _d(json['humanTextSize'], 7),
        ecLevel: _s(json['ecLevel'], 'M'),
        fontSize: _d(json['fontSize'], 9),
        bold: _b(json['bold'], false),
        italic: _b(json['italic'], false),
        align: _s(json['align'], 'left'),
        maxLines: _i(json['maxLines'], 0),
        autoFit: _b(json['autoFit'], false),
        invert: _b(json['invert'], false),
        priceField: _s(json['priceField'], 'price'),
        currencyStyle: _s(json['currencyStyle'], 'symbol'),
        decimals: _i(json['decimals'], 2),
        strike: _b(json['strike'], false),
        imageB64: json['imageB64'] as String?,
        fit: _s(json['fit'], 'contain'),
        grayscale: _b(json['grayscale'], true),
        vertical: _b(json['vertical'], false),
        stroke: _d(json['stroke'], 0.4),
        fill: _b(json['fill'], false),
        radius: _d(json['radius'], 0),
        dateFormat: _s(json['dateFormat'], 'd MMM yyyy'),
        dateOffsetDays: _i(json['dateOffsetDays'], 0),
      );

  LabelElement clone({bool newId = false}) {
    final c = LabelElement.fromJson(toJson());
    if (newId) c.id = newLabelId();
    return c;
  }

  /// Barcode / 2D data after merge fields are filled in.
  String codeData(Map<String, String> data) => resolveMergeRaw(content, data).trim();

  /// Code validation for the inline error; null when fine or not a code.
  String? codeError(Map<String, String> data) => type.isCode ? validateSymbology(symbology, codeData(data), ecLevel: ecLevel) : null;

  /// The text a textual element renders (merge fields resolved, price
  /// formatted, date stamped).
  String displayText(Map<String, String> data) {
    switch (type) {
      case LabelElementType.text:
        return resolveMerge(content, data);
      case LabelElementType.price:
        final raw = switch (priceField) {
          'mrp' => data['mrp'] ?? '',
          'custom' => resolveMergeRaw(content, data),
          _ => data['price'] ?? '',
        };
        final v = double.tryParse(raw.replaceAll(',', '').trim());
        if (v == null) return raw;
        return switch (currencyStyle) {
          'code' => formatMoneyAscii(v, decimalDigits: decimals),
          'none' => NumberFormat.decimalPatternDigits(decimalDigits: decimals).format(v),
          _ => formatMoney(v, decimalDigits: decimals),
        };
      case LabelElementType.date:
        final when = DateTime.now().add(Duration(days: dateOffsetDays));
        String stamp;
        try {
          stamp = DateFormat(dateFormat.isEmpty ? 'd MMM yyyy' : dateFormat).format(when);
        } catch (_) {
          stamp = DateFormat('d MMM yyyy').format(when);
        }
        return '${resolveMerge(content, data)}$stamp';
      default:
        return '';
    }
  }
}

// ── Label ───────────────────────────────────────────────────────────────

class LabelPreset {
  final String id;
  final String label;
  final double w;
  final double h;
  final bool roll;
  const LabelPreset(this.id, this.label, this.w, this.h, {this.roll = false});
}

const kLabelPresets = [
  LabelPreset('30x20', '30 × 20 mm', 30, 20),
  LabelPreset('40x30', '40 × 30 mm', 40, 30),
  LabelPreset('50x25', '50 × 25 mm', 50, 25),
  LabelPreset('50x30', '50 × 30 mm', 50, 30),
  LabelPreset('roll58', '58 mm roll', 58, 40, roll: true),
  LabelPreset('roll80', '80 mm roll', 80, 50, roll: true),
  LabelPreset('100x50', '100 × 50 mm', 100, 50),
  LabelPreset('100x150', '100 × 150 mm shipping', 100, 150),
];

class LabelDesign {
  String id;
  String name;
  String presetId; // one of kLabelPresets ids or 'custom'
  double widthMm;
  double heightMm;
  double cornerRadiusMm;
  bool border;
  bool blackBackground;
  int dpi; // 203 or 300
  double gapMm;
  List<LabelElement> elements;

  LabelDesign({
    required this.id,
    this.name = 'Untitled label',
    this.presetId = '50x30',
    this.widthMm = 50,
    this.heightMm = 30,
    this.cornerRadiusMm = 1.5,
    this.border = false,
    this.blackBackground = false,
    this.dpi = 203,
    this.gapMm = 3,
    List<LabelElement>? elements,
  }) : elements = elements ?? [];

  bool get landscape => widthMm >= heightMm;
  String get sizeLabel => '${_mm(widthMm)} × ${_mm(heightMm)} mm';
  static String _mm(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  int dots(double mm, [int? atDpi]) => (mm / 25.4 * (atDpi ?? dpi)).round();

  LabelElement? byId(String? id) {
    if (id == null) return null;
    for (final e in elements) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Merge-field keys referenced anywhere on the label.
  Set<String> usedFields() {
    final out = <String>{};
    for (final e in elements) {
      for (final m in RegExp(r'\{(\w+)\}').allMatches(e.content)) {
        out.add(m.group(1)!);
      }
      if (e.type == LabelElementType.price && e.priceField != 'custom') out.add(e.priceField);
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'presetId': presetId,
        'widthMm': widthMm,
        'heightMm': heightMm,
        'cornerRadiusMm': cornerRadiusMm,
        'border': border,
        'blackBackground': blackBackground,
        'dpi': dpi,
        'gapMm': gapMm,
        'elements': elements.map((e) => e.toJson()).toList(),
      };

  factory LabelDesign.fromJson(Map json) => LabelDesign(
        id: _s(json['id'], newLabelId()),
        name: _s(json['name'], 'Untitled label'),
        presetId: _s(json['presetId'], 'custom'),
        widthMm: _d(json['widthMm'], 50).clamp(5, 300).toDouble(),
        heightMm: _d(json['heightMm'], 30).clamp(5, 400).toDouble(),
        cornerRadiusMm: _d(json['cornerRadiusMm'], 0),
        border: _b(json['border'], false),
        blackBackground: _b(json['blackBackground'], false),
        dpi: _i(json['dpi'], 203) == 300 ? 300 : 203,
        gapMm: _d(json['gapMm'], 3),
        elements: [
          for (final e in (json['elements'] is List ? json['elements'] as List : const []))
            if (e is Map) LabelElement.fromJson(e),
        ],
      );

  LabelDesign clone({bool newId = false}) {
    final c = LabelDesign.fromJson(toJson());
    if (newId) c.id = newLabelId();
    return c;
  }
}
