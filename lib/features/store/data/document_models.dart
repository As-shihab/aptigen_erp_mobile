import 'store_util.dart';

/// One product line shared across every Store header+lines document (MRR,
/// SR, SPR, Return, MRR Return) — the underlying Prisma line-item tables all
/// use the same field names (`product_id`/`quantity`/`unit_price`/`batch_id`/
/// `packaging_id`/`estimated_price`/`reason`/`remarks`), just different
/// subsets per document, so one mutable class + a per-document allow-list
/// (see `buildLinePayload`) covers all of them instead of five near-identical
/// line classes.
class DocumentLine {
  int? id; // null = new/unsaved, not yet posted to the backend
  int productId;
  String productName;
  double quantity;
  double? unitPrice;
  double? estimatedPrice;
  int? batchId;
  String? batchLabel;
  int? packagingId;
  String? reason;
  String? remarks;

  DocumentLine({
    this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    this.unitPrice,
    this.estimatedPrice,
    this.batchId,
    this.batchLabel,
    this.packagingId,
    this.reason,
    this.remarks,
  });

  factory DocumentLine.fromJson(Map json) => DocumentLine(
        id: toIntOrNull(json['id']),
        productId: toNum(json['product_id']),
        productName: ((json['product'] as Map?)?['name'] ?? 'Product #${json['product_id']}').toString(),
        quantity: toDouble(json['quantity']),
        unitPrice: toDoubleOrNull(json['unit_price']),
        estimatedPrice: toDoubleOrNull(json['estimated_price']),
        batchId: toIntOrNull(json['batch_id']),
        batchLabel: toStringOrNull((json['batch'] as Map?)?['batch_no']),
        packagingId: toIntOrNull(json['packaging_id']),
        reason: toStringOrNull(json['reason']),
        remarks: toStringOrNull(json['remarks']),
      );

  /// Only the fields the target line-item table actually has — sending an
  /// unknown column to the generic OData write would fail Prisma validation.
  Map<String, dynamic> toPayload(Set<String> allowedFields) {
    final all = <String, dynamic>{
      'product_id': productId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'estimated_price': estimatedPrice,
      'batch_id': batchId,
      'packaging_id': packagingId,
      'reason': reason,
      'remarks': remarks,
    };
    final payload = <String, dynamic>{};
    for (final key in allowedFields) {
      if (all.containsKey(key)) payload[key] = all[key];
    }
    return payload;
  }
}

class StoreMrr {
  final int id;
  final int warehouseId;
  final String? warehouseLabel;
  final int? purchaseOrderId;
  final String mrrNo;
  final String type; // LOCAL | IMPORTED | REPAIR
  final String? mode; // po_mode | direct_mode
  final String status; // PARTIAL | COMPLETED | HOLD
  final String? referenceNo;
  final String? supplierName;
  final String receivedDate;
  final String? remarks;
  final int itemCount;

  const StoreMrr({
    required this.id,
    required this.warehouseId,
    this.warehouseLabel,
    this.purchaseOrderId,
    required this.mrrNo,
    required this.type,
    this.mode,
    required this.status,
    this.referenceNo,
    this.supplierName,
    required this.receivedDate,
    this.remarks,
    required this.itemCount,
  });

  factory StoreMrr.fromJson(Map json) => StoreMrr(
        id: toNum(json['id']),
        warehouseId: toNum(json['warehouse_id']),
        warehouseLabel: toStringOrNull((json['warehouse'] as Map?)?['name']),
        purchaseOrderId: toIntOrNull(json['purchase_order_id']),
        mrrNo: (json['mrr_no'] ?? '').toString(),
        type: (json['type'] ?? 'LOCAL').toString(),
        mode: toStringOrNull(json['mode']),
        status: (json['status'] ?? 'PARTIAL').toString(),
        referenceNo: toStringOrNull(json['reference_no']),
        supplierName: toStringOrNull(json['supplier_name']),
        receivedDate: (json['received_date'] ?? '').toString(),
        remarks: toStringOrNull(json['remarks']),
        itemCount: ((json['items'] as List?) ?? const []).length,
      );
}

class StoreRequisition {
  final int id;
  final int warehouseId;
  final String? warehouseLabel;
  final int? departmentId;
  final String srNo;
  final String? purpose;
  final String status; // PENDING | APPROVED | ISSUED | REJECTED
  final String requestedDate;
  final String? remarks;
  final int itemCount;

  const StoreRequisition({
    required this.id,
    required this.warehouseId,
    this.warehouseLabel,
    this.departmentId,
    required this.srNo,
    this.purpose,
    required this.status,
    required this.requestedDate,
    this.remarks,
    required this.itemCount,
  });

  factory StoreRequisition.fromJson(Map json) => StoreRequisition(
        id: toNum(json['id']),
        warehouseId: toNum(json['warehouse_id']),
        warehouseLabel: toStringOrNull((json['warehouse'] as Map?)?['name']),
        departmentId: toIntOrNull(json['department_id']),
        srNo: (json['sr_no'] ?? '').toString(),
        purpose: toStringOrNull(json['purpose']),
        status: (json['status'] ?? 'PENDING').toString(),
        requestedDate: (json['requested_date'] ?? '').toString(),
        remarks: toStringOrNull(json['remarks']),
        itemCount: ((json['items'] as List?) ?? const []).length,
      );
}

class StorePurchaseRequisition {
  final int id;
  final int? warehouseId;
  final String? warehouseLabel;
  final String sprNo;
  final String? purpose;
  final String status; // PENDING | APPROVED | ORDERED | REJECTED
  final String requestedDate;
  final String? remarks;
  final int itemCount;
  // Approval chain progress from `$expand=approvals($select=id,status)` —
  // both 0 when there's no chain or the expand wasn't requested.
  final int approvalSteps;
  final int approvalsDone;

  const StorePurchaseRequisition({
    required this.id,
    this.warehouseId,
    this.warehouseLabel,
    required this.sprNo,
    this.purpose,
    required this.status,
    required this.requestedDate,
    this.remarks,
    required this.itemCount,
    this.approvalSteps = 0,
    this.approvalsDone = 0,
  });

  /// Only PENDING or REJECTED SPRs belong to the store — once approved or
  /// ordered they're part of the purchase flow (matches desktop).
  bool get isEditable => status == 'PENDING' || status == 'REJECTED';

  factory StorePurchaseRequisition.fromJson(Map json) {
    final approvals = ((json['approvals'] as List?) ?? const []).whereType<Map>().toList();
    return StorePurchaseRequisition(
        id: toNum(json['id']),
        warehouseId: toIntOrNull(json['warehouse_id']),
        warehouseLabel: toStringOrNull((json['warehouse'] as Map?)?['name']),
        sprNo: (json['spr_no'] ?? '').toString(),
        purpose: toStringOrNull(json['purpose']),
        status: (json['status'] ?? 'PENDING').toString(),
        requestedDate: (json['requested_date'] ?? '').toString(),
        remarks: toStringOrNull(json['remarks']),
        itemCount: ((json['items'] as List?) ?? const []).length,
        approvalSteps: approvals.length,
        approvalsDone: approvals.where((a) => a['status'] == 'APPROVED' || a['status'] == 'SKIPPED').length,
      );
  }
}

class StoreReturnDoc {
  final int id;
  final int warehouseId;
  final String? warehouseLabel;
  final int? departmentId;
  final int? requisitionId;
  final String returnNo;
  final String status; // PENDING | APPROVED | RECEIVED | REJECTED
  final String returnDate;
  final String? remarks;
  final int itemCount;

  const StoreReturnDoc({
    required this.id,
    required this.warehouseId,
    this.warehouseLabel,
    this.departmentId,
    this.requisitionId,
    required this.returnNo,
    required this.status,
    required this.returnDate,
    this.remarks,
    required this.itemCount,
  });

  factory StoreReturnDoc.fromJson(Map json) => StoreReturnDoc(
        id: toNum(json['id']),
        warehouseId: toNum(json['warehouse_id']),
        warehouseLabel: toStringOrNull((json['warehouse'] as Map?)?['name']),
        departmentId: toIntOrNull(json['department_id']),
        requisitionId: toIntOrNull(json['requisition_id']),
        returnNo: (json['return_no'] ?? '').toString(),
        status: (json['status'] ?? 'PENDING').toString(),
        returnDate: (json['return_date'] ?? '').toString(),
        remarks: toStringOrNull(json['remarks']),
        itemCount: ((json['items'] as List?) ?? const []).length,
      );
}

class StoreMrrReturn {
  final int id;
  final int warehouseId;
  final String? warehouseLabel;
  final int? mrrId;
  final String returnNo;
  final String? supplierName;
  final String status; // PENDING | APPROVED | SHIPPED | REJECTED
  final String returnDate;
  final String? remarks;
  final int itemCount;

  const StoreMrrReturn({
    required this.id,
    required this.warehouseId,
    this.warehouseLabel,
    this.mrrId,
    required this.returnNo,
    this.supplierName,
    required this.status,
    required this.returnDate,
    this.remarks,
    required this.itemCount,
  });

  factory StoreMrrReturn.fromJson(Map json) => StoreMrrReturn(
        id: toNum(json['id']),
        warehouseId: toNum(json['warehouse_id']),
        warehouseLabel: toStringOrNull((json['warehouse'] as Map?)?['name']),
        mrrId: toIntOrNull(json['mrr_id']),
        returnNo: (json['return_no'] ?? '').toString(),
        supplierName: toStringOrNull(json['supplier_name']),
        status: (json['status'] ?? 'PENDING').toString(),
        returnDate: (json['return_date'] ?? '').toString(),
        remarks: toStringOrNull(json['remarks']),
        itemCount: ((json['items'] as List?) ?? const []).length,
      );
}

class StorePurchaseOrder {
  final int id;
  final int? warehouseId;
  final String? supplierName;
  final String poNo;
  final String status; // PENDING | APPROVED | SENT | PARTIALLY_RECEIVED | RECEIVED | CANCELLED
  final String orderDate;
  final String? expectedDate;
  final String? remarks;

  const StorePurchaseOrder({
    required this.id,
    this.warehouseId,
    this.supplierName,
    required this.poNo,
    required this.status,
    required this.orderDate,
    this.expectedDate,
    this.remarks,
  });

  factory StorePurchaseOrder.fromJson(Map json) => StorePurchaseOrder(
        id: toNum(json['id']),
        warehouseId: toIntOrNull(json['warehouse_id']),
        supplierName: toStringOrNull(json['supplier_name']),
        poNo: (json['po_no'] ?? '').toString(),
        status: (json['status'] ?? 'PENDING').toString(),
        orderDate: (json['order_date'] ?? '').toString(),
        expectedDate: toStringOrNull(json['expected_date']),
        remarks: toStringOrNull(json['remarks']),
      );
}
