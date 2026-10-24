import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/currency.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../../store/presentation/documents/mrr_return_list_page.dart';
import '../../data/purchase_dashboard_service.dart';
import '../approvals/purchase_approvals_page.dart';
import '../orders/purchase_orders_page.dart';
import '../rfq/rfqs_page.dart';
import '../suppliers/suppliers_page.dart';

// Purchase dashboard — port of desktop dashboard/PurchaseDashboard.tsx:
// eleven KPI tiles, monthly spend, order status, overdue deliveries, top
// suppliers and the requisition / RFQ / return pipelines. Everything is
// computed from one $batch (see PurchaseDashboardService).

// Same status colours as desktop, so a status reads the same everywhere.
const _poColors = {
  'PENDING': Color(0xFFF59E0B),
  'APPROVED': Color(0xFF0A6ED1),
  'REJECTED': Color(0xFFE11D48),
  'SENT': Color(0xFF8B5CF6),
  'PARTIALLY_RECEIVED': Color(0xFF14B8A6),
  'RECEIVED': Color(0xFF22C55E),
  'CANCELLED': Color(0xFF94A3B8),
};
const _rfqColors = {
  'DRAFT': Color(0xFFF59E0B),
  'SENT': Color(0xFF0A6ED1),
  'CLOSED': Color(0xFF8B5CF6),
  'AWARDED': Color(0xFF22C55E),
  'CANCELLED': Color(0xFFF44336),
};
const _sprColors = {
  'PENDING': Color(0xFFF59E0B),
  'APPROVED': Color(0xFF0A6ED1),
  'ORDERED': Color(0xFF22C55E),
  'REJECTED': Color(0xFFF44336),
};
const _returnColors = {
  'PENDING': Color(0xFFF59E0B),
  'APPROVED': Color(0xFF0A6ED1),
  'SHIPPED': Color(0xFF22C55E),
  'REJECTED': Color(0xFFF44336),
};
const _fallbackColor = Color(0xFF94A3B8);

String _money(num v) => formatMoney(v, decimalDigits: 0);
String _compact(num v) => NumberFormat.compact().format(v);

class PurchaseDashboardPage extends StatefulWidget {
  const PurchaseDashboardPage({super.key});

  @override
  State<PurchaseDashboardPage> createState() => _PurchaseDashboardPageState();
}

class _PurchaseDashboardPageState extends State<PurchaseDashboardPage> {
  final _service = PurchaseDashboardService();
  PurchaseDashboardData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final d = await _service.load();
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load the purchase dashboard'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _go(Widget page) => pushMotion(context, page).then((_) => _load());

  List<Widget> _kpis(PurchaseDashboardData d) {
    final change = d.monthChange;
    return [
      GradientKpi(icon: Icons.account_balance_wallet_outlined, label: 'Committed spend', value: d.totalSpend, format: _money, accent: Accent.ocean),
      GradientKpi(
        icon: Icons.bar_chart_rounded,
        label: change == null ? 'Spend this month' : 'Spend this month (${change >= 0 ? '+' : ''}${change.toStringAsFixed(0)}%)',
        value: d.monthSpend,
        format: _money,
        accent: Accent.violet,
      ),
      GradientKpi(icon: Icons.shopping_cart_outlined, label: 'Average order value', value: d.avgOrder, format: _money, accent: Accent.teal),
      GradientKpi(
        icon: Icons.fact_check_outlined,
        label: 'Pending approval',
        value: d.pending,
        accent: d.pending > 0 ? Accent.amber : Accent.slate,
        onTap: () => _go(const PurchaseApprovalsPage()),
      ),
      GradientKpi(icon: Icons.local_shipping_outlined, label: 'Awaiting delivery', value: d.awaitingDelivery, accent: Accent.sky, onTap: () => _go(const PurchaseOrdersPage())),
      GradientKpi(icon: Icons.warning_amber_rounded, label: 'Overdue deliveries', value: d.overdue.length, accent: d.overdue.isEmpty ? Accent.emerald : Accent.rose),
      GradientKpi(icon: Icons.inventory_outlined, label: 'Received orders', value: d.received, accent: Accent.emerald),
      GradientKpi(icon: Icons.assignment_outlined, label: 'Open requisitions', value: d.openRequisitions, accent: Accent.indigo),
      GradientKpi(icon: Icons.request_quote_outlined, label: 'Open RFQs', value: d.openRfqs, accent: Accent.sunset, onTap: () => _go(const RfqsPage())),
      GradientKpi(
        icon: Icons.assignment_return_outlined,
        label: 'Open returns',
        value: d.openReturns,
        accent: d.openReturns > 0 ? Accent.amber : Accent.slate,
        onTap: () => _go(const MrrReturnListPage()),
      ),
      GradientKpi(icon: Icons.groups_outlined, label: 'Suppliers', value: d.supplierCount, accent: Accent.ocean, onTap: () => _go(const SuppliersPage())),
    ];
  }

  List<Widget> _panels(PurchaseDashboardData d) {
    final monthly = d.monthlySpend;
    final top = d.topSuppliers;
    final overdue = d.overdue;
    return [
      _Panel(
        icon: Icons.bar_chart_rounded,
        title: 'Monthly spend',
        sub: 'Committed purchase orders, last 6 months',
        child: monthly.every((m) => m.value == 0)
            ? const _PanelEmpty(icon: Icons.bar_chart_rounded, text: 'No committed spend in the last 6 months.')
            : SizedBox(height: 200, child: _MonthlyBars(points: monthly)),
      ),
      _Panel(
        icon: Icons.pie_chart_outline_rounded,
        title: 'Order status',
        sub: 'All purchase orders',
        child: _StatusDonut(slices: d.orderSlices, colors: _poColors, center: 'Orders', empty: 'No purchase orders yet.'),
      ),
      _Panel(
        icon: Icons.warning_amber_rounded,
        title: 'Overdue deliveries',
        sub: overdue.isEmpty ? 'Open orders on schedule' : '${overdue.length} past the expected date',
        child: overdue.isEmpty ? const _PanelEmpty(icon: Icons.inventory_outlined, text: 'Every open order is on schedule.') : _OverdueList(orders: overdue),
      ),
      _Panel(
        icon: Icons.groups_outlined,
        title: 'Top suppliers',
        sub: 'By committed spend',
        child: top.isEmpty ? const _PanelEmpty(icon: Icons.groups_outlined, text: 'No supplier spend yet.') : _BarList(entries: top),
      ),
      _Panel(
        icon: Icons.pie_chart_outline_rounded,
        title: 'Requisitions',
        sub: 'Purchase requisitions by status',
        child: _StatusDonut(slices: d.requisitionSlices, colors: _sprColors, center: 'SPRs', empty: 'No purchase requisitions yet.'),
      ),
      _Panel(
        icon: Icons.pie_chart_outline_rounded,
        title: 'Requests for quotation',
        sub: 'RFQs by status',
        child: _StatusDonut(slices: d.rfqSlices, colors: _rfqColors, center: 'RFQs', empty: 'No requests for quotation yet.'),
      ),
      _Panel(
        icon: Icons.pie_chart_outline_rounded,
        title: 'Returns',
        sub: 'Goods returned to suppliers',
        child: _StatusDonut(slices: d.returnSlices, colors: _returnColors, center: 'Returns', empty: 'No returns yet.'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final panels = d == null ? const <Widget>[] : _panels(d);
    return MotionScaffold(
      title: 'Purchase dashboard',
      subtitle: 'Spend, deliveries and the buying pipeline',
      icon: Icons.insights_rounded,
      onRefresh: _load,
      slivers: [
        if (_loading) ...[
          SliverPadding(
            padding: const EdgeInsets.only(top: 16),
            sliver: SliverToBoxAdapter(
              child: KpiStrip(children: [for (var i = 0; i < 4; i++) const SkeletonBox(height: 112, radius: 12)]),
            ),
          ),
          sliverSkeleton(count: 3, height: 220),
        ] else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (d != null) ...[
          SliverPadding(padding: const EdgeInsets.only(top: 16), sliver: SliverToBoxAdapter(child: KpiStrip(children: _kpis(d)))),
          sliverStagger(count: panels.length, builder: (_, i) => panels[i], gap: 12, padding: const EdgeInsets.fromLTRB(16, 16, 16, 0)),
        ],
      ],
    );
  }
}

// ── Panels ──────────────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final Widget child;
  const _Panel({required this.icon, required this.title, required this.sub, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return GlowCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          AccentIcon(icon, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}

class _PanelEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PanelEmpty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(children: [
        Icon(icon, size: 26, color: p.label.withValues(alpha: 0.5)),
        const SizedBox(height: 6),
        Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.label)),
      ]),
    );
  }
}

// ── Monthly spend bars ──────────────────────────────────────────────────

class _MonthlyBars extends StatelessWidget {
  final List<({DateTime month, double value})> points;
  const _MonthlyBars({required this.points});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final maxV = points.fold<double>(0, (m, e) => math.max(m, e.value));
    final top = maxV <= 0 ? 1.0 : maxV * 1.15;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, t, _) => BarChart(
        BarChartData(
          maxY: top,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: top / 4,
            getDrawingHorizontalLine: (_) => FlLine(color: p.line, strokeWidth: 1, dashArray: [4, 4]),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: top / 4,
                getTitlesWidget: (v, m) => v == m.max ? const SizedBox.shrink() : Text(_compact(v), style: TextStyle(fontSize: 9.5, color: p.label)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, m) {
                  final i = v.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(DateFormat('MMM').format(points[i].month), style: TextStyle(fontSize: 10, color: p.label)),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => p.text,
              tooltipRoundedRadius: 8,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (g, _, _, _) => BarTooltipItem(
                '${DateFormat('MMM yyyy').format(points[g.x].month)}\n${_money(points[g.x].value)}',
                TextStyle(color: p.card, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: points[i].value * t,
                  width: 18,
                  color: p.brand,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

// ── Status donut ────────────────────────────────────────────────────────

class _StatusDonut extends StatelessWidget {
  final List<StatusSlice> slices;
  final Map<String, Color> colors;
  final String center;
  final String empty;
  const _StatusDonut({required this.slices, required this.colors, required this.center, required this.empty});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    if (slices.isEmpty) return _PanelEmpty(icon: Icons.pie_chart_outline_rounded, text: empty);
    final total = slices.fold<int>(0, (a, b) => a + b.count);
    return Row(children: [
      SizedBox(
        width: 120,
        height: 120,
        child: Stack(alignment: Alignment.center, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, t, _) => PieChart(PieChartData(
              startDegreeOffset: -90,
              sectionsSpace: slices.length > 1 ? 2 : 0,
              centerSpaceRadius: 38,
              sections: [
                for (final s in slices)
                  PieChartSectionData(value: s.count.toDouble(), color: colors[s.status] ?? _fallbackColor, radius: 16 + 4 * t, showTitle: false),
              ],
            )),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            CountUp(value: total, format: (v) => v.round().toString(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
            Text(center, style: TextStyle(fontSize: 10.5, color: p.label)),
          ]),
        ]),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < slices.length; i++) ...[
            if (i > 0) Divider(height: 12, color: p.line),
            Row(children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: colors[slices[i].status] ?? _fallbackColor, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(slices[i].label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.text))),
              Text('${slices[i].count}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text)),
              SizedBox(
                width: 38,
                child: Text('${(slices[i].count / total * 100).toStringAsFixed(0)}%', textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, color: p.label)),
              ),
            ]),
          ],
        ]),
      ),
    ]);
  }
}

// ── Overdue list ────────────────────────────────────────────────────────

class _OverdueList extends StatelessWidget {
  final List<PurchaseOrderLite> orders;
  const _OverdueList({required this.orders});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return Column(children: [
      for (var i = 0; i < orders.length; i++) ...[
        if (i > 0) Divider(height: 1, color: p.line),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(orders[i].poNo, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
                Text(
                  '${(orders[i].supplierName ?? '').isEmpty ? 'No supplier' : orders[i].supplierName} · ${purchaseStatusLabel(orders[i].status)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: p.label),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Builder(builder: (_) {
                final e = orders[i].expectedDate!;
                final days = today.difference(DateTime(e.year, e.month, e.day)).inDays;
                return Text('$days ${days == 1 ? 'day' : 'days'} late', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.error));
              }),
              Text('Due ${fmtDate(orders[i].expectedDate)}', style: TextStyle(fontSize: 11, color: p.label)),
            ]),
          ]),
        ),
      ],
    ]);
  }
}

// ── Top suppliers ───────────────────────────────────────────────────────

class _BarList extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  const _BarList({required this.entries});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final maxV = entries.fold<double>(0, (m, e) => math.max(m, e.value));
    final color = Accent.violet.primary;
    return Column(children: [
      for (var i = 0; i < entries.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Text(entries[i].key, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: p.text)),
          ),
          const SizedBox(width: 8),
          Text(_money(entries[i].value), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 6,
            color: p.surface,
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: maxV <= 0 ? 0 : (entries[i].value / maxV).clamp(0, 1).toDouble()),
              duration: Duration(milliseconds: 500 + 60 * i),
              curve: Curves.easeOutCubic,
              builder: (_, f, _) => FractionallySizedBox(
                widthFactor: f,
                child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
              ),
            ),
          ),
        ),
      ],
    ]);
  }
}
