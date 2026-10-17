typedef DiscountType = String; // 'PERCENT' | 'FLAT' | null (no discount)
typedef PaymentMethod = String; // 'CASH' | 'CARD' | 'MOBILE_BANKING'

/// One product line in an in-progress cart — mutable, in-memory only until
/// parked/checked out. Mirrors desktop's `CartLine` (PosTerminal.tsx:50-59).
class CartLine {
  final int productId;
  final String name;
  final double unitPrice;
  int quantity;
  DiscountType? discountType;
  double discountValue;
  /// Null when the product isn't stock-tracked or allows backorder — no
  /// client-side cap to enforce in that case (server still re-validates).
  final double? maxStock;

  CartLine({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.discountType,
    this.discountValue = 0,
    this.maxStock,
  });

  double get gross => unitPrice * quantity;
  double get discountAmount => computeDiscount(gross, discountType, discountValue);
  double get lineTotal => gross - discountAmount;
}

/// One payment-tender line entered at checkout — mirrors desktop's
/// `PaymentLine` (PosTerminal.tsx:70).
class PaymentLine {
  final PaymentMethod method;
  final double amount;
  final String? reference;
  const PaymentLine({required this.method, required this.amount, this.reference});

  Map<String, dynamic> toJson() => {'method': method, 'amount': amount, if (reference != null) 'reference': reference};
}

/// One register tab — POS supports several of these open at once ("Sale 1",
/// "Sale 2", ...), each independent. `saleId` is non-null only once this
/// cart has been parked or resumed from a held bill server-side — mirrors
/// desktop's `CartTab` (PosTerminal.tsx:60-69).
class CartTab {
  int? saleId;
  String label;
  int? clientId;
  String? clientName;
  List<CartLine> lines;
  DiscountType? discountType;
  double discountValue;
  double taxRate;
  String? note;

  CartTab({
    this.saleId,
    required this.label,
    this.clientId,
    this.clientName,
    List<CartLine>? lines,
    this.discountType,
    this.discountValue = 0,
    this.taxRate = 0,
    this.note,
  }) : lines = lines ?? [];

  double get subtotal => lines.fold(0.0, (sum, l) => sum + l.lineTotal);
  double get discountAmount => computeDiscount(subtotal, discountType, discountValue);
  double get taxableAmount => subtotal - discountAmount;
  double get taxAmount => taxableAmount * taxRate / 100;
  double get total => taxableAmount + taxAmount;
  bool get isEmpty => lines.isEmpty;
}

/// `PERCENT` = percent of gross, `FLAT` = a flat amount, always clamped to
/// `[0, gross]` — identical formula client- and server-side (see
/// pos.service.ts's `computeLineDiscount`), so on-screen totals match what
/// checkout() actually persists.
double computeDiscount(double gross, DiscountType? type, double value) {
  if (type == null || value <= 0) return 0;
  final amount = type == 'PERCENT' ? gross * value / 100 : value;
  return amount.clamp(0, gross);
}

const List<PaymentMethod> kPaymentMethods = ['CASH', 'CARD', 'MOBILE_BANKING'];

/// Matches desktop's current PosTerminal.tsx state — Card/Mobile Banking are
/// modeled end-to-end (schema, backend) but the desktop UI itself only
/// enables Cash today (no payment processor wired up yet); mirrored here
/// rather than offering payment methods desktop itself doesn't actually
/// support yet.
bool isPaymentMethodEnabled(PaymentMethod method) => method == 'CASH';
