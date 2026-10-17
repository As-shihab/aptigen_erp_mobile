import '../../../core/network/http_client.dart';
import '../../store/data/store_util.dart';

class DailySalesRow {
  final String date;
  final int orders;
  final double revenue;
  final double discount;
  final double tax;
  const DailySalesRow({required this.date, required this.orders, required this.revenue, required this.discount, required this.tax});

  factory DailySalesRow.fromJson(Map json) => DailySalesRow(
        date: (json['date'] ?? '').toString(),
        orders: toNum(json['orders']),
        revenue: toDouble(json['revenue']),
        discount: toDouble(json['discount']),
        tax: toDouble(json['tax']),
      );
}

class CashierSalesRow {
  final int cashierId;
  final String cashierName;
  final int orders;
  final double revenue;
  const CashierSalesRow({required this.cashierId, required this.cashierName, required this.orders, required this.revenue});

  factory CashierSalesRow.fromJson(Map json) => CashierSalesRow(
        cashierId: toNum(json['cashierId']),
        cashierName: (json['cashierName'] ?? 'Unknown').toString(),
        orders: toNum(json['orders']),
        revenue: toDouble(json['revenue']),
      );
}

/// `GET sell/sales-report` — mirrors desktop's SalesReport.tsx. Desktop
/// hardcodes '$' here regardless of workplace currency (an acknowledged
/// desktop inconsistency, see erp/desktop/src/module/sell/report/
/// SalesReport.tsx) — the mobile port uses `formatMoney()` instead of
/// copying that bug, since mobile now has proper currency-symbol support.
class SalesReportService {
  final ApiClient _client;
  SalesReportService(this._client);

  Future<({List<DailySalesRow> daily, List<CashierSalesRow> cashier})> load({required DateTime start, required DateTime end}) async {
    String d(DateTime dt) => '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final res = await _client.get('sell/sales-report?start_date=${d(start)}&end_date=${d(end)}', isV8: false);
    final map = (res as Map).cast<String, dynamic>();
    final daily = ((map['daily'] as List?) ?? const []).map((r) => DailySalesRow.fromJson((r as Map).cast<String, dynamic>())).toList();
    final cashier = ((map['cashier'] as List?) ?? const []).map((r) => CashierSalesRow.fromJson((r as Map).cast<String, dynamic>())).toList();
    return (daily: daily, cashier: cashier);
  }
}
