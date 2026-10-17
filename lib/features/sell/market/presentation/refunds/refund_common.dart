import '../orders/order_common.dart';
import '../widgets/market_ui.dart';

const refundStatusLabel = {
  'requested': 'Requested',
  'approved': 'Approved',
  'refunded': 'Refunded',
  'rejected': 'Rejected',
};

MarketTone refundStatusTone(String s) => switch (s) {
      'requested' => MarketTone.warn,
      'approved' => MarketTone.info,
      'refunded' => MarketTone.ok,
      'rejected' => MarketTone.error,
      _ => MarketTone.neutral,
    };

const refundMethods = [
  ('original', 'Original payment method'),
  ('cash', 'Cash'),
  ('mobile', 'Mobile wallet'),
  ('bank', 'Bank transfer'),
];

String refundMethodLabel(String? id) {
  for (final m in refundMethods) {
    if (m.$1 == id) return m.$2;
  }
  return id ?? '—';
}

/// Allowed next states per current status (server enforces the same).
const refundTransitions = {
  'requested': ['approved', 'rejected', 'refunded'],
  'approved': ['refunded', 'rejected'],
};

String refundBuyerName(Map<String, dynamic> r) =>
    str(r['buyer_name']) ?? str(asMap(r['buyer'])['name']) ?? str(asMap(r['order'])['shipping_name']) ?? 'Unknown buyer';

String? refundBuyerPhone(Map<String, dynamic> r) =>
    str(r['buyer_phone']) ?? str(asMap(r['buyer'])['phone']) ?? str(asMap(r['order'])['shipping_phone']);

String? refundBuyerEmail(Map<String, dynamic> r) => str(r['buyer_email']) ?? str(asMap(r['buyer'])['email']);
