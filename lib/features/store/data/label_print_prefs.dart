import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'label_pdf.dart';
import 'label_raster.dart';

enum LabelPrintMethod { bluetooth, system, pdf }

enum LabelPdfLayout { labelPages, a4Sheet }

/// Last-used Barcode lab print options, device-local (same idea as
/// `BarcodePrintPrefs` — this device's print tuning, not a workplace setting).
class LabelPrintOptions {
  LabelPrintMethod method;
  String? printerId;
  int paperWidthMm; // 58 / 80
  int copies;
  int threshold; // 0-255
  bool dither;
  double feedMm;
  LabelCutMode cut;
  LabelPdfLayout pdfLayout;
  bool monochromePdf;
  int columns;
  int rows;
  double marginTopMm;
  double marginLeftMm;
  double gapXMm;
  double gapYMm;
  int startPosition;

  LabelPrintOptions({
    this.method = LabelPrintMethod.bluetooth,
    this.printerId,
    this.paperWidthMm = 58,
    this.copies = 1,
    this.threshold = 160,
    this.dither = false,
    this.feedMm = 3,
    this.cut = LabelCutMode.none,
    this.pdfLayout = LabelPdfLayout.labelPages,
    this.monochromePdf = true,
    this.columns = 3,
    this.rows = 8,
    this.marginTopMm = 10,
    this.marginLeftMm = 7,
    this.gapXMm = 2,
    this.gapYMm = 2,
    this.startPosition = 1,
  });

  A4SheetLayout get sheet => A4SheetLayout(
        columns: columns,
        rows: rows,
        marginTopMm: marginTopMm,
        marginLeftMm: marginLeftMm,
        gapXMm: gapXMm,
        gapYMm: gapYMm,
        startPosition: startPosition,
      );

  Map<String, dynamic> toJson() => {
        'method': method.name,
        'printerId': printerId,
        'paperWidthMm': paperWidthMm,
        'copies': copies,
        'threshold': threshold,
        'dither': dither,
        'feedMm': feedMm,
        'cut': cut.name,
        'pdfLayout': pdfLayout.name,
        'monochromePdf': monochromePdf,
        'columns': columns,
        'rows': rows,
        'marginTopMm': marginTopMm,
        'marginLeftMm': marginLeftMm,
        'gapXMm': gapXMm,
        'gapYMm': gapYMm,
        'startPosition': startPosition,
      };

  factory LabelPrintOptions.fromJson(Map j) {
    double d(String k, double f) => j[k] is num ? (j[k] as num).toDouble() : f;
    int i(String k, int f) => j[k] is num ? (j[k] as num).toInt() : f;
    return LabelPrintOptions(
      method: LabelPrintMethod.values.firstWhere((m) => m.name == j['method'], orElse: () => LabelPrintMethod.bluetooth),
      printerId: j['printerId']?.toString(),
      paperWidthMm: i('paperWidthMm', 58) >= 80 ? 80 : 58,
      copies: i('copies', 1).clamp(1, 999),
      threshold: i('threshold', 160).clamp(1, 254),
      dither: j['dither'] == true,
      feedMm: d('feedMm', 3).clamp(0, 50).toDouble(),
      cut: LabelCutMode.values.firstWhere((m) => m.name == j['cut'], orElse: () => LabelCutMode.none),
      pdfLayout: LabelPdfLayout.values.firstWhere((m) => m.name == j['pdfLayout'], orElse: () => LabelPdfLayout.labelPages),
      monochromePdf: j['monochromePdf'] != false,
      columns: i('columns', 3).clamp(1, 20),
      rows: i('rows', 8).clamp(1, 40),
      marginTopMm: d('marginTopMm', 10),
      marginLeftMm: d('marginLeftMm', 7),
      gapXMm: d('gapXMm', 2),
      gapYMm: d('gapYMm', 2),
      startPosition: i('startPosition', 1).clamp(1, 800),
    );
  }

  static const _key = 'store_label_print_options_v1';

  static Future<LabelPrintOptions> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return LabelPrintOptions();
      final decoded = jsonDecode(raw);
      return decoded is Map ? LabelPrintOptions.fromJson(decoded) : LabelPrintOptions();
    } catch (_) {
      return LabelPrintOptions();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(toJson()));
  }
}
