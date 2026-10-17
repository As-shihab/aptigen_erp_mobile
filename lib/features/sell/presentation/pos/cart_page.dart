import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/utils/currency.dart';
import '../../data/cart_models.dart';
import '../../data/client_model.dart';
import '../../data/pos_service.dart';
import '../../data/sales_order_model.dart';
import '../widgets/sell_ui.dart' show MarketPalette, MarketCard, MarketEmpty, SectionHeader, marketToast;
import 'widgets/client_picker_sheet.dart';
import 'widgets/payment_sheet.dart';

/// Result of leaving the cart page — `parked` means the cart was saved as a
/// held bill (same tab, editing continues later); `completedSale` is set
/// only when checkout finished (POS terminal then swaps in a fresh empty
/// tab and shows the receipt), mirroring desktop's park-vs-complete split
/// (PosTerminal.tsx's `submitCheckout`).
class CartPageResult {
  final bool parked;
  final SalesOrder? completedSale;
  const CartPageResult({this.parked = false, this.completedSale});
}

/// Full-screen cart editor — line list with quantity steppers/per-line
/// discount, cart-level discount/tax/client/note, Park and Charge actions.
/// A full page (not a modal sheet) per this app's "forms are always
/// full-screen pages" convention.
class CartPage extends StatefulWidget {
  final CartTab cart;
  final List<Client> clients;
  final bool isPharma;
  const CartPage({super.key, required this.cart, required this.clients, this.isPharma = false});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  late final _posService = PosService(ApiClient());
  bool _parking = false;

  CartTab get _cart => widget.cart;

  Future<void> _pickClient() async {
    final picked = await showClientPickerSheet(context, clients: widget.clients);
    // showClientPickerSheet pops with null for an explicit "Walk-in" tap too
    // (indistinguishable from "dismissed without choosing" at the call site,
    // which is fine here — both mean "no client").
    setState(() {
      _cart.clientId = picked?.id;
      _cart.clientName = picked?.name;
    });
  }

  void _removeClient() => setState(() {
        _cart.clientId = null;
        _cart.clientName = null;
      });

  void _setLineQuantity(CartLine line, double next) {
    if (next <= 0) {
      setState(() => _cart.lines.remove(line));
      return;
    }
    if (line.maxStock != null && next > line.maxStock!) {
      marketToast(context, 'Only ${line.maxStock} in stock.', error: true);
      return;
    }
    setState(() => line.quantity = next.round());
  }

  Future<void> _park() async {
    setState(() => _parking = true);
    try {
      final sale = await _posService.checkout(_cart, park: true, isPharma: widget.isPharma);
      if (!mounted) return;
      _cart.saleId = sale.id;
      marketToast(context, 'Sale parked.');
      Navigator.of(context).pop(const CartPageResult(parked: true));
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Could not park this sale.', error: true);
    } finally {
      if (mounted) setState(() => _parking = false);
    }
  }

  Future<void> _charge() async {
    final sale = await showPaymentSheet(context, cart: _cart, isPharma: widget.isPharma);
    if (sale == null || !mounted) return;
    Navigator.of(context).pop(CartPageResult(completedSale: sale));
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final cart = _cart;
    final itemCount = cart.lines.fold(0, (sum, l) => sum + l.quantity);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.card,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: p.line)),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cart.label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
            Text(cart.isEmpty ? 'No items' : '$itemCount item${itemCount == 1 ? '' : 's'}', style: TextStyle(fontSize: 11.5, color: p.label)),
          ],
        ),
      ),
      body: cart.isEmpty
          ? Center(
              child: SingleChildScrollView(
                child: MarketEmpty(icon: Icons.shopping_cart_outlined, title: 'Cart is empty', message: 'Add products from the terminal to start a sale.'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _clientCard(p, cart),
                SectionHeader('Items', subtitle: 'Swipe a line left to remove it'),
                Material(
                  color: p.card,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.line)),
                  child: Column(
                    children: [
                      for (var i = 0; i < cart.lines.length; i++) ...[
                        if (i > 0) Divider(height: 1, thickness: 1, color: p.line),
                        _lineRow(p, cart, cart.lines[i]),
                      ],
                    ],
                  ),
                ),
                const SectionHeader('Discount, tax and note'),
                MarketCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              initialValue: cart.discountType,
                              decoration: const InputDecoration(labelText: 'Discount type', isDense: true),
                              items: const [
                                DropdownMenuItem(value: null, child: Text('None')),
                                DropdownMenuItem(value: 'PERCENT', child: Text('Percent (%)')),
                                DropdownMenuItem(value: 'FLAT', child: Text('Flat amount')),
                              ],
                              onChanged: (v) => setState(() => cart.discountType = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: cart.discountValue == 0 ? '' : cart.discountValue.toString(),
                              enabled: cart.discountType != null,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Discount value', isDense: true),
                              onChanged: (v) => setState(() => cart.discountValue = double.tryParse(v) ?? 0),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: cart.taxRate == 0 ? '' : cart.taxRate.toString(),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Tax rate (%)', isDense: true),
                        onChanged: (v) => setState(() => cart.taxRate = double.tryParse(v) ?? 0),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: cart.note ?? '',
                        decoration: const InputDecoration(labelText: 'Note', isDense: true),
                        onChanged: (v) => cart.note = v.trim().isEmpty ? null : v.trim(),
                      ),
                    ],
                  ),
                ),
                const SectionHeader('Summary'),
                MarketCard(
                  child: Column(
                    children: [
                      _totalsRow(p, 'Subtotal', cart.subtotal),
                      if (cart.discountAmount > 0) _totalsRow(p, 'Discount', -cart.discountAmount, color: p.error),
                      if (cart.taxAmount > 0) _totalsRow(p, 'Tax', cart.taxAmount),
                      Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1, thickness: 1, color: p.line)),
                      _totalsRow(p, 'Total', cart.total, bold: true),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: cart.isEmpty ? null : _bottomBar(p, cart, itemCount),
    );
  }

  Widget _clientCard(MarketPalette p, CartTab cart) {
    final hasClient = cart.clientId != null;
    final name = cart.clientName ?? '';
    return MarketCard(
      onTap: _pickClient,
      padding: EdgeInsets.fromLTRB(12, 10, hasClient ? 4 : 12, 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: hasClient ? p.brandSoft : p.surface, shape: BoxShape.circle),
            child: hasClient && name.isNotEmpty
                ? Text(name[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: p.brand))
                : Icon(Icons.person_outline, size: 18, color: hasClient ? p.brand : p.label),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cart.clientName ?? 'Walk-in customer', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: p.text)),
                const SizedBox(height: 2),
                Text(hasClient ? 'Tap to change client' : 'Tap to attach a client', style: TextStyle(fontSize: 12, color: p.label)),
              ],
            ),
          ),
          if (hasClient)
            IconButton(icon: Icon(Icons.close, size: 18, color: p.label), tooltip: 'Remove client', onPressed: _removeClient)
          else
            Icon(Icons.chevron_right, size: 20, color: p.label),
        ],
      ),
    );
  }

  Widget _lineRow(MarketPalette p, CartTab cart, CartLine line) {
    return Dismissible(
      key: ValueKey(identityHashCode(line)),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: p.errorBg,
        child: Icon(Icons.delete_outline, color: p.error),
      ),
      onDismissed: (_) => setState(() => cart.lines.remove(line)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: p.text)),
                  const SizedBox(height: 2),
                  Text('${formatMoney(line.unitPrice)} each', style: TextStyle(fontSize: 12, color: p.label)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _stepper(p, line),
            const SizedBox(width: 10),
            SizedBox(
              width: 76,
              child: Text(formatMoney(line.lineTotal), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: p.text)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(MarketPalette p, CartTab cart, int itemCount) {
    return Container(
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('$itemCount item${itemCount == 1 ? '' : 's'}', style: TextStyle(fontSize: 12.5, color: p.label)),
                  const Spacer(),
                  Text('Total', style: TextStyle(fontSize: 12.5, color: p.label)),
                  const SizedBox(width: 8),
                  Text(formatMoney(cart.total), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _parking ? null : _park,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: p.text,
                          side: BorderSide(color: p.line),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: _parking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.pause_circle_outline, size: 18),
                        label: const Text('Park'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _parking ? null : _charge,
                        style: FilledButton.styleFrom(
                          backgroundColor: p.brand,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text('Charge ${formatMoney(cart.total)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepper(MarketPalette p, CartLine line) {
    final last = line.quantity <= 1;
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: p.line)),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepBtn(last ? Icons.delete_outline : Icons.remove, last ? p.error : p.brand, last ? 'Remove' : 'Decrease', () => _setLineQuantity(line, (line.quantity - 1).toDouble())),
          SizedBox(width: 30, child: Text('${line.quantity}', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: p.text))),
          _stepBtn(Icons.add, p.brand, 'Increase', () => _setLineQuantity(line, (line.quantity + 1).toDouble())),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, Color color, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 16, color: color)),
      ),
    );
  }

  Widget _totalsRow(MarketPalette p, String label, double value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontSize: bold ? 15 : 13, color: bold ? p.text : p.label)),
          Text(formatMoney(value), style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w600, fontSize: bold ? 17 : 13, color: color ?? p.text)),
        ],
      ),
    );
  }
}
