import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../data/market_seller_service.dart';
import 'promotions/promotion_card.dart';
import 'promotions/promotion_detail_sheet.dart';
import 'promotions/promotion_editor_page.dart';
import 'promotions/promotion_utils.dart';
import 'widgets/market_ui.dart';

/// Promotions — coupon codes and automatic discounts on the seller's
/// listings (desktop Sell → Online → Market → Promotions; OData
/// market_promotions + market_promotion_redemptions).
class MarketPromotionsPage extends StatefulWidget {
  const MarketPromotionsPage({super.key});

  @override
  State<MarketPromotionsPage> createState() => _MarketPromotionsPageState();
}

class _MarketPromotionsPageState extends State<MarketPromotionsPage> {
  final _api = MarketSellerService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';
  final Set<int> _toggling = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      if (_items.isEmpty) _loading = true;
    });
    try {
      final list = await _api.promotions();
      if (mounted) setState(() => _items = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load promotions');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// PUT the whole row with is_active flipped (minus read-only / system
  /// fields — used_count is never sent).
  Future<void> _toggle(Map<String, dynamic> pr, bool on) async {
    final id = toInt(pr['id']);
    const skip = {'id', 'used_count', 'workplace_id', 'created_at', 'updated_at'};
    final body = <String, dynamic>{
      for (final e in pr.entries)
        if (!skip.contains(e.key) && e.value is! Map && e.value is! List) e.key: e.value,
      'is_active': on,
    };
    setState(() {
      _toggling.add(id);
      pr['is_active'] = on;
    });
    try {
      await _api.savePromotion(body, id: id);
      if (mounted) marketToast(context, on ? 'Promotion turned on' : 'Promotion turned off');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => pr['is_active'] = !on);
      marketToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _toggling.remove(id));
    }
  }

  Future<void> _edit([Map<String, dynamic>? pr]) async {
    final changed = await Navigator.of(context).push<bool>(marketRoute(PromotionEditorPage(promotion: pr)));
    if (changed == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> pr) async {
    final ok = await confirmMarket(context, title: 'Delete promotion', message: 'Delete "${pr['name'] ?? ''}"? Past orders keep their discount.');
    if (!ok || !mounted) return;
    try {
      await _api.deletePromotion(toInt(pr['id']));
      if (!mounted) return;
      marketToast(context, 'Promotion deleted');
      _load();
    } on ApiException catch (e) {
      if (mounted) marketToast(context, e.message, error: true);
    }
  }

  Future<void> _openDetail(Map<String, dynamic> pr) async {
    final action = await showPromotionDetail(context, pr, api: _api);
    if (!mounted) return;
    if (action == 'edit') _edit(pr);
    if (action == 'delete') _delete(pr);
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final coupons = _items.where(isCoupon).length;
    final visible = switch (_filter) {
      'coupon' => _items.where(isCoupon).toList(),
      'automatic' => _items.where((e) => !isCoupon(e)).toList(),
      _ => _items,
    };

    Widget body;
    if (_loading) {
      body = const SkeletonList(key: ValueKey('loading'), count: 5, itemHeight: 150);
    } else if (_error != null && _items.isEmpty) {
      body = ListView(key: const ValueKey('error'), children: [
        MarketEmpty(icon: Icons.cloud_off_outlined, title: 'Could not load promotions', message: _error, actionLabel: 'Try again', onAction: _load),
      ]);
    } else {
      body = ListView(
        key: const ValueKey('list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          MarketSegmented<String>(
            value: _filter,
            onChanged: (v) => setState(() => _filter = v),
            options: [
              (id: 'all', label: 'All', count: _items.length),
              (id: 'coupon', label: 'Coupon codes', count: coupons),
              (id: 'automatic', label: 'Automatic', count: _items.length - coupons),
            ],
          ),
          const SizedBox(height: 8),
          Text('Buyers get the single best offer from your store: an automatic discount or the coupon they enter.',
              style: TextStyle(fontSize: 12, color: p.label, height: 1.4)),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: visible.isEmpty
                ? MarketEmpty(
                    key: ValueKey('empty-$_filter'),
                    icon: Icons.confirmation_number_outlined,
                    title: _items.isEmpty ? 'No promotions yet' : 'Nothing here',
                    message: _items.isEmpty
                        ? 'Create a coupon code or an automatic discount for your listings.'
                        : _filter == 'coupon'
                            ? 'You have no coupon codes.'
                            : 'You have no automatic discounts.',
                    actionLabel: _items.isEmpty ? 'New promotion' : null,
                    onAction: _items.isEmpty ? () => _edit() : null,
                  )
                : Column(
                    key: ValueKey('list-$_filter'),
                    children: [
                      for (var i = 0; i < visible.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: FadeSlideIn(
                            index: i,
                            child: PromotionCard(
                              promotion: visible[i],
                              toggling: _toggling.contains(toInt(visible[i]['id'])),
                              onTap: () => _openDetail(visible[i]),
                              onToggle: (v) => _toggle(visible[i], v),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      );
    }

    return MarketScaffold(
      title: 'Promotions',
      subtitle: 'Coupon codes and automatic discounts',
      actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load)],
      fab: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('New promotion')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: body),
      ),
    );
  }
}
