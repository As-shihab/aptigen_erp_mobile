import '../../../core/utils/currency.dart';
import 'esc_pos_builder.dart';
import 'sales_order_model.dart';

/// Builds the raw ESC/POS byte sequence for one sale's receipt, printed
/// directly to a paired Bluetooth thermal printer (`PosPrinterService`) —
/// same content as `invoice_pdf_builder.dart`'s PDF (workplace name header,
/// `SO-000123` sales order number, itemized lines, totals, payments, receipt
/// footer), just as literal printer commands instead of a page description.
/// [lineWidth] and [fullCut] come from the configured `PrinterDevice`
/// (`features/settings/data/printer_device.dart`) — 32 chars/58mm or 48
/// chars/80mm, full vs partial cut.
List<int> buildInvoiceEscPosBytes(
  SalesOrder sale, {
  required String workplaceName,
  String? receiptFooter,
  int lineWidth = 32,
  bool fullCut = false,
}) {
  final b = EscPosBuilder()..initialize();

  b.alignCenter();
  b.textSize(width: 2, height: 2);
  b.boldOn();
  b.line(workplaceName);
  b.boldOff();
  b.textSize();
  b.line('Sales order ${sale.invoiceNo}');
  if (sale.status != 'COMPLETED') {
    b.boldOn();
    b.line('*** ${sale.status} ***');
    b.boldOff();
  }
  b.line(_formatDate(sale.completedAt ?? sale.createdAt));
  b.line('-' * lineWidth);

  b.alignLeft();
  b.boldOn();
  b.line(sale.clientName ?? 'Walk-in customer');
  b.boldOff();
  b.line('-' * lineWidth);

  for (final item in sale.items) {
    b.line(item.name);
    b.row('${item.quantity} x ${formatMoneyAscii(item.unitPrice)}', formatMoneyAscii(item.lineTotal), width: lineWidth);
  }
  b.line('-' * lineWidth);

  b.row('Subtotal', formatMoneyAscii(sale.subtotal), width: lineWidth);
  if (sale.discountAmount > 0) b.row('Discount', '-${formatMoneyAscii(sale.discountAmount)}', width: lineWidth);
  if (sale.taxAmount > 0) b.row('Tax', formatMoneyAscii(sale.taxAmount), width: lineWidth);
  b.line('-' * lineWidth);

  b.boldOn();
  b.row('Total', formatMoneyAscii(sale.total), width: lineWidth);
  b.boldOff();
  b.row('Paid', formatMoneyAscii(sale.paidAmount), width: lineWidth);
  if (sale.changeAmount > 0) b.row('Change', formatMoneyAscii(sale.changeAmount), width: lineWidth);
  if (sale.due > 0) b.row('Due', formatMoneyAscii(sale.due), width: lineWidth);

  if (sale.payments.isNotEmpty) {
    b.line('-' * lineWidth);
    for (final payment in sale.payments) {
      b.row(payment.method, formatMoneyAscii(payment.amount), width: lineWidth);
    }
  }

  if ((receiptFooter ?? '').isNotEmpty) {
    b.line('-' * lineWidth);
    b.alignCenter();
    b.line(receiptFooter!);
  }

  b.feedPaper(3);
  b.cut(full: fullCut);
  return b.build();
}

String _formatDate(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  final local = date.toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${p(local.month)}-${p(local.day)} ${p(local.hour)}:${p(local.minute)}';
}
