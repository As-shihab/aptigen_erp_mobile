import 'package:shared_preferences/shared_preferences.dart';

/// Client-only POS preferences — same idea as desktop's `localStorage`-
/// backed sound-mute toggle (PosTerminal.tsx), not synced to the backend
/// since it's a per-device cashier preference, not a workplace setting
/// (those live in `order_settings`/`sell_settings`).
class PosLocalPrefs {
  static const _showReceiptKey = 'pos_show_receipt_after_checkout';

  /// Whether the receipt/invoice screen auto-opens after a sale completes —
  /// on by default.
  static Future<bool> getShowReceiptAfterCheckout() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showReceiptKey) ?? true;
  }

  static Future<void> setShowReceiptAfterCheckout(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showReceiptKey, value);
  }

  /// Whether a completed sale's receipt is sent to the default Bluetooth
  /// printer automatically — kept separately for the sales and pharma
  /// registers, off by default.
  static String _autoPrintKey(bool isPharma) => isPharma ? 'pharma_auto_print_receipt' : 'pos_auto_print_receipt';

  static Future<bool> getAutoPrintReceipt({bool isPharma = false}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoPrintKey(isPharma)) ?? false;
  }

  static Future<void> setAutoPrintReceipt(bool value, {bool isPharma = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPrintKey(isPharma), value);
  }
}
