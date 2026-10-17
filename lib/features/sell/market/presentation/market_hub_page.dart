import 'package:flutter/material.dart';
import '../data/market_seller_service.dart';
import 'banners_page.dart';
import 'flash_sales_page.dart';
import 'gateways_page.dart';
import 'listings_page.dart';
import 'orders_page.dart';
import 'promotions_page.dart';
import 'refunds_page.dart';
import 'reviews_page.dart';
import 'storefront_page.dart';
import 'widgets/market_ui.dart';

/// Sell → Online market: the seller's overview (live KPIs, what needs
/// attention) and the entry point to every market screen — mirrors
/// erp/desktop's Sell → Online → Market navigation.
class MarketHubPage extends StatefulWidget {
  const MarketHubPage({super.key});

  @override
  State<MarketHubPage> createState() => _MarketHubPageState();
}

class _Overview {
  int listings = 0;
  int activeListings = 0;
  int pendingApproval = 0;
  double views = 0;
  double orders = 0;
  double revenue = 0;
  int pendingOrders = 0;
  int toShip = 0;
  int openRefunds = 0;
  int unreplied = 0;
  int liveSales = 0;
  String? storeName;
}

class _MarketHubPageState extends State<MarketHubPage> {
  final _api = MarketSellerService();
  _Overview? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    // Each part is independent — one failing endpoint never blanks the rest.
    Future<T?> safe<T>(Future<T> f) => f.then<T?>((v) => v).catchError((_) => null);
    final results = await Future.wait([
      safe(_api.listings(top: 200)),
      safe(_api.listingStats(from: _ymd(DateTime.now().subtract(const Duration(days: 29))), to: _ymd(DateTime.now()))),
      safe(_api.sellerOrders()),
      safe(_api.refunds(status: 'requested')),
      safe(_api.reviews()),
      safe(_api.flashSales()),
      safe(_api.storefront()),
    ]);
    if (!mounted) return;
    if (results.every((r) => r == null)) {
      setState(() => _error = 'Could not load the market overview. Check your connection and try again.');
      return;
    }
    final o = _Overview();
    final listings = (results[0] as List<Map<String, dynamic>>?) ?? const [];
    o.listings = listings.length;
    o.activeListings = listings.where((l) => l['status'] == 'active' && l['approval_status'] == 'approved').length;
    o.pendingApproval = listings.where((l) => l['approval_status'] == 'pending').length;
    for (final s in (results[1] as List<Map<String, dynamic>>?) ?? const []) {
      o.views += toDouble(s['views']);
      o.orders += toDouble(s['orders']);
      o.revenue += toDouble(s['revenue']);
    }
    final orders = (results[2] as List<Map<String, dynamic>>?) ?? const [];
    o.pendingOrders = orders.where((x) => x['status'] == 'pending').length;
    o.toShip = orders.where((x) => x['status'] == 'paid' || x['status'] == 'packaged').length;
    o.openRefunds = ((results[3] as List?) ?? const []).length;
    o.unreplied = ((results[4] as List<Map<String, dynamic>>?) ?? const []).where((r) => (r['seller_reply'] ?? '').toString().isEmpty).length;
    o.liveSales = ((results[5] as List<Map<String, dynamic>>?) ?? const []).where((s) => s['state'] == 'live').length;
    o.storeName = (results[6] as Map<String, dynamic>?)?['store_name']?.toString();
    setState(() => _data = o);
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(marketRoute(page));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final d = _data;
    return MarketScaffold(
      title: 'Online market',
      subtitle: d?.storeName?.isNotEmpty == true ? d!.storeName : 'Sell on the Aptigen market',
      actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh))],
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null && d == null
            ? ListView(children: [MarketEmpty(icon: Icons.cloud_off_outlined, title: 'Overview unavailable', message: _error, actionLabel: 'Try again', onAction: _load)])
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  const SectionHeader('Last 30 days'),
                  _kpiGrid(d),
                  if (d != null && (d.pendingOrders + d.toShip + d.openRefunds + d.unreplied + d.pendingApproval) > 0) ...[
                    const SectionHeader('Needs your attention'),
                    FadeSlideIn(
                      index: 1,
                      child: MarketCard(
                        padding: EdgeInsets.zero,
                        child: Column(children: [
                          if (d.pendingOrders > 0)
                            _attention(Icons.inbox_outlined, '${d.pendingOrders} new order${d.pendingOrders == 1 ? '' : 's'} to accept', MarketTone.warn, () => _open(const MarketOrdersPage())),
                          if (d.toShip > 0)
                            _attention(Icons.local_shipping_outlined, '${d.toShip} order${d.toShip == 1 ? '' : 's'} to pack or deliver', MarketTone.info, () => _open(const MarketOrdersPage())),
                          if (d.openRefunds > 0)
                            _attention(Icons.assignment_return_outlined, '${d.openRefunds} refund request${d.openRefunds == 1 ? '' : 's'}', MarketTone.error, () => _open(const MarketRefundsPage())),
                          if (d.unreplied > 0)
                            _attention(Icons.rate_review_outlined, '${d.unreplied} review${d.unreplied == 1 ? '' : 's'} waiting for a reply', MarketTone.brand, () => _open(const MarketReviewsPage())),
                          if (d.pendingApproval > 0)
                            _attention(Icons.hourglass_top_outlined, '${d.pendingApproval} listing${d.pendingApproval == 1 ? '' : 's'} awaiting approval', MarketTone.neutral, () => _open(const MarketListingsPage())),
                        ]),
                      ),
                    ),
                  ],
                  const SectionHeader('Manage'),
                  _tiles(p, d),
                ],
              ),
      ),
    );
  }

  Widget _kpiGrid(_Overview? d) {
    if (d == null) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.3,
        children: List.generate(4, (_) => const SkeletonBox(height: 60, radius: 12)),
      );
    }
    final tiles = [
      KpiTile(icon: Icons.storefront_outlined, label: 'Live listings', value: d.activeListings, sub: 'of ${d.listings}', onTap: () => _open(const MarketListingsPage())),
      KpiTile(icon: Icons.visibility_outlined, label: 'Views', value: d.views, tone: MarketTone.info),
      KpiTile(icon: Icons.shopping_bag_outlined, label: 'Orders', value: d.orders, tone: MarketTone.ok, onTap: () => _open(const MarketOrdersPage())),
      KpiTile(icon: Icons.payments_outlined, label: 'Revenue', value: d.revenue, format: (v) => money(v), tone: MarketTone.warn),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.3,
      children: [for (var i = 0; i < tiles.length; i++) FadeSlideIn(index: i, child: tiles[i])],
    );
  }

  Widget _attention(IconData icon, String text, MarketTone tone, VoidCallback onTap) {
    final p = MarketPalette.of(context);
    final c = p.tone(tone);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: c.fg),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text))),
          Icon(Icons.chevron_right, color: p.label),
        ]),
      ),
    );
  }

  Widget _tiles(MarketPalette p, _Overview? d) {
    final items = <({IconData icon, String title, String sub, MarketTone tone, Widget page, int? badge})>[
      (icon: Icons.inventory_2_outlined, title: 'Listings', sub: 'Products on the market', tone: MarketTone.brand, page: const MarketListingsPage(), badge: null),
      (icon: Icons.receipt_long_outlined, title: 'Website orders', sub: 'Accept, pack, deliver', tone: MarketTone.ok, page: const MarketOrdersPage(), badge: d?.pendingOrders),
      (icon: Icons.bolt_outlined, title: 'Flash sales', sub: d != null && d.liveSales > 0 ? '${d.liveSales} live now' : 'Time-boxed prices', tone: MarketTone.error, page: const MarketFlashSalesPage(), badge: null),
      (icon: Icons.local_offer_outlined, title: 'Promotions', sub: 'Coupons and discounts', tone: MarketTone.warn, page: const MarketPromotionsPage(), badge: null),
      (icon: Icons.reviews_outlined, title: 'Reviews', sub: 'Ratings and replies', tone: MarketTone.info, page: const MarketReviewsPage(), badge: d?.unreplied),
      (icon: Icons.assignment_return_outlined, title: 'Refunds', sub: 'Buyer requests', tone: MarketTone.error, page: const MarketRefundsPage(), badge: d?.openRefunds),
      (icon: Icons.account_balance_wallet_outlined, title: 'Payment methods', sub: 'What you accept', tone: MarketTone.ok, page: const MarketGatewaysPage(), badge: null),
      (icon: Icons.view_carousel_outlined, title: 'Banners', sub: 'Homepage promotions', tone: MarketTone.brand, page: const MarketBannersPage(), badge: null),
      (icon: Icons.store_mall_directory_outlined, title: 'Storefront', sub: 'Your public store', tone: MarketTone.neutral, page: const MarketStorefrontPage(), badge: null),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 640 ? 3 : 2;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 112),
        itemBuilder: (_, i) {
          final it = items[i];
          final tone = p.tone(it.tone);
          return FadeSlideIn(
            index: i + 4,
            child: MarketCard(
              onTap: () => _open(it.page),
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(9)),
                    child: Icon(it.icon, size: 18, color: tone.fg),
                  ),
                  const Spacer(),
                  if ((it.badge ?? 0) > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: p.errorBg, borderRadius: BorderRadius.circular(10)),
                      child: Text('${it.badge}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.error)),
                    ),
                ]),
                const Spacer(),
                Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
                const SizedBox(height: 2),
                Text(it.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
              ]),
            ),
          );
        },
      );
    });
  }
}
