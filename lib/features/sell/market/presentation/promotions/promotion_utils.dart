import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import '../flash_sales/flash_sale_widgets.dart';
import '../widgets/market_ui.dart';

// Helpers for market_promotions rows (desktop promotions/Coupons.tsx).

/// "10% off, max 50" / "25 off" / "Free shipping".
String discountLabel(Map<String, dynamic> p) {
  final type = '${p['discount_type'] ?? 'percent'}';
  if (type == 'free_shipping') return 'Free shipping';
  final value = toDouble(p['value']);
  if (type == 'percent') {
    final max = p['max_discount'];
    return '${plainNum(value)}% off${max == null ? '' : ', max ${plainNum(toDouble(max))}'}';
  }
  return '${plainNum(value)} off';
}

/// listing_ids is stored as a JSON array string, e.g. "[1,5]".
List<int> parseListingIds(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) return raw.map(toInt).where((n) => n > 0).toList();
  final s = '$raw'.trim();
  if (s.isEmpty) return [];
  try {
    final arr = jsonDecode(s);
    return arr is List ? arr.map(toInt).where((n) => n > 0).toList() : [];
  } catch (_) {
    return [];
  }
}

/// 8-character code without look-alike characters (no 0/O, 1/I).
String generateCouponCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
}

bool isCoupon(Map<String, dynamic> p) => '${p['code'] ?? ''}'.trim().isNotEmpty;

/// Uppercase, no whitespace — for the coupon code field.
class CouponCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    final removed = newValue.text.length - text.length;
    final offset = (newValue.selection.end - removed).clamp(0, text.length);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: offset));
  }
}

/// Live / scheduled / expired / used up / inactive for a promotion.
({String label, MarketTone tone}) promotionStatus(Map<String, dynamic> p, DateTime now) {
  if (p['is_active'] != true) return (label: 'Inactive', tone: MarketTone.neutral);
  final starts = parseDate(p['starts_at']);
  final ends = parseDate(p['ends_at']);
  if (ends != null && ends.isBefore(now)) return (label: 'Expired', tone: MarketTone.neutral);
  final limit = p['usage_limit'];
  if (limit != null && toInt(p['used_count']) >= toInt(limit)) return (label: 'Used up', tone: MarketTone.warn);
  if (starts != null && starts.isAfter(now)) return (label: 'Scheduled', tone: MarketTone.info);
  return (label: 'Active', tone: MarketTone.ok);
}
