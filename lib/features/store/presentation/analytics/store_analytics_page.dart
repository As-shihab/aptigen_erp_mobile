import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../core/network/http_client.dart';
import '../../data/store_analytics_service.dart';
import '../stock/stock_ledger_page.dart' show movementLabel, movementTone;
import '../widgets/store_ui.dart';

/// A mobile-appropriate curated subset of desktop's 8-chart
/// `StoreAnalytics.tsx` dashboard (per the plan's scope notes) — KPI grid +
/// a handful of `fl_chart` panels stacked vertically, same layout as
/// Sales analytics (sell_analytics_page.dart).
class StoreAnalyticsPage extends StatefulWidget {
  const StoreAnalyticsPage({super.key});

  @override
  State<StoreAnalyticsPage> createState() => _StoreAnalyticsPageState();
}

class _StoreAnalyticsPageState extends State<StoreAnalyticsPage> {
  final _service = StoreAnalyticsService(ApiClient());
  bool _loading = true;
  StoreAnalyticsSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _service.load();
      if (!mounted) return;
      setState(() => _snapshot = result);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final s = _snapshot;
    return MarketScaffold(
      title: 'Store analytics',
      subtitle: 'Stock, movements and purchasing at a glance',
      body: RefreshIndicator(
        onRefresh: _load,
        color: p.brand,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
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
                    child: _ChartCard(
                      title: 'Stock movements',
                      subtitle: 'Received, issued and adjusted postings',
                      isEmpty: s.movementTypeCounts.values.every((v) => v == 0),
                      child: _Donut(
                        items: [
                          for (final t in const ['IN', 'OUT', 'ADJUST'])
                            (label: movementLabel(t), value: (s.movementTypeCounts[t] ?? 0).toDouble(), color: p.tone(movementTone(t)).fg),
                        ],
                        format: (v) => v.round().toString(),
                        centerLabel: 'Movements',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeSlideIn(
                    index: 3,
                    child: _ChartCard(
                      title: 'Top products by movement',
                      subtitle: 'Most units moved in or out',
                      isEmpty: s.topProductsByVolume.isEmpty,
                      child: _BarList(entries: s.topProductsByVolume, color: p.brand, format: _compactNumber),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeSlideIn(
                    index: 4,
                    child: _ChartCard(
                      title: 'Products by category',
                      subtitle: 'How the catalogue is split',
                      isEmpty: s.categoryProductCounts.isEmpty,
                      child: _Donut(
                        items: [
                          for (final (i, e) in _topWithOther(s.categoryProductCounts).indexed)
                            (label: e.key, value: e.value.toDouble(), color: _seriesColor(p, i)),
                        ],
                        format: (v) => v.round().toString(),
                        centerLabel: 'Products',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeSlideIn(
                    index: 5,
                    child: _ChartCard(
                      title: 'Purchase order status',
                      subtitle: 'Where your orders stand',
                      isEmpty: s.poStatusCounts.isEmpty,
                      child: _Donut(
                        items: [
                          for (final (i, e) in (s.poStatusCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).indexed)
                            (label: storeStatusLabel(e.key.toUpperCase()), value: e.value.toDouble(), color: _poColor(p, e.key.toUpperCase(), i)),
                        ],
                        format: (v) => v.round().toString(),
                        centerLabel: 'Orders',
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

  Widget _kpiGrid(StoreAnalyticsSnapshot s) {
    final tiles = [
      KpiTile(icon: Icons.account_balance_wallet_outlined, label: 'Stock value', value: s.stockValue, format: (v) => money(v), tone: MarketTone.ok),
      KpiTile(icon: Icons.warning_amber_outlined, label: 'Low stock', value: s.lowStockCount, tone: s.lowStockCount > 0 ? MarketTone.error : MarketTone.ok),
      KpiTile(icon: Icons.event_busy_outlined, label: 'Expiring ≤ 30d', value: s.expiringBatchCount, tone: s.expiringBatchCount > 0 ? MarketTone.warn : MarketTone.ok),
      KpiTile(icon: Icons.shopping_cart_outlined, label: 'Pending POs', value: s.pendingPoCount, tone: MarketTone.info),
      KpiTile(icon: Icons.request_page_outlined, label: 'Pending SPR', value: s.pendingSprCount, tone: MarketTone.warn),
      KpiTile(icon: Icons.description_outlined, label: 'Pending SR', value: s.pendingSrCount, tone: MarketTone.warn),
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
          const SkeletonBox(height: 200, radius: 12),
          const SizedBox(height: 12),
          const SkeletonBox(height: 240, radius: 12),
        ]),
      );
}

// ── Helpers ──────────────────────────────────────────────────────────────

Color _seriesColor(MarketPalette p, int i) {
  final colors = [p.brand, p.ok, p.warn, p.error, p.neutral, p.info];
  return colors[i % colors.length];
}

/// PO statuses use their semantic tone; neutral (unknown) ones fall back to
/// the series palette so they stay distinguishable.
Color _poColor(MarketPalette p, String status, int i) {
  final tone = storeStatusTone(status);
  return tone == MarketTone.neutral ? _seriesColor(p, i) : p.tone(tone).fg;
}

/// Largest five entries, the rest folded into "Other" so the legend stays short.
List<MapEntry<String, int>> _topWithOther(Map<String, int> counts) {
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  if (sorted.length <= 6) return sorted;
  final rest = sorted.skip(5).fold<int>(0, (a, e) => a + e.value);
  return [...sorted.take(5), MapEntry('Other', rest)];
}

String _compactNumber(num v) {
  final a = v.abs();
  String trim(num x) => x.toStringAsFixed(x.abs() >= 10 ? 0 : 1).replaceAll(RegExp(r'\.0$'), '');
  if (a >= 1e9) return '${trim(v / 1e9)}B';
  if (a >= 1e6) return '${trim(v / 1e6)}M';
  if (a >= 1e3) return '${trim(v / 1e3)}k';
  return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
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
        Text('No data yet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
        const SizedBox(height: 2),
        Text('This chart fills in as stock activity is recorded.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.label)),
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
  const _Donut({required this.items, required this.format, required this.centerLabel});

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
            sectionsSpace: hasValue && items.where((it) => it.value > 0).length > 1 ? 2 : 0,
            centerSpaceRadius: 42,
            sections: hasValue
                ? [for (final it in items) if (it.value > 0) PieChartSectionData(value: it.value, color: it.color, radius: 20, showTitle: false)]
                : [PieChartSectionData(value: 1, color: p.surface, radius: 20, showTitle: false)],
          )),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_compactNumber(total), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.text)),
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
