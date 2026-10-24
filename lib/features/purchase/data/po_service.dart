import '../../../core/network/http_client.dart';
import '../../store/data/document_models.dart';
import '../../store/data/document_services.dart';
import 'approval_service.dart';

// Purchase orders — mobile port of desktop's purchase/PurchaseOrder.tsx data
// flow. Endpoints are Prisma model names; workplace_id is never sent (the
// OData layer scopes it).

/// `purchase_settings` toggles (desktop purchase.context.tsx).
class PurchaseSettings {
  final bool hasPoApproval;
  final int? poApproverTypeId;
  final bool hasRfq;
  final bool hasReturns;
  final bool requireSupplier;
  final bool lockApprovedPo;
  const PurchaseSettings({
    this.hasPoApproval = false,
    this.poApproverTypeId,
    this.hasRfq = true,
    this.hasReturns = true,
    this.requireSupplier = false,
    this.lockApprovedPo = true,
  });

  factory PurchaseSettings.fromRows(List<Map<String, dynamic>>? rows) {
    final r = rows == null || rows.isEmpty ? null : rows.first;
    if (r == null) return const PurchaseSettings();
    return PurchaseSettings(
      hasPoApproval: r['has_po_approval'] == true,
      poApproverTypeId: approvalInt(r['po_approver_type_id']),
      hasRfq: r['has_rfq'] == true,
      hasReturns: r['has_returns'] == true,
      requireSupplier: r['require_supplier'] == true,
      lockApprovedPo: r['lock_approved_po'] == true,
    );
  }

  static const query = r'purchase_settings?$top=1';
}

const poStatuses = ['PENDING', 'APPROVED', 'REJECTED', 'SENT', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CANCELLED'];

/// Statuses the approval chain owns while approval is on.
const poChainStatuses = ['PENDING', 'REJECTED'];

String poStatusLabel(String s) => switch (s) {
      'PENDING' => 'Pending',
      'APPROVED' => 'Approved',
      'REJECTED' => 'Rejected',
      'SENT' => 'Sent',
      'PARTIALLY_RECEIVED' => 'Partially received',
      'RECEIVED' => 'Received',
      'CANCELLED' => 'Cancelled',
      _ => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' '),
    };

class PoItem {
  final int id;
  final int productId;
  final String productName;
  final String unit;
  final double quantity;
  final double? unitPrice;
  final String? remarks;
  const PoItem({required this.id, required this.productId, required this.productName, required this.unit, required this.quantity, this.unitPrice, this.remarks});

  factory PoItem.fromJson(Map j) {
    final product = j['product'];
    final uom = product is Map ? product['uom'] : null;
    return PoItem(
      id: approvalInt(j['id']) ?? 0,
      productId: approvalInt(j['product_id']) ?? 0,
      productName: (product is Map ? approvalStr(product['name']) : null) ?? 'Product #${j['product_id']}',
      unit: uom is Map ? (approvalStr(uom['symbol']) ?? approvalStr(uom['code']) ?? '') : '',
      quantity: approvalDouble(j['quantity']),
      unitPrice: approvalDoubleOrNull(j['unit_price']),
      remarks: approvalStr(j['remarks']),
    );
  }

  double get total => quantity * (unitPrice ?? 0);
}

class PurchaseOrder {
  final int id;
  final int? purchaseRequisitionId;
  final int? supplierId;
  final int? warehouseId;
  final String poNo;
  final String? supplierName;
  final String status;
  final DateTime? orderDate;
  final DateTime? expectedDate;
  final String? remarks;
  final String? sprNo;
  final List<PoItem> items;
  final int? approveTypeId;
  final int currentSerial;
  final List<ApprovalStep> approvals;
  final Map<int, double> receivedByProduct;
  final int mrrCount;

  const PurchaseOrder({
    required this.id,
    this.purchaseRequisitionId,
    this.supplierId,
    this.warehouseId,
    required this.poNo,
    this.supplierName,
    required this.status,
    this.orderDate,
    this.expectedDate,
    this.remarks,
    this.sprNo,
    this.items = const [],
    this.approveTypeId,
    this.currentSerial = 1,
    this.approvals = const [],
    this.receivedByProduct = const {},
    this.mrrCount = 0,
  });

  factory PurchaseOrder.fromJson(Map j) {
    final received = <int, double>{};
    final mrrs = j['mrrs'] is List ? (j['mrrs'] as List).whereType<Map>().toList() : const <Map>[];
    for (final mrr in mrrs) {
      final items = mrr['items'];
      if (items is! List) continue;
      for (final it in items.whereType<Map>()) {
        final pid = approvalInt(it['product_id']);
        if (pid == null) continue;
        received[pid] = (received[pid] ?? 0) + approvalDouble(it['quantity']);
      }
    }
    final spr = j['purchase_requisition'];
    return PurchaseOrder(
      id: approvalInt(j['id']) ?? 0,
      purchaseRequisitionId: approvalInt(j['purchase_requisition_id']),
      supplierId: approvalInt(j['supplier_id']),
      warehouseId: approvalInt(j['warehouse_id']),
      poNo: approvalStr(j['po_no']) ?? '#${j['id']}',
      supplierName: approvalStr(j['supplier_name']),
      status: (approvalStr(j['status']) ?? 'PENDING').toUpperCase(),
      orderDate: j['order_date'] == null ? null : DateTime.tryParse(j['order_date'].toString()),
      expectedDate: j['expected_date'] == null ? null : DateTime.tryParse(j['expected_date'].toString()),
      remarks: approvalStr(j['remarks']),
      sprNo: spr is Map ? approvalStr(spr['spr_no']) : null,
      items: j['items'] is List ? (j['items'] as List).whereType<Map>().map(PoItem.fromJson).toList() : const [],
      approveTypeId: approvalInt(j['approve_type_id']),
      currentSerial: approvalInt(j['current_serial']) ?? 1,
      approvals: parseSteps(j['approvals']),
      receivedByProduct: received,
      mrrCount: mrrs.length,
    );
  }

  double get ordered => items.fold(0, (s, i) => s + i.quantity);

  /// Received qty for one line, capped at its ordered qty so an
  /// over-delivery on one item doesn't mask a shortfall on another.
  double receivedFor(PoItem i) {
    final r = receivedByProduct[i.productId] ?? 0;
    return r > i.quantity ? i.quantity : r;
  }

  double get received => items.fold(0, (s, i) => s + receivedFor(i));
  double get amount => items.fold(0, (s, i) => s + i.total);
  int get pct => ordered > 0 ? ((received / ordered) * 100).round() : 0;
  bool get hasChain => approvals.isNotEmpty;
  ApprovalStep? get pendingStep => status == 'PENDING' ? currentStep(approvals, currentSerial) : null;

  /// Receipt badge shown once the order is past approval.
  String? get receiptLabel {
    if (['PENDING', 'REJECTED', 'CANCELLED'].contains(status)) return null;
    if (pct >= 100) return 'Fully received';
    return received > 0 ? 'Partially received' : 'Awaiting receipt';
  }
}

class PoService {
  final ApiClient client;
  PoService(this.client);

  static const _expand = r'purchase_requisition($select=spr_no),'
      r'approvals($expand=actor($select=id,name,email)),'
      r'items($select=id,product_id,quantity,unit_price,remarks;$expand=product($select=id,name;$expand=uom($select=symbol,code))),'
      r'mrrs($select=id;$expand=items($select=product_id,quantity))';

  static const listQuery = 'purchase_orders?\$expand=$_expand&\$orderby=id desc&\$top=500';
  static String detailQuery(int id) => 'purchase_orders?\$filter=id eq $id&\$expand=$_expand&\$top=1';

  static const suppliersQuery = "suppliers?\$select=id,supplier_name&\$filter=status eq 'ACTIVE'&\$top=500";
  static const sprsQuery = r'store_purchase_requisitions?$select=id,spr_no,status&$orderby=id desc&$top=500';
  static const productsQuery = r'store_products?$select=id,name,sku,barcode,short_desc,category_id,sub_category_id,uom_id,price,compare_price,cost_price,stock_qty,low_stock_at,track_stock,is_active,is_featured,thumbnail_url&$filter=is_active eq true&$top=2000';

  DocumentService<Map<String, dynamic>> get _docs => DocumentService<Map<String, dynamic>>(
        client,
        endpoint: 'purchase_orders',
        itemsEndpoint: 'purchase_order_items',
        headerIdField: 'purchase_order_id',
        lineExpand: 'product',
        lineFields: const {'quantity', 'unit_price', 'remarks'},
        fromJson: (m) => m,
      );

  /// Best-effort next number from the code generator (custom /api route).
  Future<String?> generateCode() async {
    try {
      final res = await client.post('generate-code', {'code': 'PO', 'table': 'purchase_orders'});
      return res is Map ? approvalStr(res['code']) : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<DocumentLine>> loadLines(int poId) => _docs.loadLines(poId);

  /// Header first (sequential — lines need its id), then the line diff.
  /// Returns the purchase order id.
  Future<int> save({
    int? id,
    required Map<String, dynamic> header,
    required List<DocumentLine> lines,
    required List<int> originalLineIds,
    bool skipLines = false,
  }) async {
    int poId;
    if (id != null) {
      await _docs.updateHeader(id, header);
      poId = id;
    } else {
      final created = await _docs.createHeader(header);
      final newId = approvalInt(created['id']);
      if (newId == null) throw ApiException(500, 'Purchase order header did not return an id');
      poId = newId;
    }
    if (!skipLines) await _docs.saveLines(poId, lines, originalLineIds);
    return poId;
  }

  Future<void> setStatus(int id, String status) => client.put('purchase_orders', id, {'status': status});
  Future<void> delete(int id) => client.delete('purchase_orders', id);
}

/// Friendlier save error (unique PO number clash).
String describePoError(Object e, String fallback) {
  final msg = e is ApiException ? e.message : '';
  if (msg.contains('po_no') && msg.toLowerCase().contains('unique')) {
    return 'That PO number is already in use, use a different number';
  }
  return msg.trim().isNotEmpty && e is ApiException && e.statusCode < 500 ? msg : fallback;
}
