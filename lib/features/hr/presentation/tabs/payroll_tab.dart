import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'dash_common.dart';
import 'hr_charts.dart';

/// Ported from desktop tabs/PayrollTab.tsx — pay periods with a payslip
/// breakdown sheet, plus net-pay totals and a trend chart.
class PayrollTab extends DashSection {
  const PayrollTab({super.key, required super.employeeId, super.refreshToken});

  @override
  State<PayrollTab> createState() => _PayrollTabState();
}

class _PayrollTabState extends State<PayrollTab> with DashLoader<PayrollTab> {
  List<Map<String, dynamic>> _rows = [];

  @override
  Future<void> fetch() async {
    final rows = await service.getPayrolls(widget.employeeId);
    if (mounted) setState(() => _rows = rows);
  }

  String _period(Map<String, dynamic> r) => '${fmtDate(parseDate(r['start_date']))} to ${fmtDate(parseDate(r['end_date']))}';

  void _openSlip(Map<String, dynamic> r) {
    showMotionSheet<void>(context, (ctx) {
      final p = MarketPalette.of(ctx);
      Widget line(String label, dynamic v, {bool bold = false, Color? color}) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: p.label, fontWeight: bold ? FontWeight.w700 : FontWeight.w500))),
              Text(money(toDouble(v)), style: TextStyle(fontSize: 13.5, color: color ?? p.text, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
            ]),
          );
      return FormSheet(
        title: 'Payslip',
        subtitle: _period(r),
        children: [
          Row(children: [StatusPill(humanize('${r['status'] ?? ''}'), tone: toneForStatus('${r['status']}'))]),
          const SizedBox(height: 12),
          const SectionHeader('Earnings'),
          line('Basic salary', r['basic']),
          line('House rent', r['house_rent']),
          line('Medical allowance', r['medical_allowance']),
          line('Transport allowance', r['transport_allowance']),
          line('Other allowance', r['other_allowance']),
          line('Bonuses', r['bonuses'], color: p.ok),
          line('Gross salary', r['gross_salary'], bold: true, color: p.ok),
          const SizedBox(height: 8),
          const SectionHeader('Deductions'),
          line('Tax', r['tax'], color: p.error),
          line('Social security', r['social_security'], color: p.error),
          line('Other deductions', r['other_deductions'], color: p.error),
          line('Penalties', r['penalties'], color: p.error),
          line('Total deductions', r['total_deductions'], bold: true, color: p.error),
          const SizedBox(height: 10),
          GlowCard(
            gradient: Accent.ocean.gradient,
            child: Row(children: [
              const Text('Net pay', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              CountUp(value: toDouble(r['net_salary']), format: (v) => money(v), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
          ),
          const SizedBox(height: 12),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = stateSliver();
    if (state != null) return state;
    if (_rows.isEmpty) return sliverEmpty(icon: Icons.account_balance_wallet_outlined, title: 'No payroll records yet');

    final paid = _rows.where((r) => '${r['status']}'.toUpperCase() == 'PAID');
    final totalNet = _rows.fold<double>(0, (a, r) => a + toDouble(r['net_salary']));
    final last = _rows.first;
    final recent = _rows.take(6).toList().reversed.toList();

    return SliverMainAxisGroup(slivers: [
      sliverStats([
        MiniStat(icon: Icons.payments_rounded, label: 'Total net pay', value: totalNet, format: (v) => money(v), tone: MarketTone.ok),
        MiniStat(icon: Icons.receipt_long_rounded, label: 'Last net pay', value: toDouble(last['net_salary']), format: (v) => money(v), tone: MarketTone.brand),
        MiniStat(icon: Icons.task_alt_rounded, label: 'Paid periods', value: paid.length, tone: MarketTone.info),
        MiniStat(icon: Icons.hourglass_top_rounded, label: 'Pending periods', value: _rows.where((r) => '${r['status']}'.toUpperCase() == 'PENDING').length, tone: MarketTone.warn),
      ]),
      sliverBox(ChartPanel(
        title: 'Net pay trend',
        subtitle: 'Last ${recent.length} pay periods',
        icon: Icons.bar_chart_rounded,
        accent: Accent.emerald,
        height: 180,
        child: GroupedBarChart(
          categories: recent.map((r) {
            final d = parseDate(r['start_date']);
            return d == null ? '' : DateFormat('MMM yy').format(d.toLocal());
          }).toList(),
          series: [ChartSeries('Net pay', recent.map((r) => toDouble(r['net_salary'])).toList(), const Color(0xFF30914C))],
          format: (v) => compactNum(v),
        ),
      )),
      sliverStagger(
        count: _rows.length,
        builder: (_, i) {
          final r = _rows[i];
          return MotionTile(
            onTap: () => _openSlip(r),
            leading: const AccentIcon(Icons.receipt_long_rounded, accent: Accent.emerald, size: 42),
            title: _period(r),
            subtitle: 'Gross ${money(toDouble(r['gross_salary']))} · Deductions ${money(toDouble(r['total_deductions']))}',
            meta: 'Net ${money(toDouble(r['net_salary']))}',
            trailing: StatusPill(humanize('${r['status'] ?? ''}'), tone: toneForStatus('${r['status']}')),
          );
        },
      ),
    ]);
  }
}
