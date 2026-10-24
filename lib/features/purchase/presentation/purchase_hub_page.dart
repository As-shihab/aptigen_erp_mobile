import 'package:flutter/material.dart';
import '../../../core/utils/currency.dart';
import '../../../shared/ui/motion_kit.dart';
import '../../store/presentation/documents/mrr_return_list_page.dart';
import '../data/purchase_dashboard_service.dart';
import 'approvals/purchase_approvals_page.dart';
import 'comparative/comparative_study_page.dart';
import 'dashboard/purchase_dashboard_page.dart';
import 'orders/purchase_orders_page.dart';
import 'requisitions/purchase_requisitions_page.dart';
import 'rfq/rfqs_page.dart';
import 'settings/purchase_settings_page.dart';
import 'suppliers/supplier_groups_page.dart';
import 'suppliers/suppliers_page.dart';

/// Purchase home — mirrors desktop's purchase.layout.tsx nav (overview,
/// procurement in flow order, suppliers, settings) as a hub. Headline KPIs
/// come from the same batch as the dashboard; RFQ / comparative study and
/// returns follow purchase_settings, like desktop's sidebar.
class PurchaseHubPage extends StatefulWidget {
  const PurchaseHubPage({super.key});

  @override
  State<PurchaseHubPage> createState() => _PurchaseHubPageState();
}

class _PurchaseHubPageState extends State<PurchaseHubPage> {
  final _service = PurchaseDashboardService();
  PurchaseDashboardData? _data;
  bool _loading = true;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _service.load(withSettings: true);
      if (mounted) setState(() => _data = d);
    } catch (_) {
      // Headline numbers are a nicety — the hub still works without them.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _go(Widget page) => pushMotion(context, page).then((_) => _load());

  bool get _hasRfq => _data?.hasRfq ?? true;
  bool get _hasReturns => _data?.hasReturns ?? true;

  List<({String title, String? subtitle, List<HubTile> tiles})> get _sections {
    final d = _data;
    final pending = d?.pending ?? 0;
    return [
      (
        title: 'Overview',
        subtitle: null,
        tiles: [
          HubTile(icon: Icons.insights_rounded, label: 'Dashboard', caption: 'Spend and pipeline', accent: Accent.ocean, onTap: () => _go(const PurchaseDashboardPage())),
        ],
      ),
      (
        title: 'Procurement',
        subtitle: 'From requisition to purchase order',
        tiles: [
          HubTile(
            icon: Icons.shopping_cart_outlined,
            label: 'Purchase requisitions',
            caption: d == null ? null : '${d.openRequisitions} open',
            accent: Accent.indigo,
            onTap: () => _go(const PurchaseRequisitionsPage()),
          ),
          HubTile(
            icon: Icons.fact_check_outlined,
            label: 'Approvals',
            caption: 'Requisitions and orders',
            accent: Accent.amber,
            badge: pending > 0 ? '$pending' : null,
            onTap: () => _go(const PurchaseApprovalsPage()),
          ),
          if (_hasRfq) ...[
            HubTile(
              icon: Icons.request_quote_outlined,
              label: 'Requests for quotation',
              caption: d == null ? null : '${d.openRfqs} open',
              accent: Accent.sunset,
              onTap: () => _go(const RfqsPage()),
            ),
            HubTile(icon: Icons.compare_arrows_rounded, label: 'Comparative study', caption: 'Compare quotes', accent: Accent.violet, onTap: () => _go(const ComparativeStudyPage())),
          ],
          HubTile(
            icon: Icons.receipt_long_outlined,
            label: 'Purchase orders',
            caption: d == null ? null : '${d.orders.length} orders',
            accent: Accent.ocean,
            onTap: () => _go(const PurchaseOrdersPage()),
          ),
          if (_hasReturns)
            HubTile(
              icon: Icons.assignment_return_outlined,
              label: 'Purchase returns',
              caption: d == null ? null : '${d.openReturns} open',
              accent: Accent.rose,
              onTap: () => _go(const MrrReturnListPage()),
            ),
        ],
      ),
      (
        title: 'Suppliers',
        subtitle: null,
        tiles: [
          HubTile(
            icon: Icons.local_shipping_outlined,
            label: 'Supplier list',
            caption: d == null ? null : '${d.supplierCount} suppliers',
            accent: Accent.teal,
            onTap: () => _go(const SuppliersPage()),
          ),
          HubTile(icon: Icons.folder_outlined, label: 'Supplier group', accent: Accent.sky, onTap: () => _go(const SupplierGroupsPage())),
        ],
      ),
      (
        title: 'Setup',
        subtitle: null,
        tiles: [
          HubTile(icon: Icons.tune_rounded, label: 'Purchase settings', caption: 'Features and approvals', accent: Accent.slate, onTap: () => _go(const PurchaseSettingsPage())),
        ],
      ),
    ];
  }

  Widget _kpis() {
    final d = _data;
    if (d == null) {
      if (!_loading) return const SizedBox.shrink();
      return KpiStrip(children: [for (var i = 0; i < 4; i++) const SkeletonBox(height: 112, radius: 12)]);
    }
    return KpiStrip(children: [
      GradientKpi(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Committed spend',
        value: d.totalSpend,
        format: (v) => formatMoney(v, decimalDigits: 0),
        accent: Accent.ocean,
        onTap: () => _go(const PurchaseDashboardPage()),
      ),
      GradientKpi(
        icon: Icons.fact_check_outlined,
        label: 'Pending approval',
        value: d.pending,
        accent: d.pending > 0 ? Accent.amber : Accent.slate,
        onTap: () => _go(const PurchaseApprovalsPage()),
      ),
      GradientKpi(icon: Icons.local_shipping_outlined, label: 'Awaiting delivery', value: d.awaitingDelivery, accent: Accent.sky, onTap: () => _go(const PurchaseOrdersPage())),
      GradientKpi(
        icon: Icons.warning_amber_rounded,
        label: 'Overdue deliveries',
        value: d.overdue.length,
        accent: d.overdue.isEmpty ? Accent.emerald : Accent.rose,
        onTap: () => _go(const PurchaseDashboardPage()),
      ),
      if (_hasRfq) GradientKpi(icon: Icons.request_quote_outlined, label: 'Open RFQs', value: d.openRfqs, accent: Accent.sunset, onTap: () => _go(const RfqsPage())),
    ]);
  }

  Widget _quickActions() {
    final actions = <({IconData icon, String label, Widget page})>[
      (icon: Icons.add_shopping_cart_rounded, label: 'New requisition', page: const PurchaseRequisitionsPage()),
      (icon: Icons.note_add_outlined, label: 'New order', page: const PurchaseOrdersPage()),
      if (_hasRfq) (icon: Icons.request_quote_outlined, label: 'New RFQ', page: const RfqsPage()),
    ];
    final p = MarketPalette.of(context);
    return Row(children: [
      for (var i = 0; i < actions.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: FadeSlideIn(
            index: i,
            child: GlowCard(
              onTap: () => _go(actions[i].page),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Column(children: [
                AccentIcon(actions[i].icon, size: 36),
                const SizedBox(height: 8),
                Text(actions[i].label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.text)),
              ]),
            ),
          ),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final sections = [
      for (final s in _sections)
        (title: s.title, subtitle: s.subtitle, tiles: q.isEmpty ? s.tiles : s.tiles.where((t) => t.label.toLowerCase().contains(q)).toList()),
    ].where((s) => s.tiles.isNotEmpty).toList();

    var index = 0;
    return MotionScaffold(
      title: 'Purchase management',
      subtitle: 'Requisitions, quotations, orders and suppliers',
      icon: Icons.shopping_bag_outlined,
      onRefresh: _load,
      headerExtra: HeaderSearch(hint: 'Find a purchase area', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        if (q.isEmpty) ...[
          SliverPadding(padding: const EdgeInsets.only(top: 16), sliver: SliverToBoxAdapter(child: _kpis())),
          sliverBox(const SectionHeader('Quick actions'), padding: const EdgeInsets.symmetric(horizontal: 16)),
          sliverBox(_quickActions(), padding: const EdgeInsets.symmetric(horizontal: 16)),
        ],
        for (final s in sections) sliverHubSection(title: s.title, subtitle: s.subtitle, tiles: s.tiles, startIndex: (index += s.tiles.length) - s.tiles.length),
        if (sections.isEmpty) sliverEmpty(icon: Icons.search_off_rounded, title: 'No purchase area matches "$_q"'),
      ],
    );
  }
}
