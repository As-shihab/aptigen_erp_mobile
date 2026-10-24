import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'hr_extras.dart';

// Leave requests — port of desktop LeaveRequest.tsx: status-filtered list,
// detail sheet with the approval-chain progress (leave_type_has_middleman +
// leave_request_approvals), approve / reject, delete and a 4-step "new
// request on behalf of an employee" wizard with a multi-day calendar.

const _statuses = ['PENDING', 'APPROVED', 'REJECTED', 'CANCELLED'];
const _typeColors = [
  Color(0xFF168EFF), Color(0xFFC87B00), Color(0xFF75980B), Color(0xFFDF1278), Color(0xFF8B47D7), Color(0xFF049F9A),
  Color(0xFF0070F2), Color(0xFFCC00DC),
];

MarketTone _tone(String s) => switch (s) {
      'APPROVED' => MarketTone.ok,
      'PENDING' => MarketTone.warn,
      'REJECTED' => MarketTone.error,
      _ => MarketTone.neutral,
    };

class LeaveRequestsPage extends StatefulWidget {
  const LeaveRequestsPage({super.key});

  @override
  State<LeaveRequestsPage> createState() => _LeaveRequestsPageState();
}

class _LeaveRequestsPageState extends State<LeaveRequestsPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _emps = [];
  List<Map<String, dynamic>> _types = [];
  String _status = 'ALL';
  String _q = '';

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
      final d = await batchLoad(_client, {
        'rows':
            'leave_requests?\$expand=employee(\$select=id,first_name,last_name,employee_no),leave_type(\$select=id,name)&\$orderby=id desc&\$top=500',
        'emps': 'employees?\$select=id,first_name,last_name,employee_no&\$filter=is_active eq true&\$top=500',
        'types': 'leave_types?\$select=id,name&\$filter=is_active eq true&\$top=200',
      });
      if (!mounted) return;
      setState(() {
        _rows = d['rows'] ?? [];
        _emps = d['emps'] ?? [];
        _types = d['types'] ?? [];
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load leave requests'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _count(String s) => s == 'ALL' ? _rows.length : _rows.where((r) => str(r['status']) == s).length;

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    return _rows.where((r) {
      if (_status != 'ALL' && str(r['status']) != _status) return false;
      if (q.isEmpty) return true;
      return [empName(r['employee']), nested(r, 'leave_type'), nested(r, 'employee', 'employee_no'), htmlToText(str(r['reason']))]
          .join(' ')
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  Future<bool> _delete(Map<String, dynamic> row) async {
    final ok = await confirmMarket(context, title: 'Delete this leave request?', message: 'This request will be removed permanently.');
    if (!ok) return false;
    try {
      await _client.delete('leave_requests', row['id']);
      if (mounted) {
        setState(() => _rows.removeWhere((r) => r['id'] == row['id']));
        marketToast(context, 'Leave request deleted');
      }
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete'), error: true);
      return false;
    }
  }

  Future<void> _openDetail(Map<String, dynamic> row) async {
    final res = await showMotionSheet<String>(context, (_) => _DetailSheet(row: row));
    if (!mounted || res == null) return;
    if (res == 'delete') {
      await _delete(row);
    } else {
      marketToast(context, res);
      _load();
    }
  }

  Future<void> _openCreate() async {
    final ok = await showMotionSheet<bool>(context, (_) => _CreateWizard(emps: _emps, types: _types));
    if (ok == true) {
      if (mounted) marketToast(context, 'Leave request submitted');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final approvedDays = _rows.where((r) => str(r['status']) == 'APPROVED').fold<num>(0, (a, r) => a + (toNum(r['days_count']) ?? 0));
    return MotionScaffold(
      title: 'Leave requests',
      subtitle: '${_count('PENDING')} pending · ${_rows.length} total',
      icon: Icons.event_note_rounded,
      accent: Accent.ocean,
      onRefresh: _load,
      onFab: _openCreate,
      fabLabel: 'New request',
      headerExtra: HeaderSearch(hint: 'Search employee, type or reason', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        if (!_loading && _error == null)
          SliverPadding(
            padding: const EdgeInsets.only(top: 16),
            sliver: SliverToBoxAdapter(
              child: KpiGrid(children: [
                KpiTile(icon: Icons.hourglass_top_rounded, label: 'Pending', value: _count('PENDING'), tone: MarketTone.warn, onTap: () => setState(() => _status = 'PENDING')),
                KpiTile(icon: Icons.check_circle_rounded, label: 'Approved', value: _count('APPROVED'), tone: MarketTone.ok, onTap: () => setState(() => _status = 'APPROVED')),
                KpiTile(icon: Icons.cancel_rounded, label: 'Rejected', value: _count('REJECTED'), tone: MarketTone.error, onTap: () => setState(() => _status = 'REJECTED')),
                KpiTile(icon: Icons.calendar_month_rounded, label: 'Approved days', value: approvedDays, tone: MarketTone.brand),
              ]),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _status,
              options: [
                (id: 'ALL', label: 'All', count: _count('ALL')),
                for (final s in _statuses) (id: s, label: humanize(s), count: _count(s)),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton()
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.event_busy_rounded,
            title: _rows.isEmpty ? 'No leave requests yet' : 'No matches',
            message: _rows.isEmpty ? 'Create a request on behalf of an employee.' : null,
            actionLabel: _rows.isEmpty ? 'New request' : null,
            onAction: _rows.isEmpty ? _openCreate : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final name = empName(r['employee']);
              final s = str(r['status']);
              final start = apiDay(r['start_date']);
              final end = apiDay(r['end_date']);
              final days = toNum(r['days_count']) ?? 0;
              return MotionTile(
                key: ValueKey(r['id']),
                leading: InitialsAvatar(name.isEmpty ? '?' : name, size: 44),
                title: name.isEmpty ? 'Employee' : name,
                subtitle: '${nested(r, 'leave_type').isEmpty ? 'Leave' : nested(r, 'leave_type')} · ${fmtNum(days)} ${days == 1 ? 'day' : 'days'}',
                meta: start == null ? null : (start == end || end == null ? fmtDay(start) : '${fmtDay(start)} – ${fmtDay(end)}'),
                trailing: StatusPill(humanize(s), tone: _tone(s)),
                onTap: () => _openDetail(r),
                onDelete: () => _delete(r),
              );
            },
          ),
      ],
    );
  }
}

// ── Detail / approval ───────────────────────────────────────────────────

class _Step {
  final int serial;
  final String label;
  final bool required;
  final String expected;
  final String status;
  final String? actedBy;
  final DateTime? actedAt;
  final String? notes;
  _Step(this.serial, this.label, this.required, this.expected, this.status, this.actedBy, this.actedAt, this.notes);
}

class _DetailSheet extends StatefulWidget {
  final Map<String, dynamic> row;
  const _DetailSheet({required this.row});

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  final _client = ApiClient();
  final _notes = TextEditingController();
  bool _loadingSteps = true;
  String? _stepsError;
  List<_Step> _steps = [];
  String? _acting;

  Map<String, dynamic> get r => widget.row;

  @override
  void initState() {
    super.initState();
    _loadSteps();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadSteps() async {
    setState(() {
      _loadingSteps = true;
      _stepsError = null;
    });
    try {
      final d = await batchLoad(_client, {
        'chain':
            'leave_type_has_middleman?\$filter=leave_type_id eq ${r['leave_type_id']}&\$expand=approver_emp(\$select=id,first_name,last_name),approver_des(\$select=id,name)&\$orderby=serial asc&\$top=50',
        'acted': 'leave_request_approvals?\$filter=leave_request_id eq ${r['id']}&\$expand=approver(\$select=id,first_name,last_name)&\$orderby=serial asc&\$top=50',
      });
      final acted = {for (final a in d['acted'] ?? <Map<String, dynamic>>[]) toInt(a['serial']): a};
      final steps = <_Step>[];
      for (final m in d['chain'] ?? <Map<String, dynamic>>[]) {
        final a = acted[toInt(m['serial'])];
        final emp = empName(m['approver_emp']);
        final des = nested(m, 'approver_des');
        steps.add(_Step(
          toInt(m['serial']),
          str(m['label']),
          asBool(m['is_required'], fallback: true),
          emp.isNotEmpty ? emp : (des.isNotEmpty ? 'Any $des' : 'Any approver'),
          a == null ? 'PENDING' : str(a['status']),
          a == null ? null : (empName(a['approver']).isEmpty ? null : empName(a['approver'])),
          a == null ? null : parseDate(a['acted_at']),
          a == null ? null : (str(a['notes']).isEmpty ? null : str(a['notes'])),
        ));
      }
      if (mounted) setState(() => _steps = steps);
    } catch (e) {
      if (mounted) setState(() => _stepsError = errorMessage(e, 'Could not load approval progress'));
    } finally {
      if (mounted) setState(() => _loadingSteps = false);
    }
  }

  Future<void> _act(String status) async {
    setState(() => _acting = status);
    final note = _notes.text.trim();
    try {
      await _client.put('leave_requests', r['id'], {
        'status': status,
        if (status == 'REJECTED') 'rejection_reason': note.isEmpty ? null : note,
      });
      if (mounted) Navigator.pop(context, status == 'APPROVED' ? 'Leave approved' : 'Leave rejected');
    } catch (e) {
      if (mounted) {
        setState(() => _acting = null);
        marketToast(context, errorMessage(e, 'Action failed'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final s = str(r['status']);
    final name = empName(r['employee']);
    final reason = htmlToText(str(r['reason']));
    final rejection = str(r['rejection_reason']);
    final days = toNum(r['days_count']) ?? 0;
    return FormSheet(
      title: 'Leave request',
      subtitle: name.isEmpty ? null : name,
      extraAction: IconButton(
        tooltip: 'Delete',
        icon: Icon(Icons.delete_outline_rounded, color: p.error),
        onPressed: () => Navigator.pop(context, 'delete'),
      ),
      children: [
        Row(children: [
          InitialsAvatar(name.isEmpty ? '?' : name, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name.isEmpty ? 'Employee' : name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
              if (nested(r, 'employee', 'employee_no').isNotEmpty) Text(nested(r, 'employee', 'employee_no'), style: TextStyle(fontSize: 12.5, color: p.label)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                StatusPill(humanize(s), tone: _tone(s)),
                if (toInt(r['current_serial']) > 1) StatusPill('Approval step ${r['current_serial']}', tone: MarketTone.info),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        reviewGrid([
          ('Leave type', nested(r, 'leave_type')),
          ('Days', fmtNum(days)),
          ('From', fmtDay(apiDay(r['start_date']))),
          ('To', fmtDay(apiDay(r['end_date']))),
        ]),
        if (reason.isNotEmpty) ...[
          const SizedBox(height: 14),
          FormLabel(
            label: 'Reason',
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
              child: Text(reason, style: TextStyle(fontSize: 13.5, height: 1.5, color: p.text)),
            ),
          ),
        ],
        if (rejection.isNotEmpty)
          FormLabel(
            label: 'Rejection reason',
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.errorBg, borderRadius: BorderRadius.circular(14)),
              child: Text(rejection, style: TextStyle(fontSize: 13.5, color: p.error)),
            ),
          ),
        const SizedBox(height: 6),
        SectionHeader('Approval progress'),
        if (_loadingSteps)
          const Column(children: [SkeletonBox(height: 62, radius: 14), SizedBox(height: 8), SkeletonBox(height: 62, radius: 14)])
        else if (_stepsError != null)
          MarketEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _stepsError, actionLabel: 'Retry', onAction: _loadSteps)
        else if (_steps.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No approval chain configured for this leave type.', style: TextStyle(fontSize: 12.5, color: p.label)),
          )
        else
          for (var i = 0; i < _steps.length; i++) _stepRow(p, _steps[i], i, i == _steps.length - 1),
        if (s == 'PENDING') ...[
          const SizedBox(height: 10),
          SectionHeader('Approval action'),
          FormLabel(
            label: 'Notes (optional)',
            help: 'Saved as the rejection reason when rejecting.',
            child: TextField(controller: _notes, minLines: 2, maxLines: 4, decoration: motionInput(context, hint: 'Add a note')),
          ),
          Row(children: [
            Expanded(
              child: GradientButton(
                label: 'Approve',
                icon: Icons.check_rounded,
                accent: Accent.emerald,
                busy: _acting == 'APPROVED',
                onTap: _acting != null ? null : () => _act('APPROVED'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GradientButton(
                label: 'Reject',
                icon: Icons.close_rounded,
                accent: Accent.rose,
                busy: _acting == 'REJECTED',
                onTap: _acting != null ? null : () => _act('REJECTED'),
              ),
            ),
          ]),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ],
    );
  }

  Widget _stepRow(MarketPalette p, _Step st, int i, bool last) {
    final tone = st.status == 'SKIPPED' ? MarketTone.neutral : _tone(st.status);
    final c = p.tone(tone);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.bg, shape: BoxShape.circle, border: Border.all(color: c.fg, width: 1.5)),
            child: st.status == 'APPROVED'
                ? Icon(Icons.check_rounded, size: 16, color: c.fg)
                : st.status == 'REJECTED'
                    ? Icon(Icons.close_rounded, size: 16, color: c.fg)
                    : Text('${st.serial}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.fg)),
          ),
          if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: p.line)),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(st.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text))),
                StatusPill(humanize(st.status), tone: tone),
              ]),
              const SizedBox(height: 2),
              Text('${st.expected}${st.required ? '' : ' · optional'}', style: TextStyle(fontSize: 12, color: p.label)),
              if (st.actedBy != null)
                Text(
                  '${st.status == 'APPROVED' ? 'Approved' : st.status == 'REJECTED' ? 'Rejected' : 'Acted'} by ${st.actedBy}${st.actedAt != null ? ' · ${fmtDateTime(st.actedAt)}' : ''}',
                  style: TextStyle(fontSize: 12, color: p.label),
                ),
              if (st.notes != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text('"${st.notes}"', style: TextStyle(fontSize: 12.5, color: p.text))),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── Create wizard ───────────────────────────────────────────────────────

class _CreateWizard extends StatefulWidget {
  final List<Map<String, dynamic>> emps;
  final List<Map<String, dynamic>> types;
  const _CreateWizard({required this.emps, required this.types});

  @override
  State<_CreateWizard> createState() => _CreateWizardState();
}

class _Taken {
  final DateTime start;
  final DateTime end;
  final bool pending;
  _Taken(this.start, this.end, this.pending);
}

class _CreateWizardState extends State<_CreateWizard> {
  static const _steps = ['Employee', 'Dates', 'Reason', 'Review'];
  final _client = ApiClient();
  final _reason = TextEditingController();
  int _step = 0;
  int _dir = 1;
  Object? _emp;
  Object? _type;
  final Set<DateTime> _dates = {};
  List<_Taken> _taken = [];
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool _can(int i) {
    if (i >= 1 && (_emp == null || _type == null)) return false;
    if (i >= 2 && _dates.isEmpty) return false;
    return true;
  }

  void _go(int i) {
    if (i == _step || i < 0 || i >= _steps.length || !_can(i)) return;
    setState(() {
      _dir = i > _step ? 1 : -1;
      _step = i;
    });
  }

  Future<void> _loadTaken(Object id) async {
    try {
      final res = await _client.get('leave_requests?\$select=id,start_date,end_date,status&\$filter=employee_id eq $id&\$top=200');
      final list = unwrapList(res).whereType<Map>().where((r) => r['status'] == 'PENDING' || r['status'] == 'APPROVED');
      if (!mounted) return;
      setState(() => _taken = [
            for (final r in list)
              if (apiDay(r['start_date']) != null) _Taken(apiDay(r['start_date'])!, apiDay(r['end_date']) ?? apiDay(r['start_date'])!, r['status'] == 'PENDING'),
          ]);
    } catch (_) {
      if (mounted) setState(() => _taken = []);
    }
  }

  Color? _mark(DateTime d) {
    for (final t in _taken) {
      if (!d.isBefore(t.start) && !d.isAfter(t.end)) return t.pending ? const Color(0xFFE76500) : const Color(0xFFD20A0A);
    }
    return null;
  }

  String get _empLabel {
    final e = widget.emps.where((e) => e['id'].toString() == _emp?.toString()).firstOrNull;
    return e == null ? '' : empLabel(e);
  }

  String get _typeLabel => lookupName(widget.types, _type);

  Future<void> _save() async {
    if (!_can(3)) return;
    setState(() => _busy = true);
    final sorted = _dates.toList()..sort();
    final reason = _reason.text.trim();
    try {
      await _client.post(
        'leave_requests',
        {
          'employee_id': _emp,
          'leave_type_id': _type,
          'start_date': isoDay(sorted.first),
          'end_date': isoDay(sorted.last),
          'days_count': sorted.length,
          'reason': reason.isEmpty ? null : textToHtml(reason),
          'status': 'PENDING',
          'current_serial': 1,
        },
        isV8: true,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(e, 'Failed to submit request'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => WizardShell(
        title: 'New leave request',
        steps: _steps,
        step: _step,
        direction: _dir,
        busy: _busy,
        onStep: _go,
        onBack: () => _step == 0 ? Navigator.pop(context) : _go(_step - 1),
        onNext: _can(_step + 1) ? () => _go(_step + 1) : null,
        finalActions: [Expanded(child: GradientButton(label: 'Submit', icon: Icons.send_rounded, busy: _busy, onTap: _busy ? null : _save))],
        body: switch (_step) { 0 => _who(context), 1 => _datesStep(context), 2 => _reasonStep(context), _ => _review(context) },
      );

  Widget _who(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FormLabel(
        label: 'Employee',
        required: true,
        child: PickerField(
          value: _emp,
          hint: 'Search employee',
          icon: Icons.person_search_rounded,
          options: [for (final e in widget.emps) PickOption(e['id'], empName(e), sub: str(e['employee_no']).isEmpty ? null : str(e['employee_no']))],
          onChanged: (v) {
            setState(() {
              _emp = v;
              _taken = [];
            });
            if (v != null) _loadTaken(v);
          },
        ),
      ),
      Text.rich(
        TextSpan(children: [const TextSpan(text: 'Leave type'), TextSpan(text: ' *', style: TextStyle(color: p.error))]),
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.label),
      ),
      const SizedBox(height: 8),
      if (widget.types.isEmpty)
        Text('No active leave types.', style: TextStyle(fontSize: 13, color: p.label))
      else
        LayoutBuilder(
          builder: (_, c) => Wrap(spacing: 10, runSpacing: 10, children: [
            for (var i = 0; i < widget.types.length; i++)
              SizedBox(
                width: (c.maxWidth - 10) / 2,
                child: FadeSlideIn(
                  index: i,
                  child: PressScale(
                    onTap: () => setState(() => _type = widget.types[i]['id']),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: _type?.toString() == widget.types[i]['id'].toString() ? p.brandSoft : p.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _type?.toString() == widget.types[i]['id'].toString() ? p.brand : Colors.transparent, width: 1.5),
                      ),
                      child: Row(children: [
                        Container(width: 5, height: 28, decoration: BoxDecoration(color: _typeColors[i % _typeColors.length], borderRadius: BorderRadius.circular(3))),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(str(widget.types[i]['name']),
                              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                        ),
                        AnimatedScale(
                          scale: _type?.toString() == widget.types[i]['id'].toString() ? 1 : 0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutBack,
                          child: Icon(Icons.check_circle_rounded, size: 18, color: p.brand),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
    ]);
  }

  Widget _datesStep(BuildContext context) {
    final p = MarketPalette.of(context);
    final first = _dates.isEmpty ? DateTime.now() : (_dates.toList()..sort()).first;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GlowCard(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
        child: SwipeCalendar(
          initialMonth: first,
          isSelected: (d) => _dates.contains(d),
          markFor: _mark,
          onTap: (d) => setState(() => _dates.contains(d) ? _dates.remove(d) : _dates.add(d)),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        _legend(p, const Color(0xFFE76500), 'Pending leave'),
        const SizedBox(width: 14),
        _legend(p, const Color(0xFFD20A0A), 'Approved leave'),
      ]),
      const SizedBox(height: 12),
      GlowCard(
        gradient: Accent.ocean.gradient,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Days selected', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
              TweenAnimationBuilder<double>(
                key: ValueKey(_dates.length),
                tween: Tween(begin: 1.3, end: 1),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                builder: (_, s, child) => Transform.scale(scale: s, alignment: Alignment.centerLeft, child: child),
                child: Text('${_dates.length}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
              if (_dates.isNotEmpty) Text(rangeText(_dates.toList()), style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.9))),
            ]),
          ),
          if (_dates.isNotEmpty)
            TextButton(
              onPressed: () => setState(_dates.clear),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Clear'),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      Text('Tap days to add or remove them. Swipe to change month.', style: TextStyle(fontSize: 12, color: p.label)),
    ]);
  }

  Widget _legend(MarketPalette p, Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c.withValues(alpha: 0.35), shape: BoxShape.circle, border: Border.all(color: c))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: p.label)),
      ]);

  Widget _reasonStep(BuildContext context) => FormLabel(
        label: 'Reason',
        child: TextField(
          controller: _reason,
          minLines: 8,
          maxLines: 14,
          decoration: motionInput(context, hint: 'Describe the reason for this leave'),
        ),
      );

  Widget _review(BuildContext context) {
    final p = MarketPalette.of(context);
    final sorted = _dates.toList()..sort();
    final reason = _reason.text.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      reviewGrid([
        ('Employee', _empLabel),
        ('Leave type', _typeLabel),
        ('Days', '${_dates.length}'),
        ('Period', rangeText(sorted)),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var i = 0; i < sorted.length; i++)
          FadeSlideIn(
            index: i,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(8)),
              child: Text(DateFormat('EEE, d MMM').format(sorted[i]), style: TextStyle(fontSize: 12, color: p.brand, fontWeight: FontWeight.w600)),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Reason', style: TextStyle(fontSize: 12, color: p.label)),
          const SizedBox(height: 4),
          Text(reason.isEmpty ? 'No reason given' : reason, style: TextStyle(fontSize: 13.5, height: 1.45, color: reason.isEmpty ? p.label : p.text)),
        ]),
      ),
    ]);
  }
}
