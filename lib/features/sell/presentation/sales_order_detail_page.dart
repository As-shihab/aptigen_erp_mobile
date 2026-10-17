import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../core/network/http_client.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/models/user_model.dart';
import '../data/invoice_escpos_bytes.dart';
import '../data/invoice_pdf_builder.dart';
import '../data/order_settings_service.dart';
import '../data/pos_printer_service.dart';
import '../data/pos_service.dart';
import '../data/sales_order_model.dart';
import '../data/sales_order_service.dart';
import '../../settings/data/printer_devices_service.dart';
import 'widgets/sell_ui.dart';

const _methodLabels = {'CASH': 'Cash', 'CARD': 'Card', 'MOBILE_BANKING': 'Mobile banking'};

IconData _methodIcon(String method) => switch (method) {
      'CASH' => Icons.payments_outlined,
      'CARD' => Icons.credit_card,
      'MOBILE_BANKING' => Icons.phone_iphone,
      _ => Icons.account_balance_wallet_outlined,
    };

/// Read-only sale detail — header/lines/payments/totals, mirrors desktop's
/// SalesOrderForm.tsx (which despite its name is a read-only detail dialog,
/// not a create/edit form; sales are only ever created via POS checkout).
/// Void is the only mutating action, only offered when `status ==
/// 'COMPLETED'` — same guard as desktop and pos.service.ts.
class SalesOrderDetailPage extends StatefulWidget {
  final int saleId;
  const SalesOrderDetailPage({super.key, required this.saleId});

  @override
  State<SalesOrderDetailPage> createState() => _SalesOrderDetailPageState();
}

class _SalesOrderDetailPageState extends State<SalesOrderDetailPage> {
  final _client = ApiClient();
  late final _orderService = SalesOrderService(_client);
  late final _posService = PosService(_client);

  final _printerService = PosPrinterService();
  bool _loading = true;
  bool _voiding = false;
  bool _thermalPrinting = false;
  SalesOrder? _sale;
  String _workplaceName = 'Aptigen POS';
  String? _receiptFooter;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPrintContext();
  }

  Future<void> _loadPrintContext() async {
    final results = await Future.wait([
      AuthService(_client).getStoredUser(),
      OrderSettingsService(_client).load(),
    ]);
    if (!mounted) return;
    final user = results[0] as UserModel?;
    final settings = results[1] as OrderSettings;
    setState(() {
      final name = user?.companyName.trim();
      if (name != null && name.isNotEmpty) _workplaceName = name;
      _receiptFooter = settings.receiptFooter;
    });
  }

  Future<void> _print() async {
    final sale = _sale;
    if (sale == null) return;
    final bytes = await buildInvoicePdf(sale, workplaceName: _workplaceName, receiptFooter: _receiptFooter);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: sale.invoiceNo);
  }

  Future<void> _printThermal() async {
    final sale = _sale;
    if (sale == null) return;
    setState(() => _thermalPrinting = true);
    try {
      final device = await PrinterDevicesService().getDefault();
      if (device?.macAddress == null) {
        if (!mounted) return;
        marketToast(context, 'No printer configured. Add one in Settings > Printers.', error: true);
        return;
      }
      final bytes = buildInvoiceEscPosBytes(sale, workplaceName: _workplaceName, receiptFooter: _receiptFooter, lineWidth: device!.lineWidth, fullCut: device.fullCut);
      await _printerService.printBytes(bytes, macAddress: device.macAddress!);
      if (!mounted) return;
      marketToast(context, 'Sent to thermal printer.');
    } catch (error) {
      if (!mounted) return;
      marketToast(context, error.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _thermalPrinting = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sale = await _orderService.loadDetail(widget.saleId);
      if (!mounted) return;
      setState(() => _sale = sale);
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Could not load this sale.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _void() async {
    final confirmed = await confirmMarket(
      context,
      title: 'Void this sale?',
      message: 'Stock will be restored and the sale marked as refunded. Payments already recorded are not reversed.',
      confirm: 'Void sale',
    );
    if (!confirmed || !mounted) return;
    setState(() => _voiding = true);
    try {
      final updated = await _posService.voidSale(widget.saleId);
      if (!mounted) return;
      setState(() => _sale = updated);
      marketToast(context, 'Sale voided — stock restored');
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Could not void this sale.', error: true);
    } finally {
      if (mounted) setState(() => _voiding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final sale = _sale;
    return MarketScaffold(
      title: sale?.displayNo ?? 'Sale',
      subtitle: sale == null ? (_loading ? 'Loading…' : null) : saleStatusLabel(sale.status),
      bottom: sale == null ? null : _actionBar(p, sale),
      body: _body(p, sale),
    );
  }

  Widget _body(MarketPalette p, SalesOrder? sale) {
    if (_loading && sale == null) {
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: const [
          SkeletonBox(height: 150, radius: 12),
          SizedBox(height: 18),
          SkeletonBox(height: 16, width: 90),
          SizedBox(height: 10),
          SkeletonBox(height: 64, radius: 12),
          SizedBox(height: 8),
          SkeletonBox(height: 64, radius: 12),
          SizedBox(height: 18),
          SkeletonBox(height: 160, radius: 12),
        ],
      );
    }
    if (sale == null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          MarketEmpty(
            icon: Icons.receipt_long_outlined,
            title: 'Sale not found',
            message: 'It may have been removed, or the connection dropped.',
            actionLabel: 'Try again',
            onAction: _load,
          ),
        ]),
      );
    }

    var section = 0;
    Widget block(Widget child) => FadeSlideIn(index: section++, child: child);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          block(_header(p, sale)),
          block(SectionHeader('Items', subtitle: '${sale.items.length} ${sale.items.length == 1 ? 'line' : 'lines'}')),
          if (sale.items.isEmpty)
            block(MarketCard(child: Text('No items on this sale.', style: TextStyle(fontSize: 13, color: p.label))))
          else
            for (final item in sale.items)
              block(Padding(padding: const EdgeInsets.only(bottom: 8), child: _itemCard(p, item))),
          block(const SectionHeader('Totals')),
          block(_totals(p, sale)),
          if (sale.payments.isNotEmpty) ...[
            block(SectionHeader('Payments', subtitle: '${sale.payments.length} recorded')),
            block(_payments(p, sale)),
          ],
          if ((sale.note ?? '').isNotEmpty) ...[
            block(const SectionHeader('Note')),
            block(MarketCard(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.sticky_note_2_outlined, size: 18, color: p.label),
                const SizedBox(width: 10),
                Expanded(child: Text(sale.note!, style: TextStyle(fontSize: 13.5, color: p.text, height: 1.4))),
              ]),
            )),
          ],
        ],
      ),
    );
  }

  Widget _header(MarketPalette p, SalesOrder sale) {
    final tone = saleStatusTone(sale.status);
    return MarketCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              '${sale.displayNo} · ${sale.invoiceNo}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.label),
            ),
          ),
          StatusPill(saleStatusLabel(sale.status), tone: tone),
        ]),
        const SizedBox(height: 10),
        CountUp(
          value: sale.total,
          format: (v) => money(v),
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: p.text, height: 1.1),
        ),
        if (sale.status == 'COMPLETED' && sale.due > 0) ...[
          const SizedBox(height: 8),
          StatusPill('Due ${money(sale.due)}', tone: MarketTone.warn, icon: Icons.schedule),
        ],
        const SizedBox(height: 14),
        Divider(height: 1, color: p.line),
        const SizedBox(height: 12),
        _headerFact(p, sale.clientName == null ? Icons.person_outline : Icons.person, sale.clientName ?? 'Walk-in customer', sale.clientPhone),
        const SizedBox(height: 8),
        _headerFact(p, Icons.event_outlined, dateTimeLabel(sale.completedAt ?? sale.createdAt), null),
      ]),
    );
  }

  Widget _headerFact(MarketPalette p, IconData icon, String text, String? sub) => Row(children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: p.label),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: text, style: TextStyle(fontWeight: FontWeight.w600, color: p.text)),
              if (sub != null) TextSpan(text: '  ·  $sub', style: TextStyle(color: p.label)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
      ]);

  Widget _itemCard(MarketPalette p, SalesOrderItem item) => MarketCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Text('${item.quantity}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.brand)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
              const SizedBox(height: 2),
              Text('${item.quantity} × ${money(item.unitPrice)}', style: TextStyle(fontSize: 11.5, color: p.label)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(money(item.lineTotal), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
            if (item.discountAmount > 0) ...[
              const SizedBox(height: 4),
              StatusPill('− ${money(item.discountAmount)} off', tone: MarketTone.error),
            ],
          ]),
        ]),
      );

  Widget _totals(MarketPalette p, SalesOrder sale) {
    final dueTone = p.tone(MarketTone.warn);
    return MarketCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(children: [
        InfoRow('Subtotal', money(sale.subtotal)),
        if (sale.discountAmount > 0) InfoRow('Discount', '− ${money(sale.discountAmount)}'),
        if (sale.taxAmount > 0) InfoRow('Tax (${sale.taxRate.toStringAsFixed(1)}%)', money(sale.taxAmount)),
        Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Divider(height: 1, color: p.line)),
        InfoRow('Total', money(sale.total), emphasize: true),
        InfoRow('Paid', money(sale.paidAmount)),
        if (sale.changeAmount > 0) InfoRow('Change', money(sale.changeAmount)),
        if (sale.due > 0)
          Container(
            margin: const EdgeInsets.only(top: 6, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: dueTone.bg, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.schedule, size: 16, color: dueTone.fg),
              const SizedBox(width: 8),
              Expanded(child: Text('Due', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dueTone.fg))),
              Text(money(sale.due), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: dueTone.fg)),
            ]),
          ),
      ]),
    );
  }

  Widget _payments(MarketPalette p, SalesOrder sale) => MarketCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < sale.payments.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 58, color: p.line),
            _paymentRow(p, sale.payments[i]),
          ],
        ]),
      );

  Widget _paymentRow(MarketPalette p, OrderPayment pay) => Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: p.okBg, borderRadius: BorderRadius.circular(9)),
            child: Icon(_methodIcon(pay.method), size: 17, color: p.ok),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_methodLabels[pay.method] ?? (pay.method.isEmpty ? '—' : pay.method[0] + pay.method.substring(1).toLowerCase().replaceAll('_', ' ')), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
              const SizedBox(height: 2),
              Text(
                [if ((pay.reference ?? '').isNotEmpty) pay.reference!, dateTimeLabel(pay.createdAt)].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: p.label),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Text(money(pay.amount), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
        ]),
      );

  Widget _actionBar(MarketPalette p, SalesOrder sale) {
    final canVoid = sale.status == 'COMPLETED';
    const spinner = SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    final secondary = OutlinedButton.styleFrom(
      foregroundColor: p.text,
      side: BorderSide(color: p.line),
      minimumSize: const Size(0, 46),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      shape: shape,
    );
    return Container(
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: secondary,
                onPressed: _print,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Print PDF', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: secondary,
                onPressed: _thermalPrinting ? null : _printThermal,
                icon: _thermalPrinting ? spinner : const Icon(Icons.print_outlined, size: 18),
                label: const Text('Thermal', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            if (canVoid) ...[
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: p.error,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 46),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: shape,
                  ),
                  onPressed: _voiding ? null : _void,
                  icon: _voiding ? spinner : const Icon(Icons.undo, size: 18),
                  label: Text(_voiding ? 'Voiding…' : 'Void', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
