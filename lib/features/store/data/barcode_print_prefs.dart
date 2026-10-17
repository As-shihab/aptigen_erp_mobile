import 'package:shared_preferences/shared_preferences.dart';

/// Device-local barcode print preferences — bar height/width and the
/// physical label size (mm), persisted so they're remembered across labels/
/// sessions instead of resetting to a default every time (same idea as
/// `PosLocalPrefs`, this device's own print-tuning, not a workplace-wide
/// setting). Label width/height aren't sent to the printer — there's no
/// standard ESC/POS command for it (that's TSPL/ZPL vendor territory) —
/// they're used client-side to size the on-screen preview and to suggest a
/// bar height that actually fits the physical sticker.
class BarcodePrintPrefs {
  static const _barHeightKey = 'store_barcode_print_bar_height_v1';
  static const _barWidthKey = 'store_barcode_print_bar_width_v1';
  static const _labelWidthMmKey = 'store_barcode_print_label_width_mm_v1';
  static const _labelHeightMmKey = 'store_barcode_print_label_height_mm_v1';
  static const _showBarcodeTextKey = 'store_barcode_print_show_barcode_text_v1';

  static const defaultBarHeight = 120;
  static const defaultBarWidth = 2;
  static const defaultLabelWidthMm = 38.0;
  static const defaultLabelHeightMm = 25.0;

  /// Roughly 203dpi — the common resolution on small Bluetooth thermal
  /// printers (58/80mm receipt-and-label combos).
  static const dotsPerMm = 8.0;

  static Future<int> getBarHeight() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_barHeightKey) ?? defaultBarHeight;
  }

  static Future<void> setBarHeight(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_barHeightKey, value);
  }

  static Future<int> getBarWidth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_barWidthKey) ?? defaultBarWidth;
  }

  static Future<void> setBarWidth(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_barWidthKey, value);
  }

  static Future<double> getLabelWidthMm() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_labelWidthMmKey) ?? defaultLabelWidthMm;
  }

  static Future<void> setLabelWidthMm(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_labelWidthMmKey, value);
  }

  static Future<double> getLabelHeightMm() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_labelHeightMmKey) ?? defaultLabelHeightMm;
  }

  static Future<void> setLabelHeightMm(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_labelHeightMmKey, value);
  }

  static Future<bool> getShowBarcodeText() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showBarcodeTextKey) ?? true;
  }

  static Future<void> setShowBarcodeText(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showBarcodeTextKey, value);
  }

  /// Suggests a bar height (dots) that leaves room for the title/HRI text
  /// and top/bottom margins within the given label height.
  static int suggestBarHeight(double labelHeightMm) {
    const textAndMarginMm = 8.0;
    final barHeightMm = (labelHeightMm - textAndMarginMm).clamp(5.0, 1000.0);
    return (barHeightMm * dotsPerMm).round().clamp(40, 250);
  }
}
