import 'package:intl/intl.dart';
import '../network/http_client.dart';
import '../storage/app_storage.dart';

/// Workplace-driven currency, mirroring erp/desktop's `utils/currency.ts` —
/// every amount shown across the app uses the current workplace's ISO 4217
/// `currency` code (`workplaces.currency`, see cloud/prisma/schema/
/// workplace.prisma) instead of a hardcoded '$', so a BDT/EUR/etc. workplace
/// sees its own symbol everywhere: Store, and anywhere else money is shown.
///
/// Held as an in-memory cache rather than re-read from storage on every
/// build — `AppStorage` reads are async and most call sites need the code
/// synchronously inside `build()`/string interpolation, same reasoning
/// desktop had for keeping a `localStorage`-backed value in a React context
/// instead of an async fetch per render. Refreshed once the cached user/
/// workplace blob is known to have changed (splash-time session restore,
/// workplace activation) — see `AuthService.activateWorkplace` and
/// `_SessionGate._resolve` (app.dart).
class WorkplaceCurrency {
  static String _code = 'USD';
  static String get code => _code;

  static void set(String? currencyCode) {
    final trimmed = currencyCode?.trim() ?? '';
    _code = trimmed.isEmpty ? 'USD' : trimmed;
  }

  /// Re-derives the code from whatever's currently cached in `AppStorage` —
  /// call after a cold start where a session is being restored rather than
  /// freshly activated (activation already has the workplace object in hand
  /// and can call `set()` directly).
  ///
  /// Sessions cached **before** this currency feature existed have a
  /// `workplace`/`selectedWorkplace` blob with no `currency` key at all —
  /// that's not "unset", it's stale data, so silently defaulting to USD
  /// would keep showing the wrong symbol forever for any already-logged-in
  /// user. When the key is missing, fetch the real value once from `GET
  /// workplace/me` and patch it into the cached blob so this only happens
  /// the one time per stale session.
  static Future<void> refresh(ApiClient client) async {
    final user = await AppStorage.getUser();
    final workplace = (user?['selectedWorkplace'] ?? user?['workplace']) as Map?;
    if (workplace != null && workplace.containsKey('currency')) {
      set(workplace['currency']?.toString());
      return;
    }

    try {
      final fresh = await client.get('workplace/me', isV8: false);
      final currency = (fresh is Map ? fresh['currency'] : null)?.toString();
      set(currency);
      if (user != null && workplace != null && currency != null) {
        final patchedWorkplace = {...workplace, 'currency': currency};
        await AppStorage.setUser({...user, 'workplace': patchedWorkplace, 'selectedWorkplace': patchedWorkplace});
      }
    } catch (_) {
      set(null);
    }
  }
}

/// The workplace's currency symbol (e.g. `$`, `৳`, `€`) — falls back to the
/// raw ISO code itself if it isn't a symbol `intl` recognizes.
String currencySymbol([String? currencyCode]) {
  final code = currencyCode ?? WorkplaceCurrency.code;
  try {
    return NumberFormat.simpleCurrency(name: code).currencySymbol;
  } catch (_) {
    return code;
  }
}

/// Formats [value] with the workplace's currency symbol. `decimalDigits`
/// defaults to 2 (retail prices) — pass 0 for large aggregate KPIs (stock
/// value, revenue totals, ...), matching desktop's `formatMoney()` call
/// sites which round those to whole numbers.
String formatMoney(num value, {String? currencyCode, int decimalDigits = 2}) {
  final code = currencyCode ?? WorkplaceCurrency.code;
  try {
    return NumberFormat.simpleCurrency(name: code, decimalDigits: decimalDigits).format(value);
  } catch (_) {
    return '${currencySymbol(code)}${value.toStringAsFixed(decimalDigits)}';
  }
}

/// Same amounts, but with the ISO code (`BDT 1,234`) instead of
/// `formatMoney()`'s Unicode symbol (`৳1,234`) — for output surfaces with no
/// bundled Unicode font/code-page (the printed PDF invoice, raw ESC/POS
/// thermal-printer bytes), where a non-Latin currency sign like the Taka or
/// Rupee mark would render as a blank/tofu glyph or corrupt the byte
/// stream. The on-screen app keeps the real symbol everywhere else — this
/// is a print-only fallback, not a regression in the currency feature.
String formatMoneyAscii(num value, {String? currencyCode, int decimalDigits = 2}) {
  final code = currencyCode ?? WorkplaceCurrency.code;
  return NumberFormat.currency(symbol: '$code ', decimalDigits: decimalDigits).format(value);
}
