import 'dart:collection';
import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'payroll_common.dart';

/// Generate payroll — mirrors desktop PayrollProcess.tsx step by step:
/// 1. pick month + year (years back to the earliest payroll on record) and
///    optional departments; the period is the whole month clamped to today.
/// 2. pick employees (first one auto-selected); each shows generated /
///    pending for the period and a detail sheet from
///    hrm/employee-payroll-status (overview, payroll log, activity + HR notes).
/// 3. preview: the same per-employee computation, unsaved, with totals —
///    employees can be dropped from the run.
/// 4. confirm: POST hrm/generate-payroll/:start/:end, then show the
///    persisted results.
class PayrollProcessPage extends StatefulWidget {
  const PayrollProcessPage({super.key});

  @override
  State<PayrollProcessPage> createState() => _PayrollProcessPageState();
}

class _PayrollProcessPageState extends State<PayrollProcessPage> {
  final _client = ApiClient();
  final _notes = TextEditingController();
  final _now = DateTime.now();
  late int _year = _now.year;
  late int _month = _now.month;
  int? _minYear;
  List<Map<String, dynamic>> _depts = [];
  final Set<int> _deptIds = {};
  List<Map<String, dynamic>> _emps = [];
  List<Map<String, dynamic>> _generated = [];
  final LinkedHashMap<int, Map<String, dynamic>> _selected = LinkedHashMap();
  bool _autoSelected = false;
  bool _loading = true;
  String? _error;
  String _q = '';
  bool _onlyPending = false;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  DateTime get _start => DateTime(_year, _month, 1);
  DateTime get _end {
    final eom = DateTime(_year, _month + 1, 0);
    final today = DateTime(_now.year, _now.month, _now.day);
    return eom.isAfter(today) ? today : eom;
  }

  int get _payableDays {
    final s = DateTime.utc(_start.year, _start.month, _start.day);
    final e = DateTime.utc(_end.year, _end.month, _end.day);
    return e.difference(s).inDays + 1;
  }

  List<int> get _years => [for (var y = _now.year; y >= (_minYear ?? _now.year); y--) y];

  String get _deptFilter => _deptIds.isEmpty ? '' : ' and (${_deptIds.map((id) => 'department_id eq $id').join(' or ')})';

  Future<void> _load({bool initial = false}) async {
    setState(() {
      _loading = _emps.isEmpty;
      _error = null;
    });
    try {
      final data = await batchLoad(_client, {
        if (initial) 'depts': 'departments?\$select=id,name&\$filter=is_active eq true&\$top=500',
        if (initial) 'first': 'payrolls?\$select=start_date&\$orderby=start_date asc&\$top=1',
        'emps': 'employees?\$filter=is_active eq true$_deptFilter&\$expand=designation,department&\$orderby=first_name asc&\$top=2000',
        'gen': 'payrolls?\$filter=start_date le ${isoUtc(_end)} and end_date ge ${isoUtc(_start)}&\$select=id,employee_id,start_date&\$top=3000',
      });
      if (!mounted) return;
      setState(() {
        if (initial) {
          _depts = data['depts'] ?? [];
          final first = parseDate((data['first'] ?? const []).firstOrNull?['start_date']);
          _minYear = first?.year ?? _now.year;
        }
        _emps = data['emps'] ?? [];
        _generated = data['gen'] ?? [];
        if (!_autoSelected && _emps.isNotEmpty) {
          _autoSelected = true;
          final first = _emps.first;
          _selected
            ..clear()
            ..[toInt(first['id'])] = first;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load employees'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadGenerated() async {
    try {
      final filter = Uri.encodeComponent('start_date le ${isoUtc(_end)} and end_date ge ${isoUtc(_start)}');
      final res = await _client.get('payrolls?\$filter=$filter&\$select=id,employee_id,start_date&\$top=3000');
      if (mounted) setState(() => _generated = unwrapList(res).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList());
    } catch (_) {
      if (mounted) setState(() => _generated = []);
    }
  }

  Map<String, dynamic>? _genFor(Object? id) => _generated.where((g) => g['employee_id'].toString() == id.toString()).firstOrNull;

  void _toggle(Map<String, dynamic> emp) {
    final id = toInt(emp['id']);
    setState(() {
      if (_selected.containsKey(id)) {
        _selected.remove(id);
      } else {
        _selected[id] = emp;
      }
    });
  }

  void _setPeriod({int? year, int? month}) {
    setState(() {
      if (year != null) _year = year;
      if (month != null) _month = month;
      if (_year == _now.year && _month > _now.month) _month = _now.month;
    });
    _loadGenerated();
  }

  void _reset() {
    setState(() {
      _deptIds.clear();
      _year = _now.year;
      _month = _now.month;
      _selected.clear();
      _autoSelected = false;
    });
    _load();
  }

  Future<void> _pickDepts() async {
    final picked = await showMotionSheet<Set<int>>(context, (_) => _DeptSheet(depts: _depts, selected: _deptIds));
    if (picked == null) return;
    setState(() {
      _deptIds
        ..clear()
        ..addAll(picked);
      _selected.clear();
      _autoSelected = false;
      _emps = [];
    });
    _load();
  }

  void _openDetail(Map<String, dynamic> emp) {
    showMotionSheet<void>(
      context,
      (_) => _EmployeeDetailSheet(
        emp: emp,
        start: _start,
        end: _end,
        generated: _genFor(emp['id']) != null,
        notes: _notes,
        selected: _selected.containsKey(toInt(emp['id'])),
        onToggle: () => _toggle(emp),
      ),
    );
  }

  Future<void> _generate() async {
    if (_selected.isEmpty) return;
    final done = await showMotionSheet<bool>(
      context,
      (_) => _GenerateSheet(
        selected: Map.of(_selected),
        start: _start,
        end: _end,
        payableDays: _payableDays,
        notes: _notes,
        onRemove: (id) => setState(() => _selected.remove(id)),
      ),
    );
    if (done == true) _loadGenerated();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final q = _q.trim().toLowerCase();
    final rows = _emps.where((e) {
      if (_onlyPending && _genFor(e['id']) != null) return false;
      if (q.isEmpty) return true;
      return [employeeName(e), str(e['employee_no']), str(e['email']), nested(e, 'designation'), nested(e, 'department')].join(' ').toLowerCase().contains(q);
    }).toList();
    final genCount = _emps.where((e) => _genFor(e['id']) != null).length;
    final monthOpts = [for (var m = 1; m <= (_year == _now.year ? _now.month : 12); m++) PickOption(m, kMonths[m - 1])];
    final allVisibleSelected = rows.isNotEmpty && rows.every((e) => _selected.containsKey(toInt(e['id'])));

    return MotionScaffold(
      title: 'Payroll process',
      subtitle: '${kMonths[_month - 1]} $_year · ${fmtDate(_start)} – ${fmtDate(_end)}',
      icon: Icons.payments_outlined,
      accent: Accent.emerald,
      onRefresh: () => _load(),
      actions: [IconButton(tooltip: 'Reset', onPressed: _reset, icon: const Icon(Icons.restart_alt_rounded))],
      headerExtra: HeaderSearch(hint: 'Search employees', onChanged: (v) => setState(() => _q = v)),
      bottomBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: Text('${_selected.length} selected',
                      key: ValueKey(_selected.length), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.text)),
                ),
                Text('$_payableDays payable days', style: TextStyle(fontSize: 11.5, color: p.label)),
              ]),
            ),
            SizedBox(
              width: 200,
              child: GradientButton(
                label: _selected.isEmpty ? 'Generate payroll' : 'Generate (${_selected.length})',
                icon: Icons.play_arrow_rounded,
                accent: Accent.emerald,
                onTap: _selected.isEmpty ? null : _generate,
              ),
            ),
          ]),
        ),
      ),
      slivers: [
        sliverBox(
          GlowCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const AccentIcon(Icons.event_note_rounded, accent: Accent.emerald, size: 34),
                const SizedBox(width: 10),
                Expanded(child: Text('Pay period', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text))),
                StatusPill('$_payableDays days', tone: MarketTone.brand),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  flex: 3,
                  child: PickerField(
                    value: _month,
                    hint: 'Month',
                    icon: Icons.calendar_view_month_rounded,
                    allowClear: false,
                    options: monthOpts,
                    onChanged: (v) => v == null ? null : _setPeriod(month: toInt(v)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: PickerField(
                    value: _year,
                    hint: 'Year',
                    allowClear: false,
                    options: [for (final y in _years) PickOption(y, '$y')],
                    onChanged: (v) => v == null ? null : _setPeriod(year: toInt(v)),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              PressScale(
                scale: 0.98,
                onTap: _pickDepts,
                child: InputDecorator(
                  decoration: motionInput(context, hint: 'Filter by department', icon: Icons.apartment_rounded, suffix: Icon(Icons.expand_more_rounded, color: p.label)),
                  isEmpty: _deptIds.isEmpty,
                  child: Text(
                    _depts.where((d) => _deptIds.contains(toInt(d['id']))).map((d) => str(d['name'])).join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: p.text),
                  ),
                ),
              ),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<bool>(
              value: _onlyPending,
              options: [
                (id: false, label: 'All', count: _emps.length),
                (id: true, label: 'Pending', count: _emps.length - genCount),
              ],
              onChanged: (v) => setState(() => _onlyPending = v),
            ),
          ),
        ),
        if (!_loading && _error == null && rows.isNotEmpty)
          sliverBox(
            Row(children: [
              Text('${rows.length} employees · $genCount generated', style: TextStyle(fontSize: 12.5, color: p.label)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() {
                  if (allVisibleSelected) {
                    for (final e in rows) {
                      _selected.remove(toInt(e['id']));
                    }
                  } else {
                    for (final e in rows) {
                      _selected[toInt(e['id'])] = e;
                    }
                  }
                }),
                icon: Icon(allVisibleSelected ? Icons.deselect_rounded : Icons.select_all_rounded, size: 18),
                label: Text(allVisibleSelected ? 'Clear' : 'Select all'),
              ),
            ]),
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          ),
        if (_loading)
          sliverSkeleton(height: 74)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: () => _load(initial: _depts.isEmpty))
        else if (rows.isEmpty)
          sliverEmpty(icon: Icons.groups_outlined, title: _emps.isEmpty ? 'No active employees' : 'No matches')
        else
          sliverStagger(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            count: rows.length,
            builder: (_, i) {
              final e = rows[i];
              final gen = _genFor(e['id']);
              return _EmpTile(
                key: ValueKey(e['id']),
                emp: e,
                selected: _selected.containsKey(toInt(e['id'])),
                generatedOn: gen == null ? null : parseDate(gen['start_date']),
                isGenerated: gen != null,
                onTap: () => _toggle(e),
                onInfo: () => _openDetail(e),
              );
            },
          ),
      ],
    );
  }
}

class _EmpTile extends StatelessWidget {
  final Map<String, dynamic> emp;
  final bool selected;
  final bool isGenerated;
  final DateTime? generatedOn;
  final VoidCallback onTap;
  final VoidCallback onInfo;
  const _EmpTile({super.key, required this.emp, required this.selected, required this.isGenerated, this.generatedOn, required this.onTap, required this.onInfo});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final name = employeeName(emp);
    final sub = [str(emp['employee_no']).isNotEmpty ? '#${emp['employee_no']}' : str(emp['email']), nested(emp, 'designation'), nested(emp, 'department')]
        .where((s) => s.isNotEmpty)
        .join(' · ');
    final joined = parseDate(emp['joining_date']);
    return PressScale(
      onTap: onTap,
      onLongPress: onInfo,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: selected ? p.brandSoft : p.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? p.brand : p.line.withValues(alpha: 0.7), width: selected ? 1.4 : 1),
        ),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            InitialsAvatar(name, imageUrl: str(emp['profile_photo']), size: 42),
            Positioned(
              right: -3,
              bottom: -3,
              child: AnimatedScale(
                scale: selected ? 1 : 0,
                duration: const Duration(milliseconds: 280),
                curve: Curves.elasticOut,
                child: Container(
                  decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle, border: Border.all(color: p.card, width: 2)),
                  child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                ),
              ),
            ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.text)),
              if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
              const SizedBox(height: 3),
              Text(
                [if (joined != null) 'Joined ${fmtDate(joined)}', if (generatedOn != null) 'Last generated ${fmtDate(generatedOn)}'].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: generatedOn != null ? p.ok : p.label),
              ),
            ]),
          ),
          StatusPill(isGenerated ? 'Generated' : 'Pending', tone: isGenerated ? MarketTone.ok : MarketTone.warn),
          IconButton(onPressed: onInfo, tooltip: 'Payroll details', icon: Icon(Icons.info_outline_rounded, color: p.label, size: 21)),
        ]),
      ),
    );
  }
}

class _DeptSheet extends StatefulWidget {
  final List<Map<String, dynamic>> depts;
  final Set<int> selected;
  const _DeptSheet({required this.depts, required this.selected});

  @override
  State<_DeptSheet> createState() => _DeptSheetState();
}

class _DeptSheetState extends State<_DeptSheet> {
  late final Set<int> _sel = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return FormSheet(
      title: 'Departments',
      subtitle: _sel.isEmpty ? 'All departments' : '${_sel.length} selected',
      submitLabel: 'Apply',
      onSubmit: () => Navigator.pop(context, _sel),
      extraAction: _sel.isEmpty ? null : TextButton(onPressed: () => setState(_sel.clear), child: const Text('Clear')),
      children: [
        if (widget.depts.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('No departments', style: TextStyle(color: p.label))),
        for (final d in widget.depts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: PressScale(
              scale: 0.98,
              onTap: () => setState(() {
                final id = toInt(d['id']);
                _sel.contains(id) ? _sel.remove(id) : _sel.add(id);
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _sel.contains(toInt(d['id'])) ? p.brandSoft : p.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Expanded(child: Text(str(d['name']), style: TextStyle(fontWeight: FontWeight.w600, color: p.text))),
                  Icon(_sel.contains(toInt(d['id'])) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: _sel.contains(toInt(d['id'])) ? p.brand : p.label),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}

/// Per-employee payroll status (desktop right-hand detail pane).
class _EmployeeDetailSheet extends StatefulWidget {
  final Map<String, dynamic> emp;
  final DateTime start;
  final DateTime end;
  final bool generated;
  final bool selected;
  final TextEditingController notes;
  final VoidCallback onToggle;
  const _EmployeeDetailSheet({
    required this.emp,
    required this.start,
    required this.end,
    required this.generated,
    required this.selected,
    required this.notes,
    required this.onToggle,
  });

  @override
  State<_EmployeeDetailSheet> createState() => _EmployeeDetailSheetState();
}

class _EmployeeDetailSheetState extends State<_EmployeeDetailSheet> {
  final _client = ApiClient();
  Map<String, dynamic>? _info;
  bool _loading = true;
  String? _error;
  String _tab = 'overview';
  late bool _selected = widget.selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _client.get('hrm/employee-payroll-status/${widget.emp['id']}/${ymd(widget.start)}/${ymd(widget.end)}', isV8: false);
      if (!mounted) return;
      setState(() {
        _info = asMap(res);
        widget.notes.text = str(_info?['hr_notes']);
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load payroll details'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _m(String k) => asMap(_info?[k]) ?? const {};

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final e = widget.emp;
    final name = employeeName(e);
    final sal = _m('employeeSalary');
    final bon = _m('employeeBonuses');
    final ded = _m('employeeDeducations');
    final att = _m('employeeAttendance');
    final leave = _m('leaveStatus');
    final leaveInMonth = (leave['leaveInMonth'] is List) ? leave['leaveInMonth'] as List : const [];
    final leaveInYear = (leave['leaveInYear'] is List) ? leave['leaveInYear'] as List : const [];
    final leaveTypes = (leave['leaveTypes'] is List) ? leave['leaveTypes'] as List : const [];
    num taken(int typeId) => n(leaveInYear.whereType<Map>().where((l) => toInt(l['leave_type_id']) == typeId).firstOrNull?['total']);
    num allowed(int typeId) => n(leaveTypes.whereType<Map>().where((l) => toInt(l['id']) == typeId).firstOrNull?['days']);
    final leavesTaken = (leaveInMonth.isNotEmpty ? n((leaveInMonth[0] as Map?)?['total']) : 0) + (leaveInMonth.length > 1 ? n((leaveInMonth[1] as Map?)?['total']) : 0);

    Widget body;
    if (_loading) {
      body = const Column(children: [SkeletonBox(height: 120, radius: 12), SizedBox(height: 10), SkeletonBox(height: 120, radius: 12)]);
    } else if (_error != null) {
      body = MarketEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load);
    } else {
      body = switch (_tab) {
        'payroll' => Column(key: const ValueKey('payroll'), children: [
            SectionCard(
              title: 'Salary breakdown',
              child: Column(children: [
                AmountLine('Basic salary', n(sal['basic'])),
                AmountLine('House rent allowance', n(sal['house_rent'])),
                AmountLine('Medical allowance', n(sal['medical_allowance'])),
                AmountLine('Transport allowance', n(sal['transport_allowance'])),
                AmountLine('Other allowance', n(sal['other_allowance'])),
                const Divider(height: 14),
                AmountLine('Attendance bonus', n(bon['attendenceBonuses']), tone: MarketTone.ok),
                AmountLine('Night shift bonus', n(bon['nightShiftAttendenceBonus']), tone: MarketTone.ok),
                AmountLine('Total bonus', n(_info?['bonuses']), tone: MarketTone.ok, bold: true, count: true),
                const Divider(height: 14),
                AmountLine('Gross salary', n(_info?['grossSalary']), tone: MarketTone.ok, bold: true, count: true),
              ]),
            ),
            const SizedBox(height: 10),
            SectionCard(
              title: 'Deductions',
              child: Column(children: [
                AmountLine('Tax', n(ded['tax']), tone: MarketTone.error),
                AmountLine('Social security', n(ded['social_security']), tone: MarketTone.error),
                AmountLine('Other deductions', n(ded['other_deductions']), tone: MarketTone.error),
                AmountLine('Penalties', n(ded['penalties']), tone: MarketTone.error),
                AmountLine('Total deductions', n(ded['total_deductions']), tone: MarketTone.error, bold: true, count: true),
              ]),
            ),
          ]),
        'activity' => Column(key: const ValueKey('activity'), children: [
            SectionCard(
              title: 'Leave summary',
              child: Row(children: [
                Expanded(child: _LeaveBox(label: 'Casual leave', taken: taken(2), allowed: allowed(2), color: Accent.ocean.primary)),
                const SizedBox(width: 10),
                Expanded(child: _LeaveBox(label: 'Medical leave', taken: taken(1), allowed: allowed(1), color: Accent.rose.primary)),
              ]),
            ),
            const SizedBox(height: 10),
            SectionCard(
              title: 'HR notes',
              subtitle: 'Saved with payroll generation',
              child: TextField(controller: widget.notes, minLines: 4, maxLines: 8, decoration: motionInput(context, hint: 'Enter HR notes for this payroll period')),
            ),
          ]),
        _ => Column(key: const ValueKey('overview'), children: [
            SectionCard(
              title: 'Basic information',
              child: InfoGrid(cells: [
                InfoCell('Full name', name),
                InfoCell('Employee ID', str(e['employee_no'])),
                InfoCell('Designation', nested(e, 'designation')),
                InfoCell('Department', nested(e, 'department')),
                InfoCell('Joining date', fmtDate(parseDate(e['joining_date']))),
                InfoCell('Email', str(e['email'])),
              ]),
            ),
            const SizedBox(height: 10),
            SectionCard(
              title: 'Payroll snapshot',
              child: InfoGrid(columns: 3, cells: [
                InfoCell('Current salary', sal['total_salary'] == null ? '' : plain(n(sal['total_salary']))),
                InfoCell('Last paid', str(_info?['lastPayroll'])),
                InfoCell('Next payroll', str(_info?['nextPayroll'])),
              ]),
            ),
            const SizedBox(height: 10),
            SectionCard(
              title: 'Attendance and leave',
              child: InfoGrid(columns: 3, cells: [
                InfoCell('Attendance', '${toInt(att['totalAttendenceInMonth'])} days'),
                InfoCell('Leaves taken', plain(leavesTaken)),
                InfoCell('Leave balance', plain(n(leave['leaveBalance']))),
                InfoCell('Night shifts', '${toInt(att['nightShiftAttendances'])}'),
                InfoCell('Payable days', '${toInt(_info?['total_payable_days'])}'),
                InfoCell('Weekend days', '${toInt(_info?['total_weekend'])}'),
              ]),
            ),
          ]),
      };
    }

    return FormSheet(
      title: name,
      subtitle: [nested(e, 'designation'), nested(e, 'department')].where((s) => s.isNotEmpty).join(' · '),
      submitLabel: _selected ? 'Remove from this payroll run' : 'Add to this payroll run',
      onSubmit: () {
        widget.onToggle();
        setState(() => _selected = !_selected);
        marketToast(context, _selected ? 'Added to payroll run' : 'Removed from payroll run');
      },
      extraAction: StatusPill(widget.generated ? 'Generated' : 'Pending', tone: widget.generated ? MarketTone.ok : MarketTone.warn),
      children: [
        MarketSegmented<String>(
          value: _tab,
          options: const [
            (id: 'overview', label: 'Overview', count: null),
            (id: 'payroll', label: 'Payroll log', count: null),
            (id: 'activity', label: 'Activity', count: null),
          ],
          onChanged: (v) => setState(() => _tab = v),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a), child: c)),
          child: body,
        ),
        const SizedBox(height: 12),
        GlowCard(
          gradient: Accent.ocean.gradient,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            const Icon(Icons.account_balance_wallet_rounded, color: Colors.white),
            const SizedBox(width: 8),
            const Expanded(child: Text('Net pay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
            _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : CountUp(value: n(_info?['netSalary']), format: (v) => plain(v), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          ]),
        ),
        Padding(padding: const EdgeInsets.only(top: 8), child: Text('Period ${fmtDate(widget.start)} – ${fmtDate(widget.end)}', style: TextStyle(fontSize: 11.5, color: p.label))),
      ],
    );
  }
}

class _LeaveBox extends StatelessWidget {
  final String label;
  final num taken;
  final num allowed;
  final Color color;
  const _LeaveBox({required this.label, required this.taken, required this.allowed, required this.color});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    Widget line(String l, num v) => Row(children: [
          Expanded(child: Text(l, style: TextStyle(fontSize: 11.5, color: p.label))),
          Text(plain(v), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text)),
        ]);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text)),
        const SizedBox(height: 6),
        line('Taken', taken),
        line('Allowed', allowed),
        const SizedBox(height: 8),
        AnimatedBar(label: '', value: taken.toDouble(), max: allowed == 0 ? 1 : allowed.toDouble(), color: color, format: (_) => ''),
      ]),
    );
  }
}

/// Preview → confirm → result, in one sheet (desktop's two-phase dialog).
class _GenerateSheet extends StatefulWidget {
  final Map<int, Map<String, dynamic>> selected;
  final DateTime start;
  final DateTime end;
  final int payableDays;
  final TextEditingController notes;
  final ValueChanged<int> onRemove;
  const _GenerateSheet({required this.selected, required this.start, required this.end, required this.payableDays, required this.notes, required this.onRemove});

  @override
  State<_GenerateSheet> createState() => _GenerateSheetState();
}

class _GenerateSheetState extends State<_GenerateSheet> {
  final _client = ApiClient();
  late final Map<int, Map<String, dynamic>> _emps = Map.of(widget.selected);
  List<Map<String, dynamic>> _results = [];
  bool _previewLoading = true;
  bool _generating = false;
  bool _generated = false;

  @override
  void initState() {
    super.initState();
    _preview();
  }

  Future<void> _preview() async {
    final s = ymd(widget.start);
    final e = ymd(widget.end);
    try {
      final rows = await Future.wait(_emps.keys.map((id) async {
        final res = asMap(await _client.get('hrm/employee-payroll-status/$id/$s/$e', isV8: false)) ?? const {};
        final sal = asMap(res['employeeSalary']) ?? const {};
        final bon = asMap(res['employeeBonuses']) ?? const {};
        final ded = asMap(res['employeeDeducations']) ?? const {};
        return <String, dynamic>{
          'id': id,
          'employee_id': id,
          'basic': n(sal['basic']),
          'house_rent': n(sal['house_rent']),
          'medical_allowance': n(sal['medical_allowance']),
          'transport_allowance': n(sal['transport_allowance']),
          'other_allowance': n(sal['other_allowance']),
          'attendance_bonus': n(bon['attendenceBonuses']),
          'night_shift_bonus': n(bon['nightShiftAttendenceBonus']),
          'bonuses': n(res['bonuses']),
          'tax': n(ded['tax']),
          'social_security': n(ded['social_security']),
          'other_deductions': n(ded['other_deductions']),
          'penalties': n(ded['penalties']),
          'total_deductions': n(ded['total_deductions']),
          'gross_salary': n(res['grossSalary']),
          'net_salary': n(res['netSalary']),
          'total_payable_days': toInt(res['total_payable_days']),
        };
      }));
      if (mounted) setState(() => _results = rows);
    } catch (_) {
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  void _remove(int id) {
    setState(() {
      _emps.remove(id);
      _results.removeWhere((r) => toInt(r['employee_id']) == id);
    });
    widget.onRemove(id);
  }

  Future<void> _confirm() async {
    if (_emps.isEmpty) return;
    setState(() => _generating = true);
    try {
      final res = await _client.post(
        'hrm/generate-payroll/${ymd(widget.start)}/${ymd(widget.end)}',
        {'hr_notes': widget.notes.text, 'employee_ids': _emps.keys.toList()},
        isV8: false,
        timeout: const Duration(seconds: 60),
      );
      final data = (res is Map && res['data'] is List) ? (res['data'] as List).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList() : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _results = data;
        _generated = true;
      });
      marketToast(context, 'Payroll generated');
    } catch (e) {
      if (!mounted) return;
      marketToast(context, errorMessage(e, 'Could not generate payroll'), error: true);
      Navigator.pop(context, false);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  double _sum(String k) => _results.fold<double>(0, (a, r) => a + n(r[k]));

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final showSkel = _previewLoading && _results.isEmpty;
    final rows = _results.isNotEmpty
        ? [for (final r in _results) (id: toInt(r['employee_id']), r: r)]
        : [for (final id in _emps.keys) (id: id, r: null as Map<String, dynamic>?)];
    Widget kpi(String label, String key, IconData icon, MarketTone tone) => SizedBox(
          width: 150,
          child: showSkel
              ? const SkeletonBox(height: 60, radius: 12)
              : KpiTile(icon: icon, label: label, value: _results.isEmpty ? 0 : _sum(key), format: (v) => plain(v), tone: tone),
        );
    return FormSheet(
      title: _generated ? 'Payroll generated' : 'Confirm payroll generation',
      subtitle: '${_emps.length} employee${_emps.length == 1 ? '' : 's'} · ${fmtDate(widget.start)} – ${fmtDate(widget.end)} · ${widget.payableDays} payable days',
      submitLabel: _generated ? 'Done' : 'Confirm',
      busy: _generating,
      onSubmit: _generated ? () => Navigator.pop(context, true) : (_emps.isEmpty || _previewLoading ? null : _confirm),
      extraAction: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _generated
            ? Icon(Icons.check_circle_rounded, key: const ValueKey('ok'), color: p.ok, size: 26)
            : Icon(Icons.play_circle_outline_rounded, key: const ValueKey('go'), color: p.brand, size: 26),
      ),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(children: [
            kpi('Total gross salary', 'gross_salary', Icons.payments_outlined, MarketTone.brand),
            const SizedBox(width: 10),
            kpi('Total deductions', 'total_deductions', Icons.trending_down_rounded, MarketTone.error),
            const SizedBox(width: 10),
            kpi('Total bonus', 'bonuses', Icons.card_giftcard_rounded, MarketTone.ok),
            const SizedBox(width: 10),
            kpi('Net payroll', 'net_salary', Icons.account_balance_wallet_rounded, MarketTone.brand),
          ]),
        ),
        const SizedBox(height: 14),
        if (!_generated)
          FormLabel(
            label: 'HR notes',
            help: 'Saved with this payroll run',
            child: TextField(controller: widget.notes, minLines: 2, maxLines: 5, decoration: motionInput(context, hint: 'Enter HR notes for this payroll period')),
          ),
        if (rows.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('No employees in this run', style: TextStyle(color: p.label)))),
        for (var i = 0; i < rows.length; i++)
          FadeSlideIn(
            key: ValueKey(rows[i].id),
            index: i,
            child: _ResultRow(
              emp: widget.selected[rows[i].id],
              id: rows[i].id,
              row: rows[i].r,
              loading: showSkel,
              onRemove: _generated ? null : () => _remove(rows[i].id),
            ),
          ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  final Map<String, dynamic>? emp;
  final int id;
  final Map<String, dynamic>? row;
  final bool loading;
  final VoidCallback? onRemove;
  const _ResultRow({required this.emp, required this.id, required this.row, required this.loading, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final name = emp == null ? '#$id' : employeeName(emp);
    Widget cell(String label, String key, Color color, {bool bold = false, bool isInt = false}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 10.5, color: p.label)),
            const SizedBox(height: 2),
            loading
                ? const SkeletonBox(height: 12, width: 44)
                : Text(row == null ? '-' : (isInt ? '${toInt(row![key])}' : plain(n(row![key]))),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          InitialsAvatar(name, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
              if (str(emp?['employee_no']).isNotEmpty) Text('#${emp?['employee_no']}', style: TextStyle(fontSize: 11, color: p.label)),
            ]),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove from this payroll run',
              onPressed: onRemove,
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: p.errorBg, borderRadius: BorderRadius.circular(9)),
                child: Icon(Icons.delete_outline_rounded, size: 17, color: p.error),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          cell('Gross', 'gross_salary', p.text),
          cell('Bonus', 'bonuses', p.ok),
          cell('Deductions', 'total_deductions', p.error),
          cell('Net', 'net_salary', p.text, bold: true),
          cell('Days', 'total_payable_days', p.label, isInt: true),
        ]),
      ]),
    );
  }
}
