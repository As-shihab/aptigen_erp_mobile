import 'package:flutter/material.dart';
import '../../../core/billing/paywall_state.dart';
import '../../../core/network/http_client.dart';
import '../../sell/market/presentation/widgets/market_ui.dart';
import '../data/subscription_invoice.dart';
import 'invoice_page.dart';

bool _sheetOpen = false;

String _taka(num v) => '৳${v == v.roundToDouble() ? v.toInt() : v.toStringAsFixed(2)}';

/// Opens the subscription wall — the mobile equivalent of erp/desktop's
/// `GlobalPaywallDialog` (components/super/paywall-dialog.tsx). Shown when
/// an OData write is blocked (via [PaywallState.onBlocked]) or a locked
/// module tile is tapped. Only one wall is shown at a time.
///
/// [onViewOnly], when given, adds a "Continue in view-only mode" action —
/// desktop never blocks reads, so a locked module can still be opened to
/// look at existing data.
Future<void> showPaywallSheet(BuildContext context, PaywallBlock block, {VoidCallback? onViewOnly}) async {
  if (_sheetOpen) return;
  _sheetOpen = true;
  try {
    final viewOnly = await showMarketSheet<bool>(context, builder: (_) => _PaywallSheet(block: block, allowViewOnly: onViewOnly != null));
    if (viewOnly == true) onViewOnly?.call();
  } finally {
    _sheetOpen = false;
  }
}

class _PaywallSheet extends StatefulWidget {
  final PaywallBlock block;
  final bool allowViewOnly;
  const _PaywallSheet({required this.block, required this.allowViewOnly});

  @override
  State<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<_PaywallSheet> {
  final _client = ApiClient();
  bool _renewing = false;
  int _months = 1;
  bool _saving = false;

  PaywallBlock get b => widget.block;

  // Same "pick months, create a pending invoice" flow as desktop — no
  // self-service pay-and-activate; a platform admin approves the invoice.
  Future<void> _confirm() async {
    if (_saving) return;
    if (!await ensureWorkplacePhone(context, _client)) return;
    setState(() => _saving = true);
    try {
      final invoiceId = await createPendingInvoice(_client, moduleId: b.moduleId, moduleName: b.moduleName, unitPrice: b.modulePrice, months: _months);
      PaywallState.load(_client);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      final nav = Navigator.of(context);
      nav.pop(false);
      messenger?.showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('Invoice created. Follow the steps to pay it.')));
      // Straight to the invoice and its how-to-pay steps.
      nav.push(MaterialPageRoute(builder: (_) => InvoicePage(invoiceId: invoiceId)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      marketToast(context, 'Could not create invoice', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _renewing ? _monthsPicker(context) : _wall(context),
          ),
        ),
      ),
    );
  }

  Widget _handle(MarketPalette p) => Center(
        child: Container(width: 36, height: 4, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2))),
      );

  Widget _wall(BuildContext context) {
    final p = MarketPalette.of(context);
    final pending = b.pendingInvoice;
    final canBuy = pending == null;
    final status = pending != null ? 'Invoice awaiting approval' : (b.needsRenewal ? 'Subscription needed' : 'Payment needed');
    final bodyStyle = TextStyle(fontSize: 14, height: 1.45, color: p.text);
    final bold = const TextStyle(fontWeight: FontWeight.w700);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _handle(p),
        const SizedBox(height: 14),
        Text('Payment required', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
        const SizedBox(height: 16),
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: p.warnBg, shape: BoxShape.circle),
            child: Icon(Icons.lock_outline, size: 20, color: p.warn),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.moduleName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
              const SizedBox(height: 2),
              Text(status, style: TextStyle(fontSize: 12, color: p.label)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        if (pending != null) ...[
          Text.rich(
            TextSpan(style: bodyStyle, children: [
              const TextSpan(text: 'This action needs '),
              TextSpan(text: b.moduleName, style: bold),
              TextSpan(
                text: ' to be paid. There\'s an invoice (${pending.invoiceNo.isNotEmpty ? pending.invoiceNo : '#${pending.id}'}, '
                    '${_taka(pending.total)}) awaiting admin approval. It will unlock automatically once approved.',
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.line)),
            child: Row(children: [
              Icon(Icons.schedule, size: 16, color: p.label),
              const SizedBox(width: 8),
              Expanded(child: Text('Waiting for a platform admin to approve this invoice', style: TextStyle(fontSize: 12, color: p.label))),
            ]),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('View invoice'),
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop(false);
              nav.push(MaterialPageRoute(builder: (_) => InvoicePage(invoiceId: pending.id)));
            },
          ),
        ] else if (b.needsRenewal)
          Text.rich(TextSpan(style: bodyStyle, children: [
            TextSpan(text: b.moduleName, style: bold),
            const TextSpan(
              text: ' now requires an active subscription to continue. Pick how many months to subscribe for. '
                  'An admin will need to approve the invoice before it\'s active.',
            ),
          ]))
        else
          Text.rich(TextSpan(style: bodyStyle, children: [
            TextSpan(text: b.moduleName, style: bold),
            const TextSpan(text: ' requires payment before you can make changes here. You can still view existing data.'),
          ])),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(canBuy ? 'Cancel' : 'Close'),
            ),
          ),
          if (canBuy) ...[
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.credit_card, size: 18),
                label: Text(b.needsRenewal ? 'Subscribe' : 'Complete purchase'),
                onPressed: () => setState(() {
                  _renewing = true;
                  _months = 1;
                }),
              ),
            ),
          ],
        ]),
        if (widget.allowViewOnly) ...[
          const SizedBox(height: 4),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Continue in view-only mode')),
        ],
      ],
    );
  }

  // Port of desktop's MonthsPickerDialog.
  Widget _monthsPicker(BuildContext context) {
    final p = MarketPalette.of(context);
    final total = (b.modulePrice < 0 ? 0 : b.modulePrice) * _months;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _handle(p),
        const SizedBox(height: 14),
        Text('Subscribe to ${b.moduleName}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
        const SizedBox(height: 6),
        Text('Choose how many months to subscribe for.', style: TextStyle(fontSize: 13, color: p.label)),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton.outlined(
            tooltip: 'Fewer months',
            onPressed: _saving || _months <= 1 ? null : () => setState(() => _months--),
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 88,
            child: Column(children: [
              Text('$_months', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: p.text)),
              Text(_months > 1 ? 'months' : 'month', style: TextStyle(fontSize: 11, color: p.label)),
            ]),
          ),
          IconButton.outlined(
            tooltip: 'More months',
            onPressed: _saving ? null : () => setState(() => _months++),
            icon: const Icon(Icons.add),
          ),
        ]),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.line)),
          child: Row(children: [
            Text('Total', style: TextStyle(fontSize: 12, color: p.label)),
            const Spacer(),
            Text(_taka(total), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
          ]),
        ),
        const SizedBox(height: 10),
        Text(
          'Creates an invoice awaiting admin approval. The module stays inactive until it\'s approved.',
          style: TextStyle(fontSize: 11, color: p.label),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => setState(() => _renewing = false),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : _confirm,
              child: Text(_saving ? 'Creating…' : 'Create invoice'),
            ),
          ),
        ]),
      ],
    );
  }
}
