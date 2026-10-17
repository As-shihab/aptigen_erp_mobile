import '../../../core/network/http_client.dart';
import 'store_util.dart';

/// Dart port of erp/desktop's `store/shared/stockLedger.ts` — shared by every
/// document that posts to `store_stock_movements` (MRR receipt, SR issue,
/// Store Return receipt, Stock Adjustment). Keeps the find-or-create-location
/// + balance-lookup + ledger-write + stock_qty-sync sequence in one place,
/// exactly mirroring the desktop implementation's OData calls/semantics.

/// Warehouse-only `store_locations` row (no corridor/rack/bin — these
/// documents only track down to warehouse level, unlike Stock Adjustment's
/// full hierarchy picker). Find or create.
Future<int?> resolveWarehouseLocationId(ApiClient client, int warehouseId, {String? warehouseName}) async {
  final filter = 'warehouse_id eq $warehouseId and corridor_id eq null and rack_id eq null and bin_id eq null';
  final found = await client.get('store_locations?\$filter=${Uri.encodeComponent(filter)}&\$top=1');
  final foundList = unwrapList(found);
  if (foundList.isNotEmpty) return toIntOrNull((foundList.first as Map)['id']);

  final created = await client.post('store_locations', {
    'warehouse_id': warehouseId,
    'corridor_id': null,
    'rack_id': null,
    'bin_id': null,
    'path': warehouseName ?? 'warehouse-$warehouseId',
  }, isV8: true);
  final row = (created is Map && created['value'] is Map) ? created['value'] : created;
  return toIntOrNull((row as Map?)?['id']);
}

/// Current on-hand quantity for a product at a location — the latest ledger
/// row's running balance.
Future<double> getCurrentBalance(ApiClient client, int productId, int locationId) async {
  final res = await client.get(
    'store_stock_movements?\$select=balance_after&\$filter=product_id eq $productId and location_id eq $locationId&\$orderby=id desc&\$top=1',
  );
  final list = unwrapList(res);
  if (list.isEmpty) return 0;
  return toDouble((list.first as Map)['balance_after']);
}

class StockMovementInput {
  final int productId;
  final int locationId;
  final int? batchId;
  final String type; // IN | OUT
  final double quantity;
  final String referenceType;
  final int? referenceId;
  final String? remarks;

  StockMovementInput({
    required this.productId,
    required this.locationId,
    this.batchId,
    required this.type,
    required this.quantity,
    required this.referenceType,
    this.referenceId,
    this.remarks,
  });
}

/// Thrown when an OUT posting would take a product/location below zero —
/// callers should surface this as a toast rather than letting the rest of a
/// save silently half-complete (matches desktop's behavior).
class InsufficientStockException implements Exception {
  final double available;
  InsufficientStockException(this.available);
  @override
  String toString() => 'Only $available in stock at this location';
}

/// Posts one ledger row + syncs `store_products.stock_qty` by the same delta.
Future<void> postStockMovement(ApiClient client, StockMovementInput input) async {
  if (input.quantity <= 0) return;

  final previousBalance = await getCurrentBalance(client, input.productId, input.locationId);

  if (input.type == 'OUT' && input.quantity > previousBalance) {
    throw InsufficientStockException(previousBalance);
  }

  final delta = input.type == 'IN' ? input.quantity : -input.quantity;
  final newBalance = previousBalance + delta;

  await client.post('store_stock_movements', {
    'product_id': input.productId,
    'location_id': input.locationId,
    'batch_id': input.batchId,
    'type': input.type,
    'quantity': input.quantity,
    'balance_after': newBalance,
    'reference_type': input.referenceType,
    'reference_id': input.referenceId,
    'remarks': input.remarks,
  }, isV8: true);

  final productRes = await client.get('store_products?\$select=id,stock_qty&\$filter=id eq ${input.productId}&\$top=1');
  final productList = unwrapList(productRes);
  final currentStock = productList.isEmpty ? 0.0 : toDouble((productList.first as Map)['stock_qty']);
  await client.put('store_products', input.productId, {'stock_qty': currentStock + delta});
}
