import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'payroll_common.dart';

/// Payroll records — mirrors desktop EmployeePayroll.tsx: a date range
/// (overlap filter on start/end date), KPI totals from hrm/payroll-stats,
/// an optional report panel (status breakdown + earnings), per-row payslip
/// detail with PDF share, and delete through the dedicated hrm/payroll
/// route (which also rolls the amount out of the batch total).
class PayrollPage extends StatefulWidget {
  const PayrollPage({super.key});

  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage> {
  final _client = ApiClient();
  late DateTime _start;
  late DateTime _end;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _stats = {};
  String _q = '';
  String _status = 'ALL';
  bool _report = false;

  @override
  void initState() {
    super.initState();
    _resetRange();
    _load();
  }

  void _resetRange() {
    final now = DateTime.now();
    _end = DateTime(now.year, now.month, now.day);
    _start = DateTime(now.year, now.month - 1, now.day);
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    final filter = Uri.encodeComponent('start_date le ${isoUtc(_end)} and end_date ge ${isoUtc(_start)}');
    try {
      final results = await Future.wait([
        _client.get('payrolls?\$filter=$filter&\$expand=employee(\$expand=designation)&\$orderby=id desc&\$top=2000'),
        _client.get('hrm/payroll-stats?start_date=${ymd(_start)}&end_date=${ymd(_end)}', isV8: false).catchError((_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _rows = unwrapList(results[0]).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
        final s = results[1];
        if (s is Map) _stats = s.cast<String, dynamic>();
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load payroll'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    return _rows.where((r) {
      final st = str(r['status']).isEmpty ? 'PENDING' : str(r['status']).toUpperCase();
      if (_status != 'ALL' && st != _status) return false;
      if (q.isEmpty) return true;
      final emp = asMap(r['employee']);
      final hay = [employeeName(emp, r['employee_id']), str(emp?['employee_no']), st, nested(emp ?? const {}, 'designation')].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  int _stat(String k) => toInt(_stats[k]);
  double _statD(String k) => n(_stats[k]);

  Future<bool> _delete(Map<String, dynamic> row) async {
    final ok = await confirmMarket(context,
        title: 'Delete payroll', message: 'Delete this payroll for ${employeeName(asMap(row['employee']), row['employee_id'])}? This cannot be undone.');
    if (!ok) return false;
    try {
      await _client.delete('hrm/payroll', row['id'], isV8: false);
      if (!mounted) return true;
      setState(() => _rows.removeWhere((r) => r['id'] == row['id']));
      marketToast(context, 'Payroll deleted');
      _load();
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Failed to delete payroll'), error: true);
      return false;
    }
  }

  Future<void> _openPayslip(Map<String, dynamic> row) async {
    final deleted = await showMotionSheet<bool>(context, (_) => _PayslipSheet(id: row['id'], fallback: row, onDelete: () => _delete(row)));
    if (deleted == true) _load();
  }

  Future<void> _pickRange() async {
    final picked = await showMotionSheet<(DateTime, DateTime)>(context, (_) => _RangeSheet(start: _start, end: _end));
    if (picked == null) return;
    setState(() {
      _start = picked.$1;
      _end = picked.$2;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final rows = _visible;
    final total = _stat('total');
    final avg = total == 0 ? 0.0 : _statD('totalNet') / total;
    final statusCounts = {
      'PAID': _stat('paid'),
      'GENERATED': _stat('generated'),
      'PENDING': _stat('pending'),
      'CANCELLED': _stat('cancelled'),
    };
    return MotionScaffold(
      title: 'Payroll',
      subtitle: '${fmtDate(_start)} – ${fmtDate(_end)}',
      icon: Icons.account_balance_wallet_outlined,
      accent: Accent.ocean,
      onRefresh: _load,
      actions: [
        IconButton(
          tooltip: 'Report',
          onPressed: () => setState(() => _report = !_report),
          icon: Icon(_report ? Icons.insert_chart_rounded : Icons.insert_chart_outlined_rounded),
        ),
        IconButton(tooltip: 'Date range', onPressed: _pickRange, icon: const Icon(Icons.date_range_rounded)),
      ],
      headerExtra: HeaderSearch(hint: 'Search name, number or status', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 16),
          sliver: SliverToBoxAdapter(
            child: KpiGrid(children: [
              KpiTile(icon: Icons.groups_rounded, label: 'Payroll records', value: total, tone: MarketTone.brand),
              KpiTile(icon: Icons.payments_outlined, label: 'Total gross', value: _statD('totalGross'), format: money, tone: MarketTone.brand),
              KpiTile(icon: Icons.card_giftcard_rounded, label: 'Total bonuses', value: _statD('totalBonuses'), format: money, tone: MarketTone.ok),
              KpiTile(icon: Icons.remove_circle_outline_rounded, label: 'Total deductions', value: _statD('totalDeductions'), format: money, tone: MarketTone.error),
              KpiTile(icon: Icons.account_balance_wallet_rounded, label: 'Total net pay', value: _statD('totalNet'), format: money, tone: MarketTone.brand),
              KpiTile(icon: Icons.trending_up_rounded, label: 'Average net pay', value: avg, format: money, tone: MarketTone.brand),
              KpiTile(icon: Icons.check_circle_outline_rounded, label: 'Paid', value: _stat('paid'), tone: MarketTone.ok),
              KpiTile(icon: Icons.schedule_rounded, label: 'Pending', value: _stat('pending'), tone: MarketTone.warn),
            ]),
          ),
        ),
        sliverBox(
          GlowCard(
            onTap: _pickRange,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              const AccentIcon(Icons.date_range_rounded, accent: Accent.ocean, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Pay period overlap', style: TextStyle(fontSize: 11.5, color: p.label)),
                  Text('${fmtDate(_start)} – ${fmtDate(_end)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                ]),
              ),
              TextButton(
                onPressed: () {
                  setState(_resetRange);
                  _load();
                },
                child: const Text('Reset'),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            child: !_report
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(children: [
                      FadeSlideIn(
                        child: SectionCard(
                          title: 'Status breakdown',
                          subtitle: '${fmtDate(_start)} – ${fmtDate(_end)}',
                          icon: Icons.pie_chart_outline_rounded,
                          child: statusCounts.values.every((v) => v == 0)
                              ? Text('No payroll in this period', style: TextStyle(color: p.label, fontSize: 12.5))
                              : _StatusStack(counts: statusCounts),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FadeSlideIn(
                        index: 1,
                        child: SectionCard(
                          title: 'Earnings overview',
                          subtitle: 'Selected period',
                          icon: Icons.receipt_long_outlined,
                          child: Builder(builder: (_) {
                            final vals = [_statD('totalGross'), _statD('totalBonuses'), _statD('totalDeductions'), _statD('totalNet')];
                            final mx = vals.fold<double>(0, (a, b) => b > a ? b : a);
                            final colors = [p.info, p.ok, p.error, Accent.ocean.primary];
                            final labels = ['Gross', 'Bonuses', 'Deductions', 'Net pay'];
                            return Column(children: [
                              for (var i = 0; i < 4; i++) AnimatedBar(label: labels[i], value: vals[i], max: mx, color: colors[i], format: money),
                            ]);
                          }),
                        ),
                      ),
                    ]),
                  ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _status,
              options: [
                (id: 'ALL', label: 'All', count: _rows.length),
                for (final s in ['PENDING', 'GENERATED', 'APPROVED', 'PAID', 'CANCELLED'])
                  if (_rows.any((r) => (str(r['status']).isEmpty ? 'PENDING' : str(r['status']).toUpperCase()) == s))
                    (id: s, label: humanize(s), count: _rows.where((r) => (str(r['status']).isEmpty ? 'PENDING' : str(r['status']).toUpperCase()) == s).length),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton(height: 86)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.account_balance_wallet_outlined,
            title: _rows.isEmpty ? 'No payroll in this period' : 'No matches',
            message: _rows.isEmpty ? 'Run payroll from payroll process, or pick another date range.' : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final emp = asMap(r['employee']);
              final name = employeeName(emp, r['employee_id']);
              final sub = [if (str(emp?['employee_no']).isNotEmpty) '#${emp?['employee_no']}', nested(emp ?? const {}, 'designation')].where((s) => s.isNotEmpty).join(' · ');
              final status = str(r['status']).isEmpty ? 'PENDING' : str(r['status']);
              return MotionTile(
                key: ValueKey(r['id']),
                leading: InitialsAvatar(name, size: 42),
                title: name,
                subtitle: '${fmtDate(parseDate(r['start_date']))} to ${fmtDate(parseDate(r['end_date']))}${sub.isEmpty ? '' : '\n$sub'}',
                meta: 'Gross ${plain(n(r['gross_salary']))}  ·  bonus +${plain(n(r['bonuses']))}  ·  deductions −${plain(n(r['total_deductions']))}',
                trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  Text(money(n(r['net_salary'])), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.text)),
                  const SizedBox(height: 4),
                  StatusPill(humanize(status), tone: payrollTone(status)),
                ]),
                onTap: () => _openPayslip(r),
                onLongPress: () async {
                  final k = await showActionSheet(context, title: name, actions: [
                    (key: 'view', label: 'View payslip', icon: Icons.receipt_long_outlined, destructive: false),
                    (key: 'pdf', label: 'Share payslip', icon: Icons.picture_as_pdf_outlined, destructive: false),
                    (key: 'del', label: 'Delete payroll', icon: Icons.delete_outline_rounded, destructive: true),
                  ]);
                  if (!mounted) return;
                  if (k == 'view') _openPayslip(r);
                  if (k == 'pdf') _share(r['id'], r);
                  if (k == 'del') _delete(r);
                },
                onDelete: () => _delete(r),
              );
            },
          ),
      ],
    );
  }

  Future<void> _share(Object id, Map<String, dynamic> fallback) async {
    try {
      final res = await _client.get('payrolls($id)?\$expand=employee(\$expand=designation)');
      final row = (res is Map && res['value'] is Map) ? (res['value'] as Map).cast<String, dynamic>() : (res is Map ? res.cast<String, dynamic>() : fallback);
      await sharePayslip(row);
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not build payslip'), error: true);
    }
  }
}

class _StatusStack extends StatelessWidget {
  final Map<String, int> counts;
  const _StatusStack({required this.counts});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final entries = counts.entries.where((e) => e.value > 0).toList();
    final total = entries.fold<int>(0, (a, e) => a + e.value);
    Color c(String k) => p.tone(payrollTone(k)).fg;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        ProgressRing(
          value: total == 0 ? 0 : (counts['PAID'] ?? 0) / total,
          size: 72,
          color: p.ok,
          center: Column(mainAxisSize: MainAxisSize.min, children: [
            CountUp(value: total, format: (v) => '${v.round()}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.text)),
            Text('payrolls', style: TextStyle(fontSize: 9.5, color: p.label)),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(children: [
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: c(e.key), shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(humanize(e.key), style: TextStyle(fontSize: 12.5, color: p.text))),
                  Text('${e.value}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text)),
                ]),
              ),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 10,
          child: Row(children: [
            for (final e in entries)
              Expanded(
                flex: e.value,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 700),
                  builder: (_, v, _) => Opacity(opacity: v, child: Container(color: c(e.key))),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }
}

class _RangeSheet extends StatefulWidget {
  final DateTime start;
  final DateTime end;
  const _RangeSheet({required this.start, required this.end});

  @override
  State<_RangeSheet> createState() => _RangeSheetState();
}

class _RangeSheetState extends State<_RangeSheet> {
  late DateTime? _s = widget.start;
  late DateTime? _e = widget.end;

  @override
  Widget build(BuildContext context) => FormSheet(
        title: 'Date range',
        subtitle: 'Payrolls whose period overlaps this range',
        submitLabel: 'Apply',
        onSubmit: () {
          if (_s == null || _e == null) {
            marketToast(context, 'Pick both dates', error: true);
            return;
          }
          if (_e!.isBefore(_s!)) {
            marketToast(context, 'End date must be after start date', error: true);
            return;
          }
          Navigator.pop(context, (_s!, _e!));
        },
        children: [
          FormLabel(label: 'From', required: true, child: DatePickField(value: _s, onChanged: (d) => setState(() => _s = d))),
          FormLabel(label: 'To', required: true, child: DatePickField(value: _e, onChanged: (d) => setState(() => _e = d))),
        ],
      );
}

/// Payslip detail — re-fetches the row with a fresh $expand like desktop's
/// loadSelectedEmployee, then offers PDF share and delete.
class _PayslipSheet extends StatefulWidget {
  final Object id;
  final Map<String, dynamic> fallback;
  final Future<bool> Function() onDelete;
  const _PayslipSheet({required this.id, required this.fallback, required this.onDelete});

  @override
  State<_PayslipSheet> createState() => _PayslipSheetState();
}

class _PayslipSheetState extends State<_PayslipSheet> {
  final _client = ApiClient();
  Map<String, dynamic>? _row;
  bool _loading = true;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _client.get('payrolls(${widget.id})?\$expand=employee(\$expand=designation)');
      final v = (res is Map && res['value'] is Map) ? res['value'] : res;
      if (mounted) setState(() => _row = v is Map ? v.cast<String, dynamic>() : widget.fallback);
    } catch (_) {
      if (mounted) setState(() => _row = widget.fallback);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final r = _row ?? widget.fallback;
    final emp = asMap(r['employee']);
    final name = employeeName(emp, r['employee_id']);
    final status = str(r['status']).isEmpty ? 'PENDING' : str(r['status']);
    final sub = [if (str(emp?['employee_no']).isNotEmpty) '#${emp?['employee_no']}', nested(emp ?? const {}, 'designation').isEmpty ? 'No designation' : nested(emp ?? const {}, 'designation')].join(' · ');
    return FormSheet(
      title: 'Employee payslip',
      subtitle: '${fmtDate(parseDate(r['start_date']))} – ${fmtDate(parseDate(r['end_date']))}',
      submitLabel: 'Share payslip',
      busy: _sharing,
      onSubmit: _loading
          ? null
          : () async {
              setState(() => _sharing = true);
              try {
                await sharePayslip(r);
              } catch (e) {
                if (context.mounted) marketToast(context, errorMessage(e, 'Could not build payslip'), error: true);
              } finally {
                if (mounted) setState(() => _sharing = false);
              }
            },
      extraAction: IconButton(
        tooltip: 'Delete payroll',
        icon: Icon(Icons.delete_outline_rounded, color: p.error),
        onPressed: () async {
          final ok = await widget.onDelete();
          if (ok && context.mounted) Navigator.pop(context, true);
        },
      ),
      children: [
        if (_loading) ...[
          const SkeletonBox(height: 64, radius: 12),
          const SizedBox(height: 10),
          const SkeletonBox(height: 160, radius: 12),
        ] else ...[
          GlowCard(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              InitialsAvatar(name, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
                  Text(sub, style: TextStyle(fontSize: 12, color: p.label)),
                ]),
              ),
              StatusPill(humanize(status), tone: payrollTone(status)),
            ]),
          ),
          const SizedBox(height: 12),
          AmountLine('Gross salary', n(r['gross_salary']), count: true),
          AmountLine('Bonuses', n(r['bonuses']), tone: MarketTone.ok, count: true),
          AmountLine('Deductions', n(r['total_deductions']), tone: MarketTone.error, count: true),
          const SizedBox(height: 4),
          GlowCard(
            gradient: Accent.ocean.gradient,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Icon(Icons.account_balance_wallet_rounded, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(child: Text('Net pay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
              CountUp(value: n(r['net_salary']), format: money, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            ]),
          ),
          if (str(r['hr_notes']).isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(title: 'HR notes', child: Text(str(r['hr_notes']), style: TextStyle(color: p.text, fontSize: 13))),
          ],
        ],
      ],
    );
  }
}
