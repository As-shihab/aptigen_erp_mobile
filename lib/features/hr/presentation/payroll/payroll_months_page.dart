import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'payroll_common.dart';

/// Payroll months — mirrors desktop PayrollHistory.tsx: one row per
/// generated batch (payroll_historys), with a batch panel to review and
/// approve each employee's payroll, then send the approved total to
/// Accounting as a payment request (once per batch). The per-batch Excel
/// export becomes a shareable PDF report.
class PayrollMonthsPage extends StatefulWidget {
  const PayrollMonthsPage({super.key});

  @override
  State<PayrollMonthsPage> createState() => _PayrollMonthsPageState();
}

class _PayrollMonthsPageState extends State<PayrollMonthsPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _q = '';
  String _status = 'ALL';
  Object? _exportingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    try {
      final res = await _client.get('payroll_historys?\$expand=generator(\$expand=user)&\$orderby=start_date desc&\$top=1000');
      if (!mounted) return;
      setState(() => _rows = unwrapList(res).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList());
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load payroll months'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _month(Map<String, dynamic> r) {
    final d = parseDate(r['start_date']);
    return d == null ? '-' : DateFormat('MMMM yyyy').format(d);
  }

  String _generator(Map<String, dynamic> r) {
    final u = asMap(asMap(r['generator'])?['user']);
    final s = str(u?['name']).isNotEmpty ? str(u?['name']) : str(u?['email']);
    return s;
  }

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    return _rows.where((r) {
      if (_status != 'ALL' && str(r['status']).toUpperCase() != _status) return false;
      if (q.isEmpty) return true;
      return [_month(r), str(r['status']), str(r['hr_notes']), _generator(r), str(r['total_employee']), str(r['total_amount'])].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _export(Map<String, dynamic> row) async {
    setState(() => _exportingId = row['id']);
    try {
      final res = await _client.get('payrolls?\$filter=${Uri.encodeComponent('payroll_history_id eq ${row['id']}')}&\$expand=employee(\$expand=designation)&\$orderby=id asc&\$top=5000');
      final rows = unwrapList(res).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
      await shareBatchReport(row, rows);
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Failed to export'), error: true);
    } finally {
      if (mounted) setState(() => _exportingId = null);
    }
  }

  void _open(Map<String, dynamic> row) => pushMotion(context, PayrollBatchPage(history: row)).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final rows = _visible;
    final totalAmount = _rows.fold<double>(0, (a, r) => a + n(r['total_amount']));
    final totalEmp = _rows.fold<int>(0, (a, r) => a + toInt(r['total_employee']));
    final statuses = {for (final r in _rows) str(r['status']).toUpperCase()}..remove('');
    return MotionScaffold(
      title: 'Payroll months',
      subtitle: '${_rows.length} ${_rows.length == 1 ? 'batch' : 'batches'}',
      icon: Icons.history_rounded,
      accent: Accent.ocean,
      onRefresh: _load,
      headerExtra: HeaderSearch(hint: 'Search month, status or notes', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 16),
          sliver: SliverToBoxAdapter(
            child: KpiGrid(children: [
              KpiTile(icon: Icons.calendar_month_rounded, label: 'Payroll months', value: _rows.length, tone: MarketTone.brand),
              KpiTile(icon: Icons.account_balance_wallet_rounded, label: 'Total amount', value: totalAmount, format: money, tone: MarketTone.ok),
              KpiTile(icon: Icons.groups_rounded, label: 'Employee payrolls', value: totalEmp, tone: MarketTone.brand),
            ]),
          ),
        ),
        if (statuses.length > 1)
          SliverPadding(
            padding: const EdgeInsets.only(top: 14),
            sliver: SliverToBoxAdapter(
              child: ChipFilter<String>(
                value: _status,
                options: [
                  (id: 'ALL', label: 'All', count: _rows.length),
                  for (final s in statuses) (id: s, label: humanize(s), count: _rows.where((r) => str(r['status']).toUpperCase() == s).length),
                ],
                onChanged: (v) => setState(() => _status = v),
              ),
            ),
          ),
        if (_loading)
          sliverSkeleton(height: 92)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.history_rounded,
            title: _rows.isEmpty ? 'No payroll generated yet' : 'No matches',
            message: _rows.isEmpty ? 'Generate payroll to create the first batch.' : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final gen = _generator(r);
              final exporting = _exportingId == r['id'];
              return MotionTile(
                key: ValueKey(r['id']),
                leading: const AccentIcon(Icons.calendar_month_rounded, accent: Accent.ocean, size: 42),
                title: _month(r),
                subtitle: '${toInt(r['total_employee'])} employees${gen.isEmpty ? '' : ' · by $gen'}${str(r['hr_notes']).isEmpty ? '' : '\n${str(r['hr_notes'])}'}',
                meta: 'Generated ${fmtDateTime(parseDate(r['created_at']))}',
                trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  Text(money(n(r['total_amount'])), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.ok)),
                  const SizedBox(height: 4),
                  exporting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : StatusPill(humanize(str(r['status'])), tone: batchTone(str(r['status']))),
                ]),
                onTap: () => _open(r),
                onLongPress: () async {
                  final k = await showActionSheet(context, title: _month(r), actions: [
                    (key: 'open', label: 'Review payrolls', icon: Icons.fact_check_outlined, destructive: false),
                    (key: 'export', label: 'Export batch report', icon: Icons.picture_as_pdf_outlined, destructive: false),
                  ]);
                  if (k == 'open') _open(r);
                  if (k == 'export') _export(r);
                },
              );
            },
          ),
      ],
    );
  }
}

/// One batch's employee payrolls: approve individually, view details, send
/// the approved total to Accounting (desktop PayrollBatchPanel).
class PayrollBatchPage extends StatefulWidget {
  final Map<String, dynamic> history;
  const PayrollBatchPage({super.key, required this.history});

  @override
  State<PayrollBatchPage> createState() => _PayrollBatchPageState();
}

class _PayrollBatchPageState extends State<PayrollBatchPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic>? _sent;
  Object? _busyId;
  bool _sending = false;
  bool _exporting = false;
  String _q = '';

  Map<String, dynamic> get h => widget.history;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    try {
      final data = await batchLoad(_client, {
        'rows': 'payrolls?\$filter=payroll_history_id eq ${h['id']}&\$expand=employee(\$select=id,first_name,last_name,employee_no)&\$orderby=id asc&\$top=1000',
        'req': "payment_requests?\$filter=reference_type eq 'PAYROLL_HISTORY' and reference_id eq ${h['id']}&\$select=id,status,amount&\$top=1",
      });
      if (!mounted) return;
      setState(() {
        _rows = data['rows'] ?? [];
        final pr = data['req'] ?? [];
        _sent = pr.isEmpty ? null : pr.first;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load payrolls'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _approved(Map<String, dynamic> r) => const {'APPROVED', 'PAID'}.contains(str(r['status']).toUpperCase());
  List<Map<String, dynamic>> get _approvedRows => _rows.where(_approved).toList();
  double get _approvedAmount => _approvedRows.fold<double>(0, (a, r) => a + n(r['net_salary']));

  String get _month {
    final d = parseDate(h['start_date']);
    return d == null ? 'Payroll batch' : DateFormat('MMMM yyyy').format(d);
  }

  Future<void> _approve(Map<String, dynamic> r) async {
    setState(() => _busyId = r['id']);
    try {
      await _client.put('payrolls', r['id'], {'status': 'APPROVED'});
      if (mounted) {
        setState(() => r['status'] = 'APPROVED');
        marketToast(context, 'Payroll approved');
      }
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Failed to approve payroll'), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _sendPayment() async {
    final approved = _approvedRows;
    final amount = _approvedAmount;
    final ok = await confirmMarket(
      context,
      title: 'Send payment request?',
      message:
          'This will send a payment request for ${approved.length} approved payroll${approved.length == 1 ? '' : 's'} totaling ${money(amount)}.\n\nEvery approved payroll included will be locked from being sent again individually, and this batch can only be sent for payment once. This cannot be undone.',
      confirm: 'Confirm and send',
      destructive: false,
    );
    if (!ok) return;
    setState(() => _sending = true);
    final s = parseDate(h['start_date']);
    final e = parseDate(h['end_date']);
    try {
      await _client.post(
        'payment_requests',
        {
          'source_module': 'HR',
          'reference_type': 'PAYROLL_HISTORY',
          'reference_id': h['id'],
          'party_type': null,
          'party_id': null,
          'requested_by': null,
          'request_no': 'PR-PAYROLLHIST-${h['id']}',
          'amount': amount,
          'status': 'PENDING',
          'remarks':
              'Payroll batch ${s == null ? '-' : DateFormat('dd MMM yyyy').format(s)} – ${e == null ? '-' : DateFormat('dd MMM yyyy').format(e)} · ${approved.length}/${_rows.length} payroll${_rows.length == 1 ? '' : 's'} approved',
        },
        isV8: true,
      );
      await Future.wait(approved.map((r) => _client.put('payrolls', r['id'], {'status': 'PAID'})));
      if (!mounted) return;
      setState(() {
        for (final r in approved) {
          r['status'] = 'PAID';
        }
        _sent = {'status': 'PENDING', 'amount': amount};
      });
      marketToast(context, 'Sent to accounting for payment');
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Failed to send payment request'), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final res = await _client.get('payrolls?\$filter=${Uri.encodeComponent('payroll_history_id eq ${h['id']}')}&\$expand=employee(\$expand=designation)&\$orderby=id asc&\$top=5000');
      await shareBatchReport(h, unwrapList(res).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList());
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Failed to export'), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _detail(Map<String, dynamic> r) => showMotionSheet<void>(context, (_) => _DetailSheet(row: r));

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final q = _q.trim().toLowerCase();
    final rows = _rows.where((r) => q.isEmpty || '${employeeName(asMap(r['employee']), r['employee_id'])} ${str(asMap(r['employee'])?['employee_no'])} ${str(r['status'])}'.toLowerCase().contains(q)).toList();
    final approvedCount = _approvedRows.length;
    final alreadySent = _sent != null;
    return MotionScaffold(
      title: _month,
      subtitle: '$approvedCount/${_rows.length} approved · ${money(_approvedAmount)} ready to send',
      icon: Icons.fact_check_outlined,
      accent: Accent.ocean,
      onRefresh: _load,
      actions: [
        IconButton(
          tooltip: 'Export batch report',
          onPressed: _exporting ? null : _export,
          icon: _exporting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.picture_as_pdf_outlined),
        ),
      ],
      headerExtra: HeaderSearch(hint: 'Search employee', onChanged: (v) => setState(() => _q = v)),
      bottomBar: _loading || _error != null
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: alreadySent
                      ? Row(key: const ValueKey('sent'), children: [
                          Icon(Icons.verified_rounded, color: p.ok),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('Sent to accounting — ${money(n(_sent!['amount']))}',
                                style: TextStyle(fontWeight: FontWeight.w700, color: p.text, fontSize: 13.5)),
                          ),
                          StatusPill(humanize(str(_sent!['status'])), tone: toneForStatus(str(_sent!['status']))),
                        ])
                      : Column(key: const ValueKey('send'), mainAxisSize: MainAxisSize.min, children: [
                          GradientButton(
                            label: 'Send payment — ${money(_approvedAmount)}',
                            icon: Icons.send_rounded,
                            accent: Accent.emerald,
                            busy: _sending,
                            onTap: _approvedAmount <= 0 ? null : _sendPayment,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Approval is optional — unapproved payrolls are excluded from the amount sent. A batch can only be sent once.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: p.label),
                          ),
                        ]),
                ),
              ),
            ),
      slivers: [
        sliverBox(
          Row(children: [
            Expanded(
              child: GlowCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  ProgressRing(
                    value: _rows.isEmpty ? 0 : approvedCount / _rows.length,
                    size: 58,
                    color: p.ok,
                    center: Text('$approvedCount/${_rows.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.text)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Approved', style: TextStyle(fontSize: 12, color: p.label)),
                      CountUp(value: _approvedAmount, format: money, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
                      Text('Batch total ${money(n(h['total_amount']))}', style: TextStyle(fontSize: 11.5, color: p.label)),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        ),
        if (_loading)
          sliverSkeleton(height: 78)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(icon: Icons.fact_check_outlined, title: _rows.isEmpty ? 'No payrolls in this batch' : 'No matches')
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final name = employeeName(asMap(r['employee']), r['employee_id']);
              final approved = _approved(r);
              final busy = _busyId == r['id'];
              return MotionTile(
                key: ValueKey(r['id']),
                leading: InitialsAvatar(name, size: 40),
                title: name,
                subtitle: 'Net pay ${money(n(r['net_salary']))}',
                meta: str(asMap(r['employee'])?['employee_no']).isEmpty ? null : '#${asMap(r['employee'])?['employee_no']}',
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  StatusPill(humanize(str(r['status'])), tone: approved ? MarketTone.ok : MarketTone.warn),
                  if (!approved && !alreadySent) ...[
                    const SizedBox(width: 6),
                    busy
                        ? const SizedBox(width: 30, height: 30, child: Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator(strokeWidth: 2)))
                        : PressScale(
                            onTap: () => _approve(r),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: p.okBg, borderRadius: BorderRadius.circular(10)),
                              child: Text('Approve', style: TextStyle(color: p.ok, fontWeight: FontWeight.w700, fontSize: 12)),
                            ),
                          ),
                  ],
                ]),
                onTap: () => _detail(r),
              );
            },
          ),
      ],
    );
  }
}

class _DetailSheet extends StatelessWidget {
  final Map<String, dynamic> row;
  const _DetailSheet({required this.row});

  @override
  Widget build(BuildContext context) {
    final r = row;
    String num0(String k) => r[k] == null ? '-' : plain(n(r[k]));
    String int0(String k) => r[k] == null ? '-' : str(r[k]);
    final fields = <(String, String)>[
      ('Basic', num0('basic')),
      ('House rent', num0('house_rent')),
      ('Medical allowance', num0('medical_allowance')),
      ('Transport allowance', num0('transport_allowance')),
      ('Other allowance', num0('other_allowance')),
      ('Attendance bonus', num0('attendance_bonus')),
      ('Night shift bonus', num0('night_shift_bonus')),
      ('Bonuses', num0('bonuses')),
      ('Gross salary', num0('gross_salary')),
      ('Tax', num0('tax')),
      ('Social security', num0('social_security')),
      ('Other deductions', num0('other_deductions')),
      ('Penalties', num0('penalties')),
      ('Total deductions', num0('total_deductions')),
      ('Net salary', num0('net_salary')),
      ('Payable days', int0('total_payable_days')),
      ('Weekend days', int0('total_weekend')),
      ('Present days', int0('present_days')),
      ('Absent days', int0('absent_days')),
      ('Late days', int0('late_days')),
      ('Night shift days', int0('night_shift_days')),
      ('Overtime (minutes)', int0('overtime_minutes')),
    ];
    return FormSheet(
      title: 'Payroll detail',
      subtitle: employeeName(asMap(r['employee']), r['employee_id']),
      children: [
        InfoGrid(cells: [for (final f in fields) InfoCell(f.$1, f.$2)]),
        const SizedBox(height: 10),
        InfoCell('HR notes', str(r['hr_notes'])),
        const SizedBox(height: 16),
      ],
    );
  }
}
