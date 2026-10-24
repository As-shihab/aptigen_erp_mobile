import '../../store/data/store_util.dart';

/// One `sales_items` line as it was actually sold — name/unit_price are a
/// snapshot at sale time (see sell.prisma's `sales_items` comment), so this
/// never needs to join back to the live product for historical display.
class SalesOrderItem {
  final int id;
  final int productId;
  final String name;
  final double unitPrice;
  final int quantity;
  final double discountAmount;
  final double lineTotal;

  const SalesOrderItem({
    required this.id,
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.discountAmount,
    required this.lineTotal,
  });

  factory SalesOrderItem.fromJson(Map json) => SalesOrderItem(
        id: toNum(json['id']),
        productId: toNum(json['product_id']),
        name: (json['name'] ?? '').toString(),
        unitPrice: toDouble(json['unit_price']),
        quantity: toNum(json['quantity']),
        discountAmount: toDouble(json['discount_amount']),
        lineTotal: toDouble(json['line_total']),
      );
}

class OrderPayment {
  final int id;
  final String method;
  final double amount;
  final String? reference;
  final String createdAt;

  const OrderPayment({required this.id, required this.method, required this.amount, this.reference, required this.createdAt});

  factory OrderPayment.fromJson(Map json) => OrderPayment(
        id: toNum(json['id']),
        method: (json['method'] ?? '').toString(),
        amount: toDouble(json['amount']),
        reference: toStringOrNull(json['reference']),
        createdAt: (json['created_at'] ?? '').toString(),
      );
}

/// A `sales_orders` row — the single table behind POS sales, Sales Orders,
/// Invoices (unfiltered) and Returns (REFUNDED filter) and Held Bills
/// (PARKED filter), mirroring desktop's `ReceiptSale` shape (PosReceipt.tsx).
class SalesOrder {
  final int id;
  final String status; // DRAFT | PARKED | COMPLETED | REFUNDED | CANCELLED
  final int? clientId;
  final String? clientName;
  final String? clientPhone;
  final double subtotal;
  final String? discountType;
  final double discountValue;
  final double discountAmount;
  final double taxRate;
  final double taxAmount;
  final double total;
  final double paidAmount;
  final double changeAmount;
  final String? note;
  final String? completedAt;
  final String createdAt;
  final String updatedAt;
  final List<SalesOrderItem> items;
  final List<OrderPayment> payments;

  const SalesOrder({
    required this.id,
    required this.status,
    this.clientId,
    this.clientName,
    this.clientPhone,
    required this.subtotal,
    this.discountType,
    required this.discountValue,
    required this.discountAmount,
    required this.taxRate,
    required this.taxAmount,
    required this.total,
    required this.paidAmount,
    required this.changeAmount,
    this.note,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
    this.payments = const [],
  });

  double get due => (total - paidAmount) < 0 ? 0 : (total - paidAmount);

  /// `SO-000123` — same zero-padded id format desktop's SalesOrderList.tsx
  /// uses for this sale in lists/detail views.
  String get displayNo => 'SO-${id.toString().padLeft(6, '0')}';

  /// Receipt / invoice number — the same `SO-000123` as [displayNo], as
  /// desktop's PosReceipt.tsx prints it.
  String get invoiceNo => displayNo;

  factory SalesOrder.fromJson(Map json) {
    final client = json['client'] as Map?;
    return SalesOrder(
      id: toNum(json['id']),
      status: (json['status'] ?? 'DRAFT').toString(),
      clientId: toIntOrNull(json['client_id']),
      clientName: toStringOrNull(client?['name']),
      clientPhone: toStringOrNull(client?['phone']),
      subtotal: toDouble(json['subtotal']),
      discountType: toStringOrNull(json['discount_type']),
      discountValue: toDouble(json['discount_value']),
      discountAmount: toDouble(json['discount_amount']),
      taxRate: toDouble(json['tax_rate']),
      taxAmount: toDouble(json['tax_amount']),
      total: toDouble(json['total']),
      paidAmount: toDouble(json['paid_amount']),
      changeAmount: toDouble(json['change_amount']),
      note: toStringOrNull(json['note']),
      completedAt: toStringOrNull(json['completed_at']),
      createdAt: (json['created_at'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? '').toString(),
      items: ((json['items'] as List?) ?? const []).map((i) => SalesOrderItem.fromJson((i as Map).cast<String, dynamic>())).toList(),
      payments: ((json['payments'] as List?) ?? const []).map((p) => OrderPayment.fromJson((p as Map).cast<String, dynamic>())).toList(),
    );
  }
}
