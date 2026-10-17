import '../../../core/network/http_client.dart';
import 'sales_order_model.dart';

/// Read-mostly access to `sales_orders` — the one table behind POS sales,
/// Sales Orders, Invoices, Returns and Held Bills (all just different
/// filters over the same rows, confirmed against desktop's SalesOrderList/
/// InvoiceList/ReturnList/HeldBillList.tsx — none of them are separate
/// models). Actual mutation of a sale only ever happens through
/// `PosService.checkout()`/`.void()` (bespoke, business-rule-heavy) except
/// for cancelling a still-PARKED held bill, which desktop does as a raw
/// status PUT with no side effects (a parked sale never touched stock).
class SalesOrderService {
  final ApiClient _client;
  SalesOrderService(this._client);

  Future<List<SalesOrder>> list({String? statusFilter, int top = 500, bool expandItems = false, bool isPharma = false}) async {
    final params = ['\$expand=${expandItems ? 'client,items' : 'client'}', '\$orderby=id desc', '\$top=$top'];
    final clauses = <String>[
      if (statusFilter != null) "status eq '$statusFilter'",
      // Sales shows only non-pharma sales; the pharma POS asks for its own.
      'is_pharma eq $isPharma',
    ];
    if (clauses.isNotEmpty) params.add('\$filter=${clauses.join(' and ')}');
    final res = await _client.get('sales_orders?${params.join('&')}');
    return unwrapList(res).cast<Map<String, dynamic>>().map(SalesOrder.fromJson).toList();
  }

  Future<SalesOrder> loadDetail(int id) async {
    final res = await _client.get('sales_orders?\$filter=id eq $id&\$expand=client,items,payments&\$top=1');
    final rows = unwrapList(res);
    if (rows.isEmpty) throw ApiException(404, 'Sale not found.');
    return SalesOrder.fromJson((rows.first as Map).cast<String, dynamic>());
  }

  /// A PARKED bill can be dropped without any stock/ledger reversal —
  /// mirrors desktop's HeldBillList.tsx `PUT sales_orders/{id}
  /// {status:'CANCELLED'}`.
  Future<void> cancelHeldBill(int id) async {
    await _client.put('sales_orders', id, {'status': 'CANCELLED'});
  }
}
