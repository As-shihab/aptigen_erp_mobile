import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/market_seller_service.dart';
import '../orders/order_common.dart';
import '../widgets/market_ui.dart';
import 'refund_common.dart';

/// Opens the refund detail sheet; resolves with a confirmation message when
/// the refund was approved / rejected / refunded so the list can reload.
Future<String?> showRefundDetailSheet(BuildContext context, {required Map<String, dynamic> refund, required MarketSellerService service}) =>
    showMarketSheet<String>(context, builder: (_) => _RefundDetailSheet(refund: refund, service: service));

class _RefundDetailSheet extends StatefulWidget {
  final Map<String, dynamic> refund;
  final MarketSellerService service;
  const _RefundDetailSheet({required this.refund, required this.service});

  @override
  State<_RefundDetailSheet> createState() => _RefundDetailSheetState();
}

class _RefundDetailSheetState extends State<_RefundDetailSheet> {
  late final Map<String, dynamic> r = widget.refund;
  late final _note = TextEditingController(text: str(r['seller_note']) ?? '');
  late String _method = str(r['method']) ?? 'original';
  bool _restock = true;
  String? _busy;
  bool _noteError = false;

  String get _status => '${r['status']}';
  List<String> get _next => refundTransitions[_status] ?? const [];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _act(String status) async {
    final note = _note.text.trim();
    if (status == 'rejected' && note.isEmpty) {
      setState(() => _noteError = true);
      marketToast(context, 'Add a note telling the buyer why the refund is rejected', error: true);
      return;
    }
    if (status == 'rejected') {
      final ok = await confirmMarket(context, title: 'Reject refund', message: 'Reject this refund request? The buyer will see your note.', confirm: 'Reject');
      if (!ok || !mounted) return;
    }
    setState(() => _busy = status);
    try {
      await widget.service.resolveRefund(
        toInt(r['id']),
        status: status,
        sellerNote: note.isEmpty ? null : note,
        method: status == 'rejected' ? null : _method,
        restock: status == 'refunded' && _restock,
      );
      if (!mounted) return;
      Navigator.of(context).pop(status == 'approved' ? 'Refund approved' : status == 'rejected' ? 'Refund rejected' : 'Marked as refunded');
      return;
    } catch (e) {
      if (mounted) marketToast(context, errorText(e, 'Could not update the refund'), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final order = asMap(r['order']);
    final item = asMap(r['order_item']);
    final phone = refundBuyerPhone(r);
    final email = refundBuyerEmail(r);
    final reason = str(r['reason']);
    final sellerNote = str(r['seller_note']);
    final next = _next;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Center(
            child: Container(width: 36, height: 4, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Refund for order ${str(order['order_no']) ?? '#${r['order_id']}'}',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
                const SizedBox(height: 3),
                Text('Requested ${fmtDateTime(r['created_at'])}', style: TextStyle(fontSize: 12, color: p.label)),
                if (r['resolved_at'] != null)
                  Text('Resolved ${fmtDateTime(r['resolved_at'])}', style: TextStyle(fontSize: 12, color: p.label)),
              ]),
            ),
            const SizedBox(width: 8),
            StatusPill(refundStatusLabel[_status] ?? _status, tone: refundStatusTone(_status)),
          ]),
          const SizedBox(height: 14),
          // Amount header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(str(item['title']) ?? 'Item',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                  const SizedBox(height: 3),
                  Text('${toInt(r['quantity'])} × ${money(toDouble(item['price']))}', style: TextStyle(fontSize: 12.5, color: p.label)),
                ]),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Refund', style: TextStyle(fontSize: 11.5, color: p.label)),
                Text(money(toDouble(r['amount'])), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
              ]),
            ]),
          ),
          const SectionHeader('Buyer'),
          _contact(p, Icons.person_outline, refundBuyerName(r)),
          _contact(p, Icons.phone_outlined, phone, copyAs: 'Phone'),
          _contact(p, Icons.mail_outline, email, copyAs: 'Email'),
          const SectionHeader('Order payment'),
          InfoRow('Method', paymentName(order['payment_method'])),
          InfoRow('Reference', str(order['payment_reference']) ?? '—'),
          InfoRow('Ordered', fmtDateTime(order['created_at'])),
          const SectionHeader('Reason'),
          Text(reason ?? 'No reason given.', style: TextStyle(fontSize: 13.5, color: reason == null ? p.label : p.text, height: 1.4)),
          if (r['method'] != null) ...[
            const SizedBox(height: 8),
            Text('Refund method: ${refundMethodLabel(str(r['method']))}', style: TextStyle(fontSize: 12, color: p.label)),
          ],
          if (_status == 'refunded') ...[
            const SizedBox(height: 4),
            Text(r['restocked'] == true ? 'Items returned to stock' : 'Items not returned to stock', style: TextStyle(fontSize: 12, color: p.label)),
          ],
          if (next.isEmpty && sellerNote != null) ...[
            const SectionHeader('Your note'),
            Text(sellerNote, style: TextStyle(fontSize: 13.5, color: p.text, height: 1.4)),
          ],
          if (next.isNotEmpty) ..._resolveForm(p, next),
        ]),
      ),
    );
  }

  Widget _contact(MarketPalette p, IconData icon, String? value, {String? copyAs}) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: value != null && copyAs != null
            ? () {
                Clipboard.setData(ClipboardData(text: value));
                marketToast(context, '$copyAs copied');
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Icon(icon, size: 18, color: p.label),
            const SizedBox(width: 12),
            Expanded(
              child: Text(value ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: value == null ? p.label : p.text)),
            ),
            if (value != null && copyAs != null) Icon(Icons.copy_outlined, size: 16, color: p.brand),
          ]),
        ),
      );

  List<Widget> _resolveForm(MarketPalette p, List<String> next) {
    final busy = _busy != null;
    Widget spinner(Color c) => SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c));
    final primary = next.contains('approved') ? 'approved' : 'refunded';
    return [
      const SectionHeader('Resolve'),
      Text('Refund method', style: TextStyle(fontSize: 12.5, color: p.label)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in refundMethods)
          ChoiceChip(
            label: Text(m.$2),
            selected: _method == m.$1,
            onSelected: busy ? null : (_) => setState(() => _method = m.$1),
            showCheckmark: false,
            labelStyle: TextStyle(fontSize: 12.5, color: _method == m.$1 ? p.brand : p.text, fontWeight: _method == m.$1 ? FontWeight.w600 : FontWeight.w500),
            selectedColor: p.brandSoft,
            backgroundColor: p.card,
            side: BorderSide(color: _method == m.$1 ? p.brand : p.line),
          ),
      ]),
      if (next.contains('refunded')) ...[
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _restock,
          onChanged: busy ? null : (v) => setState(() => _restock = v),
          title: Text('Return items to stock', style: TextStyle(fontSize: 13.5, color: p.text)),
          subtitle: Text('Applies when you mark it refunded', style: TextStyle(fontSize: 12, color: p.label)),
        ),
      ],
      const SizedBox(height: 8),
      TextField(
        controller: _note,
        maxLines: 3,
        maxLength: 1000,
        enabled: !busy,
        onChanged: (_) {
          if (_noteError) setState(() => _noteError = false);
        },
        style: TextStyle(fontSize: 13.5, color: p.text),
        decoration: InputDecoration(
          labelText: 'Note to buyer',
          hintText: 'Optional for approvals, required when rejecting',
          errorText: _noteError ? 'A note is required when rejecting' : null,
          alignLabelWithHint: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
        onPressed: busy ? null : () => _act(primary),
        icon: _busy == primary ? spinner(Colors.white) : Icon(primary == 'approved' ? Icons.check : Icons.payments_outlined, size: 18),
        label: Text(primary == 'approved' ? 'Approve' : 'Mark refunded'),
      ),
      if (primary == 'approved' && next.contains('refunded')) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          onPressed: busy ? null : () => _act('refunded'),
          icon: _busy == 'refunded' ? spinner(p.brand) : const Icon(Icons.payments_outlined, size: 18),
          label: const Text('Mark refunded'),
        ),
      ],
      if (next.contains('rejected')) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: p.error,
            side: BorderSide(color: busy ? p.line : p.error.withValues(alpha: 0.6)),
            minimumSize: const Size.fromHeight(46),
          ),
          onPressed: busy ? null : () => _act('rejected'),
          icon: _busy == 'rejected' ? spinner(p.error) : const Icon(Icons.block, size: 18),
          label: const Text('Reject'),
        ),
      ],
    ];
  }
}
