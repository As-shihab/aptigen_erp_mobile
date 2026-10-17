import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../../core/network/http_client.dart';
import '../widgets/market_ui.dart';

// Shared bits for the website orders list + detail (desktop parity with
// sell/sales-order/WebsiteOrders.tsx and online/pages/market/orders).

const orderStatusLabel = {
  'pending': 'Pending',
  'paid': 'Accepted',
  'packaged': 'Packed',
  'delivered': 'Delivered',
  'cancelled': 'Cancelled',
};

MarketTone orderStatusTone(String s) => switch (s) {
      'pending' => MarketTone.warn,
      'paid' || 'packaged' => MarketTone.info,
      'delivered' => MarketTone.ok,
      'cancelled' => MarketTone.error,
      _ => MarketTone.neutral,
    };

IconData orderStatusIcon(String s) => switch (s) {
      'pending' => Icons.schedule_outlined,
      'paid' => Icons.thumb_up_alt_outlined,
      'packaged' => Icons.inventory_2_outlined,
      'delivered' => Icons.check_circle_outline,
      'cancelled' => Icons.cancel_outlined,
      _ => Icons.circle_outlined,
    };

const paymentLabel = {
  'cash': 'Cash on delivery',
  'card': 'Card',
  'mobile': 'Mobile wallet',
  'bank': 'Bank transfer',
};

String paymentName(dynamic m) {
  final k = (m ?? '').toString();
  if (k.isEmpty) return '—';
  return paymentLabel[k] ?? k;
}

/// Next forward step for a status: (status to set, button label).
({String status, String label, IconData icon})? nextOrderStep(String s) => switch (s) {
      'pending' => (status: 'paid', label: 'Accept', icon: Icons.thumb_up_alt_outlined),
      'paid' => (status: 'packaged', label: 'Mark packed', icon: Icons.inventory_2_outlined),
      'packaged' => (status: 'delivered', label: 'Mark delivered', icon: Icons.local_shipping_outlined),
      _ => null,
    };

bool orderCancellable(String s) => s == 'pending' || s == 'paid' || s == 'packaged';

String fmtDateTime(dynamic v) {
  final d = DateTime.tryParse('${v ?? ''}');
  if (d == null) return '—';
  return DateFormat('d MMM yyyy, h:mm a').format(d.toLocal());
}

String fmtDate(dynamic v) {
  final d = DateTime.tryParse('${v ?? ''}');
  if (d == null) return '—';
  return DateFormat('d MMM yyyy').format(d.toLocal());
}

String? str(dynamic v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

Map<String, dynamic> asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

String deliveryLine(Map<String, dynamic> d) =>
    [d['address'], d['area'], d['city'], d['postcode']].map(str).whereType<String>().join(', ');

String errorText(Object e, String fallback) => e is ApiException && e.message.isNotEmpty ? e.message : fallback;
