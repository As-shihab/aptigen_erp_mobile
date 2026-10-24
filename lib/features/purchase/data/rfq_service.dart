import '../../../core/network/http_client.dart';
import '../../../core/storage/app_storage.dart';

// RFQ data layer — mirrors desktop purchase/rfq/PurchaseRfqs.tsx,
// RfqQuotesDialog.tsx and shared/awardQuote.ts (+ the startPoApproval step
// of shared/poApproval.ts). Endpoints are the Prisma model names from
// cloud/prisma/schema/purchase.prisma; workplace_id is never sent (the
// OData layer scopes it).

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
int? _i(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
String? _s(dynamic v) {
  final t = v?.toString().trim() ?? '';
  return t.isEmpty ? null : t;
}

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
Map<String, dynamic> _m(dynamic v) => v is Map ? v.cast<String, dynamic>() : const {};
List<Map<String, dynamic>> _rows(dynamic v) => (v is List ? v : const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();

/// `{value: row}` single-row OData wrapper (create / update responses).
Map<String, dynamic> unwrapRow(dynamic res) {
  final v = (res is Map && res['value'] is Map) ? res['value'] : res;
  return v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
}

/// Date-only value as the desktop DatePicker sends it (`new Date('yyyy-MM-dd').toISOString()`).
String? isoDateOnly(DateTime? d) => d == null ? null : DateTime.utc(d.year, d.month, d.day).toIso8601String();

const rfqStatuses = ['DRAFT', 'SENT', 'CLOSED', 'AWARDED', 'CANCELLED'];
const rfqStatusLabel = {'DRAFT': 'Draft', 'SENT': 'Sent', 'CLOSED': 'Closed', 'AWARDED': 'Awarded', 'CANCELLED': 'Cancelled'};
const quoteStatusLabel = {'RECEIVED': 'Received', 'AWARDED': 'PO created', 'REJECTED': 'Not selected'};

const _acronyms = {'PI', 'PO', 'RFQ', 'SPR', 'MRR'};

/// PENDING → "Pending", PI_CREATED → "PI created". Sentence case, acronyms kept.
String purchaseStatusLabel(String? code) {
  if (code == null || code.isEmpty) return '—';
  final words = code.split(RegExp(r'[_\s]+')).where((w) => w.isNotEmpty).toList();
  return [
    for (var i = 0; i < words.length; i++)
      _acronyms.contains(words[i].toUpperCase())
          ? words[i].toUpperCase()
          : (i == 0 ? words[i][0].toUpperCase() + words[i].substring(1).toLowerCase() : words[i].toLowerCase()),
  ].join(' ');
}

class RfqItem {
  final int id;
  final int productId;
  final double quantity;
  final String? remarks;
  final String productName;
  final String? sku;
  const RfqItem({required this.id, required this.productId, required this.quantity, this.remarks, required this.productName, this.sku});

  factory RfqItem.fromJson(Map<String, dynamic> j) {
    final p = _m(j['product']);
    return RfqItem(
      id: _i(j['id']) ?? 0,
      productId: _i(j['product_id']) ?? _i(p['id']) ?? 0,
      quantity: _d(j['quantity']),
      remarks: _s(j['remarks']),
      productName: _s(p['name']) ?? '—',
      sku: _s(p['sku']),
    );
  }

  String get code => sku ?? '#$productId';
}

class RfqQuoteLine {
  final int id;
  final int rfqItemId;
  final double unitPrice;
  const RfqQuoteLine({required this.id, required this.rfqItemId, required this.unitPrice});
  factory RfqQuoteLine.fromJson(Map<String, dynamic> j) =>
      RfqQuoteLine(id: _i(j['id']) ?? 0, rfqItemId: _i(j['rfq_item_id']) ?? 0, unitPrice: _d(j['unit_price']));
}

class RfqQuote {
  final int id;
  final int? rfqId;
  final int? supplierId;
  final String? supplierName;
  final String status;
  final DateTime? quoteDate;
  final DateTime? validUntil;
  final int? leadTimeDays;
  final String? remarks;
  final int? purchaseOrderId;
  final String? poNo;
  final List<RfqQuoteLine> items;
  const RfqQuote({
    required this.id,
    this.rfqId,
    this.supplierId,
    this.supplierName,
    required this.status,
    this.quoteDate,
    this.validUntil,
    this.leadTimeDays,
    this.remarks,
    this.purchaseOrderId,
    this.poNo,
    this.items = const [],
  });

  factory RfqQuote.fromJson(Map<String, dynamic> j) {
    final sup = _m(j['supplier']);
    final po = _m(j['purchase_order']);
    return RfqQuote(
      id: _i(j['id']) ?? 0,
      rfqId: _i(j['rfq_id']),
      supplierId: _i(j['supplier_id']),
      supplierName: _s(j['supplier_name']) ?? _s(sup['supplier_name']),
      status: _s(j['status']) ?? 'RECEIVED',
      quoteDate: _date(j['quote_date']),
      validUntil: _date(j['valid_until']),
      leadTimeDays: _i(j['lead_time_days']),
      remarks: _s(j['remarks']),
      purchaseOrderId: _i(j['purchase_order_id']) ?? _i(po['id']),
      poNo: _s(po['po_no']),
      items: _rows(j['items']).map(RfqQuoteLine.fromJson).toList(),
    );
  }

  String get supplier => supplierName ?? 'Unknown supplier';

  String get statusText => status == 'AWARDED' && poNo != null ? 'PO $poNo' : (quoteStatusLabel[status] ?? purchaseStatusLabel(status));
}

class Rfq {
  final int id;
  final String rfqNo;
  final String? title;
  final String status;
  final DateTime? rfqDate;
  final DateTime? deadline;
  final String? remarks;
  final int? sprId;
  final String? sprNo;
  final String? sprStatus;
  final String? warehouseName;
  final int? clientId;
  final String? clientName;
  final List<RfqItem> items;
  final List<RfqQuote> quotes;
  const Rfq({
    required this.id,
    required this.rfqNo,
    this.title,
    required this.status,
    this.rfqDate,
    this.deadline,
    this.remarks,
    this.sprId,
    this.sprNo,
    this.sprStatus,
    this.warehouseName,
    this.clientId,
    this.clientName,
    this.items = const [],
    this.quotes = const [],
  });

  factory Rfq.fromJson(Map<String, dynamic> j) {
    final spr = _m(j['purchase_requisition']);
    final client = _m(j['client']);
    final items = _rows(j['items']).map(RfqItem.fromJson).toList()..sort((a, b) => a.id.compareTo(b.id));
    final quotes = _rows(j['quotes']).map(RfqQuote.fromJson).toList()..sort((a, b) => a.id.compareTo(b.id));
    return Rfq(
      id: _i(j['id']) ?? 0,
      rfqNo: _s(j['rfq_no']) ?? '—',
      title: _s(j['title']),
      status: _s(j['status']) ?? 'DRAFT',
      rfqDate: _date(j['rfq_date']),
      deadline: _date(j['deadline_date']),
      remarks: _s(j['remarks']),
      sprId: _i(j['purchase_requisition_id']),
      sprNo: _s(spr['spr_no']),
      sprStatus: _s(spr['status']),
      warehouseName: _s(_m(spr['warehouse'])['name']),
      clientId: _i(j['client_id']),
      clientName: _s(client['name']),
      items: items,
      quotes: quotes,
    );
  }

  String get statusText => rfqStatusLabel[status] ?? purchaseStatusLabel(status);
  bool get isAwarded => status == 'AWARDED' || quotes.any((q) => q.status == 'AWARDED');
}

// ── Pricing helpers (awardQuote.ts / RfqQuotesDialog.tsx) ───────────────

double? quotePriceOf(RfqQuote quote, int rfqItemId) {
  for (final l in quote.items) {
    if (l.rfqItemId == rfqItemId) return l.unitPrice;
  }
  return null;
}

typedef QuoteTotal = ({double total, int priced, bool complete});

/// Σ line quantity × quoted unit price; `complete` when every line is priced.
QuoteTotal quoteTotalOf(List<RfqItem> items, RfqQuote quote) {
  var total = 0.0;
  var priced = 0;
  for (final item in items) {
    final price = quotePriceOf(quote, item.id);
    if (price == null) continue;
    priced++;
    total += price * item.quantity;
  }
  return (total: total, priced: priced, complete: items.isNotEmpty && priced == items.length);
}

/// Cheapest complete, non-rejected quote.
int? bestQuoteIdOf(List<RfqItem> items, List<RfqQuote> quotes) {
  int? best;
  double? bestTotal;
  for (final q in quotes) {
    if (q.status == 'REJECTED') continue;
    final t = quoteTotalOf(items, q);
    if (!t.complete) continue;
    if (bestTotal == null || t.total < bestTotal) {
      bestTotal = t.total;
      best = q.id;
    }
  }
  return best;
}

/// Lowest price quoted for one RFQ line across [quotes].
double? lowestPriceFor(int rfqItemId, List<RfqQuote> quotes) {
  double? low;
  for (final q in quotes) {
    final p = quotePriceOf(q, rfqItemId);
    if (p != null && (low == null || p < low)) low = p;
  }
  return low;
}

/// Same gate as ComparativeStudy.tsx's canAward().
bool canAwardQuote(Rfq rfq, RfqQuote quote) {
  if (quote.status != 'RECEIVED') return false;
  if (quoteTotalOf(rfq.items, quote).priced == 0) return false;
  if (rfq.status == 'AWARDED' || rfq.status == 'CANCELLED') return false;
  return !rfq.quotes.any((q) => q.status == 'AWARDED');
}

// ── Settings ────────────────────────────────────────────────────────────

class PurchaseApprovalSettings {
  final bool hasPoApproval;
  final int? poApproverTypeId;
  const PurchaseApprovalSettings({this.hasPoApproval = false, this.poApproverTypeId});
  factory PurchaseApprovalSettings.fromRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return const PurchaseApprovalSettings();
    final r = rows.first;
    final v = r['has_po_approval'];
    return PurchaseApprovalSettings(hasPoApproval: v == true || v == 1 || v == 'true', poApproverTypeId: _i(r['po_approver_type_id']));
  }
}

// ── Form payloads ───────────────────────────────────────────────────────

class RfqLineDraft {
  int? id;
  int? productId;
  String productName;
  String quantity;
  String remarks;
  RfqLineDraft({this.id, this.productId, this.productName = '', this.quantity = '1', this.remarks = ''});
  bool get isValid => productId != null && (double.tryParse(quantity.trim()) ?? 0) > 0;
}

class RfqLookups {
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> requisitions;
  final List<Map<String, dynamic>> clients;
  const RfqLookups({this.products = const [], this.requisitions = const [], this.clients = const []});
}

class RfqDetailBundle {
  final Rfq? rfq;
  final List<Map<String, dynamic>> suppliers;
  final PurchaseApprovalSettings settings;
  const RfqDetailBundle({this.rfq, this.suppliers = const [], this.settings = const PurchaseApprovalSettings()});
}

class AwardResult {
  final int poId;
  final String poNo;
  final bool submittedForApproval;
  const AwardResult(this.poId, this.poNo, this.submittedForApproval);
}

const _detailExpand = 'purchase_requisition(\$select=id,spr_no,status;\$expand=warehouse(\$select=name)),client(\$select=id,name),'
    'items(\$expand=product(\$select=id,name,sku)),'
    'quotes(\$expand=items(\$select=id,rfq_item_id,unit_price),supplier(\$select=id,supplier_name),purchase_order(\$select=id,po_no))';

class RfqService {
  final ApiClient _client;
  RfqService([ApiClient? client]) : _client = client ?? ApiClient();

  static const listUrl = 'purchase_rfqs?\$expand=purchase_requisition(\$select=id,spr_no,status;\$expand=warehouse(\$select=name)),client(\$select=id,name),'
      'items(\$select=id,quantity,product_id),quotes(\$select=id,status,supplier_name,quote_date,valid_until,lead_time_days,purchase_order_id;\$expand=items(\$select=id,rfq_item_id,unit_price),purchase_order(\$select=id,po_no))'
      '&\$orderby=id desc&\$top=500';

  Future<List<Rfq>> loadList() async => unwrapList(await _client.get(listUrl)).whereType<Map>().map((m) => Rfq.fromJson(m.cast<String, dynamic>())).toList();

  /// Products, approved SPRs and clients for the RFQ form — one batch.
  Future<RfqLookups> loadLookups() async {
    final res = await _client.batch([
      BatchRequest(id: '1', method: 'GET', url: 'store_products?\$select=id,name,sku&\$filter=is_active eq true&\$top=2000'),
      // Flow: only SPRs the store approved (and purchase hasn't ordered yet) go out for quotation.
      BatchRequest(id: '2', method: 'GET', url: "store_purchase_requisitions?\$select=id,spr_no&\$filter=status eq 'APPROVED'&\$orderby=id desc&\$top=500"),
      BatchRequest(id: '3', method: 'GET', url: 'clients?\$select=id,name&\$filter=is_active eq true&\$orderby=name asc&\$top=1000'),
    ]);
    List<Map<String, dynamic>> rows(String id) => _rows(unwrapList(unwrapBatchBody(res, id)));
    return RfqLookups(products: rows('1'), requisitions: rows('2'), clients: rows('3'));
  }

  /// One RFQ with lines + quotes, the active suppliers and purchase settings — one batch.
  Future<RfqDetailBundle> loadDetail(int rfqId) async {
    final res = await _client.batch([
      BatchRequest(id: '1', method: 'GET', url: 'purchase_rfqs?\$filter=id eq $rfqId&\$expand=$_detailExpand&\$top=1'),
      BatchRequest(id: '2', method: 'GET', url: "suppliers?\$select=id,supplier_name&\$filter=status eq 'ACTIVE'&\$top=500"),
      BatchRequest(id: '3', method: 'GET', url: 'purchase_settings'),
    ]);
    final rfqRows = _rows(unwrapList(unwrapBatchBody(res, '1')));
    return RfqDetailBundle(
      rfq: rfqRows.isEmpty ? null : Rfq.fromJson(rfqRows.first),
      suppliers: _rows(unwrapList(unwrapBatchBody(res, '2'))),
      settings: PurchaseApprovalSettings.fromRows(_rows(unwrapList(unwrapBatchBody(res, '3')))),
    );
  }

  Future<List<RfqLineDraft>> loadRfqLines(int rfqId) async {
    final res = await _client.get('purchase_rfq_items?\$filter=rfq_id eq $rfqId&\$expand=product(\$select=id,name)&\$orderby=id asc&\$top=500');
    return _rows(unwrapList(res))
        .map((r) => RfqLineDraft(
              id: _i(r['id']),
              productId: _i(r['product_id']),
              productName: _s(_m(r['product'])['name']) ?? '',
              quantity: _fmtQty(r['quantity']),
              remarks: _s(r['remarks']) ?? '',
            ))
        .toList();
  }

  /// Picking a source SPR on a fresh RFQ pulls its lines in.
  Future<List<RfqLineDraft>> loadRequisitionLines(int sprId) async {
    final res = await _client.get('store_purchase_requisition_items?\$filter=purchase_requisition_id eq $sprId&\$expand=product(\$select=id,name)&\$top=500');
    return _rows(unwrapList(res))
        .map((r) => RfqLineDraft(
              productId: _i(r['product_id']),
              productName: _s(_m(r['product'])['name']) ?? '',
              quantity: _fmtQty(r['quantity']),
              remarks: _s(r['remarks']) ?? '',
            ))
        .toList();
  }

  static String _fmtQty(dynamic v) {
    final d = _d(v ?? 1);
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }

  /// Best effort — null leaves the field for manual entry.
  Future<String?> generateCode(String code, String table) async {
    try {
      final res = await _client.post('generate-code', {'code': code, 'table': table}, isV8: false);
      return res is Map ? _s(res['code']) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<int?> currentUserId() async {
    final user = await AppStorage.getUser();
    final id = _i(user?['id']);
    return id != null && id > 0 ? id : null;
  }

  /// Header create/update, then the line create/update/delete diff — same
  /// order as PurchaseRfqs.tsx's save().
  Future<int> saveRfq({
    int? editingId,
    required Map<String, dynamic> header,
    required List<RfqLineDraft> lines,
    required List<int> originalLineIds,
  }) async {
    int? rfqId = editingId;
    if (editingId != null) {
      await _client.put('purchase_rfqs', editingId, header);
    } else {
      final createdBy = await currentUserId();
      final created = unwrapRow(await _client.post('purchase_rfqs', {...header, 'created_by': createdBy}, isV8: true));
      rfqId = _i(created['id']);
      if (rfqId == null) throw Exception('RFQ header did not return an id');
    }
    final valid = lines.where((l) => l.isValid).toList();
    final surviving = valid.map((l) => l.id).whereType<int>().toSet();
    for (final id in originalLineIds.where((id) => !surviving.contains(id))) {
      await _client.delete('purchase_rfq_items', id);
    }
    for (final line in valid) {
      final body = {
        'rfq_id': rfqId,
        'product_id': line.productId,
        'quantity': double.tryParse(line.quantity.trim()) ?? 0,
        'remarks': _s(line.remarks),
      };
      if (line.id != null) {
        await _client.put('purchase_rfq_items', line.id!, body);
      } else {
        await _client.post('purchase_rfq_items', body, isV8: true);
      }
    }
    return rfqId!;
  }

  Future<void> deleteRfq(int id) => _client.delete('purchase_rfqs', id);

  /// Quote header + per-line price diff (RfqQuotesDialog.saveQuote).
  Future<void> saveQuote({
    required Rfq rfq,
    RfqQuote? editing,
    required int? supplierId,
    required String supplierName,
    DateTime? validUntil,
    int? leadTimeDays,
    String? remarks,
    required Map<int, String> prices,
  }) async {
    final body = {
      'rfq_id': rfq.id,
      'supplier_id': supplierId,
      'supplier_name': supplierName.trim(),
      'valid_until': isoDateOnly(validUntil),
      'lead_time_days': leadTimeDays,
      'remarks': _s(remarks),
    };
    int? quoteId = editing?.id;
    if (editing != null) {
      await _client.put('purchase_rfq_quotes', editing.id, body);
    } else {
      final created = unwrapRow(await _client.post('purchase_rfq_quotes', body, isV8: true));
      quoteId = _i(created['id']);
      if (quoteId == null) throw Exception('Quote did not return an id');
    }
    final existing = {for (final qi in editing?.items ?? const <RfqQuoteLine>[]) qi.rfqItemId: qi.id};
    for (final item in rfq.items) {
      final raw = (prices[item.id] ?? '').trim();
      final price = double.tryParse(raw);
      final existingId = existing[item.id];
      if (raw.isEmpty || price == null || !price.isFinite) {
        if (existingId != null) await _client.delete('purchase_rfq_quote_items', existingId);
        continue;
      }
      final lineBody = {'quote_id': quoteId, 'rfq_item_id': item.id, 'unit_price': price};
      if (existingId != null) {
        await _client.put('purchase_rfq_quote_items', existingId, lineBody);
      } else {
        await _client.post('purchase_rfq_quote_items', lineBody, isV8: true);
      }
    }
    // First quote in means the RFQ has gone out.
    if (rfq.status == 'DRAFT') {
      try {
        await _client.put('purchase_rfqs', rfq.id, {'status': 'SENT'});
      } catch (_) {}
    }
  }

  Future<void> deleteQuote(int id) => _client.delete('purchase_rfq_quotes', id);

  /// (Re)starts the PO approval chain — shared/poApproval.ts startPoApproval.
  Future<int> startPoApproval(int purchaseOrderId, int? approveTypeId) async {
    final existing = _rows(unwrapList(await _client.get('purchase_order_approvals?\$select=id&\$filter=purchase_order_id eq $purchaseOrderId&\$top=200')));
    for (final row in existing) {
      await _client.delete('purchase_order_approvals', row['id']);
    }
    if (approveTypeId == null) return 0;
    final approvers = _rows(unwrapList(await _client.get('approve_type_has_approvers?\$filter=approve_type_id eq $approveTypeId&\$orderby=serial asc&\$top=100')));
    if (approvers.isEmpty) return 0;
    for (var i = 0; i < approvers.length; i++) {
      final a = approvers[i];
      await _client.post(
        'purchase_order_approvals',
        {
          'purchase_order_id': purchaseOrderId,
          'serial': i + 1,
          'label': _s(a['label']) ?? 'Step ${i + 1}',
          'is_required': a['is_required'] != false,
          'approver_emp_id': a['approver_emp_id'],
          'approver_des_id': a['approver_des_id'],
          'workplace_member_id': a['workplace_member_id'],
          'status': 'PENDING',
        },
        isV8: true,
      );
    }
    await _client.put('purchase_orders', purchaseOrderId, {'status': 'PENDING', 'approve_type_id': approveTypeId, 'current_serial': 1});
    return approvers.length;
  }

  /// Award → one new PO for the winning supplier at the quoted prices, then
  /// this quote AWARDED (linked to the PO), the rest REJECTED, the RFQ
  /// AWARDED and its SPR ORDERED. Same steps as shared/awardQuote.ts.
  /// Returns null when the supplier priced nothing.
  Future<AwardResult?> awardQuote({required Rfq rfq, required RfqQuote quote, required PurchaseApprovalSettings settings}) async {
    final lines = [
      for (final item in rfq.items)
        if (quotePriceOf(quote, item.id) != null) (item: item, price: quotePriceOf(quote, item.id)!),
    ];
    if (lines.isEmpty) return null;

    var poNo = await generateCode('PO', 'purchase_orders') ?? '';
    if (poNo.isEmpty) poNo = 'PO-${rfq.rfqNo}';

    final created = unwrapRow(await _client.post(
      'purchase_orders',
      {
        'po_no': poNo,
        'supplier_id': quote.supplierId,
        'supplier_name': quote.supplierName,
        'purchase_requisition_id': rfq.sprId,
        'status': 'PENDING',
        'expected_date': quote.leadTimeDays != null ? DateTime.now().add(Duration(days: quote.leadTimeDays!)).toUtc().toIso8601String() : null,
        'remarks': 'Awarded from ${rfq.rfqNo}',
      },
      isV8: true,
    ));
    final poId = _i(created['id']);
    if (poId == null) throw Exception('Purchase order did not return an id');

    for (final l in lines) {
      await _client.post(
        'purchase_order_items',
        {'purchase_order_id': poId, 'product_id': l.item.productId, 'quantity': l.item.quantity, 'unit_price': l.price, 'remarks': l.item.remarks},
        isV8: true,
      );
    }

    var submitted = false;
    if (settings.hasPoApproval) submitted = await startPoApproval(poId, settings.poApproverTypeId) > 0;

    await _client.put('purchase_rfq_quotes', quote.id, {'status': 'AWARDED', 'purchase_order_id': poId});
    for (final other in rfq.quotes.where((q) => q.id != quote.id && q.status != 'REJECTED')) {
      try {
        await _client.put('purchase_rfq_quotes', other.id, {'status': 'REJECTED'});
      } catch (_) {}
    }
    await _client.put('purchase_rfqs', rfq.id, {'status': 'AWARDED'});
    // Last step of SPR → RFQ → comparative study → PO: the requisition is now ordered.
    if (rfq.sprId != null) {
      try {
        await _client.put('store_purchase_requisitions', rfq.sprId!, {'status': 'ORDERED'});
      } catch (_) {}
    }
    return AwardResult(poId, poNo, submitted);
  }
}
