import '../../../core/network/http_client.dart';
import 'store_util.dart';

/// Client-computed KPIs/chart inputs — same approach as desktop's
/// StoreAnalytics.tsx (no dedicated backend aggregation endpoint exists for
/// Store; everything is plain OData GETs batched in one round trip, then
/// reduced client-side). Curated to a mobile-appropriate subset per the plan
/// (KPI grid + a handful of charts, not all 8 desktop panels).
class StoreAnalyticsSnapshot {
  final double stockValue;
  final int lowStockCount;
  final int pendingSrCount;
  final int pendingSprCount;
  final int expiringBatchCount;
  final int pendingPoCount;
  final Map<String, int> movementTypeCounts; // IN/OUT/ADJUST
  final Map<String, int> categoryProductCounts; // category name -> count
  final Map<String, int> poStatusCounts;
  final List<MapEntry<String, double>> topProductsByVolume; // name -> |qty|

  const StoreAnalyticsSnapshot({
    required this.stockValue,
    required this.lowStockCount,
    required this.pendingSrCount,
    required this.pendingSprCount,
    required this.expiringBatchCount,
    required this.pendingPoCount,
    required this.movementTypeCounts,
    required this.categoryProductCounts,
    required this.poStatusCounts,
    required this.topProductsByVolume,
  });
}

class StoreAnalyticsService {
  final ApiClient _client;
  StoreAnalyticsService(this._client);

  Future<StoreAnalyticsSnapshot> load() async {
    final result = await _client.batch([
      BatchRequest(
        id: 'products',
        method: 'GET',
        url: r'store_products?$select=id,name,stock_qty,cost_price,price,low_stock_at,track_stock,category_id&$filter=is_active eq true and is_pharma eq false&$top=2000',
      ),
      BatchRequest(id: 'categories', method: 'GET', url: r'store_product_categories?$select=id,name&$filter=is_pharma eq false&$top=200'),
      BatchRequest(
        id: 'batches',
        method: 'GET',
        url: r"store_product_batches?$select=id,expiry_date&$filter=status eq 'ACTIVE' and is_pharma eq false&$top=3000",
      ),
      BatchRequest(id: 'srs', method: 'GET', url: r"store_requisitions?$select=id,status&$filter=status eq 'PENDING'&$top=2000"),
      BatchRequest(id: 'sprs', method: 'GET', url: r"store_purchase_requisitions?$select=id,status&$filter=status eq 'PENDING'&$top=2000"),
      BatchRequest(id: 'pos', method: 'GET', url: r'purchase_orders?$select=id,status&$filter=is_pharma eq false&$top=2000'),
      BatchRequest(id: 'movements', method: 'GET', url: r'store_stock_movements?$select=id,type,quantity,product_id&$filter=product/is_pharma eq false&$top=5000'),
    ]);

    Map<String, dynamic>? body(String id) => unwrapBatchBody(result, id);
    List<Map<String, dynamic>> rows(String id) => unwrapList(body(id)).cast<Map<String, dynamic>>();

    final products = rows('products');
    final categories = {for (final c in rows('categories')) toNum(c['id']): (c['name'] ?? '').toString()};
    final batches = rows('batches');
    final srs = rows('srs');
    final sprs = rows('sprs');
    final pos = rows('pos');
    final movements = rows('movements');

    double stockValue = 0;
    int lowStockCount = 0;
    final categoryCounts = <String, int>{};
    for (final p in products) {
      final stockQty = toDouble(p['stock_qty']);
      final unitValue = toDoubleOrNull(p['cost_price']) ?? toDouble(p['price']);
      stockValue += stockQty * unitValue;
      if (toBool(p['track_stock'], fallback: true) && stockQty <= toDouble(p['low_stock_at'])) lowStockCount++;
      final categoryId = toIntOrNull(p['category_id']);
      final categoryName = categories[categoryId] ?? 'Uncategorized';
      categoryCounts[categoryName] = (categoryCounts[categoryName] ?? 0) + 1;
    }

    final now = DateTime.now();
    var expiringBatchCount = 0;
    for (final b in batches) {
      final expiry = DateTime.tryParse((b['expiry_date'] ?? '').toString());
      if (expiry == null) continue;
      final days = expiry.difference(DateTime(now.year, now.month, now.day)).inDays;
      if (days >= 0 && days <= 30) expiringBatchCount++;
    }

    final poStatusCounts = <String, int>{};
    var pendingPoCount = 0;
    for (final po in pos) {
      final status = (po['status'] ?? '').toString();
      poStatusCounts[status] = (poStatusCounts[status] ?? 0) + 1;
      if (status == 'PENDING' || status == 'APPROVED' || status == 'SENT') pendingPoCount++;
    }

    final movementTypeCounts = <String, int>{'IN': 0, 'OUT': 0, 'ADJUST': 0};
    final volumeByProduct = <int, double>{};
    for (final m in movements) {
      final type = (m['type'] ?? '').toString();
      movementTypeCounts[type] = (movementTypeCounts[type] ?? 0) + 1;
      final productId = toNum(m['product_id']);
      volumeByProduct[productId] = (volumeByProduct[productId] ?? 0) + toDouble(m['quantity']).abs();
    }
    final productNames = {for (final p in products) toNum(p['id']): (p['name'] ?? '').toString()};
    final topProducts = volumeByProduct.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topProductsByVolume = topProducts
        .take(8)
        .map((e) => MapEntry(productNames[e.key] ?? 'Product #${e.key}', e.value))
        .toList();

    return StoreAnalyticsSnapshot(
      stockValue: stockValue,
      lowStockCount: lowStockCount,
      pendingSrCount: srs.length,
      pendingSprCount: sprs.length,
      expiringBatchCount: expiringBatchCount,
      pendingPoCount: pendingPoCount,
      movementTypeCounts: movementTypeCounts,
      categoryProductCounts: categoryCounts,
      poStatusCounts: poStatusCounts,
      topProductsByVolume: topProductsByVolume,
    );
  }
}
