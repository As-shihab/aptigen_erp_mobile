import '../../../core/network/http_client.dart';
import '../../store/data/store_util.dart';

/// `GET sell/dashboard-analytics` — a bespoke aggregation endpoint (real
/// SQL-side grouping/sums), not generic OData, mirroring desktop's
/// Analytics.tsx. Response is parsed defensively (missing keys default to
/// empty/zero) since the backend may add metrics the mobile client doesn't
/// yet know about.
class SellAnalyticsSnapshot {
  final int totalOrders;
  final int completedOrders;
  final int pendingOrders;
  final int voidedOrders;
  final double totalRevenue;
  final double totalDiscount;
  final double totalTax;
  final double totalOutstanding;
  final double totalRefunded;
  final int totalClients;
  final List<String> trendDates;
  final List<double> trendData;
  final List<MapEntry<String, double>> topProducts;
  final List<MapEntry<String, double>> topClients;
  final Map<String, double> statusCounts;
  final Map<String, double> revenueByGroup;

  const SellAnalyticsSnapshot({
    this.totalOrders = 0,
    this.completedOrders = 0,
    this.pendingOrders = 0,
    this.voidedOrders = 0,
    this.totalRevenue = 0,
    this.totalDiscount = 0,
    this.totalTax = 0,
    this.totalOutstanding = 0,
    this.totalRefunded = 0,
    this.totalClients = 0,
    this.trendDates = const [],
    this.trendData = const [],
    this.topProducts = const [],
    this.topClients = const [],
    this.statusCounts = const {},
    this.revenueByGroup = const {},
  });

  double get avgOrderValue => completedOrders > 0 ? totalRevenue / completedOrders : 0;

  factory SellAnalyticsSnapshot.fromJson(Map json) {
    final metrics = (json['metrics'] as Map?) ?? const {};
    final trend = (json['trend'] as Map?) ?? const {};
    final products = (json['products'] as Map?) ?? const {};
    final topClientsMap = (json['topClients'] as Map?) ?? const {};
    final statusList = (json['status'] as List?) ?? const [];
    final group = (json['group'] as Map?) ?? const {};

    List<MapEntry<String, double>> seriesFrom(Map m) {
      final categories = ((m['categories'] as List?) ?? const []).cast<dynamic>();
      final series = ((m['series'] as List?) ?? const []).cast<dynamic>();
      final data = series.isNotEmpty && series.first is Map ? ((series.first as Map)['data'] as List?) ?? const [] : const [];
      final out = <MapEntry<String, double>>[];
      for (var i = 0; i < categories.length; i++) {
        out.add(MapEntry(categories[i].toString(), i < data.length ? toDouble(data[i]) : 0));
      }
      return out;
    }

    final statusCounts = <String, double>{};
    for (final row in statusList) {
      final m = row as Map;
      statusCounts[(m['label'] ?? '').toString()] = toDouble(m['value']);
    }

    final groupLabels = ((group['labels'] as List?) ?? const []).cast<dynamic>();
    final groupData = ((group['data'] as List?) ?? const []).cast<dynamic>();
    final revenueByGroup = <String, double>{};
    for (var i = 0; i < groupLabels.length; i++) {
      revenueByGroup[groupLabels[i].toString()] = i < groupData.length ? toDouble(groupData[i]) : 0;
    }

    return SellAnalyticsSnapshot(
      totalOrders: toNum(metrics['totalOrders']),
      completedOrders: toNum(metrics['completedOrders']),
      pendingOrders: toNum(metrics['pendingOrders']),
      voidedOrders: toNum(metrics['voidedOrders']),
      totalRevenue: toDouble(metrics['totalRevenue']),
      totalDiscount: toDouble(metrics['totalDiscount']),
      totalTax: toDouble(metrics['totalTax']),
      totalOutstanding: toDouble(metrics['totalOutstanding']),
      totalRefunded: toDouble(metrics['totalRefunded']),
      totalClients: toNum(metrics['totalClients']),
      trendDates: ((trend['dates'] as List?) ?? const []).map((d) => d.toString()).toList(),
      trendData: ((trend['data'] as List?) ?? const []).map(toDouble).toList(),
      topProducts: seriesFrom(products),
      topClients: seriesFrom(topClientsMap),
      statusCounts: statusCounts,
      revenueByGroup: revenueByGroup,
    );
  }
}

class SellAnalyticsService {
  final ApiClient _client;
  SellAnalyticsService(this._client);

  Future<SellAnalyticsSnapshot> load({required DateTime start, required DateTime end, int? clientGroupId, String? status}) async {
    String d(DateTime dt) => '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final params = <String>['start_date=${d(start)}', 'end_date=${d(end)}'];
    if (clientGroupId != null) params.add('client_group_id=$clientGroupId');
    if (status != null) params.add('status=$status');
    final res = await _client.get('sell/dashboard-analytics?${params.join('&')}', isV8: false);
    return SellAnalyticsSnapshot.fromJson((res as Map).cast<String, dynamic>());
  }
}
