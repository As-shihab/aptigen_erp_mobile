import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/utils/currency.dart';
import '../../../auth/data/auth_service.dart';
import '../../../settings/data/printer_devices_service.dart';
import '../../../store/data/store_util.dart';
import '../../data/invoice_escpos_bytes.dart';
import '../../data/invoice_pdf_builder.dart';
import '../../data/pos_printer_service.dart';
import '../../data/sales_order_model.dart';
import '../widgets/sell_ui.dart' show MarketPalette, MarketCard, StatusPill, FadeSlideIn, marketToast, saleStatusLabel, saleStatusTone;

/// Sends a sale's receipt as raw ESC/POS bytes to the default Bluetooth
/// printer (Settings > Printers). Returns an error message, or null when
/// it was sent.
Future<String?> printSaleReceiptToBluetooth(SalesOrder sale, {String? receiptFooter, String? workplaceName}) async {
  try {
    var name = workplaceName;
    if (name == null || name.trim().isEmpty) {
      final user = await AuthService(ApiClient()).getStoredUser();
      name = (user?.workplaceName.trim().isNotEmpty ?? false) ? user!.workplaceName.trim() : '';
    }
    final device = await PrinterDevicesService().getDefault();
    if (device?.macAddress == null) return 'No printer configured. Add one in Settings > Printers.';
    final bytes = buildInvoiceEscPosBytes(sale, workplaceName: name, receiptFooter: receiptFooter, lineWidth: device!.lineWidth, fullCut: device.fullCut);
    await PosPrinterService().printBytes(bytes, macAddress: device.macAddress!);
    return null;
  } catch (error) {
    return error.toString().replaceFirst('Exception: ', '');
  }
}

/// Post-checkout receipt — same field set and layout idea as desktop's
/// `PosReceipt.tsx` (workplace name header, `SO-000123` sales order number,
/// itemized qty×price lines, totals block, receipt-footer text). The
/// download icon hands a generated PDF to the platform's print dialog
/// (save as PDF or any system printer); the bottom print button sends raw
/// ESC/POS bytes to the paired Bluetooth thermal printer. With
/// [autoPrint] the Bluetooth print starts as soon as the page opens.
class PosReceiptPage extends StatefulWidget {
  final SalesOrder sale;
  final String? receiptFooter;
  final bool autoPrint;
  const PosReceiptPage({super.key, required this.sale, this.receiptFooter, this.autoPrint = false});

  @override
  State<PosReceiptPage> createState() => _PosReceiptPageState();
}

class _PosReceiptPageState extends State<PosReceiptPage> {
  String _workplaceName = '';
  bool _thermalPrinting = false;

  @override
  void initState() {
    super.initState();
    _loadWorkplaceName();
    if (widget.autoPrint) WidgetsBinding.instance.addPostFrameCallback((_) => _printThermal());
  }

  Future<void> _loadWorkplaceName() async {
    final user = await AuthService(ApiClient()).getStoredUser();
    if (!mounted || user == null) return;
    final name = user.workplaceName.trim();
    if (name.isNotEmpty) setState(() => _workplaceName = name);
  }

  Future<void> _download() async {
    final bytes = await buildInvoicePdf(widget.sale, workplaceName: _workplaceName, receiptFooter: widget.receiptFooter);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: widget.sale.invoiceNo);
  }

  Future<void> _printThermal() async {
    if (_thermalPrinting) return;
    setState(() => _thermalPrinting = true);
    final error = await printSaleReceiptToBluetooth(widget.sale, receiptFooter: widget.receiptFooter, workplaceName: _workplaceName);
    if (!mounted) return;
    setState(() => _thermalPrinting = false);
    marketToast(context, error ?? 'Sent to printer.', error: error != null);
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final sale = widget.sale;
    final completed = sale.status == 'COMPLETED';
    final tone = p.tone(saleStatusTone(sale.status));
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.card,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: p.line)),
        title: Text('Invoice', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.download_outlined), tooltip: 'Download receipt', onPressed: _download),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: [
          // Success header
          FadeSlideIn(
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(color: completed ? p.okBg : tone.bg, shape: BoxShape.circle),
                  child: Icon(completed ? Icons.check_rounded : Icons.info_outline, size: 36, color: completed ? p.ok : tone.fg),
                ),
                const SizedBox(height: 12),
                Text(completed ? 'Sale completed' : 'Sale saved', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
                const SizedBox(height: 4),
                Text(formatMoney(sale.total), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: p.text, height: 1.15)),
                const SizedBox(height: 4),
                Text(
                  'Paid ${formatMoney(sale.paidAmount)}${sale.changeAmount > 0 ? ' · change ${formatMoney(sale.changeAmount)}' : ''}${sale.due > 0 ? ' · due ${formatMoney(sale.due)}' : ''}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: p.label),
                ),
                if (!completed) ...[
                  const SizedBox(height: 8),
                  StatusPill(saleStatusLabel(sale.status), tone: saleStatusTone(sale.status)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          // Receipt card
          FadeSlideIn(
            index: 1,
            child: MarketCard(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                children: [
                  Text(_workplaceName, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: p.text)),
                  const SizedBox(height: 3),
                  Text('Sales order ${sale.invoiceNo}', style: TextStyle(color: p.label, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(displayDate(sale.completedAt ?? sale.createdAt), style: TextStyle(color: p.label, fontSize: 11.5)),
                  const SizedBox(height: 14),
                  const _DashedDivider(),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 15, color: p.label),
                      const SizedBox(width: 6),
                      Text('Customer', style: TextStyle(fontSize: 12.5, color: p.label)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(sale.clientName ?? 'Walk-in customer',
                            textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: p.text)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const _DashedDivider(),
                  const SizedBox(height: 6),
                  ...sale.items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: p.text)),
                                  const SizedBox(height: 1),
                                  Text('${item.quantity} × ${formatMoney(item.unitPrice)}', style: TextStyle(fontSize: 11.5, color: p.label)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(formatMoney(item.lineTotal), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.text)),
                          ],
                        ),
                      )),
                  const SizedBox(height: 6),
                  const _DashedDivider(),
                  const SizedBox(height: 8),
                  _row(p, 'Subtotal', formatMoney(sale.subtotal)),
                  if (sale.discountAmount > 0) _row(p, 'Discount', '-${formatMoney(sale.discountAmount)}', color: p.error),
                  if (sale.taxAmount > 0) _row(p, 'Tax', formatMoney(sale.taxAmount)),
                  const SizedBox(height: 6),
                  const _DashedDivider(),
                  const SizedBox(height: 6),
                  _row(p, 'Total', formatMoney(sale.total), bold: true),
                  _row(p, 'Paid', formatMoney(sale.paidAmount)),
                  if (sale.changeAmount > 0) _row(p, 'Change', formatMoney(sale.changeAmount), color: p.ok),
                  if (sale.due > 0) _row(p, 'Due', formatMoney(sale.due), color: p.error),
                  if ((widget.receiptFooter ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const _DashedDivider(),
                    const SizedBox(height: 10),
                    Text(widget.receiptFooter!, textAlign: TextAlign.center, style: TextStyle(color: p.label, fontSize: 12, height: 1.4)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _thermalPrinting ? null : _printThermal,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.text,
                        side: BorderSide(color: p.line),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _thermalPrinting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.print_outlined, size: 18),
                      label: const Text('Print'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.brand,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Done', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(MarketPalette p, String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontSize: bold ? 15.5 : 13, color: bold ? p.text : p.label)),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w600, fontSize: bold ? 16 : 13, color: color ?? p.text)),
        ],
      ),
    );
  }
}

/// A thin dashed rule — evokes the perforated look of a thermal receipt
/// without needing an image asset or CustomPainter.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    final color = MarketPalette.of(context).line;
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 5.0;
        const gap = 4.0;
        final count = (constraints.maxWidth / (dashWidth + gap)).floor();
        return Row(
          children: List.generate(count, (_) => Padding(
                padding: const EdgeInsets.only(right: gap),
                child: Container(width: dashWidth, height: 1, color: color),
              )),
        );
      },
    );
  }
}
