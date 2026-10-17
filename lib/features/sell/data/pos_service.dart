import '../../../core/network/http_client.dart';
import 'cart_models.dart';
import 'sales_order_model.dart';

/// `sell/pos/checkout` and `sell/pos/:id/void` — bespoke (non-OData) routes
/// that own all the checkout business logic server-side (re-priced from
/// live `store_products`, stock decrement/restore, ledger posting against
/// `order_settings.default_warehouse_id` if set). The client only ever
/// builds the request; it must never persist its own computed totals —
/// see cloud/src/module/sell/pos/pos.service.ts's `priceItems`/
/// `computeTotals`. Mirrors desktop's `submitCheckout` (PosTerminal.tsx).
class PosService {
  final ApiClient _client;
  PosService(this._client);

  /// Same endpoint/body shape for both "Park" (park: true, no payments) and
  /// "Complete" (park: false, at least one payment line) — only `park`
  /// differs, matching desktop exactly.
  Future<SalesOrder> checkout(CartTab cart, {required bool park, List<PaymentLine> payments = const [], bool isPharma = false}) async {
    final body = {
      'sale_id': cart.saleId,
      'client_id': cart.clientId,
      'items': cart.lines
          .map((l) => {
                'product_id': l.productId,
                'quantity': l.quantity,
                'discount_type': l.discountType,
                'discount_value': l.discountValue,
              })
          .toList(),
      'discount_type': cart.discountType,
      'discount_value': cart.discountValue,
      'tax_rate': cart.taxRate,
      'note': cart.note,
      'park': park,
      'payments': payments.map((p) => p.toJson()).toList(),
      'is_pharma': isPharma,
    };
    final res = await _client.post('sell/pos/checkout', body, isV8: false);
    final unwrapped = (res is Map && res['value'] is Map) ? res['value'] : res;
    return SalesOrder.fromJson((unwrapped as Map).cast<String, dynamic>());
  }

  /// Full-sale-only — restores every line's stock and flips status to
  /// REFUNDED; payment rows are left as-is (matches pos.service.ts, no
  /// partial-line refund concept exists).
  Future<SalesOrder> voidSale(int saleId) async {
    final res = await _client.post('sell/pos/$saleId/void', const {}, isV8: false);
    final unwrapped = (res is Map && res['value'] is Map) ? res['value'] : res;
    return SalesOrder.fromJson((unwrapped as Map).cast<String, dynamic>());
  }
}
