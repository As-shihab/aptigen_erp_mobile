import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../../chat/data/chat_socket.dart';
import '../shift/shift_common.dart';

/// Attendance logs — mirrors erp/desktop hrm/employee-attendance/
/// employee-attendance-list/EmployeeAttendanceList.tsx: attendance_logs with
/// the employee expanded, active / inactive filter, search, manual create /
/// edit / delete, and a live refresh whenever a device punch arrives
/// (`attendance:recorded`). Mobile adds a date range + employee filter and
/// status chips so the list stays phone sized.
class AttendanceListPage extends StatefulWidget {
  const AttendanceListPage({super.key});

  @override
  State<AttendanceListPage> createState() => _AttendanceListPageState();
}

const _statusOptions = ['present', 'absent', 'late', 'on_leave', 'holiday'];
const _otStatusOptions = ['pending', 'approved', 'rejected'];

class _AttendanceListPageState extends State<AttendanceListPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _employees = [];
  bool _employeesLoaded = false;

  DateTime? _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _to = dayOnly(DateTime.now());
  Object? _employeeId;
  String _active = 'All'; // All / Active / Inactive
  String _chip = 'All';
  String _q = '';

  VoidCallback? _unsubscribe;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    // A fingerprint punch emits this from the backend — quietly re-sync.
    _unsubscribe = subscribeChatSocket('attendance:recorded', (_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), () {
        if (mounted) _load();
      });
    });
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    _debounce?.cancel();
    super.dispose();
  }

  String get _listUrl {
    final f = <String>[
      if (_from != null) "attendance_date ge '${ymd(_from!)}'",
      if (_to != null) "attendance_date le '${ymd(_to!)}'",
      if (_employeeId != null) 'employee_id eq $_employeeId',
      if (_active == 'Active') 'is_active eq true',
      if (_active == 'Inactive') 'is_active eq false',
    ];
    final params = <String>[
      '\$expand=employee(\$select=id,first_name,last_name,employee_no,profile_photo),shift(\$select=id,name,color,is_night)',
      if (f.isNotEmpty) '\$filter=${Uri.encodeComponent(f.join(' and '))}',
      '\$orderby=${Uri.encodeComponent('id desc')}',
      '\$top=1000',
    ];
    return 'attendance_logs?${params.join('&')}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    try {
      final data = await batchLoad(_client, {
        'rows': _listUrl,
        if (!_employeesLoaded)
          'employees': 'employees?\$select=id,first_name,last_name,employee_no&\$orderby=${Uri.encodeComponent('first_name asc')}&\$top=2000',
      });
      if (!mounted) return;
      setState(() {
        _rows = data['rows'] ?? [];
        if (data.containsKey('employees')) {
          _employees = data['employees'] ?? [];
          _employeesLoaded = true;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load attendance'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Derived ──

  static String _status(Map<String, dynamic> r) => str(r['status']).toLowerCase();
  static bool _isLate(Map<String, dynamic> r) => asBool(r['has_late']) || _status(r) == 'late';
  static bool _hasOt(Map<String, dynamic> r) => asBool(r['has_overtime']);

  Map<String, bool Function(Map<String, dynamic>)> get _chips => {
        'All': (_) => true,
        'Present': (r) => _status(r) == 'present',
        'Late': _isLate,
        'Absent': (r) => _status(r) == 'absent',
        'On leave': (r) => _status(r) == 'on_leave',
        'Holiday': (r) => _status(r) == 'holiday',
        'Overtime': _hasOt,
        'Open': (r) => r['check_out_time'] == null,
      };

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    final pred = _chips[_chip] ?? (_) => true;
    return _rows.where((r) {
      if (!pred(r)) return false;
      if (q.isEmpty) return true;
      final hay = [personName(r['employee']), str(r['employee_no']), str(r['custom_id']), str(r['device_ip']), str(r['status'])].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  String get _rangeLabel {
    if (_from == null && _to == null) return 'All dates';
    if (_from != null && _to != null && ymd(_from!) == ymd(_to!)) return fmtDate(_from);
    return '${_from == null ? 'Any' : fmtDate(_from)} to ${_to == null ? 'today' : fmtDate(_to)}';
  }

  // ── Actions ──

  Future<void> _openFilters() async {
    final res = await showMotionSheet<_Filters>(
      context,
      (_) => _FilterSheet(initial: _Filters(_from, _to, _employeeId, _active), employees: _employees),
    );
    if (res == null) return;
    setState(() {
      _from = res.from;
      _to = res.to;
      _employeeId = res.employeeId;
      _active = res.active;
      _rows = [];
    });
    _load();
  }

  void _quickRange(String key) {
    final today = dayOnly(DateTime.now());
    setState(() {
      switch (key) {
        case 'today':
          _from = today;
          _to = today;
        case 'week':
          _from = today.subtract(Duration(days: today.weekday - 1));
          _to = today;
        case 'month':
          _from = DateTime(today.year, today.month, 1);
          _to = today;
        case 'all':
          _from = null;
          _to = null;
      }
      _rows = [];
    });
    _load();
  }

  Future<void> _openForm([Map<String, dynamic>? row]) async {
    final saved = await showMotionSheet<bool>(context, (_) => _AttendanceForm(client: _client, employees: _employees, existing: row));
    if (saved == true) {
      if (mounted) marketToast(context, row == null ? 'Attendance record created' : 'Attendance record updated');
      _load();
    }
  }

  Future<bool> _delete(Map<String, dynamic> row) async {
    final who = str(row['employee_no']).isNotEmpty ? str(row['employee_no']) : personName(row['employee']);
    final ok = await confirmMarket(context, title: 'Delete attendance record?', message: 'The record for "${who.isEmpty ? row['id'] : who}" will be removed permanently.');
    if (!ok) return false;
    try {
      await _client.delete('attendance_logs', row['id']);
      if (mounted) {
        setState(() => _rows.removeWhere((r) => r['id'] == row['id']));
        marketToast(context, 'Attendance record deleted');
      }
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete'), error: true);
      return false;
    }
  }

  Future<void> _details(Map<String, dynamic> r) async {
    final action = await showMotionSheet<String>(context, (ctx) => _DetailSheet(row: r));
    if (!mounted || action == null) return;
    if (action == 'edit') _openForm(r);
    if (action == 'delete') _delete(r);
  }

  Future<void> _more(Map<String, dynamic> r) async {
    final key = await showActionSheet(context, title: personName(r['employee']).isEmpty ? 'Attendance record' : personName(r['employee']), actions: [
      (key: 'view', label: 'View details', icon: Icons.visibility_outlined, destructive: false),
      (key: 'edit', label: 'Edit', icon: Icons.edit_outlined, destructive: false),
      (key: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted || key == null) return;
    if (key == 'view') _details(r);
    if (key == 'edit') _openForm(r);
    if (key == 'delete') _delete(r);
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final rows = _visible;
    final chips = _chips;
    final present = _rows.where((r) => _status(r) == 'present').length;
    final late = _rows.where(_isLate).length;
    final ot = _rows.where(_hasOt).length;
    final selEmp = _employeeId == null ? null : _employees.firstWhere((e) => e['id'].toString() == _employeeId.toString(), orElse: () => <String, dynamic>{});
    return MotionScaffold(
      title: 'Attendance list',
      subtitle: '$_rangeLabel · ${_rows.length} ${_rows.length == 1 ? 'record' : 'records'}',
      icon: Icons.fact_check_outlined,
      accent: Accent.emerald,
      onRefresh: _load,
      onFab: () => _openForm(),
      fabLabel: 'New record',
      actions: [
        IconButton(
          tooltip: 'Filters',
          onPressed: _openFilters,
          icon: Badge(
            isLabelVisible: _employeeId != null || _active != 'All',
            smallSize: 8,
            child: const Icon(Icons.tune_rounded),
          ),
        ),
      ],
      headerExtra: HeaderSearch(hint: 'Search name, employee no or device', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 16),
          sliver: SliverToBoxAdapter(
            child: KpiGrid(children: [
              KpiTile(icon: Icons.list_alt_rounded, label: 'Records', value: _rows.length, tone: MarketTone.brand, onTap: () => setState(() => _chip = 'All')),
              KpiTile(icon: Icons.how_to_reg_rounded, label: 'Present', value: present, tone: MarketTone.ok, onTap: () => setState(() => _chip = 'Present')),
              KpiTile(icon: Icons.running_with_errors_rounded, label: 'Late', value: late, tone: MarketTone.warn, onTap: () => setState(() => _chip = 'Late')),
              KpiTile(icon: Icons.more_time_rounded, label: 'With overtime', value: ot, tone: MarketTone.brand, onTap: () => setState(() => _chip = 'Overtime')),
            ]),
          ),
        ),
        sliverBox(
          Row(children: [
            Expanded(
              child: PressScale(
                onTap: _openFilters,
                child: GlowCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Icon(Icons.date_range_rounded, size: 18, color: p.brand),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_rangeLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text)),
                        Text(
                          [
                            selEmp == null ? 'All employees' : (personName(selEmp).isEmpty ? 'Employee #$_employeeId' : personName(selEmp)),
                            if (_active != 'All') _active.toLowerCase(),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: p.label),
                        ),
                      ]),
                    ),
                    Icon(Icons.expand_more_rounded, color: p.label),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Quick range',
              onSelected: _quickRange,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'today', child: Text('Today')),
                PopupMenuItem(value: 'week', child: Text('This week')),
                PopupMenuItem(value: 'month', child: Text('This month')),
                PopupMenuItem(value: 'all', child: Text('All dates')),
              ],
              child: const RoundIconButton(Icons.bolt_rounded),
            ),
          ]),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 12),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _chip,
              options: [for (final k in chips.keys) (id: k, label: k, count: _rows.where(chips[k]!).length)],
              onChanged: (v) => setState(() => _chip = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton(height: 92)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.fact_check_outlined,
            title: _rows.isEmpty ? 'No attendance in this range' : 'No matches',
            message: _rows.isEmpty ? 'Try a wider date range or add a record manually.' : null,
            actionLabel: _rows.isEmpty && (_from != null || _to != null) ? 'Show all dates' : null,
            onAction: _rows.isEmpty && (_from != null || _to != null) ? () => _quickRange('all') : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              return _AttendanceTile(
                key: ValueKey(r['id']),
                row: r,
                onTap: () => _details(r),
                onLongPress: () => _more(r),
                onDelete: () => _delete(r),
              );
            },
          ),
      ],
    );
  }
}

// ── Row ─────────────────────────────────────────────────────────────────

String _inOut(Map<String, dynamic> r) {
  final cin = parseDate(r['check_in_time']);
  final cout = parseDate(r['check_out_time']);
  return '${cin == null ? '--' : fmtTime(cin)}  →  ${cout == null ? '--' : fmtTime(cout)}';
}

String? _worked(Map<String, dynamic> r) {
  final cin = parseDate(r['check_in_time']);
  final cout = parseDate(r['check_out_time']);
  if (cin == null || cout == null) return null;
  return fmtMinutes(cout.difference(cin).inMinutes);
}

String? _otLabel(Map<String, dynamic> r) {
  if (!asBool(r['has_overtime'])) return null;
  final mins = r['overtime_minutes'];
  if (mins is num) return fmtMinutes(mins.toInt());
  final ot = str(r['over_time']);
  final m = minutesOfDay(ot);
  return m == null ? (ot.isEmpty ? 'Overtime' : ot) : fmtMinutes(m);
}

class _AttendanceTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Future<bool> Function() onDelete;
  const _AttendanceTile({super.key, required this.row, required this.onTap, required this.onLongPress, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final r = row;
    final emp = r['employee'];
    final name = personName(emp).isEmpty ? (str(r['employee_no']).isEmpty ? 'Unknown employee' : str(r['employee_no'])) : personName(emp);
    final status = str(r['status']);
    final late = asBool(r['has_late']) || status.toLowerCase() == 'late';
    final ot = _otLabel(r);
    final worked = _worked(r);
    final open = r['check_out_time'] == null;
    final inactive = !asBool(r['is_active'], fallback: true);
    final shift = r['shift'];

    final card = GlowCard(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          InitialsAvatar(name, imageUrl: emp is Map ? str(emp['profile_photo']) : null, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text)),
              const SizedBox(height: 1),
              Text(
                [if (str(r['employee_no']).isNotEmpty) str(r['employee_no']), fmtDate(calDate(r['attendance_date']))].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: p.label),
              ),
            ]),
          ),
          if (status.isNotEmpty) StatusPill(humanize(status), tone: toneForStatus(status)) else if (inactive) const StatusPill('Inactive'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          if (open && parseDate(r['check_in_time']) != null) ...[PulseDot(color: p.ok, size: 7), const SizedBox(width: 2)],
          Icon(Icons.login_rounded, size: 14, color: p.ok),
          const SizedBox(width: 4),
          Expanded(child: Text(_inOut(r), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.text))),
          if (worked != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8)),
              child: Text(worked, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: p.text)),
            ),
        ]),
        if (late || ot != null || shift is Map || inactive) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (shift is Map) ShiftChip(name: str(shift['name']), color: hexColor(shift['color']), night: asBool(shift['is_night'])),
            if (late) SoftChip(r['late_minutes'] is num ? 'Late ${r['late_minutes']} min' : 'Late', icon: Icons.running_with_errors_rounded, color: p.warn),
            if (ot != null)
              SoftChip(
                'Overtime $ot${str(r['overtime_status']).isEmpty ? '' : ' · ${humanize(str(r['overtime_status']))}'}',
                icon: Icons.more_time_rounded,
                color: const Color(0xFFE76500),
              ),
            if (inactive && status.isNotEmpty) const SoftChip('Inactive', icon: Icons.visibility_off_outlined),
          ]),
        ],
      ]),
    );

    return Dismissible(
      key: ValueKey('att_${r['id']}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(color: p.errorBg, borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.delete_outline_rounded, color: p.error),
      ),
      child: card,
    );
  }
}

// ── Detail sheet ────────────────────────────────────────────────────────

class _DetailSheet extends StatelessWidget {
  final Map<String, dynamic> row;
  const _DetailSheet({required this.row});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final r = row;
    final emp = r['employee'];
    final name = personName(emp).isEmpty ? 'Unknown employee' : personName(emp);
    final status = str(r['status']);
    String or(String v) => v.isEmpty ? '—' : v;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetGrabber(),
            Row(children: [
              InitialsAvatar(name, imageUrl: emp is Map ? str(emp['profile_photo']) : null, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
                  Text(fmtDate(calDate(r['attendance_date'])), style: TextStyle(fontSize: 12.5, color: p.label)),
                ]),
              ),
              if (status.isNotEmpty) StatusPill(humanize(status), tone: toneForStatus(status)),
            ]),
            const SizedBox(height: 14),
            FadeSlideIn(
              child: GlowCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  _TimeBlock(label: 'Check in', value: fmtTime(parseDate(r['check_in_time'])), color: p.ok, icon: Icons.login_rounded),
                  Container(width: 1, height: 40, color: p.line),
                  _TimeBlock(label: 'Check out', value: fmtTime(parseDate(r['check_out_time'])), color: p.error, icon: Icons.logout_rounded),
                  Container(width: 1, height: 40, color: p.line),
                  _TimeBlock(label: 'Worked', value: _worked(r) ?? '--', color: p.brand, icon: Icons.timelapse_rounded),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            InfoRow('Employee no', or(str(r['employee_no']))),
            InfoRow('Custom id', or(str(r['custom_id']))),
            InfoRow('Shift', or(nested(r, 'shift'))),
            InfoRow('Late', asBool(r['has_late']) ? (r['late_minutes'] is num ? '${r['late_minutes']} min' : 'Yes') : 'No'),
            InfoRow('Has overtime', asBool(r['has_overtime']) ? 'Yes' : 'No'),
            InfoRow('Overtime time', or(str(r['over_time']))),
            InfoRow('Overtime minutes', or(str(r['overtime_minutes']))),
            InfoRow('Overtime status', or(humanize(str(r['overtime_status'])))),
            InfoRow('Device ip', or(str(r['device_ip']))),
            InfoRow('Active', asBool(r['is_active'], fallback: true) ? 'Yes' : 'No'),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, 'delete'),
                  icon: Icon(Icons.delete_outline_rounded, color: p.error),
                  label: Text('Delete', style: TextStyle(color: p.error, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    side: BorderSide(color: p.error.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: GradientButton(label: 'Edit record', icon: Icons.edit_outlined, accent: Accent.emerald, onTap: () => Navigator.pop(context, 'edit'))),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _TimeBlock({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Expanded(
      child: Column(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(value.isEmpty ? '--' : value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.text)),
        Text(label, style: TextStyle(fontSize: 11, color: p.label)),
      ]),
    );
  }
}

// ── Filter sheet ────────────────────────────────────────────────────────

class _Filters {
  final DateTime? from;
  final DateTime? to;
  final Object? employeeId;
  final String active;
  const _Filters(this.from, this.to, this.employeeId, this.active);
}

class _FilterSheet extends StatefulWidget {
  final _Filters initial;
  final List<Map<String, dynamic>> employees;
  const _FilterSheet({required this.initial, required this.employees});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late DateTime? _from = widget.initial.from;
  late DateTime? _to = widget.initial.to;
  late Object? _emp = widget.initial.employeeId;
  late String _active = widget.initial.active;

  @override
  Widget build(BuildContext context) => FormSheet(
        title: 'Filter attendance',
        submitLabel: 'Apply filters',
        extraAction: TextButton(
          onPressed: () => setState(() {
            final today = dayOnly(DateTime.now());
            _from = DateTime(today.year, today.month, 1);
            _to = today;
            _emp = null;
            _active = 'All';
          }),
          child: const Text('Reset'),
        ),
        onSubmit: () {
          if (_from != null && _to != null && _from!.isAfter(_to!)) {
            marketToast(context, 'From date must be before to date', error: true);
            return;
          }
          Navigator.pop(context, _Filters(_from, _to, _emp, _active));
        },
        children: [
          FormLabel(label: 'From', child: DatePickField(value: _from, hint: 'Any date', onChanged: (d) => setState(() => _from = d))),
          FormLabel(label: 'To', child: DatePickField(value: _to, hint: 'Any date', onChanged: (d) => setState(() => _to = d))),
          FormLabel(
            label: 'Employee',
            child: PickerField(
              value: _emp,
              hint: 'All employees',
              icon: Icons.person_search_outlined,
              options: [for (final e in widget.employees) employeeOption(e)],
              onChanged: (v) => setState(() => _emp = v),
            ),
          ),
          FormLabel(
            label: 'Record state',
            child: Wrap(spacing: 8, children: [
              for (final a in const ['All', 'Active', 'Inactive'])
                ChoiceChip(label: Text(a), selected: _active == a, onSelected: (_) => setState(() => _active = a)),
            ]),
          ),
        ],
      );
}

// ── Create / edit form ──────────────────────────────────────────────────

class _AttendanceForm extends StatefulWidget {
  final ApiClient client;
  final List<Map<String, dynamic>> employees;
  final Map<String, dynamic>? existing;
  const _AttendanceForm({required this.client, required this.employees, this.existing});

  @override
  State<_AttendanceForm> createState() => _AttendanceFormState();
}

class _AttendanceFormState extends State<_AttendanceForm> {
  late final Map<String, dynamic>? e = widget.existing;
  late bool _active = e == null ? true : asBool(e!['is_active'], fallback: true);
  late bool _hasOt = e == null ? false : asBool(e!['has_overtime']);
  late Object? _employeeId = e?['employee_id'];
  late String _employeeNo = str(e?['employee_no']);
  late final _customId = TextEditingController(text: str(e?['custom_id']));
  late DateTime? _date = calDate(e?['attendance_date']) ?? dayOnly(DateTime.now());
  late DateTime? _in = parseDate(e?['check_in_time'])?.toLocal();
  late DateTime? _out = parseDate(e?['check_out_time'])?.toLocal();
  late final _overTime = TextEditingController(text: str(e?['over_time']));
  late final _otMinutes = TextEditingController(text: str(e?['overtime_minutes']));
  late String? _status = str(e?['status']).isEmpty ? null : str(e?['status']);
  late String? _otStatus = str(e?['overtime_status']).isEmpty ? null : str(e?['overtime_status']);
  late final _deviceIp = TextEditingController(text: str(e?['device_ip']));
  bool _busy = false;

  @override
  void dispose() {
    _customId.dispose();
    _overTime.dispose();
    _otMinutes.dispose();
    _deviceIp.dispose();
    super.dispose();
  }

  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (_date == null || _in == null) {
      marketToast(context, 'Attendance date and check in are required', error: true);
      return;
    }
    if (_out != null && _out!.isBefore(_in!)) {
      marketToast(context, 'Check out must be after check in', error: true);
      return;
    }
    final body = <String, dynamic>{
      'custom_id': _t(_customId),
      'is_active': _active,
      'employee_id': _employeeId == null ? null : int.tryParse(_employeeId.toString()),
      'employee_no': _employeeNo.trim().isEmpty ? null : _employeeNo.trim(),
      'attendance_date': DateTime.utc(_date!.year, _date!.month, _date!.day).toIso8601String(),
      'check_in_time': _in!.toUtc().toIso8601String(),
      'check_out_time': _out?.toUtc().toIso8601String(),
      'over_time': _t(_overTime),
      'has_overtime': _hasOt,
      'overtime_status': _otStatus,
      'overtime_minutes': _t(_otMinutes) == null ? null : int.tryParse(_otMinutes.text.trim()),
      'status': _status,
      'device_ip': _t(_deviceIp),
    };
    setState(() => _busy = true);
    try {
      final api = EntityApi(widget.client, 'attendance_logs');
      if (e == null) {
        await api.create(body);
      } else {
        await api.update(e!['id'], body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(err, 'Failed to save attendance record'), error: true);
      }
    }
  }

  Widget _choices(List<String> values, String? selected, ValueChanged<String?> onChanged) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in values)
          ChoiceChip(label: Text(humanize(s)), selected: selected == s, onSelected: (on) => onChanged(on ? s : null)),
      ]);

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    return FormSheet(
      title: e == null ? 'New attendance record' : 'Edit attendance record',
      subtitle: e == null ? null : personName(e!['employee']),
      busy: _busy,
      submitLabel: e == null ? 'Create' : 'Save changes',
      onSubmit: _date != null && _in != null ? _save : null,
      children: [
        Row(children: [
          Expanded(child: SwitchField(label: 'Active', value: _active, onChanged: (v) => setState(() => _active = v))),
          const SizedBox(width: 10),
          Expanded(child: SwitchField(label: 'Overtime', value: _hasOt, onChanged: (v) => setState(() => _hasOt = v))),
        ]),
        FormLabel(
          label: 'Employee',
          required: true,
          help: _employeeNo.isEmpty ? null : 'Employee no $_employeeNo',
          child: PickerField(
            value: _employeeId,
            hint: 'Search by name or employee no',
            icon: Icons.person_search_outlined,
            options: [for (final emp in widget.employees) employeeOption(emp)],
            onChanged: (v) => setState(() {
              _employeeId = v;
              final emp = widget.employees.firstWhere((x) => x['id'].toString() == v.toString(), orElse: () => {});
              _employeeNo = v == null ? '' : str(emp['employee_no']);
            }),
          ),
        ),
        FormLabel(label: 'Custom id', child: TextField(controller: _customId, decoration: motionInput(ctx, hint: 'Optional', icon: Icons.tag_rounded))),
        FormLabel(label: 'Attendance date', required: true, child: DatePickField(value: _date, onChanged: (d) => setState(() => _date = d))),
        FormLabel(label: 'Check in', required: true, child: DatePickField(value: _in, withTime: true, hint: 'Pick date and time', onChanged: (d) => setState(() => _in = d))),
        FormLabel(label: 'Check out', child: DatePickField(value: _out, withTime: true, hint: 'Pick date and time', onChanged: (d) => setState(() => _out = d))),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: FormLabel(label: 'Over time (hh:mm:ss)', child: TextField(controller: _overTime, decoration: motionInput(ctx, hint: 'e.g. 01:30:00'))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FormLabel(
              label: 'Overtime minutes',
              child: TextField(controller: _otMinutes, keyboardType: TextInputType.number, decoration: motionInput(ctx, hint: 'e.g. 90')),
            ),
          ),
        ]),
        FormLabel(label: 'Status', child: _choices(_statusOptions, _status, (v) => setState(() => _status = v))),
        FormLabel(label: 'Overtime status', child: _choices(_otStatusOptions, _otStatus, (v) => setState(() => _otStatus = v))),
        FormLabel(
          label: 'Device ip',
          child: TextField(controller: _deviceIp, keyboardType: TextInputType.url, decoration: motionInput(ctx, hint: 'e.g. 192.168.1.1', icon: Icons.router_outlined)),
        ),
      ],
    );
  }
}
