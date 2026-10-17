import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../data/sales_order_model.dart';
import '../data/sales_order_service.dart';
import '../data/sell_analytics_service.dart';
import '../market/presentation/market_hub_page.dart';
import 'client_form_page.dart';
import 'clients_list_page.dart';
import 'configs/sell_entity_configs.dart';
import 'held_bills_list_page.dart';
import 'payments_list_page.dart';
import 'pos/pos_terminal_page.dart';
import 'sales_order_detail_page.dart';
import 'sales_order_list_page.dart';
import 'sales_report_page.dart';
import 'sell_analytics_page.dart';
import 'sell_products_page.dart';
import 'sell_settings_page.dart';
import 'widgets/sell_ui.dart';
import '../../store/presentation/widgets/field_spec.dart';

/// Sales module home — today's numbers, quick actions, recent sales and every
/// Sales area (same set as desktop's sell.layout.tsx nav) in one place.
class SalesHubPage extends StatefulWidget {
  const SalesHubPage({super.key});

  @override
  State<SalesHubPage> createState() => _SalesHubPageState();
}

class _SalesHubPageState extends State<SalesHubPage> {
  final _analytics = SellAnalyticsService(ApiClient());
  final _orders = SalesOrderService(ApiClient());

  bool _loading = true;
  SellAnalyticsSnapshot? _today;
  SellAnalyticsSnapshot? _month;
  List<SalesOrder> _recent = [];
  int _heldCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Independent reads — fire together, tolerate any one failing.
    final results = await Future.wait<Object?>([
      _analytics.load(start: today, end: today).then<Object?>((v) => v).catchError((_) => null),
      _analytics.load(start: today.subtract(const Duration(days: 29)), end: today).then<Object?>((v) => v).catchError((_) => null),
      _orders.list(top: 6).then<Object?>((v) => v).catchError((_) => <SalesOrder>[]),
      _orders.list(statusFilter: 'PARKED', top: 200).then<Object?>((v) => v).catchError((_) => <SalesOrder>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _today = results[0] as SellAnalyticsSnapshot?;
      _month = results[1] as SellAnalyticsSnapshot?;
      _recent = (results[2] as List<SalesOrder>?) ?? [];
      _heldCount = ((results[3] as List<SalesOrder>?) ?? []).length;
      _loading = false;
    });
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(marketRoute(page));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketScaffold(
      title: 'Sales',
      subtitle: 'Point of sale, orders and clients',
      actions: [
        IconButton(tooltip: 'Sales settings', icon: const Icon(Icons.settings_outlined), onPressed: () => _open(const SellSettingsPage())),
      ],
      fab: FloatingActionButton.extended(
        onPressed: () => _open(const PosTerminalPage()),
        backgroundColor: p.brand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.point_of_sale_outlined),
        label: const Text('New sale'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            _todayCard(p),
            const SizedBox(height: 12),
            _kpis(),
            _quickActions(p),
            SectionHeader(
              'Recent sales',
              trailing: TextButton(onPressed: () => _open(const SalesOrderListPage(title: 'Sales orders')), child: const Text('See all')),
            ),
            _recentList(p),
            const SectionHeader('All sales areas'),
            _areas(p),
          ],
        ),
      ),
    );
  }

  Widget _todayCard(MarketPalette p) {
    final t = _today;
    return FadeSlideIn(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Today's revenue", style: TextStyle(color: Colors.white70, fontSize: 12.5)),
          const SizedBox(height: 6),
          _loading && t == null
              ? const SizedBox(height: 30, child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 120, child: LinearProgressIndicator(color: Colors.white, backgroundColor: Colors.white24))))
              : CountUp(
                  value: t?.totalRevenue ?? 0,
                  format: (v) => money(v),
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.1),
                ),
          const SizedBox(height: 12),
          Row(children: [
            _todayStat('Orders', '${t?.totalOrders ?? 0}'),
            _todayStat('Completed', '${t?.completedOrders ?? 0}'),
            _todayStat('Held', '$_heldCount'),
          ]),
        ]),
      ),
    );
  }

  Widget _todayStat(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
        ]),
      );

  Widget _kpis() {
    final m = _month;
    final tiles = [
      KpiTile(icon: Icons.trending_up, label: 'Revenue', sub: '30 days', value: m?.totalRevenue ?? 0, format: (v) => money(v), tone: MarketTone.ok,
          onTap: () => _open(const SellAnalyticsPage())),
      KpiTile(icon: Icons.receipt_long_outlined, label: 'Orders', sub: '30 days', value: m?.totalOrders ?? 0,
          onTap: () => _open(const SalesOrderListPage(title: 'Sales orders'))),
      KpiTile(icon: Icons.account_balance_wallet_outlined, label: 'Outstanding', value: m?.totalOutstanding ?? 0, format: (v) => money(v), tone: MarketTone.warn,
          onTap: () => _open(const PaymentsListPage())),
      KpiTile(icon: Icons.people_alt_outlined, label: 'Clients', value: m?.totalClients ?? 0, tone: MarketTone.info,
          onTap: () => _open(const ClientsListPage())),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.35,
      children: [for (var i = 0; i < tiles.length; i++) FadeSlideIn(index: i + 1, child: tiles[i])],
    );
  }

  Widget _quickActions(MarketPalette p) {
    final actions = [
      (Icons.point_of_sale_outlined, 'POS', () => _open(const PosTerminalPage())),
      (Icons.pause_circle_outline, 'Held bills', () => _open(const HeldBillsListPage())),
      (Icons.person_add_alt_1_outlined, 'Add client', () => _open(const ClientFormPage())),
      (Icons.bar_chart_outlined, 'Reports', () => _open(const SalesReportPage())),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(children: [
        for (final a in actions)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: a.$3,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: p.card, shape: BoxShape.circle, border: Border.all(color: p.line)),
                    child: Icon(a.$1, color: p.brand, size: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(a.$2, style: TextStyle(fontSize: 12, color: p.text, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _recentList(MarketPalette p) {
    if (_loading && _recent.isEmpty) {
      return Column(children: List.generate(3, (_) => const Padding(padding: EdgeInsets.only(bottom: 8), child: SkeletonBox(height: 58, radius: 12))));
    }
    if (_recent.isEmpty) {
      return MarketCard(
        child: Row(children: [
          Icon(Icons.receipt_long_outlined, color: p.label),
          const SizedBox(width: 10),
          Expanded(child: Text('No sales yet. Start one from the POS.', style: TextStyle(color: p.label, fontSize: 13))),
        ]),
      );
    }
    return MarketCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < _recent.length; i++) ...[
          if (i > 0) Divider(height: 1, color: p.line),
          _recentRow(p, _recent[i]),
        ],
      ]),
    );
  }

  Widget _recentRow(MarketPalette p, SalesOrder o) {
    final when = parseLocal(o.completedAt ?? o.createdAt);
    return InkWell(
      onTap: () => _open(SalesOrderDetailPage(saleId: o.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.clientName ?? 'Walk-in', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: p.text)),
              const SizedBox(height: 2),
              Text('${o.displayNo}${when == null ? '' : ' · ${dayLabel(when)}, ${timeLabel(when)}'}', style: TextStyle(fontSize: 11.5, color: p.label)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(money(o.total), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: p.text)),
            const SizedBox(height: 3),
            StatusPill(saleStatusLabel(o.status), tone: saleStatusTone(o.status)),
          ]),
        ]),
      ),
    );
  }

  // One accent per area so the list scans by colour — SAP-style accent set,
  // (light, dark) shades so icons stay readable in both themes.
  static const _accents = <(Color, Color)>[
    (Color(0xFF0A6ED1), Color(0xFF4DB1FF)), // blue
    (Color(0xFF188918), Color(0xFF5DC122)), // green
    (Color(0xFFD20A0A), Color(0xFFFF6A6A)), // red
    (Color(0xFF0E7490), Color(0xFF38BDF8)), // teal
    (Color(0xFFE76500), Color(0xFFFF8A3D)), // orange
    (Color(0xFF7858FF), Color(0xFFA78BFA)), // violet
    (Color(0xFF4F46E5), Color(0xFF818CF8)), // indigo
    (Color(0xFFDF1278), Color(0xFFF472B6)), // pink
    (Color(0xFF0891B2), Color(0xFF22D3EE)), // cyan
    (Color(0xFFB45309), Color(0xFFFBBF24)), // amber
    (Color(0xFF4D7C0F), Color(0xFFA3E635)), // olive
    (Color(0xFF5B738B), Color(0xFFA9B4BE)), // grey
  ];

  Widget _areas(MarketPalette p) {
    final areas = <(IconData, String, String, Widget Function())>[
      (Icons.receipt_long_outlined, 'Sales orders', 'Every sale, any status', () => const SalesOrderListPage(title: 'Sales orders')),
      (Icons.description_outlined, 'Invoices', 'Completed sales, print or void', () => const SalesOrderListPage(title: 'Invoices', statusFilter: 'COMPLETED')),
      (Icons.assignment_return_outlined, 'Returns', 'Refunded sales', () => const SalesOrderListPage(title: 'Sales returns', statusFilter: 'REFUNDED')),
      (Icons.payments_outlined, 'Payments', 'Collected and outstanding', () => const PaymentsListPage()),
      (Icons.pause_circle_outline, 'Held bills', 'Parked sales to resume', () => const HeldBillsListPage()),
      (Icons.inventory_2_outlined, 'Products', 'Sellable catalogue and stock', () => const SellProductsPage()),
      (Icons.people_alt_outlined, 'Clients', 'Customers and balances', () => const ClientsListPage()),
      (Icons.groups_outlined, 'Client groups', 'Group discounts and limits', () => SimpleEntityListPage(config: clientGroupsConfig())),
      (Icons.insights_outlined, 'Analytics', 'Trends, top products and clients', () => const SellAnalyticsPage()),
      (Icons.bar_chart_outlined, 'Reports', 'Daily and product sales', () => const SalesReportPage()),
      (Icons.storefront_outlined, 'Online market', 'Listings, orders and storefront', () => const MarketHubPage()),
      (Icons.settings_outlined, 'Settings', 'POS, receipt and tax defaults', () => const SellSettingsPage()),
    ];
    return MarketCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < areas.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 62, color: p.line),
          ListTile(
            onTap: () => _open(areas[i].$4()),
            leading: Builder(builder: (_) {
              final (light, dark) = _accents[i % _accents.length];
              final fg = p.dark ? dark : light;
              return Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: fg.withValues(alpha: p.dark ? 0.18 : 0.12), borderRadius: BorderRadius.circular(9)),
                child: Icon(areas[i].$1, size: 19, color: fg),
              );
            }),
            title: Text(areas[i].$2, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
            subtitle: Text(areas[i].$3, style: TextStyle(fontSize: 12, color: p.label)),
            trailing: Icon(Icons.chevron_right, color: p.label),
          ),
        ],
      ]),
    );
  }
}
