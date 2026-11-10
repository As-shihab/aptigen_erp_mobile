import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/billing/paywall_state.dart';
import '../../../core/network/http_client.dart';
import '../../billing/data/subscription_invoice.dart';
import '../../billing/presentation/invoice_page.dart';
import '../../sell/market/presentation/widgets/market_ui.dart';
import '../data/market_service.dart';
import '../models/market_app.dart';

/// Month → Payment → Success purchase flow for a paid module — mobile port of
/// erp/desktop's `module/market/shared/PurchaseWizard.tsx`. Creates a pending
/// invoice (with the chosen payment method + account) and installs the
/// module; a platform admin approves the invoice before the subscription is
/// active. Resolves true once the module was installed.
Future<bool> showPurchaseWizard(BuildContext context, MarketApp app, MarketService service) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: MarketPalette.of(context).card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _PurchaseWizard(app: app, service: service),
  );
  return result == true;
}

const _methods = [
  (value: 'bank', label: 'Bank', icon: Icons.account_balance_outlined),
  (value: 'mobile', label: 'Mobile', icon: Icons.smartphone_outlined),
];

const _stepLabels = ['Month', 'Payment', 'Done'];

String _taka(num v) => '৳${v == v.roundToDouble() ? v.toInt() : v.toStringAsFixed(2)}';

/// Payment instructions are stored as HTML (desktop renders them as-is).
String _plain(String? html) => (html ?? '')
    .replaceAll(RegExp(r'<br\s*/?>|</p>|</li>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

class _PurchaseWizard extends StatefulWidget {
  final MarketApp app;
  final MarketService service;
  const _PurchaseWizard({required this.app, required this.service});

  @override
  State<_PurchaseWizard> createState() => _PurchaseWizardState();
}

class _PurchaseWizardState extends State<_PurchaseWizard> {
  final _client = ApiClient();
  int _step = 0; // 0 month, 1 payment, 2 result
  int _months = 1;
  String _method = 'bank';
  int? _accountId;
  List<Map<String, dynamic>> _accounts = [];
  bool _loadingAccounts = false;
  bool _busy = false;
  String? _error;
  int? _invoiceId;
  bool _installed = false;

  MarketApp get app => widget.app;
  double get _total => (app.price * _months * 100).round() / 100;
  Map<String, dynamic>? get _account => _accounts.where((a) => toInt(a['id']) == _accountId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _loadingAccounts = true;
      _accountId = null;
    });
    try {
      final rows = await widget.service.loadPaymentAccounts(_method);
      if (mounted) setState(() => _accounts = rows);
    } catch (_) {
      if (mounted) setState(() => _accounts = []);
    } finally {
      if (mounted) setState(() => _loadingAccounts = false);
    }
  }

  // One run per tap — guarded by _busy so a double tap can't create two invoices.
  Future<void> _confirm() async {
    if (_busy || _accountId == null) return;
    if (!await ensureWorkplacePhone(context, _client)) return;
    setState(() {
      _busy = true;
      _error = null;
      _step = 2;
    });
    try {
      _invoiceId ??= await createPendingInvoice(
        _client,
        moduleId: app.id,
        moduleName: app.name,
        unitPrice: app.price,
        months: _months,
        paymentMethod: _method,
        paymentAccountId: _accountId,
      );
      await widget.service.install(app.id);
      PaywallState.load(_client);
      if (mounted) setState(() => _installed = true);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(children: [
                Expanded(
                  child: Text('Subscribe to ${app.name}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(_installed),
                  icon: Icon(Icons.close, color: p.label),
                ),
              ]),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 4), child: _stepper(p)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: switch (_step) {
                      0 => _monthStep(p),
                      1 => _paymentStep(p),
                      _ => _resultStep(p),
                    },
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _stepper(MarketPalette p) {
    final success = _installed;
    return Row(children: [
      for (var i = 0; i < _stepLabels.length; i++) ...[
        Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _step > i || (i == 2 && success) ? p.okBg : (_step == i ? p.brand : p.card),
              border: Border.all(color: _step > i || (i == 2 && success) ? p.ok : (_step == i ? p.brand : p.line), width: 2),
            ),
            alignment: Alignment.center,
            child: _step > i || (i == 2 && success)
                ? Icon(Icons.check, size: 16, color: p.ok)
                : Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _step == i ? Colors.white : p.label)),
          ),
          const SizedBox(height: 4),
          Text(_stepLabels[i], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _step == i ? p.brand : p.label)),
        ]),
        if (i < _stepLabels.length - 1)
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(left: 6, right: 6, bottom: 16),
              height: 2,
              color: _step > i ? p.ok : p.line,
            ),
          ),
      ],
    ]);
  }

  Widget _monthStep(MarketPalette p) {
    final offer = app.welcomeOffer;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
        child: Row(children: [
          CircleAvatar(radius: 22, backgroundColor: app.color.withValues(alpha: 0.15), child: Icon(app.icon, color: app.color)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(app.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: p.text)),
              Text('${_taka(app.price)} per month', style: TextStyle(fontSize: 12, color: p.label)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 22),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton.outlined(
          tooltip: 'Fewer months',
          onPressed: _months <= 1 ? null : () => setState(() => _months--),
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 92,
          child: Column(children: [
            Text('$_months', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: p.text)),
            Text(_months > 1 ? 'months' : 'month', style: TextStyle(fontSize: 11, color: p.label)),
          ]),
        ),
        IconButton.outlined(
          tooltip: 'More months',
          onPressed: () => setState(() => _months++),
          icon: const Icon(Icons.add),
        ),
      ]),
      const SizedBox(height: 18),
      _totalBox(p),
      if (offer != null) ...[
        const SizedBox(height: 8),
        Text('Welcome offer: ${offer.percent}% off for ${offer.months} month${offer.months > 1 ? 's' : ''}',
            style: TextStyle(fontSize: 12, color: p.ok)),
      ],
      const SizedBox(height: 10),
      Text("Creates an invoice awaiting admin approval. Access stays pending until it's approved.",
          textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: p.label)),
      const SizedBox(height: 18),
      SizedBox(
        height: 46,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: p.brand),
          onPressed: () => setState(() => _step = 1),
          child: const Text('Continue to payment'),
        ),
      ),
    ]);
  }

  Widget _totalBox(MarketPalette p) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
        child: Row(children: [
          Text('Total', style: TextStyle(fontSize: 12.5, color: p.label)),
          const Spacer(),
          Text(_taka(_total), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: p.text)),
        ]),
      );

  Widget _paymentStep(MarketPalette p) {
    final account = _account;
    final methodLabel = _methods.firstWhere((m) => m.value == _method).label.toLowerCase();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Payment method', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
      const SizedBox(height: 8),
      Row(children: [
        for (final m in _methods) ...[
          if (m != _methods.first) const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (_method == m.value) return;
                setState(() => _method = m.value);
                _loadAccounts();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _method == m.value ? p.brandSoft : p.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _method == m.value ? p.brand : p.line, width: _method == m.value ? 2 : 1),
                ),
                child: Column(children: [
                  Icon(m.icon, color: _method == m.value ? p.brand : p.label),
                  const SizedBox(height: 6),
                  Text(m.label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.text)),
                ]),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 18),
      Text('Choose an account', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
      const SizedBox(height: 8),
      if (_loadingAccounts)
        ...List.generate(2, (_) => const Padding(padding: EdgeInsets.only(bottom: 8), child: SkeletonBox(height: 58, radius: 12)))
      else if (_accounts.isEmpty)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
          child: Text('No $methodLabel accounts are set up yet. Try another method.', style: TextStyle(fontSize: 12.5, color: p.label)),
        )
      else
        for (final a in _accounts) _accountTile(p, a),
      if (account != null && _plain(account['instructions']?.toString()).isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Payment instructions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
          child: Text(_plain(account['instructions']?.toString()), style: TextStyle(fontSize: 12.5, height: 1.45, color: p.text)),
        ),
      ],
      const SizedBox(height: 16),
      _totalBox(p),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: SizedBox(
            height: 46,
            child: OutlinedButton(onPressed: () => setState(() => _step = 0), child: const Text('Back')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 46,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: p.brand),
              onPressed: _accountId == null ? null : _confirm,
              child: const Text('Confirm and install'),
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _accountTile(MarketPalette p, Map<String, dynamic> a) {
    final id = toInt(a['id']);
    final selected = _accountId == id;
    final logo = '${a['logo_url'] ?? ''}';
    final number = '${a['account_number'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _accountId = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? p.brandSoft : p.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? p.brand : p.line, width: selected ? 2 : 1),
          ),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: logo.startsWith('http')
                  ? CachedNetworkImage(imageUrl: logo, width: 36, height: 36, fit: BoxFit.cover, errorWidget: (_, _, _) => _logoFallback(p))
                  : _logoFallback(p),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a['name'] ?? 'Account'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                if (number.isNotEmpty) Text(number, style: TextStyle(fontSize: 12, color: p.label)),
              ]),
            ),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? p.brand : p.label, size: 20),
          ]),
        ),
      ),
    );
  }

  Widget _logoFallback(MarketPalette p) => Container(
        width: 36,
        height: 36,
        color: p.surface,
        child: Icon(_method == 'bank' ? Icons.account_balance_outlined : Icons.smartphone_outlined, size: 18, color: p.label),
      );

  Widget _resultStep(MarketPalette p) {
    if (_busy) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3, color: p.brand)),
          const SizedBox(height: 14),
          Text('Creating your invoice…', style: TextStyle(fontSize: 13, color: p.label)),
        ]),
      );
    }
    if (_error != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 12),
        Icon(Icons.error_outline, size: 40, color: p.error),
        const SizedBox(height: 10),
        Text('Could not complete the purchase', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
        const SizedBox(height: 6),
        Text(_error!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: p.label)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: SizedBox(height: 46, child: OutlinedButton(onPressed: () => setState(() => _step = 1), child: const Text('Back')))),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 46,
              child: FilledButton(style: FilledButton.styleFrom(backgroundColor: p.brand), onPressed: _confirm, child: const Text('Try again')),
            ),
          ),
        ]),
      ]);
    }
    final account = _account;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: p.okBg, shape: BoxShape.circle),
        child: Icon(Icons.check, size: 30, color: p.ok),
      ),
      const SizedBox(height: 12),
      Text('${app.name} installed', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
      const SizedBox(height: 4),
      Text('Your invoice is waiting for admin approval. Pay it and send the transaction id from the invoice.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: p.label, height: 1.4)),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
        child: Column(children: [
          _summaryRow(p, 'Module', app.name),
          _summaryRow(p, 'Months', '$_months'),
          _summaryRow(p, 'Payment', '${_methods.firstWhere((m) => m.value == _method).label}${account != null ? ' · ${account['name']}' : ''}'),
          Divider(color: p.line, height: 18),
          _summaryRow(p, 'Total', _taka(_total), bold: true),
        ]),
      ),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(
          child: SizedBox(height: 46, child: OutlinedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Done'))),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 46,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: p.brand),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('View invoice'),
              onPressed: _invoiceId == null
                  ? null
                  : () {
                      final nav = Navigator.of(context);
                      final id = _invoiceId!;
                      nav.pop(true);
                      nav.push(MaterialPageRoute(builder: (_) => InvoicePage(invoiceId: id)));
                    },
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _summaryRow(MarketPalette p, String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: p.label)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: bold ? 15 : 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: p.text)),
          ),
        ]),
      );
}
