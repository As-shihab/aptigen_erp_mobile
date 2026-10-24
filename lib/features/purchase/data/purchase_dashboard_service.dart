import '../../../core/network/http_client.dart';
import '../../../shared/ui/entity_crud.dart';

// Purchase overview — port of desktop dashboard/PurchaseDashboard.tsx. Like
// desktop there's no aggregation endpoint: one $batch reads orders (with
// line quantities/prices), RFQs, returns, requisitions and suppliers, and
// every KPI / chart is computed on the client.

/// Statuses whose value counts as committed spend.
const purchaseSpendStatuses = {'APPROVED', 'SENT', 'PARTIALLY_RECEIVED', 'RECEIVED'};

/// Statuses where goods are still expected to arrive.
const purchaseAwaitingDelivery = {'APPROVED', 'SENT', 'PARTIALLY_RECEIVED'};

/// Sentence-case status label, same wording as desktop ("Partly received").
String purchaseStatusLabel(String s) {
  if (s == 'PARTIALLY_RECEIVED') return 'Partly received';
  if (s.isEmpty) return s;
  final t = s.toLowerCase().replaceAll('_', ' ');
  return t[0].toUpperCase() + t.substring(1);
}

class PurchaseOrderLite {
  final int id;
  final String poNo;
  final String status;
  final String? supplierName;
  final DateTime? orderDate;
  final DateTime? expectedDate;
  final double value;

  const PurchaseOrderLite({
    required this.id,
    required this.poNo,
    required this.status,
    this.supplierName,
    this.orderDate,
    this.expectedDate,
    required this.value,
  });

  factory PurchaseOrderLite.fromJson(Map<String, dynamic> j) {
    final items = j['items'];
    var value = 0.0;
    if (items is List) {
      for (final i in items) {
        if (i is! Map) continue;
        value += (double.tryParse('${i['quantity']}') ?? 0) * (double.tryParse('${i['unit_price']}') ?? 0);
      }
    }
    return PurchaseOrderLite(
      id: int.tryParse('${j['id']}') ?? 0,
      poNo: '${j['po_no'] ?? ''}',
      status: '${j['status'] ?? ''}',
      supplierName: j['supplier_name']?.toString(),
      orderDate: j['order_date'] == null ? null : DateTime.tryParse('${j['order_date']}')?.toLocal(),
      expectedDate: j['expected_date'] == null ? null : DateTime.tryParse('${j['expected_date']}')?.toLocal(),
      value: value,
    );
  }
}

class StatusSlice {
  final String status;
  final String label;
  final int count;
  const StatusSlice(this.status, this.label, this.count);
}

class PurchaseDashboardData {
  final List<PurchaseOrderLite> orders;
  final List<String> rfqStatuses;
  final List<String> returnStatuses;
  final List<String> requisitionStatuses;
  final int supplierCount;

  /// purchase_settings row (only when requested); null when not installed.
  final Map<String, dynamic>? settings;

  PurchaseDashboardData({
    required this.orders,
    required this.rfqStatuses,
    required this.returnStatuses,
    required this.requisitionStatuses,
    required this.supplierCount,
    this.settings,
  });

  static bool _sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

  List<PurchaseOrderLite> get committed => orders.where((o) => purchaseSpendStatuses.contains(o.status)).toList();

  double get totalSpend => committed.fold(0.0, (s, o) => s + o.value);

  double spendInMonth(DateTime month) =>
      committed.where((o) => o.orderDate != null && _sameMonth(o.orderDate!, month)).fold(0.0, (s, o) => s + o.value);

  double get monthSpend => spendInMonth(DateTime.now());
  double get lastMonthSpend {
    final n = DateTime.now();
    return spendInMonth(DateTime(n.year, n.month - 1));
  }

  /// Month-over-month change in percent, or null when last month had none.
  double? get monthChange => lastMonthSpend == 0 ? null : (monthSpend - lastMonthSpend) / lastMonthSpend * 100;

  double get avgOrder => committed.isEmpty ? 0 : totalSpend / committed.length;
  int get pending => orders.where((o) => o.status == 'PENDING').length;
  int get awaitingDelivery => orders.where((o) => purchaseAwaitingDelivery.contains(o.status)).length;
  int get received => orders.where((o) => o.status == 'RECEIVED').length;

  List<PurchaseOrderLite> get overdue {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final list = orders.where((o) => purchaseAwaitingDelivery.contains(o.status) && o.expectedDate != null && o.expectedDate!.isBefore(today)).toList()
      ..sort((a, b) => a.expectedDate!.compareTo(b.expectedDate!));
    return list;
  }

  int get openRfqs => rfqStatuses.where((s) => s == 'DRAFT' || s == 'SENT').length;
  int get openRequisitions => requisitionStatuses.where((s) => s == 'PENDING' || s == 'APPROVED').length;
  int get openReturns => returnStatuses.where((s) => s == 'PENDING' || s == 'APPROVED').length;

  /// Committed spend for the last 6 months, oldest first.
  List<({DateTime month, double value})> get monthlySpend {
    final n = DateTime.now();
    return [
      for (var i = 5; i >= 0; i--)
        (month: DateTime(n.year, n.month - i), value: spendInMonth(DateTime(n.year, n.month - i))),
    ];
  }

  /// Top six suppliers by committed spend.
  List<MapEntry<String, double>> get topSuppliers {
    final totals = <String, double>{};
    for (final o in committed) {
      final name = (o.supplierName ?? '').trim().isEmpty ? 'No supplier' : o.supplierName!.trim();
      totals[name] = (totals[name] ?? 0) + o.value;
    }
    final list = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list.take(6).toList();
  }

  static List<StatusSlice> _slices(Iterable<String> statuses) {
    final counts = <String, int>{};
    for (final s in statuses) {
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final list = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in list) StatusSlice(e.key, purchaseStatusLabel(e.key), e.value)];
  }

  List<StatusSlice> get orderSlices => _slices(orders.map((o) => o.status));
  List<StatusSlice> get rfqSlices => _slices(rfqStatuses);
  List<StatusSlice> get requisitionSlices => _slices(requisitionStatuses);
  List<StatusSlice> get returnSlices => _slices(returnStatuses);

  bool get hasRfq => settings == null || settings!['has_rfq'] != false;
  bool get hasReturns => settings == null || settings!['has_returns'] != false;
}

class PurchaseDashboardService {
  final ApiClient _client;
  PurchaseDashboardService([ApiClient? client]) : _client = client ?? ApiClient();

  /// One $batch for everything. [withSettings] also reads purchase_settings
  /// (the hub uses it to show / hide RFQ and returns like desktop's nav).
  Future<PurchaseDashboardData> load({bool withSettings = false}) async {
    final d = await batchLoad(_client, {
      'orders': 'purchase_orders?\$expand=items(\$select=quantity,unit_price)&\$orderby=id desc&\$top=2000',
      'rfqs': 'purchase_rfqs?\$select=id,status&\$top=1000',
      'returns': 'store_mrr_returns?\$select=id,status&\$top=1000',
      'requisitions': 'store_purchase_requisitions?\$select=id,status&\$top=1000',
      'suppliers': 'suppliers?\$select=id&\$top=5000',
      if (withSettings) 'settings': 'purchase_settings?\$top=1',
    });
    List<String> statuses(String k) => [for (final r in d[k] ?? const <Map<String, dynamic>>[]) '${r['status'] ?? ''}'];
    final settingsRows = d['settings'] ?? const [];
    return PurchaseDashboardData(
      orders: [for (final r in d['orders'] ?? const <Map<String, dynamic>>[]) PurchaseOrderLite.fromJson(r)],
      rfqStatuses: statuses('rfqs'),
      returnStatuses: statuses('returns'),
      requisitionStatuses: statuses('requisitions'),
      supplierCount: (d['suppliers'] ?? const []).length,
      settings: settingsRows.isEmpty ? null : settingsRows.first,
    );
  }
}
