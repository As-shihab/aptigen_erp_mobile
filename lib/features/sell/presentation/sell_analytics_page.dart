import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/network/http_client.dart';
import '../data/sell_analytics_service.dart';
import '../../store/data/store_util.dart' show toNum;
import 'widgets/sell_ui.dart';

const _statusOptions = ['DRAFT', 'PARKED', 'COMPLETED', 'REFUNDED', 'CANCELLED'];
const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Mirrors desktop's Analytics.tsx — filter bar (date range, status, client
/// group) driving a bespoke `sell/dashboard-analytics` aggregation, KPI grid
/// + a curated subset of the desktop's 6 chart panels stacked for a phone
/// screen (same "mobile-appropriate dashboard, not pixel parity" approach
/// Store's analytics page took).
class SellAnalyticsPage extends StatefulWidget {
  const SellAnalyticsPage({super.key});

  @override
  State<SellAnalyticsPage> createState() => _SellAnalyticsPageState();
}

class _SellAnalyticsPageState extends State<SellAnalyticsPage> {
  final _client = ApiClient();
  late final _service = SellAnalyticsService(_client);

  DateTimeRange _range = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 30)), end: DateTime.now());
  String? _status;
  int? _clientGroupId;
  List<Map<String, dynamic>> _clientGroups = [];

  bool _loading = true;
  SellAnalyticsSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _loadClientGroups();
    _load();
  }

  Future<void> _loadClientGroups() async {
    try {
      final res = await _client.get(r'client_groups?$select=id,name&$filter=is_active eq true&$top=200');
      if (!mounted) return;
      setState(() => _clientGroups = unwrapList(res).cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _service.load(start: _range.start, end: _range.end, clientGroupId: _clientGroupId, status: _status);
      if (!mounted) return;
      setState(() => _snapshot = result);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(context: context, firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)), lastDate: DateTime.now(), initialDateRange: _range);
    if (picked == null) return;
    setState(() => _range = picked);
    _load();
  }

  /// Quick range presets — same shape as the default range (now − N days → now).
  void _setPreset(int days) {
    if (days == 0) {
      _pickRange();
      return;
    }
    setState(() => _range = DateTimeRange(start: DateTime.now().subtract(Duration(days: days)), end: DateTime.now()));
    _load();
  }

  void _reset() {
    setState(() {
      _range = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 30)), end: DateTime.now());
      _status = null;
      _clientGroupId = null;
    });
    _load();
  }

  int get _activePreset => _presetOf(_range);

  String? get _clientGroupName {
    if (_clientGroupId == null) return null;
    for (final g in _clientGroups) {
      if (toNum(g['id']) == _clientGroupId) return (g['name'] ?? '').toString();
    }
    return 'Client group';
  }

  bool get _hasFilters => _status != null || _clientGroupId != null || _activePreset != 30;

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final s = _snapshot;
    return MarketScaffold(
      title: 'Sales analytics',
      subtitle: _rangeLabel(_range),
      actions: [
        if (_hasFilters) IconButton(tooltip: 'Reset filters', onPressed: _reset, icon: const Icon(Icons.filter_alt_off_outlined)),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        color: p.brand,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _filters(p),
            if (_loading && s == null)
              _skeleton()
            else if (s == null)
              MarketEmpty(
                icon: Icons.insights_outlined,
                title: 'Analytics could not be loaded',
                message: 'Check your connection and try again.',
                actionLabel: 'Retry',
                onAction: _load,
              )
            else
              AnimatedOpacity(
                opacity: _loading ? 0.5 : 1,
                duration: const Duration(milliseconds: 200),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SectionHeader('Overview'),
                  _kpiGrid(s),
                  const SizedBox(height: 16),
                  FadeSlideIn(
                    index: 2,
                    child: _ChartCard(title: 'Revenue trend', subtitle: 'Daily revenue for the selected range', isEmpty: s.trendData.isEmpty, child: _trendLine(p, s)),
                  ),
                  const SizedBox(height: 12),
                  FadeSlideIn(
                    index: 3,
                    child: _ChartCard(
                      title: 'Top selling products',
                      subtitle: 'Best performers in this range',
                      isEmpty: s.topProducts.isEmpty,
                      child: _BarList(entries: s.topProducts, color: p.brand, format: _compactNumber),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeSlideIn(
                    index: 4,
                    child: _ChartCard(
                      title: 'Top clients by revenue',
                      subtitle: 'Clients who spent the most',
                      isEmpty: s.topClients.isEmpty,
                      child: _BarList(entries: s.topClients, color: p.ok, format: (v) => money(v)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeSlideIn(
                    index: 5,
                    child: _ChartCard(
                      title: 'Order status',
                      subtitle: 'How orders are split by status',
                      isEmpty: s.statusCounts.isEmpty,
                      child: _Donut(
                        items: [
                          for (final e in s.statusCounts.entries)
                            (label: saleStatusLabel(e.key.toUpperCase()), value: e.value, color: p.tone(saleStatusTone(e.key.toUpperCase())).fg),
                        ],
                        format: (v) => v.round().toString(),
                        centerLabel: 'Orders',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeSlideIn(
                    index: 6,
                    child: _ChartCard(
                      title: 'Revenue by client group',
                      subtitle: 'Share of revenue per group',
                      isEmpty: s.revenueByGroup.isEmpty,
                      child: _Donut(
                        items: [
                          for (final (i, e) in s.revenueByGroup.entries.indexed)
                            (label: e.key.isEmpty ? 'No group' : e.key, value: e.value, color: _seriesColor(p, i)),
                        ],
                        format: (v) => money(v),
                        centerLabel: 'Revenue',
                        compactCenter: true,
                      ),
                    ),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  // ── Filters ────────────────────────────────────────────────────────────

  Widget _filters(MarketPalette p) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MarketSegmented<int>(
        value: _activePreset,
        options: const [
          (id: 7, label: '7 days', count: null),
          (id: 30, label: '30 days', count: null),
          (id: 90, label: '90 days', count: null),
          (id: 0, label: 'Custom', count: null),
        ],
        onChanged: _setPreset,
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(children: [
          _FilterChip(icon: Icons.calendar_today_outlined, label: _rangeLabel(_range), active: _activePreset == 0, onTap: _pickRange),
          const SizedBox(width: 8),
          _FilterChip(icon: Icons.groups_outlined, label: _clientGroupName ?? 'All client groups', active: _clientGroupId != null, onTap: _pickClientGroup),
          const SizedBox(width: 8),
          _FilterChip(
            icon: Icons.flag_outlined,
            label: _status == null ? 'All statuses' : saleStatusLabel(_status!),
            active: _status != null,
            onTap: _pickStatus,
          ),
        ]),
      ),
    ]);
  }

  Future<void> _pickClientGroup() async {
    final options = <({int? value, String label})>[
      (value: null, label: 'All client groups'),
      for (final g in _clientGroups) (value: toNum(g['id']), label: (g['name'] ?? '').toString()),
    ];
    final picked = await _pickFrom<int?>('Client group', options, _clientGroupId);
    if (picked == null) return;
    setState(() => _clientGroupId = picked.value);
    _load();
  }

  Future<void> _pickStatus() async {
    final options = <({String? value, String label})>[
      (value: null, label: 'All statuses'),
      for (final s in _statusOptions) (value: s, label: saleStatusLabel(s)),
    ];
    final picked = await _pickFrom<String?>('Status', options, _status);
    if (picked == null) return;
    setState(() => _status = picked.value);
    _load();
  }

  /// Bottom-sheet single choice. Returns a record so "All" (null) is
  /// distinguishable from a dismissed sheet.
  Future<({T value})?> _pickFrom<T>(String title, List<({T value, String label})> options, T current) {
    return showMarketSheet<({T value})>(context, builder: (ctx) {
      final p = MarketPalette.of(ctx);
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
          ),
          Divider(height: 1, color: p.line),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final o in options)
                ListTile(
                  title: Text(o.label, style: TextStyle(fontSize: 14, color: p.text, fontWeight: o.value == current ? FontWeight.w700 : FontWeight.w500)),
                  trailing: o.value == current ? Icon(Icons.check, color: p.brand) : null,
                  onTap: () => Navigator.pop(ctx, (value: o.value)),
                ),
            ]),
          ),
        ]),
      );
    });
  }

  // ── KPIs ───────────────────────────────────────────────────────────────

  Widget _kpiGrid(SellAnalyticsSnapshot s) {
    String m(num v) => money(v);
    final tiles = [
      KpiTile(icon: Icons.trending_up, label: 'Revenue', value: s.totalRevenue, format: m, tone: MarketTone.ok),
      KpiTile(icon: Icons.receipt_long_outlined, label: 'Orders', value: s.totalOrders),
      KpiTile(icon: Icons.check_circle_outline, label: 'Completed', value: s.completedOrders, tone: MarketTone.ok),
      KpiTile(icon: Icons.pause_circle_outline, label: 'Held or pending', value: s.pendingOrders, tone: MarketTone.warn),
      KpiTile(icon: Icons.block_outlined, label: 'Refunded or cancelled', value: s.voidedOrders, tone: MarketTone.error),
      KpiTile(icon: Icons.shopping_basket_outlined, label: 'Avg. order value', value: s.avgOrderValue, format: m, tone: MarketTone.info),
      KpiTile(icon: Icons.account_balance_wallet_outlined, label: 'Outstanding', value: s.totalOutstanding, format: m, tone: MarketTone.warn),
      KpiTile(icon: Icons.assignment_return_outlined, label: 'Refunded', value: s.totalRefunded, format: m, tone: MarketTone.error),
      KpiTile(icon: Icons.local_offer_outlined, label: 'Discount', value: s.totalDiscount, format: m, tone: MarketTone.neutral),
      KpiTile(icon: Icons.account_balance_outlined, label: 'Tax', value: s.totalTax, format: m, tone: MarketTone.neutral),
      KpiTile(icon: Icons.people_alt_outlined, label: 'Clients', value: s.totalClients, tone: MarketTone.info),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.35,
      children: [for (var i = 0; i < tiles.length; i++) FadeSlideIn(index: i, child: tiles[i])],
    );
  }

  // ── Charts ─────────────────────────────────────────────────────────────

  Widget _trendLine(MarketPalette p, SellAnalyticsSnapshot s) {
    final spots = <FlSpot>[for (var i = 0; i < s.trendData.length; i++) FlSpot(i.toDouble(), s.trendData[i])];
    final maxY = s.trendData.fold<double>(0, math.max);
    final total = s.trendData.fold<double>(0, (a, b) => a + b);
    final interval = (s.trendDates.length / 4).ceilToDouble().clamp(1, math.max(1, s.trendDates.length)).toDouble();
    String dateAt(int i) => i >= 0 && i < s.trendDates.length ? _shortDate(s.trendDates[i]) : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Flexible(child: CountUp(value: total, format: (v) => money(v), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text))),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text('over ${s.trendData.length} ${s.trendData.length == 1 ? 'day' : 'days'}', style: TextStyle(fontSize: 12, color: p.label)),
        ),
      ]),
      const SizedBox(height: 14),
      SizedBox(
        height: 190,
        child: LineChart(LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.15,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: p.brand,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(show: spots.length == 1),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [p.brand.withValues(alpha: p.dark ? 0.35 : 0.22), p.brand.withValues(alpha: 0)],
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            getTouchedSpotIndicator: (_, idx) => [
              for (final _ in idx)
                TouchedSpotIndicatorData(
                  FlLine(color: p.label.withValues(alpha: 0.5), strokeWidth: 1),
                  FlDotData(getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 4, color: p.brand, strokeWidth: 2, strokeColor: p.card)),
                ),
            ],
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => p.text,
              tooltipRoundedRadius: 8,
              getTooltipItems: (touched) => [
                for (final t in touched)
                  LineTooltipItem(
                    '${dateAt(t.x.toInt())}\n',
                    TextStyle(color: p.card.withValues(alpha: 0.75), fontSize: 11),
                    children: [TextSpan(text: money(t.y), style: TextStyle(color: p.card, fontSize: 12.5, fontWeight: FontWeight.w700))],
                  ),
              ],
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: interval,
                getTitlesWidget: (v, m) {
                  final i = v.toInt();
                  if (i < 0 || i >= s.trendDates.length || v != i.toDouble()) return const SizedBox.shrink();
                  return Padding(padding: const EdgeInsets.only(top: 6), child: Text(dateAt(i), style: TextStyle(fontSize: 10, color: p.label)));
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, m) {
                  if (v == m.max) return const SizedBox.shrink();
                  return Text(_compactNumber(v), style: TextStyle(fontSize: 10, color: p.label));
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: p.line, strokeWidth: 1, dashArray: const [4, 4]),
          ),
          borderData: FlBorderData(show: false),
        )),
      ),
    ]);
  }

  Widget _skeleton() => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.35,
            children: List.generate(6, (_) => const SkeletonBox(radius: 12)),
          ),
          const SizedBox(height: 16),
          const SkeletonBox(height: 260, radius: 12),
          const SizedBox(height: 12),
          const SkeletonBox(height: 200, radius: 12),
        ]),
      );
}

// ── Helpers ──────────────────────────────────────────────────────────────

Color _seriesColor(MarketPalette p, int i) {
  final colors = [p.brand, p.ok, p.warn, p.error, p.neutral, p.info];
  return colors[i % colors.length];
}

/// 7 / 30 / 90 when the range is "now − N days → today", else 0 (custom).
int _presetOf(DateTimeRange r) {
  final now = DateTime.now();
  final endIsToday = r.end.year == now.year && r.end.month == now.month && r.end.day == now.day;
  final days = r.end.difference(r.start).inDays;
  return endIsToday && const [7, 30, 90].contains(days) ? days : 0;
}

String _rangeLabel(DateTimeRange r) {
  final s = r.start, e = r.end;
  if (s.year == e.year) return '${s.day} ${_monthsShort[s.month - 1]} – ${e.day} ${_monthsShort[e.month - 1]} ${e.year}';
  return '${s.day} ${_monthsShort[s.month - 1]} ${s.year} – ${e.day} ${_monthsShort[e.month - 1]} ${e.year}';
}

/// "2026-10-12" → "12 Oct"; anything unparseable is shown as-is.
String _shortDate(String raw) {
  final d = DateTime.tryParse(raw);
  return d == null ? raw : '${d.day} ${_monthsShort[d.month - 1]}';
}

String _compactNumber(num v) {
  final a = v.abs();
  String trim(num x) => x.toStringAsFixed(x.abs() >= 10 ? 0 : 1).replaceAll(RegExp(r'\.0$'), '');
  if (a >= 1e9) return '${trim(v / 1e9)}B';
  if (a >= 1e6) return '${trim(v / 1e6)}M';
  if (a >= 1e3) return '${trim(v / 1e3)}k';
  return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

class _FilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Material(
      color: active ? p.brandSoft : p.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: active ? p.brand.withValues(alpha: 0.5) : p.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: active ? p.brand : p.label),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: active ? p.brand : p.text)),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 16, color: p.label),
          ]),
        ),
      ),
    );
  }
}

/// Chart card: section-style title, hairline divider, then the chart or a
/// compact empty state.
class _ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isEmpty;
  final Widget child;
  const _ChartCard({required this.title, this.subtitle, required this.isEmpty, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: TextStyle(fontSize: 12, color: p.label)),
            ],
          ]),
        ),
        Divider(height: 1, thickness: 1, color: p.line),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: isEmpty ? const _ChartEmpty() : child,
        ),
      ]),
    );
  }
}

class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty();

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle),
          child: Icon(Icons.bar_chart_outlined, size: 22, color: p.label),
        ),
        const SizedBox(height: 10),
        Text('No data for this range', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
        const SizedBox(height: 2),
        Text('Try a wider date range or clear the filters.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.label)),
      ]),
    );
  }
}

/// Ranked horizontal bar list: rank, label, value and a proportional bar.
class _BarList extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  final Color color;
  final String Function(num v) format;
  const _BarList({required this.entries, required this.color, required this.format});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final max = entries.fold<double>(0, (m, e) => math.max(m, e.value));
    return Column(children: [
      for (var i = 0; i < entries.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        Row(children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: i == 0 ? color.withValues(alpha: 0.15) : p.surface, borderRadius: BorderRadius.circular(6)),
            child: Text('${i + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: i == 0 ? color : p.label)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Text(entries[i].key.isEmpty ? '—' : entries[i].key,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: p.text)),
                ),
                const SizedBox(width: 8),
                Text(format(entries[i].value), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 6,
                  color: p.surface,
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: max <= 0 ? 0 : (entries[i].value / max).clamp(0, 1).toDouble()),
                    duration: Duration(milliseconds: 500 + 60 * i.clamp(0, 8)),
                    curve: Curves.easeOutCubic,
                    builder: (_, f, _) => FractionallySizedBox(
                      widthFactor: f,
                      child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ],
    ]);
  }
}

/// Donut with the total in the middle and a side legend (dot, label, value).
class _Donut extends StatelessWidget {
  final List<({String label, double value, Color color})> items;
  final String Function(num v) format;
  final String centerLabel;
  final bool compactCenter;
  const _Donut({required this.items, required this.format, required this.centerLabel, this.compactCenter = false});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final total = items.fold<double>(0, (a, b) => a + b.value);
    final hasValue = total > 0;
    return Row(children: [
      SizedBox(
        width: 128,
        height: 128,
        child: Stack(alignment: Alignment.center, children: [
          PieChart(PieChartData(
            startDegreeOffset: -90,
            sectionsSpace: hasValue && items.length > 1 ? 2 : 0,
            centerSpaceRadius: 42,
            sections: hasValue
                ? [for (final it in items) PieChartSectionData(value: it.value, color: it.color, radius: 20, showTitle: false)]
                : [PieChartSectionData(value: 1, color: p.surface, radius: 20, showTitle: false)],
          )),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(compactCenter ? _compactNumber(total) : format(total), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.text)),
            Text(centerLabel, style: TextStyle(fontSize: 10.5, color: p.label)),
          ]),
        ]),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 14, color: p.line),
            Row(children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: items[i].color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(items[i].label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.text))),
              const SizedBox(width: 6),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(format(items[i].value), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text)),
                if (hasValue) Text('${(items[i].value / total * 100).toStringAsFixed(0)}%', style: TextStyle(fontSize: 10.5, color: p.label)),
              ]),
            ]),
          ],
        ]),
      ),
    ]);
  }
}
