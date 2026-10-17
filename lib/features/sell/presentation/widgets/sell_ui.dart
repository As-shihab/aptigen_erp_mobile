import '../../market/presentation/widgets/market_ui.dart';

// Sales screens share the online-market design kit (SAP Horizon cards,
// semantic pills, KPI tiles, skeletons, motion) — one look across the whole
// Sales module. Import this file instead of market_ui.dart directly.
export '../../market/presentation/widgets/market_ui.dart';

/// `sales_orders.status` → sentence-case label (desktop shows the raw code).
String saleStatusLabel(String status) => switch (status) {
      'COMPLETED' => 'Completed',
      'PARKED' => 'Held',
      'REFUNDED' => 'Refunded',
      'CANCELLED' => 'Cancelled',
      'DRAFT' => 'Draft',
      '' => '—',
      _ => status[0] + status.substring(1).toLowerCase().replaceAll('_', ' '),
    };

MarketTone saleStatusTone(String status) => switch (status) {
      'COMPLETED' => MarketTone.ok,
      'PARKED' => MarketTone.warn,
      'REFUNDED' => MarketTone.error,
      'CANCELLED' => MarketTone.neutral,
      _ => MarketTone.info,
    };

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

DateTime? parseLocal(String? iso) => iso == null || iso.isEmpty ? null : DateTime.tryParse(iso)?.toLocal();

/// "Today", "Yesterday", or "12 Oct 2026" — used for list group headers.
String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// "14:05" — time of day for list rows.
String timeLabel(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "12 Oct 2026, 14:05".
String dateTimeLabel(String? iso) {
  final d = parseLocal(iso);
  if (d == null) return '—';
  return '${d.day} ${_months[d.month - 1]} ${d.year}, ${timeLabel(d)}';
}
