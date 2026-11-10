import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/market_seller_service.dart';
import '../widgets/market_ui.dart';
import 'order_common.dart';
import 'order_pipeline.dart';

/// Object-page style detail of one website order: header (status + this
/// store's total), animated fulfilment pipeline, customer, delivery,
/// payment, items, totals and the next-step action bar.
class MarketOrderDetailPage extends StatefulWidget {
  final Map<String, dynamic> order;
  final void Function(int id, String status)? onStatusChanged;
  const MarketOrderDetailPage({super.key, required this.order, this.onStatusChanged});

  @override
  State<MarketOrderDetailPage> createState() => _MarketOrderDetailPageState();
}

class _MarketOrderDetailPageState extends State<MarketOrderDetailPage> {
  final _service = MarketSellerService();
  late Map<String, dynamic> _o = Map<String, dynamic>.from(widget.order);
  String? _busy;

  String get _status => '${_o['status']}';
  bool get _multi => _o['multi_store'] == true;
  String? get _currency => str(_o['currency']);
  String _m(dynamic v) => money(toDouble(v), currency: _currency);

  Future<void> _setStatus(String status) async {
    if (status == 'cancelled') {
      final ok = await confirmMarket(
        context,
        title: 'Cancel order',
        message: 'Cancel order ${str(_o['order_no']) ?? ''}? The buyer will see it as cancelled.',
        confirm: 'Cancel order',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = status);
    try {
      await _service.setOrderStatus(toInt(_o['id']), status);
      if (!mounted) return;
      setState(() => _o = {..._o, 'status': status});
      widget.onStatusChanged?.call(toInt(_o['id']), status);
      marketToast(context, switch (status) {
        'paid' => 'Order accepted',
        'packaged' => 'Marked as packed',
        'delivered' => 'Marked as delivered',
        'cancelled' => 'Order cancelled',
        _ => 'Order updated',
      });
    } catch (e) {
      if (mounted) marketToast(context, errorText(e, 'Could not update the order'), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _copy(String value, String what) {
    Clipboard.setData(ClipboardData(text: value));
    marketToast(context, '$what copied');
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final next = nextOrderStep(_status);
    final canCancel = orderCancellable(_status);
    final hasActions = next != null || canCancel;

    return MarketScaffold(
      title: 'Order ${str(_o['order_no']) ?? '#${_o['id']}'}',
      subtitle: fmtDateTime(_o['created_at']),
      bottom: hasActions ? _actionBar(p, next, canCancel) : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          FadeSlideIn(child: _header(p)),
          FadeSlideIn(index: 1, child: _customer(p)),
          FadeSlideIn(index: 2, child: _delivery(p)),
          FadeSlideIn(index: 3, child: _payment(p)),
          FadeSlideIn(index: 4, child: _items(p)),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────

  Widget _header(MarketPalette p) {
    final items = toInt(_o['item_count']);
    return Container(
      margin: const EdgeInsets.only(top: 14),
      child: MarketCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your total', style: TextStyle(fontSize: 12, color: p.label)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_m(_o['seller_total']), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: p.text)),
                ),
                const SizedBox(height: 4),
                Text('${items == 1 ? '1 item' : '$items items'} · ${paymentName(_o['payment_method'])}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.label)),
              ]),
            ),
            const SizedBox(width: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(a), child: c)),
              child: StatusPill(
                orderStatusLabel[_status] ?? _status,
                key: ValueKey(_status),
                tone: orderStatusTone(_status),
                icon: orderStatusIcon(_status),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          OrderPipeline(status: _status),
          if (_multi) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: p.infoBg, borderRadius: BorderRadius.circular(8)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 16, color: p.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This order includes items from other stores, so its status can\'t be changed here. '
                    'The buyer\'s full total across all stores is ${_m(_o['order_total'])}.',
                    style: TextStyle(fontSize: 12, color: p.text, height: 1.35),
                  ),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  // ── Sections ───────────────────────────────────────────────────────

  Widget _section(MarketPalette p, String title, List<Widget> children, {Widget? trailing}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title, trailing: trailing),
          MarketCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), child: Column(children: children)),
        ],
      );

  Widget _contact(MarketPalette p, IconData icon, String? value, {String? copyAs, String empty = '—'}) {
    final has = value != null;
    return InkWell(
      onTap: value != null && copyAs != null ? () => _copy(value, copyAs) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Icon(icon, size: 18, color: p.label),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value ?? empty,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: has ? p.text : p.label)),
          ),
          if (has && copyAs != null) Icon(Icons.copy_outlined, size: 16, color: p.brand),
        ]),
      ),
    );
  }

  Widget _customer(MarketPalette p) {
    final b = asMap(_o['buyer']);
    final account = str(b['account_name']);
    return _section(p, 'Customer', [
      _contact(p, Icons.person_outline, str(b['name'])),
      _contact(p, Icons.phone_outlined, str(b['phone']), copyAs: 'Phone'),
      _contact(p, Icons.mail_outline, str(b['email']), copyAs: 'Email'),
      if (account != null && account != str(b['name']))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Account name: $account', style: TextStyle(fontSize: 12, color: p.label)),
          ),
        ),
    ]);
  }

  Widget _delivery(MarketPalette p) {
    final d = asMap(_o['delivery']);
    final line = deliveryLine(d);
    final note = str(d['note']);
    final name = str(d['name']);
    final phone = str(d['phone']);
    final full = [name, phone, line.isEmpty ? null : line].whereType<String>().join('\n');
    return _section(
      p,
      'Delivery address',
      [
        if (line.isEmpty && name == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('No delivery address on this order.', style: TextStyle(fontSize: 13, color: p.label)),
            ),
          )
        else ...[
          if (name != null) _contact(p, Icons.badge_outlined, name),
          if (phone != null) _contact(p, Icons.phone_outlined, phone, copyAs: 'Phone'),
          if (line.isNotEmpty) _contact(p, Icons.place_outlined, line),
        ],
        if (note != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 2, bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8)),
            child: Text('Note: $note', style: TextStyle(fontSize: 12.5, color: p.text, height: 1.35)),
          ),
      ],
      trailing: full.isEmpty
          ? null
          : TextButton.icon(
              onPressed: () => _copy(full, 'Address'),
              icon: const Icon(Icons.copy_outlined, size: 16),
              label: const Text('Copy'),
            ),
    );
  }

  Widget _payment(MarketPalette p) {
    final ref = str(_o['payment_reference']);
    final coupon = str(_o['coupon_code']);
    final discount = toDouble(_o['seller_discount']);
    return _section(p, 'Payment', [
      InfoRow('Method', paymentName(_o['payment_method'])),
      if (ref != null)
        InkWell(onTap: () => _copy(ref, 'Transaction id'), child: InfoRow('Transaction id', ref))
      else
        const InfoRow('Transaction id', '—'),
      InfoRow('Coupon code', coupon ?? '—'),
      InfoRow('Discount', discount > 0 ? '−${_m(discount)}' : '—'),
    ]);
  }

  Widget _items(MarketPalette p) {
    final items = (_o['items'] is List ? _o['items'] as List : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final discount = toDouble(_o['seller_discount']);
    final subtotal = items.fold<double>(0, (s, i) => s + toDouble(i['line_total']));
    final coupon = str(_o['coupon_code']);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Items from your store'),
      MarketCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.line),
            _itemRow(p, items[i]),
          ],
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('No items from your store.', style: TextStyle(fontSize: 13, color: p.label)),
            ),
          Container(
            decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.line))),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Column(children: [
              InfoRow('Subtotal', _m(subtotal)),
              if (discount > 0) InfoRow(coupon != null ? 'Discount ($coupon)' : 'Discount', '−${_m(discount)}'),
              InfoRow('Your total', _m(_o['seller_total']), emphasize: true),
              if (_multi) InfoRow('Order total (all stores)', _m(_o['order_total'])),
            ]),
          ),
        ]),
      ),
    ]);
  }

  Widget _itemRow(MarketPalette p, Map<String, dynamic> it) {
    final price = toDouble(it['price']);
    final original = it['original_price'] == null ? null : toDouble(it['original_price']);
    final onSale = original != null && original > price;
    final qty = toInt(it['quantity']);
    final lineDiscount = toDouble(it['discount']);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.shopping_bag_outlined, size: 18, color: p.label),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(str(it['title']) ?? 'Item', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
            if (str(it['variant_label']) != null) ...[
              const SizedBox(height: 1),
              Text(str(it['variant_label'])!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
            ],
            const SizedBox(height: 3),
            Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${_m(price)} × $qty', style: TextStyle(fontSize: 12.5, color: p.label)),
              if (onSale)
                Text(_m(original), style: TextStyle(fontSize: 11.5, color: p.label, decoration: TextDecoration.lineThrough)),
            ]),
            if (lineDiscount > 0) ...[
              const SizedBox(height: 2),
              Text('−${_m(lineDiscount)} promo', style: TextStyle(fontSize: 11.5, color: p.ok, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        Text(_m(it['line_total']), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
      ]),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────

  Widget _actionBar(MarketPalette p, ({String status, String label, IconData icon})? next, bool canCancel) {
    final disabled = _multi || _busy != null;
    Widget spinner(Color c) => SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c));
    return Container(
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            if (canCancel)
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.error,
                    side: BorderSide(color: disabled ? p.line : p.error.withValues(alpha: 0.6)),
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: disabled ? null : () => _setStatus('cancelled'),
                  child: _busy == 'cancelled' ? spinner(p.error) : const Text('Cancel', maxLines: 1),
                ),
              ),
            if (canCancel && next != null) const SizedBox(width: 10),
            if (next != null)
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: disabled ? null : () => _setStatus(next.status),
                  icon: _busy == next.status ? spinner(Colors.white) : Icon(next.icon, size: 18),
                  label: Text(next.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
