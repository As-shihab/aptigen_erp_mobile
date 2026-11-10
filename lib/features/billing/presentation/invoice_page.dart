import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/billing/paywall_state.dart';
import '../../../core/network/http_client.dart';
import '../../sell/market/presentation/widgets/market_ui.dart';

/// Aptigen billing / support line, printed on every invoice.
const _supportPhone = '01516514719';

/// A workplace's module invoice (module_purchase_invoices) — mobile port of
/// erp/desktop's `InvoiceViewerDialog`: the invoice, "Save as PDF" (Aptigen
/// logo, items, totals, how to pay) and a three-step "how to pay" guide that
/// ends with sending the transaction id for an admin to approve.
Future<void> openInvoicePage(BuildContext context, int invoiceId) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoicePage(invoiceId: invoiceId)));
}

class InvoicePage extends StatefulWidget {
  final int invoiceId;
  const InvoicePage({super.key, required this.invoiceId});

  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  final _client = ApiClient();
  final _txn = TextEditingController();
  Map<String, dynamic>? _invoice;
  List<Map<String, dynamic>> _accounts = [];
  bool _failed = false;
  int _step = 0;
  int? _accountId;
  bool _saving = false;
  bool _pdfBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _txn.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final res = await _client.batch([
        BatchRequest(id: '1', method: 'GET', url: 'module_purchase_invoices?\$filter=id eq ${widget.invoiceId}&\$expand=items,workplace&\$top=1'),
        BatchRequest(id: '2', method: 'GET', url: 'payment_accounts?\$filter=is_active eq true&\$orderby=sort_order asc&\$top=50'),
      ]);
      final responses = res is Map ? (res['responses'] as List? ?? const []) : const [];
      List<Map<String, dynamic>> rows(int i) {
        final body = i < responses.length && responses[i] is Map ? responses[i]['body'] : null;
        return unwrapList(body).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      }

      final inv = rows(0).isNotEmpty ? rows(0).first : null;
      if (!mounted) return;
      if (inv == null) {
        setState(() => _failed = true);
        return;
      }
      setState(() {
        _invoice = inv;
        _accounts = rows(1);
        _accountId = int.tryParse('${inv['payment_account_id'] ?? ''}');
        _txn.text = '${inv['transaction_ref'] ?? ''}';
        if (_txn.text.isNotEmpty) _step = 2;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  String get _ref {
    final no = '${_invoice?['invoice_no'] ?? ''}';
    return no.isNotEmpty ? no : '#${widget.invoiceId}';
  }

  double get _total => toDouble(_invoice?['total']);
  String get _status => '${_invoice?['status'] ?? 'pending'}';
  Map<String, dynamic>? get _account => _accounts.where((a) => a['id'] == _accountId).firstOrNull;

  String _taka(num v) => '৳${NumberFormat('#,##0.00').format(v)}';
  String _day(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? '-' : DateFormat('d MMM y').format(d.toLocal());
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) marketToast(context, '$label copied');
  }

  Future<void> _call() => launchUrl(Uri(scheme: 'tel', path: _supportPhone));

  Future<void> _submit() async {
    final account = _account;
    final txn = _txn.text.trim();
    if (account == null || txn.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await _client.put('module_purchase_invoices', widget.invoiceId, {
        'transaction_ref': txn,
        'payment_account_id': account['id'],
        'payment_method': account['method_type'],
      });
      PaywallState.load(_client);
      if (!mounted) return;
      setState(() {
        _invoice = {...?_invoice, 'transaction_ref': txn, 'payment_account_id': account['id']};
        _saving = false;
      });
      marketToast(context, 'Payment sent for review. The module unlocks once it\'s confirmed.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      marketToast(context, 'Could not send the transaction id. Try again.', error: true);
    }
  }

  // ── PDF ────────────────────────────────────────────────────────────────
  // ASCII money (BDT 1,200.00) — the built-in PDF font has no ৳ glyph.
  String _bdt(num v) => 'BDT ${NumberFormat('#,##0.00').format(v)}';

  Future<void> _savePdf() async {
    final inv = _invoice;
    if (inv == null || _pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      pw.MemoryImage? logo;
      try {
        logo = pw.MemoryImage((await rootBundle.load('assets/icon/app_logo.png')).buffer.asUint8List());
      } catch (_) {}
      final brand = PdfColor.fromInt(0xFF0A6ED1);
      final grey = PdfColor.fromInt(0xFF556B82);
      final paid = _status == 'paid';
      final items = (inv['items'] as List? ?? const []).whereType<Map>().toList();
      final wp = inv['workplace'] is Map ? inv['workplace'] as Map : const {};
      final statusLabel = paid ? 'Paid' : _status == 'rejected' ? 'Rejected' : 'Awaiting payment';

      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            if (logo != null) pw.Image(logo, height: 36),
            if (logo != null) pw.SizedBox(width: 8),
            pw.Text('Aptigen', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Spacer(),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('Invoice', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.Text(_ref, style: pw.TextStyle(color: grey)),
              pw.SizedBox(height: 4),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: paid ? PdfColors.green700 : PdfColors.orange700), borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Text(statusLabel, style: pw.TextStyle(fontSize: 9, color: paid ? PdfColors.green700 : PdfColors.orange700)),
              ),
            ]),
          ]),
          pw.SizedBox(height: 24),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Billed to', style: pw.TextStyle(fontSize: 9, color: grey)),
              pw.Text('${wp['name'] ?? 'Your workplace'}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              if ('${wp['phone'] ?? ''}'.isNotEmpty) pw.Text('${wp['phone']}', style: pw.TextStyle(color: grey)),
              if ('${wp['email'] ?? ''}'.isNotEmpty) pw.Text('${wp['email']}', style: pw.TextStyle(color: grey)),
              if ('${wp['address'] ?? ''}'.isNotEmpty) pw.Text('${wp['address']}', style: pw.TextStyle(color: grey)),
            ])),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('Issued', style: pw.TextStyle(fontSize: 9, color: grey)),
              pw.Text(_day(inv['created_at'])),
              if (paid) ...[pw.SizedBox(height: 6), pw.Text('Paid', style: pw.TextStyle(fontSize: 9, color: grey)), pw.Text(_day(inv['paid_at']))],
              if ('${inv['transaction_ref'] ?? ''}'.isNotEmpty) ...[
                pw.SizedBox(height: 6),
                pw.Text('Transaction id', style: pw.TextStyle(fontSize: 9, color: grey)),
                pw.Text('${inv['transaction_ref']}'),
              ],
            ]),
          ]),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['Module', 'Months', 'Price per month', 'Amount'],
            data: items.map((i) => [
                  '${i['name']}',
                  '${i['quantity']}',
                  _bdt(toDouble(i['price'])),
                  _bdt(toDouble(i['price']) * (int.tryParse('${i['quantity']}') ?? 1)),
                ]).toList(),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: grey),
            headerDecoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: brand, width: 2))),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
            border: null,
            rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
          ),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 220,
              child: pw.Column(children: [
                _pdfRow('Subtotal', _bdt(toDouble(inv['subtotal'])), grey),
                if (toDouble(inv['discount_total']) > 0) _pdfRow('Discount', '-${_bdt(toDouble(inv['discount_total']))}', grey),
                pw.Divider(thickness: 1.5),
                _pdfRow('Total', _bdt(_total), PdfColors.black, bold: true),
              ]),
            ),
          ),
          if (!paid) ...[
            pw.SizedBox(height: 24),
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('How to pay', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Text('1. Send ${_bdt(_total)} to one of the accounts below.'),
                pw.Text('2. Write $_ref as the reference, if the app or bank asks for one.'),
                pw.Text('3. In Aptigen, open this invoice and enter the transaction id you received.'),
                pw.Text('4. We check the payment and your module unlocks automatically.'),
                pw.SizedBox(height: 8),
                ..._accounts.map((a) => pw.Text('${a['name']}${'${a['account_number'] ?? ''}'.isNotEmpty ? ': ${a['account_number']}' : ''}',
                    style: const pw.TextStyle(fontSize: 10))),
                pw.SizedBox(height: 8),
                pw.Text('Need help paying? Call $_supportPhone', style: pw.TextStyle(color: grey, fontSize: 10)),
              ]),
            ),
          ],
          pw.SizedBox(height: 24),
          pw.Center(child: pw.Text('Thank you for using Aptigen · aptigen.net · Call $_supportPhone', style: pw.TextStyle(fontSize: 9, color: grey))),
        ],
      ));
      await Printing.layoutPdf(onLayout: (_) => doc.save(), name: 'invoice-${_ref.replaceAll('#', '')}');
    } catch (_) {
      if (mounted) marketToast(context, 'Could not make the PDF', error: true);
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  pw.Widget _pdfRow(String label, String value, PdfColor color, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(children: [
          pw.Text(label, style: pw.TextStyle(color: color, fontWeight: bold ? pw.FontWeight.bold : null, fontSize: bold ? 13 : 10)),
          pw.Spacer(),
          pw.Text(value, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : null, fontSize: bold ? 13 : 10)),
        ]),
      );

  // ── UI ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: Text('Invoice $_ref'),
        actions: [
          IconButton(
            tooltip: 'Save as PDF',
            onPressed: _invoice == null || _pdfBusy ? null : _savePdf,
            icon: _pdfBusy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: _failed
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Couldn\'t load this invoice', style: TextStyle(color: p.label)),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: _load, child: const Text('Retry')),
              ]),
            )
          : _invoice == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _summary(p),
                    const SizedBox(height: 16),
                    if (_status == 'pending') _howToPay(p) else _done(p),
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton.icon(
                        onPressed: _call,
                        icon: const Icon(Icons.call_outlined, size: 18),
                        label: const Text('Need help? Call $_supportPhone'),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _card(MarketPalette p, {required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
        child: child,
      );

  Widget _summary(MarketPalette p) {
    final inv = _invoice!;
    final items = (inv['items'] as List? ?? const []).whereType<Map>().toList();
    final tone = _status == 'paid'
        ? p.tone(MarketTone.ok)
        : _status == 'rejected'
            ? p.tone(MarketTone.error)
            : p.tone(MarketTone.warn);
    return _card(
      p,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Image.asset('assets/icon/app_logo.png', height: 28, errorBuilder: (_, _, _) => const SizedBox.shrink()),
          const SizedBox(width: 8),
          Text('Aptigen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(999)),
            child: Text(
              _status == 'paid' ? 'Paid' : _status == 'rejected' ? 'Rejected' : 'Awaiting payment',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tone.fg),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Text('Issued ${_day(inv['created_at'])}', style: TextStyle(fontSize: 12, color: p.label)),
        const SizedBox(height: 10),
        ...items.map((i) {
          final qty = int.tryParse('${i['quantity']}') ?? 1;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i['name']}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                  Text('$qty ${qty == 1 ? 'month' : 'months'} × ${_taka(toDouble(i['price']))}', style: TextStyle(fontSize: 12, color: p.label)),
                ]),
              ),
              Text(_taka(toDouble(i['price']) * qty), style: TextStyle(fontSize: 14, color: p.text)),
            ]),
          );
        }),
        Divider(color: p.line, height: 20),
        if (toDouble(inv['discount_total']) > 0)
          Row(children: [
            Text('Discount', style: TextStyle(fontSize: 13, color: p.label)),
            const Spacer(),
            Text('−${_taka(toDouble(inv['discount_total']))}', style: TextStyle(fontSize: 13, color: p.text)),
          ]),
        Row(children: [
          Text('Total', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
          const Spacer(),
          Text(_taka(_total), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text)),
        ]),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pdfBusy ? null : _savePdf,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('Save as PDF'),
        ),
      ]),
    );
  }

  Widget _done(MarketPalette p) => _card(
        p,
        child: Text(
          _status == 'paid' ? 'This invoice is paid. Thank you!' : 'This invoice was rejected. Call us if you think this is a mistake.',
          style: TextStyle(fontSize: 14, color: p.text),
        ),
      );

  static const _steps = ['Choose an account', 'Send the money', 'Confirm payment'];

  Widget _howToPay(MarketPalette p) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('How to pay', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
      const SizedBox(height: 10),
      // step bar
      Row(
        children: List.generate(_steps.length, (i) {
          return Expanded(
            child: GestureDetector(
              onTap: i > 0 && _account == null ? null : () => setState(() => _step = i),
              child: Padding(
                padding: EdgeInsets.only(right: i < _steps.length - 1 ? 6 : 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 4,
                    decoration: BoxDecoration(color: i <= _step ? p.brand : p.surface, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(height: 6),
                  Text('${i + 1}. ${_steps[i]}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, fontWeight: i == _step ? FontWeight.w700 : FontWeight.w400, color: i == _step ? p.text : p.label)),
                ]),
              ),
            ),
          );
        }),
      ),
      const SizedBox(height: 12),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(
          key: ValueKey(_step),
          child: _card(p, child: _step == 0 ? _stepAccount(p) : _step == 1 ? _stepSend(p) : _stepConfirm(p)),
        ),
      ),
    ]);
  }

  Widget _stepAccount(MarketPalette p) {
    if (_accounts.isEmpty) {
      return Text('No payment accounts are set up yet. Call $_supportPhone to pay this invoice.', style: TextStyle(fontSize: 13, color: p.label));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Pick where you\'ll send the money.', style: TextStyle(fontSize: 14, color: p.text)),
      const SizedBox(height: 10),
      ..._accounts.map((a) {
        final selected = a['id'] == _accountId;
        final logo = '${a['logo_url'] ?? ''}';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() {
              _accountId = a['id'] as int?;
              _step = 1;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? p.brandSoft : p.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? p.brand : p.line),
              ),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: logo.isNotEmpty
                      ? Image.network(logo, width: 32, height: 32, fit: BoxFit.contain, errorBuilder: (_, _, _) => _initials(p, '${a['name']}'))
                      : _initials(p, '${a['name']}'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${a['name']}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                    Text(
                      '${a['method_type'] == 'bank' ? 'Bank transfer' : 'Mobile wallet'}${'${a['account_number'] ?? ''}'.isNotEmpty ? ' · ${a['account_number']}' : ''}',
                      style: TextStyle(fontSize: 12, color: p.label),
                    ),
                  ]),
                ),
                if (selected) Icon(Icons.check_circle, size: 20, color: p.brand),
              ]),
            ),
          ),
        );
      }),
    ]);
  }

  Widget _initials(MarketPalette p, String name) => Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        color: p.surface,
        child: Text(name.length >= 2 ? name.substring(0, 2) : name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.label)),
      );

  Widget _copyRow(MarketPalette p, String label, String shown, String raw) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 11.5, color: p.label)),
              Text(shown, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
            ]),
          ),
          IconButton(tooltip: 'Copy', onPressed: () => _copy(label, raw), icon: Icon(Icons.copy_rounded, size: 18, color: p.label)),
        ]),
      );

  Widget _stepSend(MarketPalette p) {
    final a = _account;
    if (a == null) return const SizedBox.shrink();
    final number = '${a['account_number'] ?? ''}';
    final instructions = '${a['instructions'] ?? ''}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text.rich(TextSpan(style: TextStyle(fontSize: 14, color: p.text), children: [
        const TextSpan(text: 'Send the exact amount to '),
        TextSpan(text: '${a['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        const TextSpan(text: '.'),
      ])),
      const SizedBox(height: 10),
      _copyRow(p, 'Amount', _taka(_total), _total.toStringAsFixed(2)),
      if (number.isNotEmpty) _copyRow(p, 'Account number', number, number),
      _copyRow(p, 'Reference', _ref, _ref),
      if (instructions.isNotEmpty) ...[
        Text(instructions, style: TextStyle(fontSize: 12, color: p.label)),
        const SizedBox(height: 6),
      ],
      Text('Keep the transaction id from the confirmation message. You\'ll need it next.', style: TextStyle(fontSize: 12, color: p.label)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => setState(() => _step = 0), child: const Text('Back'))),
        const SizedBox(width: 10),
        Expanded(child: FilledButton(onPressed: () => setState(() => _step = 2), child: const Text('I\'ve sent it'))),
      ]),
    ]);
  }

  Widget _stepConfirm(MarketPalette p) {
    final sent = '${_invoice?['transaction_ref'] ?? ''}';
    final txn = _txn.text.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Enter the transaction id so we can match your payment.', style: TextStyle(fontSize: 14, color: p.text)),
      const SizedBox(height: 10),
      TextField(
        controller: _txn,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(hintText: 'e.g. 8N7A6K2Q1D', border: OutlineInputBorder(), isDense: true),
        onChanged: (_) => setState(() {}),
      ),
      if (_account == null) ...[
        const SizedBox(height: 8),
        Text('Choose the account you paid to first.', style: TextStyle(fontSize: 12, color: p.warn)),
      ],
      if (sent.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Sent. We\'re checking the payment. The module unlocks automatically once it\'s confirmed.', style: TextStyle(fontSize: 12, color: p.ok)),
      ],
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => setState(() => _step = _account == null ? 0 : 1), child: const Text('Back'))),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: _saving || _account == null || txn.isEmpty || txn == sent ? null : _submit,
            child: Text(_saving ? 'Sending…' : sent.isNotEmpty ? 'Update' : 'Submit payment'),
          ),
        ),
      ]),
    ]);
  }
}
