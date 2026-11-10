import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/utils/currency.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/accounting_reports_service.dart';
import 'report_widgets.dart';

typedef _AccountShare = ({int id, String code, String name, double amount});

class _DayTotal {
  final DateTime date;
  final double income;
  final double expense;
  final List<_AccountShare> expenseAccounts;
  const _DayTotal(this.date, this.income, this.expense, this.expenseAccounts);
  double get net => income - expense;
}

// Below this many days of history the trend line isn't drawn — same
// threshold desktop's forecast panel uses before refusing to forecast.
const _minTrendDays = 7;
const _trendHorizons = [7, 14, 30];

String _axisMoney(num v) => '${currencySymbol()}${NumberFormat.compact().format(v)}';

// Accounting analytics — port of desktop analytics/AccountingAnalytics.tsx.
// Same journal-ledger source as Profit & loss (income − expense), bucketed
// by day instead of summed over the range, so it can answer "where was the
// loss": which days went net-negative and which expense accounts drove them.
//
// Desktop's forecast panel runs a WASM ARIMA/ETS/Theta auto-forecaster that
// has no Dart equivalent. Mobile shows a plain least-squares linear trend
// over the daily net instead, labelled as such — it's a straight-line
// projection, not a statistical forecast, and carries no confidence range.
class AccountingAnalyticsPage extends StatefulWidget {
  const AccountingAnalyticsPage({super.key});

  @override
  State<AccountingAnalyticsPage> createState() => _AccountingAnalyticsPageState();
}

class _AccountingAnalyticsPageState extends State<AccountingAnalyticsPage> {
  final _service = AccountingReportsService(ApiClient());
  List<ReportLine> _lines = [];
  bool _loading = true;
  String? _error;

  // Desktop defaults to the last 30 days.
  ReportRangePreset _preset = ReportRangePreset.last30;
  late DateTime _start;
  late DateTime _end;
  int _horizon = 7;

  @override
  void initState() {
    super.initState();
    final (start, end) = ReportDateRange.rangeFor(_preset);
    _start = start;
    _end = end;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _lines.isEmpty;
      _error = null;
    });
    try {
      final lines = await _service.loadAllLines();
      if (mounted) setState(() => _lines = lines);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load the ledger'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_DayTotal> _dayTotals() {
    // Capped at a year of days, same guard as desktop against a typo'd
    // range turning this into a huge loop.
    final days = <DateTime>[];
    for (var d = _start; !d.isAfter(_end) && days.length < 366; d = DateTime(d.year, d.month, d.day + 1)) {
      days.add(d);
    }
    final income = <DateTime, double>{for (final d in days) d: 0};
    final expense = <DateTime, Map<int, _AccountShare>>{for (final d in days) d: {}};

    for (final l in _lines) {
      final date = l.entryDate;
      if (date == null) continue;
      final day = dayOnly(date);
      if (!income.containsKey(day)) continue;
      if (l.accountType == 'INCOME') {
        income[day] = income[day]! + (l.credit - l.debit);
      } else if (l.accountType == 'EXPENSE') {
        final bucket = expense[day]!;
        final prev = bucket[l.accountId];
        bucket[l.accountId] = (
          id: l.accountId,
          code: l.accountCode ?? '',
          name: l.accountName ?? 'Account ${l.accountId}',
          amount: (prev?.amount ?? 0) + (l.debit - l.credit),
        );
      }
    }

    return [
      for (final d in days)
        () {
          final accounts = expense[d]!.values.where((a) => a.amount != 0).toList()..sort((a, b) => b.amount.compareTo(a.amount));
          return _DayTotal(d, income[d]!, accounts.fold<double>(0, (s, a) => s + a.amount), accounts);
        }(),
    ];
  }

  /// Least-squares line through the daily nets: (intercept, slope) over
  /// x = 0..n−1, or null below [_minTrendDays] days.
  (double, double)? _fitTrend(List<double> nets) {
    final n = nets.length;
    if (n < _minTrendDays) return null;
    final xMean = (n - 1) / 2;
    final yMean = nets.fold<double>(0, (s, v) => s + v) / n;
    var cov = 0.0, den = 0.0;
    for (var i = 0; i < n; i++) {
      cov += (i - xMean) * (nets[i] - yMean);
      den += (i - xMean) * (i - xMean);
    }
    final slope = den == 0 ? 0.0 : cov / den;
    return (yMean - slope * xMean, slope);
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final days = _dayTotals();
    final totalIncome = days.fold<double>(0, (s, d) => s + d.income);
    final totalExpense = days.fold<double>(0, (s, d) => s + d.expense);
    final net = totalIncome - totalExpense;

    // Worst days first — the direct answer to "where was the loss".
    final lossDays = days.where((d) => d.net < 0).toList()..sort((a, b) => a.net.compareTo(b.net));

    // Which expense accounts drove those loss days, across all of them.
    final drivers = <int, _AccountShare>{};
    for (final d in lossDays) {
      for (final a in d.expenseAccounts) {
        final prev = drivers[a.id];
        drivers[a.id] = (id: a.id, code: a.code, name: a.name, amount: (prev?.amount ?? 0) + a.amount);
      }
    }
    final topDrivers = (drivers.values.toList()..sort((a, b) => b.amount.compareTo(a.amount))).take(8).toList();

    final nets = [for (final d in days) d.net];
    final trend = _fitTrend(nets);
    final projected = trend == null
        ? null
        : List.generate(_horizon, (i) => trend.$1 + trend.$2 * (nets.length + i)).fold<double>(0, (s, v) => s + v);

    final panels = <Widget>[
      ReportPanel(
        icon: Icons.bar_chart_rounded,
        title: 'Daily net',
        sub: 'Green = profit, red = loss',
        child: days.every((d) => d.net == 0)
            ? const ReportEmpty(icon: Icons.bar_chart_rounded, text: 'Nothing posted in this range.')
            : SizedBox(height: 200, child: _NetBars(days: days)),
      ),
      ReportPanel(
        icon: Icons.show_chart_rounded,
        accent: Accent.violet,
        title: 'Net trend',
        sub: 'Straight-line fit of the daily net, extended $_horizon days — a simple trend, not a forecast model',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ChipFilter<int>(
            padding: EdgeInsets.zero,
            value: _horizon,
            options: [for (final h in _trendHorizons) (id: h, label: '$h days', count: null)],
            onChanged: (v) => setState(() => _horizon = v),
          ),
          const SizedBox(height: 12),
          trend == null
              ? const ReportEmpty(icon: Icons.show_chart_rounded, text: 'Not enough history yet (need at least 7 days) to show a trend.')
              : SizedBox(height: 200, child: _TrendChart(days: days, intercept: trend.$1, slope: trend.$2, horizon: _horizon)),
        ]),
      ),
      ReportPanel(
        icon: Icons.waves_rounded,
        accent: Accent.teal,
        title: 'Income vs expense',
        sub: 'Streamgraph of daily income and expense',
        child: days.every((d) => d.income == 0 && d.expense == 0)
            ? const ReportEmpty(icon: Icons.waves_rounded, text: 'Nothing posted in this range.')
            : Column(children: [
                SizedBox(height: 180, child: _Streamgraph(days: days)),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _Legend(color: p.ok, label: 'Income'),
                  const SizedBox(width: 16),
                  _Legend(color: p.error, label: 'Expense'),
                ]),
              ]),
      ),
      ReportPanel(
        icon: Icons.warning_amber_rounded,
        accent: Accent.rose,
        title: 'What drove the loss',
        sub: 'Top expense accounts on loss days',
        child: topDrivers.isEmpty
            ? const ReportEmpty(icon: Icons.check_circle_outline_rounded, text: 'No loss days in this range.')
            : AccountAmountList(rows: [for (final a in topDrivers) (code: a.code, name: a.name, amount: a.amount)], amountColor: p.error),
      ),
    ];

    return MotionScaffold(
      title: 'Accounting analytics',
      icon: Icons.insights_rounded,
      onRefresh: _load,
      headerExtra: ReportDateRange(
        preset: _preset,
        start: _start,
        end: _end,
        onChanged: (preset, start, end) => setState(() {
          _preset = preset;
          _start = start;
          _end = end;
        }),
      ),
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
        else ...[
          SliverPadding(
            padding: const EdgeInsets.only(top: 16),
            sliver: SliverToBoxAdapter(
              child: KpiStrip(children: [
                GradientKpi(icon: Icons.trending_up_rounded, label: 'Total income', value: totalIncome, format: reportMoney, accent: Accent.emerald),
                GradientKpi(icon: Icons.trending_down_rounded, label: 'Total expense', value: totalExpense, format: reportMoney, accent: Accent.rose),
                GradientKpi(
                  icon: Icons.balance_rounded,
                  label: net >= 0 ? 'Net profit' : 'Net loss',
                  value: net,
                  format: reportMoney,
                  accent: net >= 0 ? Accent.ocean : Accent.rose,
                ),
                GradientKpi(icon: Icons.event_busy_rounded, label: 'Loss days', value: lossDays.length, accent: lossDays.isEmpty ? Accent.slate : Accent.amber),
                if (projected != null)
                  GradientKpi(
                    icon: Icons.show_chart_rounded,
                    label: 'Trend net (next $_horizon days)',
                    value: projected,
                    format: reportMoney,
                    accent: projected < 0 ? Accent.amber : Accent.violet,
                  ),
              ]),
            ),
          ),
          sliverStagger(count: panels.length, builder: (_, i) => panels[i], gap: 12, padding: const EdgeInsets.fromLTRB(16, 16, 16, 0)),
        ],
      ],
    );
  }
}

// ── Charts ──────────────────────────────────────────────────────────────

/// Bottom axis showing ~5 evenly spaced day labels.
SideTitles _dayTitles(List<DateTime> dates, Color color) {
  final step = math.max(1, (dates.length / 5).ceil());
  return SideTitles(
    showTitles: true,
    reservedSize: 24,
    interval: 1,
    getTitlesWidget: (v, m) {
      final i = v.round();
      if (v != i.toDouble() || i < 0 || i >= dates.length || i % step != 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(DateFormat('d MMM').format(dates[i]), style: TextStyle(fontSize: 9.5, color: color)),
      );
    },
  );
}

/// (min, max) for a value axis that always includes zero, padded 15%.
(double, double) _axisBounds(Iterable<double> values) {
  final lo = values.fold<double>(0, math.min);
  final hi = values.fold<double>(0, math.max);
  if (lo == 0 && hi == 0) return (-1, 1);
  return (lo * 1.15, hi * 1.15);
}

class _NetBars extends StatelessWidget {
  final List<_DayTotal> days;
  const _NetBars({required this.days});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final (minY, maxY) = _axisBounds(days.map((d) => d.net));
    final interval = (maxY - minY) / 4;
    return LayoutBuilder(builder: (_, box) {
      final barWidth = ((box.maxWidth - 44) / days.length * 0.65).clamp(1.5, 18.0);
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, t, _) => BarChart(BarChartData(
          minY: minY,
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (_) => FlLine(color: p.line, strokeWidth: 1, dashArray: const [4, 4]),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: interval,
                getTitlesWidget: (v, m) => v == m.max || v == m.min ? const SizedBox.shrink() : Text(_axisMoney(v), style: TextStyle(fontSize: 9.5, color: p.label)),
              ),
            ),
            bottomTitles: AxisTitles(sideTitles: _dayTitles([for (final d in days) d.date], p.label)),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => p.text,
              tooltipRoundedRadius: 8,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (g, _, _, _) => BarTooltipItem(
                '${fmtDate(days[g.x].date)}\n${reportMoney(days[g.x].net)}',
                TextStyle(color: p.card, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: days[i].net * t,
                  width: barWidth,
                  color: days[i].net >= 0 ? p.ok : p.error,
                  borderRadius: BorderRadius.circular(math.min(4, barWidth / 2)),
                ),
              ]),
          ],
        )),
      );
    });
  }
}

/// Actual daily net (solid) with the fitted straight line drawn across the
/// history and extended [horizon] days ahead (dashed).
class _TrendChart extends StatelessWidget {
  final List<_DayTotal> days;
  final double intercept;
  final double slope;
  final int horizon;
  const _TrendChart({required this.days, required this.intercept, required this.slope, required this.horizon});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final trendColor = Accent.violet.primary;
    final total = days.length + horizon;
    final dates = [
      for (final d in days) d.date,
      for (var i = 1; i <= horizon; i++) DateTime(days.last.date.year, days.last.date.month, days.last.date.day + i),
    ];
    final trendAt = [for (var i = 0; i < total; i++) intercept + slope * i];
    final (minY, maxY) = _axisBounds([...days.map((d) => d.net), ...trendAt]);
    final interval = (maxY - minY) / 4;

    return LineChart(LineChartData(
      minX: 0,
      maxX: (total - 1).toDouble(),
      minY: minY,
      maxY: maxY,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: interval,
        getDrawingHorizontalLine: (_) => FlLine(color: p.line, strokeWidth: 1, dashArray: const [4, 4]),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            interval: interval,
            getTitlesWidget: (v, m) => v == m.max || v == m.min ? const SizedBox.shrink() : Text(_axisMoney(v), style: TextStyle(fontSize: 9.5, color: p.label)),
          ),
        ),
        bottomTitles: AxisTitles(sideTitles: _dayTitles(dates, p.label)),
      ),
      extraLinesData: ExtraLinesData(verticalLines: [
        VerticalLine(x: (days.length - 1).toDouble(), color: p.line, strokeWidth: 1, dashArray: const [3, 3]),
      ]),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => p.text,
          tooltipRoundedRadius: 8,
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(
                '${s.barIndex == 0 ? fmtDate(dates[s.x.round()]) : 'Trend'}: ${reportMoney(s.y)}',
                TextStyle(color: s.barIndex == 0 ? p.card : trendColor.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [for (var i = 0; i < days.length; i++) FlSpot(i.toDouble(), days[i].net)],
          color: p.brand,
          barWidth: 2,
          isCurved: true,
          preventCurveOverShooting: true,
          dotData: const FlDotData(show: false),
        ),
        LineChartBarData(
          spots: [for (var i = 0; i < total; i++) FlSpot(i.toDouble(), trendAt[i])],
          color: trendColor,
          barWidth: 2,
          dashArray: const [6, 4],
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: trendColor.withValues(alpha: 0.08), cutOffY: 0, applyCutOffY: true),
          aboveBarData: BarAreaData(show: true, color: trendColor.withValues(alpha: 0.08), cutOffY: 0, applyCutOffY: true),
        ),
      ],
    ));
  }
}

/// Streamgraph — a stacked area whose invisible baseline sits at minus half
/// each day's total, so the income/expense bands float centred on zero.
/// Same construction as desktop's StreamgraphChart, drawn with fl_chart's
/// between-lines fill.
class _Streamgraph extends StatelessWidget {
  final List<_DayTotal> days;
  const _Streamgraph({required this.days});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    // Negative daily totals (net reversals) are drawn as zero thickness.
    final income = [for (final d in days) math.max(0.0, d.income)];
    final expense = [for (final d in days) math.max(0.0, d.expense)];
    final base = [for (var i = 0; i < days.length; i++) -(income[i] + expense[i]) / 2];
    final mid = [for (var i = 0; i < days.length; i++) base[i] + income[i]];
    final top = [for (var i = 0; i < days.length; i++) mid[i] + expense[i]];
    final extent = top.fold<double>(0, math.max);

    LineChartBarData edge(List<double> ys) => LineChartBarData(
          spots: [for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])],
          isCurved: true,
          preventCurveOverShooting: true,
          color: Colors.transparent,
          barWidth: 0,
          dotData: const FlDotData(show: false),
        );

    return LineChart(LineChartData(
      minX: 0,
      maxX: math.max(1, days.length - 1).toDouble(),
      minY: -extent * 1.1,
      maxY: extent * 1.1,
      borderData: FlBorderData(show: false),
      gridData: const FlGridData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: _dayTitles([for (final d in days) d.date], p.label)),
      ),
      lineBarsData: [edge(base), edge(mid), edge(top)],
      betweenBarsData: [
        BetweenBarsData(fromIndex: 0, toIndex: 1, color: p.ok.withValues(alpha: 0.85)),
        BetweenBarsData(fromIndex: 1, toIndex: 2, color: p.error.withValues(alpha: 0.85)),
      ],
      lineTouchData: LineTouchData(
        getTouchedSpotIndicator: (_, idx) => [for (final _ in idx) null],
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => p.text,
          tooltipRoundedRadius: 8,
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItems: (spots) => [
            for (final s in spots)
              s.barIndex == 0
                  ? null
                  : LineTooltipItem(
                      s.barIndex == 1
                          ? '${fmtDate(days[s.x.round()].date)}\nIncome: ${reportMoney(days[s.x.round()].income)}'
                          : 'Expense: ${reportMoney(days[s.x.round()].expense)}',
                      TextStyle(color: p.card, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
          ],
        ),
      ),
    ));
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 11.5, color: p.label)),
    ]);
  }
}
