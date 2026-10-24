import '../../../core/network/http_client.dart';
import 'rfq_service.dart';

// Comparative study data — desktop purchase/comparative/ComparativeStudy.tsx.
// Chain: store_purchase_requisitions → purchase_rfqs (purchase_requisition_id)
// → purchase_rfq_items + purchase_rfq_quotes → purchase_rfq_quote_items.

class SprSummary {
  final int id;
  final String sprNo;
  final String status;
  final String? purpose;
  final DateTime? requestedDate;
  final String? warehouseName;
  final int quoteCount;
  final int rfqCount;
  const SprSummary({
    required this.id,
    required this.sprNo,
    required this.status,
    this.purpose,
    this.requestedDate,
    this.warehouseName,
    this.quoteCount = 0,
    this.rfqCount = 0,
  });

  factory SprSummary.fromJson(Map<String, dynamic> j) {
    final rfqs = (j['rfqs'] is List ? j['rfqs'] as List : const []).whereType<Map>().toList();
    var quotes = 0;
    for (final r in rfqs) {
      final q = r['quotes'];
      if (q is List) quotes += q.length;
    }
    final wh = j['warehouse'];
    return SprSummary(
      id: j['id'] is num ? (j['id'] as num).toInt() : int.tryParse('${j['id']}') ?? 0,
      sprNo: (j['spr_no'] ?? '—').toString(),
      status: (j['status'] ?? '').toString(),
      purpose: j['purpose']?.toString(),
      requestedDate: j['requested_date'] == null ? null : DateTime.tryParse(j['requested_date'].toString()),
      warehouseName: wh is Map ? wh['name']?.toString() : null,
      quoteCount: quotes,
      rfqCount: rfqs.length,
    );
  }
}

/// One quote across every RFQ raised for an SPR.
class QuoteCardData {
  final RfqQuote quote;
  final Rfq rfq;
  final double total;
  final bool complete;
  final int pricedCount;
  const QuoteCardData({required this.quote, required this.rfq, required this.total, required this.complete, required this.pricedCount});
  String get supplier => quote.supplier;
}

/// One requested product (matched by product_id across RFQs) with a price
/// slot per quote card.
class ComparisonRow {
  final int productId;
  final String code;
  final String name;
  final double quantity;
  final List<double?> prices;
  final double? lowest;
  final String? bestSupplier;
  const ComparisonRow({required this.productId, required this.code, required this.name, required this.quantity, required this.prices, this.lowest, this.bestSupplier});
}

/// Cards cheapest-first (complete ones ahead), same as desktop.
List<QuoteCardData> buildQuoteCards(List<Rfq> rfqs) {
  final list = <QuoteCardData>[];
  for (final rfq in rfqs) {
    for (final q in rfq.quotes) {
      final t = quoteTotalOf(rfq.items, q);
      list.add(QuoteCardData(quote: q, rfq: rfq, total: t.total, complete: t.complete, pricedCount: t.priced));
    }
  }
  list.sort((a, b) {
    final c = (b.complete ? 1 : 0) - (a.complete ? 1 : 0);
    return c != 0 ? c : a.total.compareTo(b.total);
  });
  return list;
}

int? bestCardQuoteId(List<QuoteCardData> cards) {
  QuoteCardData? best;
  for (final c in cards) {
    if (!c.complete || c.quote.status == 'REJECTED') continue;
    if (best == null || c.total < best.total) best = c;
  }
  return best?.quote.id;
}

List<ComparisonRow> buildComparisonRows(List<Rfq> rfqs, List<QuoteCardData> cards) {
  final seen = <int, RfqItem>{};
  for (final rfq in rfqs) {
    for (final item in rfq.items) {
      seen.putIfAbsent(item.productId, () => item);
    }
  }
  return [
    for (final item in seen.values)
      () {
        final prices = <double?>[
          for (final c in cards)
            () {
              final hit = c.rfq.items.where((i) => i.productId == item.productId).firstOrNull;
              return hit == null ? null : quotePriceOf(c.quote, hit.id);
            }(),
        ];
        var lowIdx = -1;
        for (var i = 0; i < prices.length; i++) {
          final p = prices[i];
          if (p != null && (lowIdx == -1 || p < prices[lowIdx]!)) lowIdx = i;
        }
        return ComparisonRow(
          productId: item.productId,
          code: item.code,
          name: item.productName,
          quantity: item.quantity,
          prices: prices,
          lowest: lowIdx == -1 ? null : prices[lowIdx],
          bestSupplier: lowIdx == -1 ? null : cards[lowIdx].supplier,
        );
      }(),
  ];
}

class ComparativeService {
  final ApiClient _client;
  ComparativeService([ApiClient? client]) : _client = client ?? ApiClient();

  /// Requisitions at the quotation stage (approved or already ordered) plus
  /// purchase settings for the award step — one batch.
  Future<({List<SprSummary> sprs, PurchaseApprovalSettings settings})> loadRequisitions() async {
    final res = await _client.batch([
      BatchRequest(
        id: '1',
        method: 'GET',
        url: "store_purchase_requisitions?\$select=id,spr_no,status,purpose,requested_date&\$filter=status eq 'APPROVED' or status eq 'ORDERED'"
            '&\$expand=warehouse(\$select=id,name),rfqs(\$select=id;\$expand=quotes(\$select=id))&\$orderby=id desc&\$top=500',
      ),
      BatchRequest(id: '2', method: 'GET', url: 'purchase_settings'),
    ]);
    List<Map<String, dynamic>> rows(String id) => unwrapList(unwrapBatchBody(res, id)).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    return (sprs: rows('1').map(SprSummary.fromJson).toList(), settings: PurchaseApprovalSettings.fromRows(rows('2')));
  }

  Future<List<Rfq>> loadRfqsForSpr(int sprId) async {
    final res = await _client.get(
      'purchase_rfqs?\$filter=purchase_requisition_id eq $sprId'
      '&\$select=id,rfq_no,status,deadline_date,purchase_requisition_id'
      '&\$expand=items(\$select=id,product_id,quantity,remarks;\$expand=product(\$select=id,name,sku)),'
      'quotes(\$expand=items(\$select=id,rfq_item_id,unit_price),supplier(\$select=id,supplier_name),purchase_order(\$select=id,po_no))'
      '&\$orderby=id asc&\$top=100',
    );
    return unwrapList(res).whereType<Map>().map((m) => Rfq.fromJson(m.cast<String, dynamic>())).toList();
  }
}
