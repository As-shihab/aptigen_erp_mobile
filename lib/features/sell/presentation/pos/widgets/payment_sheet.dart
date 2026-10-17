import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/network/http_client.dart';
import '../../../../../core/utils/currency.dart';
import '../../../data/cart_models.dart';
import '../../../data/pos_service.dart';
import '../../../data/sales_order_model.dart';
import '../../widgets/sell_ui.dart' show MarketPalette, MarketTone, StatusPill, showMarketSheet, marketToast;

const _methodLabels = {'CASH': 'Cash', 'CARD': 'Card', 'MOBILE_BANKING': 'Mobile'};
const _methodIcons = {'CASH': Icons.payments_outlined, 'CARD': Icons.credit_card_outlined, 'MOBILE_BANKING': Icons.phone_android_outlined};

/// Split-tender payment entry + checkout call — mirrors desktop's pay
/// dialog (PosTerminal.tsx) including the underpay rule: a walk-in sale
/// (no client) must be paid in full; a client-attached sale may be
/// underpaid, leaving a due balance on the client's account. Returns the
/// completed `SalesOrder` on success, or null if the sheet was dismissed.
Future<SalesOrder?> showPaymentSheet(BuildContext context, {required CartTab cart, bool isPharma = false}) {
  return showMarketSheet<SalesOrder>(
    context,
    builder: (_) => _PaymentSheet(cart: cart, isPharma: isPharma),
  );
}

class _PaymentSheet extends StatefulWidget {
  final CartTab cart;
  final bool isPharma;
  const _PaymentSheet({required this.cart, this.isPharma = false});

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _posService = PosService(ApiClient());
  final _amountController = TextEditingController();
  String _method = 'CASH';
  final List<PaymentLine> _payments = [];
  bool _checkingOut = false;

  double get _paid => _payments.fold(0.0, (sum, p) => sum + p.amount);
  double get _remaining => (widget.cart.total - _paid) < 0 ? 0 : (widget.cart.total - _paid);
  double get _change => (_paid - widget.cart.total) < 0 ? 0 : (_paid - widget.cart.total);
  bool get _canComplete => _remaining <= 0.004 ? _payments.isNotEmpty : widget.cart.clientId != null;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.cart.total.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _addPayment() {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;
    setState(() {
      _payments.add(PaymentLine(method: _method, amount: amount));
      final left = widget.cart.total - _paid - amount;
      _amountController.text = left > 0 ? left.toStringAsFixed(2) : '';
    });
  }

  Future<void> _complete() async {
    if (_remaining > 0.004 && widget.cart.clientId == null) {
      marketToast(context, 'A walk-in sale must be paid in full — attach a client to allow a due balance.', error: true);
      return;
    }
    if (_remaining <= 0.004 && _payments.isEmpty) {
      marketToast(context, 'Add at least one payment.', error: true);
      return;
    }
    setState(() => _checkingOut = true);
    try {
      final sale = await _posService.checkout(widget.cart, park: false, payments: _payments, isPharma: widget.isPharma);
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.of(context).pop(sale);
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Checkout failed. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final hasClient = widget.cart.clientId != null;
    final owing = _remaining > 0.004;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Payment', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: p.text)),
                        const SizedBox(height: 2),
                        Text(widget.cart.clientName ?? 'Walk-in customer', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(hasClient ? 'Due allowed' : 'Pay in full', tone: hasClient ? MarketTone.info : MarketTone.neutral),
                ],
              ),
              const SizedBox(height: 14),
              // Amount header
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total due', style: TextStyle(fontSize: 12, color: p.label)),
                          const SizedBox(height: 2),
                          Text(formatMoney(widget.cart.total), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.text)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(owing ? 'Remaining' : (_change > 0 ? 'Change' : 'Settled'), style: TextStyle(fontSize: 12, color: p.label)),
                        const SizedBox(height: 2),
                        Text(
                          formatMoney(owing ? _remaining : _change),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: owing ? (hasClient ? p.warn : p.error) : p.ok),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Method', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.label)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var i = 0; i < kPaymentMethods.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: _methodTile(p, kPaymentMethods[i])),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Amount', prefixText: '${currencySymbol()} ', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 46,
                    child: FilledButton.icon(
                      onPressed: _addPayment,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.brandSoft,
                        foregroundColor: p.brand,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                  ),
                ],
              ),
              if (_payments.isNotEmpty) ...[
                const SizedBox(height: 14),
                Material(
                  color: p.card,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.line)),
                  child: Column(
                    children: [
                      for (final entry in _payments.asMap().entries) ...[
                        if (entry.key > 0) Divider(height: 1, thickness: 1, color: p.line),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 2, 2, 2),
                          child: Row(
                            children: [
                              Icon(_methodIcons[entry.value.method] ?? Icons.payments_outlined, size: 18, color: p.label),
                              const SizedBox(width: 10),
                              Expanded(child: Text(_methodLabels[entry.value.method] ?? entry.value.method, style: TextStyle(fontSize: 13.5, color: p.text))),
                              Text(formatMoney(entry.value.amount), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: p.text)),
                              IconButton(
                                icon: Icon(Icons.close, size: 18, color: p.label),
                                tooltip: 'Remove payment',
                                onPressed: () => setState(() => _payments.removeAt(entry.key)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Divider(height: 1, thickness: 1, color: p.line),
              const SizedBox(height: 8),
              _row(p, 'Paid', formatMoney(_paid)),
              if (_change > 0) _row(p, 'Change', formatMoney(_change), color: p.ok),
              if (_remaining > 0.004) _row(p, 'Remaining due', formatMoney(_remaining), color: widget.cart.clientId != null ? p.warn : p.error),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: (_checkingOut || !_canComplete) ? null : _complete,
                  style: FilledButton.styleFrom(
                    backgroundColor: p.brand,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: p.surface,
                    disabledForegroundColor: p.label,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _checkingOut
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_remaining > 0.004 ? 'Complete sale (${formatMoney(_remaining)} due)' : 'Complete sale', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _methodTile(MarketPalette p, String m) {
    final enabled = isPaymentMethodEnabled(m);
    final selected = _method == m;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: selected ? p.brandSoft : p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: selected ? p.brand : p.line, width: selected ? 1.5 : 1)),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? () => setState(() => _method = m) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_methodIcons[m] ?? Icons.payments_outlined, size: 20, color: selected ? p.brand : p.label),
                const SizedBox(height: 4),
                Text(_methodLabels[m] ?? m, style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? p.brand : p.text)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(MarketPalette p, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5, color: p.label)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: color ?? p.text)),
        ],
      ),
    );
  }
}
