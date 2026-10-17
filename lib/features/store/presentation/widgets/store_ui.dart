import '../../../sell/market/presentation/widgets/market_ui.dart';

// Store screens share the same SAP Horizon design kit as Sales and the online
// market (cards, semantic pills, KPI tiles, skeletons, motion). Import this
// file instead of market_ui.dart directly. Note: the kit also exports
// `toDouble`/`toInt`, which clash with store_util.dart — import store_util
// with `show`/`hide` where both are needed.
export '../../../sell/market/presentation/widgets/market_ui.dart';

/// Store document status codes (SPR, SR, MRR, returns, PO) → sentence case.
String storeStatusLabel(String status) => switch (status) {
      'PENDING' => 'Pending',
      'APPROVED' => 'Approved',
      'REJECTED' => 'Rejected',
      'ORDERED' => 'Ordered',
      'ISSUED' => 'Issued',
      'PARTIAL' => 'Partial',
      'COMPLETED' => 'Completed',
      'HOLD' => 'On hold',
      'SENT' => 'Sent',
      'PARTIALLY_RECEIVED' => 'Partially received',
      'RECEIVED' => 'Received',
      'CANCELLED' => 'Cancelled',
      'ACTIVE' => 'Active',
      'EXPIRED' => 'Expired',
      'DRAFT' => 'Draft',
      '' => '—',
      _ => status[0] + status.substring(1).toLowerCase().replaceAll('_', ' '),
    };

MarketTone storeStatusTone(String status) => switch (status) {
      'APPROVED' || 'COMPLETED' || 'RECEIVED' || 'ISSUED' || 'ACTIVE' => MarketTone.ok,
      'PENDING' || 'PARTIAL' || 'PARTIALLY_RECEIVED' || 'HOLD' || 'DRAFT' => MarketTone.warn,
      'REJECTED' || 'CANCELLED' || 'EXPIRED' => MarketTone.error,
      'ORDERED' || 'SENT' => MarketTone.info,
      _ => MarketTone.neutral,
    };

/// Stock pill for a product: (label, tone).
(String, MarketTone) stockPill({required bool trackStock, required double qty, required double lowAt}) {
  String q(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  if (!trackStock) return ('Not tracked', MarketTone.neutral);
  if (qty <= 0) return ('Out of stock', MarketTone.error);
  if (qty <= lowAt) return ('Low · ${q(qty)}', MarketTone.warn);
  return ('${q(qty)} in stock', MarketTone.ok);
}
