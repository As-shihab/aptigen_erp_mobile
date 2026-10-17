import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/network/http_client.dart';
import '../../../core/storage/app_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../store/data/store_util.dart';

class _InvoiceItem {
  final String name;
  final double price;
  final double quantity;
  _InvoiceItem({required this.name, required this.price, required this.quantity});

  factory _InvoiceItem.fromJson(Map json) => _InvoiceItem(
        name: (json['name'] ?? '').toString(),
        price: toDouble(json['price']),
        quantity: toDouble(json['quantity']),
      );
}

/// One row from `module_purchase_invoices` — mirrors desktop's
/// `ProfileInvoices.tsx` `InvoiceRow`. Created `pending` by the Market
/// install flow; only a platform admin flips one to `paid`. Read-only here,
/// same as desktop — this screen is a statement of account with a printable
/// copy per row.
class _InvoiceRow {
  final int id;
  final String? invoiceNo;
  final double subtotal;
  final double total;
  final String currency;
  final String paymentMethod;
  final String status;
  final String? transactionRef;
  final String? paidAt;
  final String createdAt;
  final List<_InvoiceItem> items;

  _InvoiceRow({
    required this.id,
    required this.invoiceNo,
    required this.subtotal,
    required this.total,
    required this.currency,
    required this.paymentMethod,
    required this.status,
    required this.transactionRef,
    required this.paidAt,
    required this.createdAt,
    required this.items,
  });

  factory _InvoiceRow.fromJson(Map json) => _InvoiceRow(
        id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
        invoiceNo: toStringOrNull(json['invoice_no']),
        subtotal: toDouble(json['subtotal']),
        total: toDouble(json['total']),
        currency: (json['currency'] ?? '').toString(),
        paymentMethod: (json['payment_method'] ?? '').toString(),
        status: (json['status'] ?? '').toString(),
        transactionRef: toStringOrNull(json['transaction_ref']),
        paidAt: toStringOrNull(json['paid_at']),
        createdAt: (json['created_at'] ?? '').toString(),
        items: (json['items'] is List ? json['items'] as List : const []).cast<Map>().map(_InvoiceItem.fromJson).toList(),
      );
}

Color _statusColor(String status) => switch (status) {
      'paid' => AppColors.success,
      'pending' => AppColors.warning,
      _ => AppColors.error,
    };

String _money(num value, String currency) => '$currency ${value.toStringAsFixed(2)}';

Future<String> _resolveWorkplaceName() async {
  final user = await AppStorage.getUser();
  final workplace = (user?['selectedWorkplace'] ?? user?['workplace']) as Map?;
  final name = (workplace?['name'] ?? '').toString().trim();
  return name.isEmpty ? 'Aptigen' : name;
}

/// Module purchase invoices for this workplace — read-only list mirroring
/// desktop's `ProfileInvoices.tsx`, with a per-row PDF export via
/// `package:printing` (desktop opens a print popup instead; mobile hands
/// the same document to the platform's native print/share sheet).
class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  final _client = ApiClient();
  bool _loading = true;
  List<_InvoiceRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _client.get('module_purchase_invoices?\$expand=items&\$orderby=id desc');
      final rows = unwrapList(res).cast<Map>().map(_InvoiceRow.fromJson).toList();
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _rows = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportPdf(_InvoiceRow row) async {
    final workplaceName = await _resolveWorkplaceName();
    final bytes = await _buildInvoicePdf(row, workplaceName: workplaceName);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: row.invoiceNo ?? 'Invoice #${row.id}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : RefreshIndicator(
              onRefresh: _load,
              child: _rows.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 100),
                        Icon(Icons.receipt_long_outlined, size: 40, color: AppColors.slate400),
                        const SizedBox(height: 12),
                        Center(child: Text('No invoices yet.', style: TextStyle(color: AppColors.slate600))),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.slate400.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(row.invoiceNo ?? '#${row.id}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _statusColor(row.status).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            row.status,
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _statusColor(row.status)),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text('${row.items.length} module${row.items.length == 1 ? '' : 's'} · ${row.paymentMethod}',
                                        style: TextStyle(fontSize: 11, color: AppColors.slate600)),
                                    const SizedBox(height: 3),
                                    Text(displayDate(row.createdAt), style: TextStyle(fontSize: 11, color: AppColors.slate400)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(_money(row.total, row.currency), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                  IconButton(
                                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                                    onPressed: () => _exportPdf(row),
                                    color: AppColors.brand,
                                    tooltip: 'Export PDF',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

Future<Uint8List> _buildInvoicePdf(_InvoiceRow row, {required String workplaceName}) async {
  final doc = pw.Document();
  String money(num v) => _money(v, row.currency);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(workplaceName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Module Purchase Invoice', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(row.invoiceNo ?? '#${row.id}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text(_formatDateTime(row.createdAt), style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    pw.Text(
                      row.status.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: row.status == 'paid' ? PdfColors.green700 : PdfColors.orange700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.SizedBox(height: 8),
            pw.Table(
              border: null,
              columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1)},
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400))),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6), child: pw.Text('Module', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                    pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6), child: pw.Text('Months', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.center)),
                    pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6), child: pw.Text('Price', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.right)),
                    pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6), child: pw.Text('Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.right)),
                  ],
                ),
                ...row.items.map(
                  (item) => pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: pw.Text(item.name, style: const pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: pw.Text('${item.quantity}', style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: pw.Text(money(item.price), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right)),
                      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: pw.Text(money(item.price * item.quantity), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.SizedBox(
                width: 220,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    _totalsRow('Subtotal', money(row.subtotal)),
                    _totalsRow('Total', money(row.total), bold: true),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text('Payment method: ${row.paymentMethod}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            if (row.transactionRef != null) pw.Text('Transaction ref: ${row.transactionRef}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            if (row.paidAt != null) pw.Text('Paid at: ${_formatDateTime(row.paidAt!)}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          ],
        );
      },
    ),
  );

  return doc.save();
}

pw.Widget _totalsRow(String label, String value, {bool bold = false}) {
  final style = pw.TextStyle(fontSize: bold ? 13 : 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(label, style: style), pw.Text(value, style: style)]),
  );
}

String _formatDateTime(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  final local = date.toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${p(local.month)}-${p(local.day)} ${p(local.hour)}:${p(local.minute)}';
}
