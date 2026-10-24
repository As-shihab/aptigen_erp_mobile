import '../../../core/network/http_client.dart';
import '../../store/data/document_models.dart';
import '../../store/data/document_services.dart';
import '../../store/data/store_settings_service.dart';
import 'approval_service.dart';

// Purchase requisitions (SPR) — mobile port of desktop's
// purchase/PurchaseRequisitions.tsx (review, approve / reject, create PO)
// plus the store-side create / edit flow (StorePurchaseRequisitions.tsx).
// No destination warehouse field anywhere on the form.

const sprStatuses = ['PENDING', 'APPROVED', 'ORDERED', 'REJECTED'];

String sprStatusText(String s) => switch (s) {
      'PENDING' => 'Pending',
      'APPROVED' => 'Approved',
      'ORDERED' => 'Ordered',
      'REJECTED' => 'Rejected',
      _ => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' '),
    };

class SprItem {
  final int id;
  final int productId;
  final String productName;
  final double quantity;
  final double? estimatedPrice;
  final String? remarks;
  const SprItem({required this.id, required this.productId, required this.productName, required this.quantity, this.estimatedPrice, this.remarks});

  factory SprItem.fromJson(Map j) {
    final product = j['product'];
    return SprItem(
      id: approvalInt(j['id']) ?? 0,
      productId: approvalInt(j['product_id']) ?? 0,
      productName: (product is Map ? approvalStr(product['name']) : null) ?? 'Product #${j['product_id']}',
      quantity: approvalDouble(j['quantity']),
      estimatedPrice: approvalDoubleOrNull(j['estimated_price']),
      remarks: approvalStr(j['remarks']),
    );
  }

  double get total => quantity * (estimatedPrice ?? 0);
}

class SprRfq {
  final int id;
  final String status;
  final int quotes;
  const SprRfq(this.id, this.status, this.quotes);
}

/// Where a requisition is in the purchase flow, and the tone to show it in.
enum SprStageTone { error, ok, warn, info, violet }

class PurchaseRequisition {
  final int id;
  final int? warehouseId;
  final String sprNo;
  final String? purpose;
  final String status;
  final DateTime? requestedDate;
  final String? remarks;
  final String? warehouseName;
  final String? requesterName;
  final List<SprItem> items;
  final List<SprRfq> rfqs;
  final List<({int id, String poNo})> purchaseOrders;
  final List<ApprovalStep> approvals;
  final int currentSerial;

  const PurchaseRequisition({
    required this.id,
    this.warehouseId,
    required this.sprNo,
    this.purpose,
    required this.status,
    this.requestedDate,
    this.remarks,
    this.warehouseName,
    this.requesterName,
    this.items = const [],
    this.rfqs = const [],
    this.purchaseOrders = const [],
    this.approvals = const [],
    this.currentSerial = 1,
  });

  factory PurchaseRequisition.fromJson(Map j) {
    final wh = j['warehouse'];
    final req = j['requester'];
    return PurchaseRequisition(
      id: approvalInt(j['id']) ?? 0,
      warehouseId: approvalInt(j['warehouse_id']),
      sprNo: approvalStr(j['spr_no']) ?? '#${j['id']}',
      purpose: approvalStr(j['purpose']),
      status: (approvalStr(j['status']) ?? 'PENDING').toUpperCase(),
      requestedDate: j['requested_date'] == null ? null : DateTime.tryParse(j['requested_date'].toString()),
      remarks: approvalStr(j['remarks']),
      warehouseName: wh is Map ? approvalStr(wh['name']) : null,
      requesterName: req is Map ? (approvalStr(req['name']) ?? approvalStr(req['email'])) : null,
      items: j['items'] is List ? (j['items'] as List).whereType<Map>().map(SprItem.fromJson).toList() : const [],
      rfqs: j['rfqs'] is List
          ? (j['rfqs'] as List)
              .whereType<Map>()
              .map((r) => SprRfq(approvalInt(r['id']) ?? 0, (approvalStr(r['status']) ?? '').toUpperCase(), r['quotes'] is List ? (r['quotes'] as List).length : 0))
              .toList()
          : const [],
      purchaseOrders: j['purchase_orders'] is List
          ? (j['purchase_orders'] as List).whereType<Map>().map((p) => (id: approvalInt(p['id']) ?? 0, poNo: approvalStr(p['po_no']) ?? '#${p['id']}')).toList()
          : const [],
      approvals: parseSteps(j['approvals']),
      currentSerial: approvalInt(j['current_serial']) ?? 1,
    );
  }

  double get estimate => items.fold(0, (s, i) => s + i.total);
  bool get inChain => approvals.isNotEmpty;
  bool get isEditable => status == 'PENDING' || status == 'REJECTED';
  List<SprRfq> get liveRfqs => rfqs.where((r) => r.status != 'CANCELLED').toList();
  bool get hasRfq => liveRfqs.isNotEmpty;
  int get quoteCount => liveRfqs.fold(0, (n, r) => n + r.quotes);
  bool get hasQuotes => rfqs.any((r) => r.quotes > 0);
  bool get isOrdered => status == 'ORDERED' || purchaseOrders.isNotEmpty;
  ApprovalStep? get pendingStep => status == 'PENDING' ? currentStep(approvals, currentSerial) : null;

  /// Desktop's sprStage(): derived from what hangs off the requisition.
  ({String label, SprStageTone tone}) get stage {
    if (status == 'REJECTED') return (label: 'Rejected', tone: SprStageTone.error);
    if (isOrdered) return (label: 'PO created', tone: SprStageTone.ok);
    if (status == 'PENDING') {
      final done = approvals.where((s) => s.isDone).length;
      return (label: approvals.isEmpty ? 'Awaiting approval' : 'Awaiting approval ($done/${approvals.length})', tone: SprStageTone.warn);
    }
    if (quoteCount > 0) return (label: 'Quotes received ($quoteCount)', tone: SprStageTone.violet);
    if (hasRfq) return (label: 'RFQ sent', tone: SprStageTone.info);
    return (label: 'Ready for RFQ', tone: SprStageTone.info);
  }
}

class PrService {
  final ApiClient client;
  PrService(this.client);

  static const _expand = r'warehouse($select=name),requester($select=name,email),'
      r'items($select=id,product_id,quantity,estimated_price,remarks;$expand=product($select=id,name)),'
      r'rfqs($select=id,status;$expand=quotes($select=id)),purchase_orders($select=id,po_no),'
      r'approvals($expand=actor($select=id,name,email))';

  static const listQuery = 'store_purchase_requisitions?\$expand=$_expand&\$orderby=id desc&\$top=500';
  static String detailQuery(int id) => 'store_purchase_requisitions?\$filter=id eq $id&\$expand=$_expand&\$top=1';

  /// Store-side products (non-pharma), like desktop's SPR form.
  static const productsQuery = r'store_products?$select=id,name,sku,barcode,short_desc,category_id,sub_category_id,uom_id,price,compare_price,cost_price,stock_qty,low_stock_at,track_stock,is_active,is_featured,thumbnail_url&$filter=is_active eq true and is_pharma eq false&$top=2000';

  DocumentService<Map<String, dynamic>> get _docs => DocumentService<Map<String, dynamic>>(
        client,
        endpoint: 'store_purchase_requisitions',
        itemsEndpoint: 'store_purchase_requisition_items',
        headerIdField: 'purchase_requisition_id',
        lineExpand: 'product',
        lineFields: const {'quantity', 'estimated_price', 'remarks'},
        fromJson: (m) => m,
      );

  Future<String?> generateCode() async {
    try {
      final res = await client.post('generate-code', {'code': 'SPR', 'table': 'store_purchase_requisitions'});
      return res is Map ? approvalStr(res['code']) : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<DocumentLine>> loadLines(int sprId) => _docs.loadLines(sprId);

  Future<int> save({int? id, required Map<String, dynamic> header, required List<DocumentLine> lines, required List<int> originalLineIds}) async {
    int sprId;
    if (id != null) {
      await _docs.updateHeader(id, header);
      sprId = id;
    } else {
      final created = await _docs.createHeader(header);
      final newId = approvalInt(created['id']);
      if (newId == null) throw ApiException(500, 'Purchase requisition header did not return an id');
      sprId = newId;
    }
    await _docs.saveLines(sprId, lines, originalLineIds);
    return sprId;
  }

  /// (Re)starts the SPR chain when store_settings.has_spr_approval is on.
  /// 0 on no chain / no approvers / any failure — the SPR is saved either
  /// way and waits for purchasing to approve it.
  Future<int> startApproval(int sprId) async {
    try {
      final settings = await StoreSettingsService(client).load();
      if (!settings.hasSprApproval) return 0;
      return await ApprovalService(client).start(ApprovalDoc.spr, sprId, settings.sprApproverTypeId);
    } catch (_) {
      return 0;
    }
  }

  Future<void> setStatus(int id, String status) => client.put('store_purchase_requisitions', id, {'status': status});
  Future<void> delete(int id) => client.delete('store_purchase_requisitions', id);
}

String describeSprError(Object e, String fallback) {
  final msg = e is ApiException ? e.message : '';
  if (msg.contains('spr_no') && msg.toLowerCase().contains('unique')) {
    return 'That SPR number is already in use, use a different number';
  }
  return msg.trim().isNotEmpty && e is ApiException && e.statusCode < 500 ? msg : fallback;
}
