import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/accounting_reports_service.dart';
import 'report_widgets.dart';

typedef _AccountTotal = ({int id, String code, String name, double amount});

// Profit & loss — port of desktop profit-loss/ProfitLoss.tsx: Income
// accounts total minus Expense accounts total over a date range. Computed
// client-side from every journal_entry_lines row (fetched once, then
// filtered by entry date and grouped by account), same reasoning as desktop:
// OData can't aggregate across rows and there's no backend P&L endpoint.
class ProfitLossPage extends StatefulWidget {
  const ProfitLossPage({super.key});

  @override
  State<ProfitLossPage> createState() => _ProfitLossPageState();
}

class _ProfitLossPageState extends State<ProfitLossPage> {
  final _service = AccountingReportsService(ApiClient());
  List<ReportLine> _lines = [];
  bool _loading = true;
  String? _error;

  // Desktop defaults to month-to-date.
  ReportRangePreset _preset = ReportRangePreset.thisMonth;
  late DateTime _start;
  late DateTime _end;

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

  /// Per-account totals for one account type in the range, biggest first.
  /// [sign] turns a line into its natural-balance amount (credit − debit for
  /// income, debit − credit for expense), same as desktop's groupByAccount.
  List<_AccountTotal> _group(String type, double Function(ReportLine) sign) {
    final totals = <int, _AccountTotal>{};
    for (final l in _lines) {
      if (l.accountType != type || !inDayRange(l.entryDate, _start, _end)) continue;
      final prev = totals[l.accountId];
      totals[l.accountId] = (
        id: l.accountId,
        code: l.accountCode ?? '',
        name: l.accountName ?? 'Account ${l.accountId}',
        amount: (prev?.amount ?? 0) + sign(l),
      );
    }
    return totals.values.where((a) => a.amount != 0).toList()..sort((a, b) => b.amount.compareTo(a.amount));
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final income = _group('INCOME', (l) => l.credit - l.debit);
    final expense = _group('EXPENSE', (l) => l.debit - l.credit);
    final totalIncome = income.fold<double>(0, (s, a) => s + a.amount);
    final totalExpense = expense.fold<double>(0, (s, a) => s + a.amount);
    final net = totalIncome - totalExpense;

    return MotionScaffold(
      title: 'Profit & loss',
      icon: Icons.stacked_line_chart_rounded,
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
              child: KpiStrip(children: [for (var i = 0; i < 3; i++) const SkeletonBox(height: 112, radius: 12)]),
            ),
          ),
          sliverSkeleton(count: 3, height: 200),
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
              ]),
            ),
          ),
          sliverStagger(
            count: 3,
            gap: 12,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            builder: (_, i) => switch (i) {
              0 => ReportPanel(
                  icon: Icons.donut_large_rounded,
                  title: 'Income vs expense',
                  sub: 'Posted in the selected range',
                  child: totalIncome <= 0 && totalExpense <= 0
                      ? const ReportEmpty(icon: Icons.donut_large_rounded, text: 'Nothing posted in this range.')
                      : _IncomeExpenseDonut(income: totalIncome, expense: totalExpense),
                ),
              1 => ReportPanel(
                  icon: Icons.south_west_rounded,
                  accent: Accent.emerald,
                  title: 'Income accounts',
                  sub: '${income.length} ${income.length == 1 ? 'account' : 'accounts'}',
                  child: income.isEmpty
                      ? const ReportEmpty(icon: Icons.south_west_rounded, text: 'No income posted in this range.')
                      : AccountAmountList(rows: [for (final a in income) (code: a.code, name: a.name, amount: a.amount)], amountColor: p.ok),
                ),
              _ => ReportPanel(
                  icon: Icons.north_east_rounded,
                  accent: Accent.rose,
                  title: 'Expense accounts',
                  sub: '${expense.length} ${expense.length == 1 ? 'account' : 'accounts'}',
                  child: expense.isEmpty
                      ? const ReportEmpty(icon: Icons.north_east_rounded, text: 'No expense posted in this range.')
                      : AccountAmountList(rows: [for (final a in expense) (code: a.code, name: a.name, amount: a.amount)], amountColor: p.error),
                ),
            },
          ),
        ],
      ],
    );
  }
}

class _IncomeExpenseDonut extends StatelessWidget {
  final double income;
  final double expense;
  const _IncomeExpenseDonut({required this.income, required this.expense});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    // Same as desktop: a negative total (more reversals than postings)
    // contributes no slice rather than a nonsensical negative one.
    final slices = [
      (label: 'Income', value: income < 0 ? 0.0 : income, color: p.ok),
      (label: 'Expense', value: expense < 0 ? 0.0 : expense, color: p.error),
    ].where((s) => s.value > 0).toList();
    final total = slices.fold<double>(0, (s, e) => s + e.value);

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
                for (final s in slices) PieChartSectionData(value: s.value, color: s.color, radius: 16 + 4 * t, showTitle: false),
              ],
            )),
          ),
          Text('Total', style: TextStyle(fontSize: 11, color: p.label)),
        ]),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < slices.length; i++) ...[
            if (i > 0) Divider(height: 14, color: p.line),
            Row(children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: slices[i].color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(slices[i].label, style: TextStyle(fontSize: 12.5, color: p.text))),
              Text(reportMoneyWhole(slices[i].value), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text)),
              SizedBox(
                width: 40,
                child: Text('${(slices[i].value / total * 100).toStringAsFixed(0)}%', textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, color: p.label)),
              ),
            ]),
          ],
        ]),
      ),
    ]);
  }
}
