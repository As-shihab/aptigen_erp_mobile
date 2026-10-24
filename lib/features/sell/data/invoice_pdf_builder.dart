import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/utils/currency.dart';
import 'sales_order_model.dart';

/// Builds a printable invoice PDF for one sale — the mobile counterpart to
/// desktop's `PosReceipt.tsx` `buildReceiptHtml()`/`printReceipt()`, just
/// handed to the platform's native print dialog (via `package:printing`)
/// instead of desktop's Electron silent-print/browser-print split. Same
/// field set: workplace name, `SO-000123` sales order number, itemized lines,
/// totals, payments, receipt-footer text. Amounts use `formatMoneyAscii()`
/// (see core/utils/currency.dart) rather than `formatMoney()` — the default
/// PDF font has no bundled Unicode glyphs for non-Latin currency signs.
String _pdfMoney(num value) => formatMoneyAscii(value);

Future<Uint8List> buildInvoicePdf(SalesOrder sale, {required String workplaceName, String? receiptFooter}) async {
  final doc = pw.Document();
  const pageFormat = PdfPageFormat(58 * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm);

  doc.addPage(
    pw.Page(
      pageFormat: pageFormat,
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(child: pw.Text(workplaceName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
            pw.SizedBox(height: 2),
            pw.Center(child: pw.Text('Sales order ${sale.invoiceNo}', style: const pw.TextStyle(fontSize: 9))),
            if (sale.status != 'COMPLETED')
              pw.Center(child: pw.Text('*** ${sale.status} ***', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
            pw.Center(child: pw.Text(_formatDate(sale.completedAt ?? sale.createdAt), style: const pw.TextStyle(fontSize: 8))),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5),
            pw.Text(sale.clientName ?? 'Walk-in customer', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 4),
            ...sale.items.map(
              (item) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(item.name, style: const pw.TextStyle(fontSize: 9)),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('${item.quantity} x ${_pdfMoney(item.unitPrice)}', style: const pw.TextStyle(fontSize: 8)),
                        pw.Text(_pdfMoney(item.lineTotal), style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 0.5),
            _totalsRow('Subtotal', _pdfMoney(sale.subtotal)),
            if (sale.discountAmount > 0) _totalsRow('Discount', '-${_pdfMoney(sale.discountAmount)}'),
            if (sale.taxAmount > 0) _totalsRow('Tax', _pdfMoney(sale.taxAmount)),
            pw.Divider(thickness: 0.5),
            _totalsRow('Total', _pdfMoney(sale.total), bold: true),
            _totalsRow('Paid', _pdfMoney(sale.paidAmount)),
            if (sale.changeAmount > 0) _totalsRow('Change', _pdfMoney(sale.changeAmount)),
            if (sale.due > 0) _totalsRow('Due', _pdfMoney(sale.due)),
            if (sale.payments.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.5),
              pw.Text('Payments', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
              ...sale.payments.map((p) => _totalsRow(p.method, _pdfMoney(p.amount))),
            ],
            if ((receiptFooter ?? '').isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 0.5),
              pw.Center(child: pw.Text(receiptFooter!, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8))),
            ],
          ],
        );
      },
    ),
  );

  return doc.save();
}

pw.Widget _totalsRow(String label, String value, {bool bold = false}) {
  final style = pw.TextStyle(fontSize: bold ? 10 : 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [pw.Text(label, style: style), pw.Text(value, style: style)],
    ),
  );
}

String _formatDate(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  final local = date.toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${p(local.month)}-${p(local.day)} ${p(local.hour)}:${p(local.minute)}';
}
