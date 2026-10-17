import '../../../core/network/http_client.dart';
import 'simple_crud_service.dart' show withoutPharma;
import 'document_models.dart';
import 'store_util.dart';

/// One generic header+lines service reused by MRR/SR/SPR/Return/MRR-Return —
/// confirmed identical save shape in erp/desktop's context.md ("Save flow in
/// both StoreRequisitions.tsx and StorePurchaseRequisitions.tsx is
/// identical"): header write first (sequential, not `http.batch()` — later
/// writes depend on the header's id), then diff current lines against the
/// ids captured when the record was opened for edit to figure out
/// deletes/creates/updates, each a separate sequential call.
class DocumentService<T> {
  final ApiClient client;
  final String endpoint;
  final String itemsEndpoint;
  final String headerIdField;
  final String lineExpand; // e.g. 'product' or 'product,batch'
  final Set<String> lineFields;
  final T Function(Map<String, dynamic>) fromJson;

  DocumentService(
    this.client, {
    required this.endpoint,
    required this.itemsEndpoint,
    required this.headerIdField,
    required this.lineExpand,
    required this.lineFields,
    required this.fromJson,
  });

  /// `expand` defaults to `items` (only its length is used, for the item
  /// count); SPR passes a richer expand for warehouse + approval progress.
  Future<List<T>> list({String? filter, int top = 200, String expand = 'items'}) async {
    final params = ['\$expand=$expand', '\$orderby=id desc', '\$top=$top'];
    if (filter != null) params.add('\$filter=${Uri.encodeComponent(filter)}');
    final res = await client.get('$endpoint?${params.join('&')}');
    return unwrapList(res).cast<Map<String, dynamic>>().map(fromJson).toList();
  }

  Future<Map<String, dynamic>> createHeader(Map<String, dynamic> payload) async {
    final res = await client.post(endpoint, payload, isV8: true);
    final unwrapped = (res is Map && res['value'] is Map) ? res['value'] : res;
    return (unwrapped as Map).cast<String, dynamic>();
  }

  Future<void> updateHeader(int id, Map<String, dynamic> payload) async {
    await client.put(endpoint, id, payload);
  }

  Future<void> deleteHeader(int id) async {
    await client.delete(endpoint, id);
  }

  Future<List<DocumentLine>> loadLines(int headerId) async {
    final res = await client.get('$itemsEndpoint?\$filter=$headerIdField eq $headerId&\$expand=$lineExpand&\$top=500');
    return unwrapList(res).cast<Map<String, dynamic>>().map(DocumentLine.fromJson).toList();
  }

  /// `originalLineIds` must be captured when the record was opened for edit
  /// (empty list for a fresh create). Deletes first, then create/update
  /// survivors — every call sequential since each depends on the header id
  /// already being known (batching mutations that depend on each other
  /// isn't valid, matches CLAUDE.md's batch rule).
  Future<void> saveLines(int headerId, List<DocumentLine> lines, List<int> originalLineIds) async {
    final currentIds = lines.where((l) => l.id != null).map((l) => l.id!).toSet();
    final toDelete = originalLineIds.where((id) => !currentIds.contains(id));
    for (final id in toDelete) {
      await client.delete(itemsEndpoint, id);
    }
    for (final line in lines) {
      final payload = line.toPayload(lineFields)..[headerIdField] = headerId;
      if (line.id == null) {
        await client.post(itemsEndpoint, payload, isV8: true);
      } else {
        await client.put(itemsEndpoint, line.id!, payload);
      }
    }
  }
}

DocumentService<StoreMrr> mrrService(ApiClient client) => DocumentService<StoreMrr>(
      client,
      endpoint: 'store_mrrs',
      itemsEndpoint: 'store_mrr_items',
      headerIdField: 'mrr_id',
      lineExpand: 'product,batch',
      lineFields: const {'quantity', 'unit_price', 'batch_id', 'packaging_id', 'remarks'},
      fromJson: StoreMrr.fromJson,
    );

DocumentService<StoreRequisition> requisitionService(ApiClient client) => DocumentService<StoreRequisition>(
      client,
      endpoint: 'store_requisitions',
      itemsEndpoint: 'store_requisition_items',
      headerIdField: 'requisition_id',
      lineExpand: 'product',
      lineFields: const {'quantity', 'remarks'},
      fromJson: StoreRequisition.fromJson,
    );

DocumentService<StorePurchaseRequisition> purchaseRequisitionService(ApiClient client) => DocumentService<StorePurchaseRequisition>(
      client,
      endpoint: 'store_purchase_requisitions',
      itemsEndpoint: 'store_purchase_requisition_items',
      headerIdField: 'purchase_requisition_id',
      lineExpand: 'product',
      lineFields: const {'quantity', 'estimated_price', 'remarks'},
      fromJson: StorePurchaseRequisition.fromJson,
    );

DocumentService<StoreReturnDoc> storeReturnService(ApiClient client) => DocumentService<StoreReturnDoc>(
      client,
      endpoint: 'store_returns',
      itemsEndpoint: 'store_return_items',
      headerIdField: 'return_id',
      lineExpand: 'product',
      lineFields: const {'quantity', 'reason', 'remarks'},
      fromJson: StoreReturnDoc.fromJson,
    );

DocumentService<StoreMrrReturn> mrrReturnService(ApiClient client) => DocumentService<StoreMrrReturn>(
      client,
      endpoint: 'store_mrr_returns',
      itemsEndpoint: 'store_mrr_return_items',
      headerIdField: 'mrr_return_id',
      lineExpand: 'product,batch',
      lineFields: const {'quantity', 'unit_price', 'batch_id', 'reason', 'remarks'},
      fromJson: StoreMrrReturn.fromJson,
    );

/// Read-only — Purchase Order authoring stays desktop/Purchase-module
/// territory. Mobile only needs to list/pick a PO and pull its items for
/// MRR's "Load items from PO".
class PurchaseOrderService {
  final ApiClient _client;
  PurchaseOrderService(this._client);

  Future<List<StorePurchaseOrder>> list({String? filter, int top = 200}) async {
    final params = ['\$orderby=id desc', '\$top=$top'];
    // Store receives against non-pharma purchase orders only.
    params.add('\$filter=${Uri.encodeComponent(withoutPharma(filter)!)}');
    final res = await _client.get('purchase_orders?${params.join('&')}');
    return unwrapList(res).cast<Map<String, dynamic>>().map(StorePurchaseOrder.fromJson).toList();
  }

  Future<List<DocumentLine>> loadItems(int purchaseOrderId) async {
    final res = await _client.get('purchase_order_items?\$filter=purchase_order_id eq $purchaseOrderId&\$expand=product&\$top=500');
    return unwrapList(res).cast<Map<String, dynamic>>().map(DocumentLine.fromJson).toList();
  }

  /// Sums every MRR line ever raised against this PO (relation-path filter,
  /// same technique as Sales Dispatch's `sale/status eq 'COMPLETED'`) and
  /// flips the PO to RECEIVED (every line fully covered) or
  /// PARTIALLY_RECEIVED — mirrors desktop's `syncPurchaseOrderStatus()`.
  Future<void> syncStatusAfterReceipt(int purchaseOrderId) async {
    final itemsRes = await _client.get('purchase_order_items?\$filter=purchase_order_id eq $purchaseOrderId&\$top=500');
    final poItems = unwrapList(itemsRes).cast<Map<String, dynamic>>();
    if (poItems.isEmpty) return;

    final receivedRes = await _client.get(
      'store_mrr_items?\$filter=mrr/purchase_order_id eq $purchaseOrderId&\$top=2000',
    );
    final receivedItems = unwrapList(receivedRes).cast<Map<String, dynamic>>();
    final receivedByProduct = <int, double>{};
    for (final row in receivedItems) {
      final productId = toNum(row['product_id']);
      receivedByProduct[productId] = (receivedByProduct[productId] ?? 0) + toDouble(row['quantity']);
    }

    var allCovered = true;
    var anyCovered = false;
    for (final item in poItems) {
      final productId = toNum(item['product_id']);
      final ordered = toDouble(item['quantity']);
      final received = receivedByProduct[productId] ?? 0;
      if (received > 0) anyCovered = true;
      if (received < ordered) allCovered = false;
    }

    final newStatus = allCovered ? 'RECEIVED' : (anyCovered ? 'PARTIALLY_RECEIVED' : null);
    if (newStatus != null) {
      await _client.put('purchase_orders', purchaseOrderId, {'status': newStatus});
    }
  }
}
