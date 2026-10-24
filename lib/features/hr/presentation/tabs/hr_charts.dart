import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../shared/ui/motion_kit.dart';

// Small animated chart kit shared by the employee dashboard and HR
// analytics: donut with legend, area trend, grouped bars and horizontal
// bars. Every chart grows in from zero on first build.

const kChartPalette = [
  Color(0xFF168EFF), Color(0xFFC87B00), Color(0xFF75980B), Color(0xFFDF1278), Color(0xFF8B47D7), Color(0xFF049F9A),
  Color(0xFF0070F2), Color(0xFFCC00DC),
];

Color chartColorAt(int i) => kChartPalette[i % kChartPalette.length];

/// Parses '#RRGGBB' / '#RGB' (falls back when missing or malformed).
Color hexColor(dynamic v, [Color fallback = const Color(0xFF8396A8)]) {
  var s = (v ?? '').toString().trim().replaceFirst('#', '');
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (s.length != 6) return fallback;
  final n = int.tryParse(s, radix: 16);
  return n == null ? fallback : Color(0xFF000000 | n);
}

class ChartSlice {
  final String label;
  final double value;
  final Color color;
  const ChartSlice(this.label, this.value, this.color);
}

class ChartSeries {
  final String name;
  final List<double> data;
  final Color color;
  const ChartSeries(this.name, this.data, this.color);
}

List<ChartSlice> parseSlices(dynamic raw) {
  if (raw is! List) return const [];
  var i = 0;
  return raw.whereType<Map>().map((m) {
    final c = hexColor(m['color'], chartColorAt(i));
    i++;
    return ChartSlice('${m['label'] ?? ''}', toDouble(m['value']), c);
  }).toList();
}

List<double> parseNums(dynamic raw) => raw is List ? raw.map(toDouble).toList() : const [];
List<String> parseStrings(dynamic raw) => raw is List ? raw.map((e) => '$e').toList() : const [];

List<ChartSeries> parseSeries(dynamic raw) {
  if (raw is! List) return const [];
  var i = 0;
  return raw.whereType<Map>().map((m) {
    final c = hexColor(m['color'], chartColorAt(i));
    i++;
    return ChartSeries('${m['name'] ?? ''}', parseNums(m['data']), c);
  }).toList();
}

String compactNum(num v) => NumberFormat.compact().format(v);

// ── Panel ───────────────────────────────────────────────────────────────

/// Card with icon, title, optional subtitle and an empty fallback.
class ChartPanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Accent accent;
  final bool empty;
  final Widget child;
  final double height;
  final Widget? trailing;
  const ChartPanel({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.accent = Accent.ocean,
    this.empty = false,
    required this.child,
    this.height = 220,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return GlowCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AccentIcon(icon, accent: accent, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
              if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
            ]),
          ),
          ?trailing,
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: height,
          child: empty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.insights_outlined, size: 30, color: p.label.withValues(alpha: 0.5)),
                    const SizedBox(height: 6),
                    Text('No data in this range', style: TextStyle(fontSize: 12.5, color: p.label)),
                  ]),
                )
              : child,
        ),
      ]),
    );
  }
}

/// Animates 0 → 1 once, for chart grow-in effects.
class _Grow extends StatelessWidget {
  final Widget Function(double t) builder;
  const _Grow({required this.builder});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, t, _) => builder(t),
      );
}

// ── Donut ───────────────────────────────────────────────────────────────

class DonutLegend extends StatefulWidget {
  final List<ChartSlice> slices;
  final String Function(num v)? format;
  final String? centerLabel;
  const DonutLegend({super.key, required this.slices, this.format, this.centerLabel});

  @override
  State<DonutLegend> createState() => _DonutLegendState();
}

class _DonutLegendState extends State<DonutLegend> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final slices = widget.slices.where((s) => s.value > 0).toList();
    final total = slices.fold<double>(0, (a, s) => a + s.value);
    final fmt = widget.format ?? (num v) => NumberFormat.decimalPattern().format(v.round());
    return Row(children: [
      Expanded(
        flex: 5,
        child: Stack(alignment: Alignment.center, children: [
          _Grow(
            builder: (t) => PieChart(
              PieChartData(
                startDegreeOffset: -90,
                sectionsSpace: 2,
                centerSpaceRadius: 46,
                pieTouchData: PieTouchData(touchCallback: (e, r) {
                  if (!e.isInterestedForInteractions || r?.touchedSection == null) {
                    if (_touched != -1) setState(() => _touched = -1);
                    return;
                  }
                  final i = r!.touchedSection!.touchedSectionIndex;
                  if (i != _touched && i < slices.length) setState(() => _touched = i);
                }),
                sections: [
                  for (var i = 0; i < slices.length; i++)
                    PieChartSectionData(
                      value: slices[i].value * t,
                      color: slices[i].color,
                      radius: i == _touched ? 26 : 20,
                      showTitle: false,
                    ),
                  if (t < 1) PieChartSectionData(value: math.max(total * (1 - t), 0.0001), color: Colors.transparent, radius: 12, showTitle: false),
                ],
              ),
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            CountUp(
              value: _touched >= 0 && _touched < slices.length ? slices[_touched].value : total,
              format: (v) => widget.format != null ? fmt(v) : compactNum(v.round()),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.text),
            ),
            Text(_touched >= 0 && _touched < slices.length ? slices[_touched].label : (widget.centerLabel ?? 'Total'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: p.label)),
          ]),
        ]),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 5,
        child: ListView(
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          children: [
            for (var i = 0; i < slices.length; i++)
              FadeSlideIn(
                index: i,
                offsetY: 6,
                child: PressScale(
                  onTap: () => setState(() => _touched = _touched == i ? -1 : i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: slices[i].color, borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(slices[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: p.text, fontWeight: i == _touched ? FontWeight.w700 : FontWeight.w500)),
                      ),
                      Text(
                        total > 0 ? '${(slices[i].value / total * 100).round()}%' : '',
                        style: TextStyle(fontSize: 11.5, color: p.label, fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    ]);
  }
}

// ── Area trend ──────────────────────────────────────────────────────────

class TrendLineChart extends StatelessWidget {
  final List<String> categories;
  final List<ChartSeries> series;
  const TrendLineChart({super.key, required this.categories, required this.series});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final maxY = series.expand((s) => s.data).fold<double>(0, math.max);
    final top = maxY <= 0 ? 1.0 : maxY * 1.2;
    final n = categories.length;
    final step = n <= 6 ? 1 : (n / 5).ceil();
    return Column(children: [
      if (series.length > 1) _Legend(series: series),
      Expanded(
        child: _Grow(
          builder: (t) => LineChart(
            LineChartData(
              minY: 0,
              maxY: top,
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: top / 4,
                getDrawingHorizontalLine: (_) => FlLine(color: p.line, strokeWidth: 1, dashArray: [4, 4]),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: top / 4,
                    getTitlesWidget: (v, m) => v == m.max ? const SizedBox.shrink() : Text(compactNum(v.round()), style: TextStyle(fontSize: 10, color: p.label)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: 1,
                    getTitlesWidget: (v, m) {
                      final i = v.round();
                      if (i < 0 || i >= n || i % step != 0 || v != i.toDouble()) return const SizedBox.shrink();
                      return Padding(padding: const EdgeInsets.only(top: 6), child: Text(_shortLabel(categories[i]), style: TextStyle(fontSize: 9.5, color: p.label)));
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => p.text,
                  tooltipRoundedRadius: 10,
                  fitInsideHorizontally: true,
                  getTooltipItems: (spots) => spots
                      .map((s) => LineTooltipItem(
                            '${s.barIndex == 0 && s.x.round() < n ? '${categories[s.x.round()]}\n' : ''}${series[s.barIndex].name}: ${s.y.round()}',
                            TextStyle(color: p.card, fontSize: 11, fontWeight: FontWeight.w600),
                          ))
                      .toList(),
                ),
              ),
              lineBarsData: [
                for (final s in series)
                  LineChartBarData(
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: s.color,
                    barWidth: 2.4,
                    dotData: FlDotData(show: n <= 14),
                    belowBarData: BarAreaData(
                      show: true,
                      color: s.color.withValues(alpha: series.length > 1 ? 0.06 : 0.1),
                    ),
                    spots: [for (var i = 0; i < s.data.length && i < n; i++) FlSpot(i.toDouble(), s.data[i] * t)],
                  ),
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}

String _shortLabel(String s) {
  final d = DateTime.tryParse(s);
  if (d != null) return DateFormat('d MMM').format(d);
  return s.length > 8 ? '${s.substring(0, 7)}…' : s;
}

class _Legend extends StatelessWidget {
  final List<ChartSeries> series;
  const _Legend({required this.series});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(spacing: 12, runSpacing: 4, children: [
        for (final s in series)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(s.name, style: TextStyle(fontSize: 11, color: p.label)),
          ]),
      ]),
    );
  }
}

// ── Grouped bars ────────────────────────────────────────────────────────

class GroupedBarChart extends StatelessWidget {
  final List<String> categories;
  final List<ChartSeries> series;
  final String Function(num v)? format;
  const GroupedBarChart({super.key, required this.categories, required this.series, this.format});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final fmt = format ?? (num v) => compactNum(v);
    final maxY = series.expand((s) => s.data).fold<double>(0, math.max);
    final top = maxY <= 0 ? 1.0 : maxY * 1.18;
    final n = categories.length;
    final rodW = (series.length > 1 ? 9.0 : 16.0) * (n > 8 ? 0.7 : 1);
    final chartWidthPer = series.length * rodW + 22;
    return Column(children: [
      if (series.length > 1) _Legend(series: series),
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final width = math.max(c.maxWidth, n * chartWidthPer + 40);
          final chart = _Grow(
            builder: (t) => BarChart(
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
                      getTitlesWidget: (v, m) => v == m.max ? const SizedBox.shrink() : Text(fmt(v), style: TextStyle(fontSize: 9.5, color: p.label)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, m) {
                        final i = v.toInt();
                        if (i < 0 || i >= n) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_shortLabel(categories[i]), style: TextStyle(fontSize: 9.5, color: p.label)),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => p.text,
                    tooltipRoundedRadius: 10,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                      '${categories[g.x]}\n${series[ri].name}: ${fmt(g.x < series[ri].data.length ? series[ri].data[g.x] : 0)}',
                      TextStyle(color: p.card, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < n; i++)
                    BarChartGroupData(x: i, barsSpace: 3, barRods: [
                      for (final s in series)
                        BarChartRodData(
                          toY: (i < s.data.length ? s.data[i] : 0) * t,
                          width: rodW,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                          color: s.color,
                        ),
                    ]),
                ],
              ),
            ),
          );
          if (width <= c.maxWidth) return chart;
          return SingleChildScrollView(scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(), child: SizedBox(width: width, height: c.maxHeight, child: chart));
        }),
      ),
    ]);
  }
}

// ── Horizontal bars ─────────────────────────────────────────────────────

class HBarList extends StatelessWidget {
  final List<String> categories;
  final List<double> data;
  final Color color;
  final String Function(num v)? format;
  const HBarList({super.key, required this.categories, required this.data, this.color = const Color(0xFF0070F2), this.format});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final maxV = data.fold<double>(0, math.max);
    final fmt = format ?? (num v) => NumberFormat.decimalPattern().format(v.round());
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      itemCount: math.min(categories.length, data.length),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final frac = maxV <= 0 ? 0.0 : data[i] / maxV;
        return FadeSlideIn(
          index: i,
          offsetY: 8,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(categories[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.text, fontWeight: FontWeight.w600))),
              Text(fmt(data[i]), style: TextStyle(fontSize: 12, color: p.label, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(children: [
                Container(height: 8, color: p.surface),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: frac),
                  duration: Duration(milliseconds: 700 + i * 60),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: v.clamp(0.0, 1.0),
                    child: Container(height: 8, decoration: BoxDecoration(color: color)),
                  ),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

/// Thin animated progress bar.
class GrowBar extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final double height;
  const GrowBar({super.key, required this.value, required this.color, this.height = 7});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(children: [
        Container(height: height, color: p.surface),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: v,
            child: Container(height: height, decoration: BoxDecoration(color: color)),
          ),
        ),
      ]),
    );
  }
}
