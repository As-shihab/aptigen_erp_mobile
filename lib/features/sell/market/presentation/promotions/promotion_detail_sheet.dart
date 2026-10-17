import 'package:flutter/material.dart';
import '../../../../../core/network/http_client.dart';
import '../../data/market_seller_service.dart';
import '../flash_sales/flash_sale_widgets.dart';
import '../widgets/market_ui.dart';
import 'promotion_card.dart';
import 'promotion_utils.dart';

/// Object-header style detail for one promotion with its redemptions.
/// Resolves to 'edit' or 'delete' when the seller picks an action.
Future<String?> showPromotionDetail(BuildContext context, Map<String, dynamic> promotion, {MarketSellerService? api}) =>
    showMarketSheet<String>(context, builder: (_) => _PromotionDetail(promotion: promotion, api: api ?? MarketSellerService()));

class _PromotionDetail extends StatefulWidget {
  final Map<String, dynamic> promotion;
  final MarketSellerService api;
  const _PromotionDetail({required this.promotion, required this.api});

  @override
  State<_PromotionDetail> createState() => _PromotionDetailState();
}

class _PromotionDetailState extends State<_PromotionDetail> {
  List<Map<String, dynamic>>? _redemptions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.redemptions(toInt(widget.promotion['id']));
      if (mounted) setState(() => _redemptions = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load redemptions');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final pr = widget.promotion;
    final status = promotionStatus(pr, DateTime.now());
    final used = toInt(pr['used_count']);
    final limit = pr['usage_limit'] == null ? null : toInt(pr['usage_limit']);
    final ids = parseListingIds(pr['listing_ids']);
    final totalDiscount = (_redemptions ?? const []).fold<double>(0, (a, r) => a + toDouble(r['discount']));
    final desc = '${pr['description'] ?? ''}'.trim();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(children: [
        const SizedBox(height: 8),
        Container(width: 36, height: 4, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2))),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(10)),
                child: Icon(isCoupon(pr) ? Icons.confirmation_number_outlined : Icons.auto_awesome_outlined, color: p.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${pr['name'] ?? 'Promotion'}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [PromoCodeChip(pr), StatusPill(status.label, tone: status.tone)]),
                ]),
              ),
            ]),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(desc, style: TextStyle(fontSize: 13, color: p.label, height: 1.4)),
            ],
            const SizedBox(height: 16),
            FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Expanded(child: MiniStat('Redeemed', limit == null ? '$used' : '$used / $limit')),
                  Expanded(child: MiniStat('Discount given', _redemptions == null ? '…' : money(totalDiscount))),
                ]),
              ),
            ),
            if (limit != null && limit > 0) ...[
              const SizedBox(height: 8),
              MarketProgress(value: used / limit, tone: used >= limit ? MarketTone.warn : MarketTone.brand),
            ],
            const SizedBox(height: 12),
            InfoRow('Discount', discountLabel(pr), emphasize: true),
            InfoRow('Min order', toDouble(pr['min_order']) > 0 ? money(toDouble(pr['min_order'])) : 'None'),
            InfoRow('Applies to', pr['applies_to'] == 'listings' ? '${ids.length} selected listing${ids.length == 1 ? '' : 's'}' : 'All listings'),
            InfoRow('Usage limit', limit == null ? 'Unlimited' : '$limit'),
            InfoRow('Per customer', pr['per_user_limit'] == null ? 'Unlimited' : '${toInt(pr['per_user_limit'])}'),
            InfoRow('Window', fmtWindow(parseDate(pr['starts_at']), parseDate(pr['ends_at']))),
            const SectionHeader('Redemptions'),
            AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: _redemptionList(p)),
          ]),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: p.error),
                  onPressed: () => Navigator.pop(context, 'delete'),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, 'edit'),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _redemptionList(MarketPalette p) {
    if (_error != null) {
      return Padding(
        key: const ValueKey('err'),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(_error!, style: TextStyle(fontSize: 13, color: p.error)),
      );
    }
    if (_redemptions == null) {
      return Column(key: const ValueKey('load'), children: [
        for (var i = 0; i < 3; i++) const Padding(padding: EdgeInsets.only(bottom: 8), child: SkeletonBox(height: 52, radius: 10)),
      ]);
    }
    if (_redemptions!.isEmpty) {
      return const MarketEmpty(key: ValueKey('empty'), icon: Icons.receipt_long_outlined, title: 'Not redeemed yet', message: 'Orders that use this promotion show up here.');
    }
    return Column(key: const ValueKey('list'), children: [
      for (var i = 0; i < _redemptions!.length; i++)
        FadeSlideIn(
          index: i,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_orderNo(_redemptions![i]),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if ('${_redemptions![i]['code'] ?? ''}'.isNotEmpty) '${_redemptions![i]['code']}',
                      fmtDateTime(parseDate(_redemptions![i]['created_at'])),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.label),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Text('-${money(toDouble(_redemptions![i]['discount']))}', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.ok)),
            ]),
          ),
        ),
    ]);
  }

  String _orderNo(Map<String, dynamic> r) {
    final o = r['order'];
    final no = o is Map ? '${o['order_no'] ?? ''}' : '';
    return no.isNotEmpty ? no : 'Order #${r['order_id'] ?? '—'}';
  }
}
