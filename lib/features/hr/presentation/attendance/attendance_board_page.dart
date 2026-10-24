import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../../chat/data/chat_socket.dart';
import '../shift/shift_common.dart';

/// Daily attendance board — mirrors erp/desktop hrm/employee-attendance/
/// daily-attendance-list/DailyAttendanceList.tsx.
///
/// With hr_settings.has_shift AND has_roster on, the day's roster schedule
/// (GET /api/hrm/roster-schedule) is merged with that day's attendance_logs;
/// otherwise every active employee gets a card, matched against the day's
/// punches and approved leave. Filters: date, shift (defaults to the shift
/// running now), department, search. Live refresh on `attendance:recorded`.
class AttendanceBoardPage extends StatefulWidget {
  const AttendanceBoardPage({super.key});

  @override
  State<AttendanceBoardPage> createState() => _AttendanceBoardPageState();
}

enum _St { present, late, absent, leave }

extension on _St {
  String get label => switch (this) {
        _St.present => 'Present',
        _St.late => 'Late',
        _St.absent => 'Absent',
        _St.leave => 'On leave',
      };
  MarketTone get tone => switch (this) {
        _St.present => MarketTone.ok,
        _St.late => MarketTone.warn,
        _St.absent => MarketTone.error,
        _St.leave => MarketTone.info,
      };
  Color get color => switch (this) {
        _St.present => const Color(0xFF30914C),
        _St.late => const Color(0xFFE76500),
        _St.absent => const Color(0xFFD20A0A),
        _St.leave => const Color(0xFF0070F2),
      };
}

class _Rec {
  final String key;
  final int employeeId;
  final String name;
  final String employeeNo;
  final String? photo;
  final String department;
  final String shiftName;
  final Color shiftColor;
  final bool night;
  final String assignment; // Regular / SWAP / EXTRA / REPLACEMENT
  final _St status;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final String? absentType;
  final String? overtime;
  const _Rec({
    required this.key,
    required this.employeeId,
    required this.name,
    required this.employeeNo,
    required this.photo,
    required this.department,
    required this.shiftName,
    required this.shiftColor,
    required this.night,
    required this.assignment,
    required this.status,
    required this.checkIn,
    required this.checkOut,
    required this.absentType,
    required this.overtime,
  });

  bool get ongoing => checkIn != null && checkOut == null;

  String worked(DateTime now) {
    if (checkIn == null) return '--';
    final end = checkOut ?? now;
    return fmtMinutes(end.difference(checkIn!).inMinutes);
  }
}

String? _overtimeOf(Map<String, dynamic> log) {
  if (!asBool(log['has_overtime'])) return null;
  final mins = log['overtime_minutes'];
  if (mins is num) return fmtMinutes(mins.toInt());
  final m = minutesOfDay(log['over_time']);
  return m == null ? null : fmtMinutes(m);
}

class _AttendanceBoardPageState extends State<AttendanceBoardPage> {
  final _client = ApiClient();

  // Settings (default true so shift UI doesn't flash-hide, like desktop).
  bool _hasShift = true;
  bool _hasRoster = true;
  bool _bootstrapped = false;

  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _shifts = [];

  DateTime _date = dayOnly(DateTime.now());
  String? _shift;
  String? _dept;
  String _q = '';
  _St? _status;

  bool _loading = true;
  String? _error;
  List<_Rec> _records = [];
  int _loadSeq = 0;

  VoidCallback? _unsubscribe;
  Timer? _debounce;
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _unsubscribe = subscribeChatSocket('attendance:recorded', (_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), () {
        if (mounted) _loadBoard(silent: true);
      });
    });
    // Live "worked" counters for people still checked in — 30s is plenty
    // since only hours / minutes are shown.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _records.any((r) => r.ongoing)) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    _debounce?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  String? _currentShiftName() {
    final now = DateTime.now();
    final mins = now.hour * 60 + now.minute;
    for (final s in _shifts) {
      final a = minutesOfDay(s['start_time']);
      final b = minutesOfDay(s['end_time']);
      if (a == null || b == null) continue;
      final inside = a <= b ? mins >= a && mins < b : mins >= a || mins < b;
      if (inside) return str(s['name']);
    }
    return null;
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await batchLoad(_client, {
        'settings': 'hr_settings?\$select=id,has_shift,has_roster&\$top=1',
        'departments': 'departments?\$select=id,name&\$top=500',
        'shifts': 'employee_shifts?\$select=id,name,start_time,end_time,color,is_night&\$filter=${Uri.encodeComponent('is_active eq true')}&\$top=500',
      });
      if (!mounted) return;
      final s = (data['settings'] ?? []).firstOrNull;
      setState(() {
        if (s != null) {
          _hasShift = asBool(s['has_shift'], fallback: true);
          _hasRoster = asBool(s['has_roster'], fallback: true);
        }
        _departments = data['departments'] ?? [];
        _shifts = data['shifts'] ?? [];
        _shift ??= _currentShiftName();
        _bootstrapped = true;
      });
    } catch (_) {
      // Settings / lookups are best effort — the board still loads with defaults.
      _bootstrapped = true;
    }
    await _loadBoard();
  }

  Future<void> _refresh() => _bootstrapped ? _loadBoard() : _bootstrap();

  Future<void> _loadBoard({bool silent = false}) async {
    final seq = ++_loadSeq;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final apiDate = ymd(_date);
    const logSelect = 'id,employee_id,check_in_time,check_out_time,status,over_time,has_overtime,overtime_minutes';
    try {
      final List<_Rec> built;
      if (_hasShift && _hasRoster) {
        final res = await Future.wait([
          _client.get('hrm/roster-schedule?start_date=$apiDate&end_date=$apiDate&all_employees=1', isV8: false),
          _client.get("attendance_logs?\$filter=${Uri.encodeComponent("attendance_date eq '$apiDate'")}&\$select=$logSelect&\$top=1000"),
        ]);
        final days = res[0] is Map ? (res[0] as Map)['data'] : null;
        final first = days is List && days.isNotEmpty && days.first is Map ? days.first as Map : const {};
        final shifts = (first['shifts'] is List ? first['shifts'] as List : const []).whereType<Map>().toList();
        final logs = _logsByEmployee(rowsOf(res[1]));
        built = [
          for (final sh in shifts)
            for (final emp in (sh['employees'] is List ? sh['employees'] as List : const []).whereType<Map>())
              _fromRoster(sh.cast<String, dynamic>(), emp.cast<String, dynamic>(), logs, apiDate),
        ];
      } else {
        final data = await batchLoad(_client, {
          'employees': 'employees?\$select=id,employee_no,first_name,last_name,profile_photo'
              '&\$expand=department(\$select=id,name),shift(\$select=id,name,start_time,end_time,color,is_night,late_start_minute)'
              '&\$filter=${Uri.encodeComponent('is_active eq true')}&\$top=2000',
          'logs': "attendance_logs?\$filter=${Uri.encodeComponent("attendance_date eq '$apiDate'")}&\$select=$logSelect&\$top=2000",
          'leave': "leave_requests?\$filter=${Uri.encodeComponent("status eq 'APPROVED' and start_date le '$apiDate' and end_date ge '$apiDate'")}&\$select=employee_id&\$top=2000",
        });
        final logs = _logsByEmployee(data['logs'] ?? []);
        final onLeave = {for (final l in data['leave'] ?? <Map<String, dynamic>>[]) l['employee_id'].toString()};
        built = [for (final e in data['employees'] ?? <Map<String, dynamic>>[]) _fromEmployee(e, logs, apiDate, onLeave.contains(e['id'].toString()))];
      }
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _records = built;
        _now = DateTime.now();
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      if (!silent) setState(() => _error = errorMessage(e, 'Could not load the attendance board'));
    } finally {
      if (mounted && seq == _loadSeq) setState(() => _loading = false);
    }
  }

  Map<String, Map<String, dynamic>> _logsByEmployee(List<Map<String, dynamic>> logs) => {
        for (final l in logs)
          if (l['employee_id'] != null) l['employee_id'].toString(): l,
      };

  DateTime? _shiftStart(String apiDate, dynamic startTime) {
    final m = minutesOfDay(startTime);
    if (m == null) return null;
    final d = DateTime.parse(apiDate);
    return DateTime(d.year, d.month, d.day).add(Duration(minutes: m));
  }

  _Rec _fromRoster(Map<String, dynamic> shift, Map<String, dynamic> emp, Map<String, Map<String, dynamic>> logs, String apiDate) {
    final det = (emp['employee_details'] is Map ? emp['employee_details'] as Map : const {}).cast<String, dynamic>();
    final id = int.tryParse(str(det['id'])) ?? 0;
    final holiday = str(det['holiday_status']);
    final log = logs[id.toString()];
    _St status;
    DateTime? cin;
    DateTime? cout;
    String? absentType;
    String? ot;
    if (holiday.isNotEmpty) {
      status = _St.leave;
      absentType = holiday == 'Leave' ? 'On leave' : humanize(holiday);
    } else if (log != null) {
      cin = parseDate(log['check_in_time'])?.toLocal();
      cout = parseDate(log['check_out_time'])?.toLocal();
      final start = _shiftStart(apiDate, shift['start_time']);
      status = cin != null && start != null && cin.isAfter(start.add(const Duration(minutes: 10))) ? _St.late : _St.present;
      ot = _overtimeOf(log);
    } else {
      status = _St.absent;
      absentType = 'Unmarked';
    }
    return _Rec(
      key: '${shift['shift_id']}-$id',
      employeeId: id,
      name: str(det['name']),
      employeeNo: str(det['employee_no']),
      photo: str(det['profile_photo']).isEmpty ? null : str(det['profile_photo']),
      department: str(det['department']).isEmpty ? '—' : str(det['department']),
      shiftName: str(shift['shift_name']),
      shiftColor: hexColor(shift['color']),
      night: wrapsMidnight(shift['start_time'], shift['end_time']),
      assignment: str(emp['status']).isEmpty ? 'Regular' : str(emp['status']),
      status: status,
      checkIn: cin,
      checkOut: cout,
      absentType: absentType,
      overtime: ot,
    );
  }

  _Rec _fromEmployee(Map<String, dynamic> emp, Map<String, Map<String, dynamic>> logs, String apiDate, bool onLeave) {
    final id = int.tryParse(str(emp['id'])) ?? 0;
    final shift = emp['shift'] is Map ? (emp['shift'] as Map).cast<String, dynamic>() : null;
    final log = logs[id.toString()];
    var status = _St.absent;
    String? absentType = 'Unmarked';
    DateTime? cin;
    DateTime? cout;
    String? ot;
    if (onLeave) {
      status = _St.leave;
      absentType = 'On leave';
    } else if (log != null) {
      absentType = null;
      cin = parseDate(log['check_in_time'])?.toLocal();
      cout = parseDate(log['check_out_time'])?.toLocal();
      status = _St.present;
      if (_hasShift && shift != null) {
        final start = _shiftStart(apiDate, shift['start_time']);
        final grace = shift['late_start_minute'] is num ? (shift['late_start_minute'] as num).toInt() : 10;
        if (cin != null && start != null && cin.isAfter(start.add(Duration(minutes: grace)))) status = _St.late;
      }
      ot = _overtimeOf(log);
    }
    return _Rec(
      key: 'simple-$id',
      employeeId: id,
      name: personName(emp),
      employeeNo: str(emp['employee_no']),
      photo: str(emp['profile_photo']).isEmpty ? null : str(emp['profile_photo']),
      department: nested(emp, 'department').isEmpty ? '—' : nested(emp, 'department'),
      shiftName: _hasShift ? (shift == null ? '—' : str(shift['name'])) : '—',
      shiftColor: hexColor(shift?['color']),
      night: _hasShift && asBool(shift?['is_night']),
      assignment: 'Regular',
      status: status,
      checkIn: cin,
      checkOut: cout,
      absentType: absentType,
      overtime: ot,
    );
  }

  // ── Filtering ──

  List<_Rec> get _scoped {
    final q = _q.trim().toLowerCase();
    return _records.where((r) {
      if (_dept != null && r.department != _dept) return false;
      if (_hasShift && _shift != null && r.shiftName != _shift) return false;
      if (q.isNotEmpty && !r.name.toLowerCase().contains(q) && !r.employeeNo.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  void _setDate(DateTime d) {
    setState(() {
      _date = dayOnly(d);
      _records = [];
    });
    _loadBoard();
  }

  void _reset() {
    setState(() {
      _dept = null;
      _status = null;
      _shift = _currentShiftName();
    });
    if (ymd(_date) != ymd(DateTime.now())) {
      _setDate(DateTime.now());
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 366)));
    if (d != null) _setDate(d);
  }

  Future<void> _pickDept() async {
    final picked = await showPickerSheet(context,
        title: 'Department', selected: _dept, options: [const PickOption('__all', 'All departments'), for (final d in _departments) PickOption(str(d['name']), str(d['name']))]);
    if (picked == null) return;
    setState(() => _dept = picked.id == '__all' ? null : picked.id.toString());
  }

  void _details(_Rec r) {
    showMotionSheet<void>(context, (ctx) {
      final p = MarketPalette.of(ctx);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetGrabber(),
            Row(children: [
              _StatusAvatar(rec: r, size: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
                  Text(r.employeeNo.isEmpty ? fmtDate(_date) : '${r.employeeNo} · ${fmtDate(_date)}', style: TextStyle(fontSize: 12.5, color: p.label)),
                ]),
              ),
              StatusPill(r.status.label, tone: r.status.tone),
            ]),
            const SizedBox(height: 14),
            InfoRow('Department', r.department),
            if (_hasShift) InfoRow('Shift', r.night ? '${r.shiftName} (night)' : r.shiftName),
            if (r.assignment != 'Regular') InfoRow('Assignment', humanize(r.assignment)),
            InfoRow('Check in', r.checkIn == null ? '--' : fmtTime(r.checkIn)),
            InfoRow('Check out', r.checkOut == null ? '--' : fmtTime(r.checkOut)),
            InfoRow(r.ongoing ? 'Worked so far' : 'Total hours', r.worked(DateTime.now()), emphasize: true),
            if (r.overtime != null) InfoRow('Overtime', r.overtime!),
            if (r.absentType != null) InfoRow('Note', r.absentType!),
          ]),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final scoped = _scoped;
    final count = {for (final s in _St.values) s: scoped.where((r) => r.status == s).length};
    final visible = _status == null ? scoped : scoped.where((r) => r.status == _status).toList();
    final total = scoped.length;
    final attended = (count[_St.present] ?? 0) + (count[_St.late] ?? 0);
    final isToday = ymd(_date) == ymd(DateTime.now());

    return MotionScaffold(
      title: 'Attendance board',
      subtitle: isToday ? 'Today at a glance' : DateFormat('EEEE, d MMM yyyy').format(_date),
      icon: Icons.dashboard_customize_outlined,
      accent: Accent.ocean,
      onRefresh: _refresh,
      actions: [IconButton(tooltip: 'Reset filters', onPressed: _reset, icon: const Icon(Icons.restart_alt_rounded))],
      headerExtra: HeaderSearch(hint: 'Search by name or id', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        // Date stepper
        sliverBox(
          Row(children: [
            RoundIconButton(Icons.chevron_left_rounded, onTap: () => _setDate(_date.subtract(const Duration(days: 1)))),
            const SizedBox(width: 10),
            Expanded(
              child: GlowCard(
                onTap: _pickDate,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a), child: c)),
                  child: Row(key: ValueKey(ymd(_date)), mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.event_rounded, size: 18, color: p.brand),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isToday ? 'Today, ${DateFormat('d MMM').format(_date)}' : DateFormat('EEE, d MMM yyyy').format(_date),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 10),
            RoundIconButton(Icons.chevron_right_rounded, onTap: () => _setDate(_date.add(const Duration(days: 1)))),
          ]),
        ),
        // Summary ring + KPIs
        sliverBox(
          _loading && _records.isEmpty
              ? const SkeletonBox(height: 150, radius: 12)
              : GlowCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    ProgressRing(
                      value: total == 0 ? 0 : attended / total,
                      size: 104,
                      stroke: 10,
                      color: const Color(0xFF30914C),
                      center: Column(mainAxisSize: MainAxisSize.min, children: [
                        CountUp(
                          value: total == 0 ? 0 : attended * 100 / total,
                          format: (v) => '${v.round()}%',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.text),
                        ),
                        Text('$attended of $total in', style: TextStyle(fontSize: 10.5, color: p.label)),
                      ]),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(children: [
                        Row(children: [
                          _StatChip(st: _St.present, value: count[_St.present] ?? 0, selected: _status == _St.present, onTap: _toggle),
                          const SizedBox(width: 8),
                          _StatChip(st: _St.late, value: count[_St.late] ?? 0, selected: _status == _St.late, onTap: _toggle),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          _StatChip(st: _St.absent, value: count[_St.absent] ?? 0, selected: _status == _St.absent, onTap: _toggle),
                          const SizedBox(width: 8),
                          _StatChip(st: _St.leave, value: count[_St.leave] ?? 0, selected: _status == _St.leave, onTap: _toggle),
                        ]),
                      ]),
                    ),
                  ]),
                ),
        ),
        // Shift chips
        if (_hasShift && _shifts.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.only(top: 14),
            sliver: SliverToBoxAdapter(
              child: ChipFilter<String>(
                value: _shift ?? '__all',
                options: [
                  (id: '__all', label: 'All shifts', count: null),
                  for (final s in _shifts) (id: str(s['name']), label: str(s['name']), count: null),
                ],
                onChanged: (v) => setState(() => _shift = v == '__all' ? null : v),
              ),
            ),
          ),
        // Department + status summary line
        sliverBox(
          Row(children: [
            PressScale(
              onTap: _pickDept,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: _dept == null ? p.card : p.brandSoft, borderRadius: BorderRadius.circular(12), border: Border.all(color: _dept == null ? p.line : p.brand)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.account_tree_outlined, size: 15, color: _dept == null ? p.label : p.brand),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(_dept ?? 'All departments',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _dept == null ? p.text : p.brand)),
                  ),
                  Icon(Icons.expand_more_rounded, size: 18, color: p.label),
                ]),
              ),
            ),
            const Spacer(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _status == null ? '${visible.length} people' : '${visible.length} ${_status!.label.toLowerCase()}',
                key: ValueKey('${_status}_${visible.length}'),
                style: TextStyle(fontSize: 12.5, color: p.label, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        ),
        if (_loading && _records.isEmpty)
          sliverSkeleton(height: 132)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _refresh)
        else if (visible.isEmpty)
          sliverEmpty(
            icon: Icons.event_busy_outlined,
            title: _records.isNotEmpty
                ? 'No records match the selected filters'
                : (_hasShift && _hasRoster ? 'No roster scheduled for this date' : 'No active employees found'),
            actionLabel: _records.isNotEmpty ? 'Clear filters' : null,
            onAction: _records.isNotEmpty
                ? () => setState(() {
                      _dept = null;
                      _shift = null;
                      _status = null;
                    })
                : null,
          )
        else
          sliverStagger(
            count: visible.length,
            builder: (_, i) => _BoardCard(key: ValueKey(visible[i].key), rec: visible[i], now: _now, showShift: _hasShift, onTap: () => _details(visible[i])),
          ),
      ],
    );
  }

  void _toggle(_St s) => setState(() => _status = _status == s ? null : s);
}

class _StatChip extends StatelessWidget {
  final _St st;
  final int value;
  final bool selected;
  final ValueChanged<_St> onTap;
  const _StatChip({required this.st, required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Expanded(
      child: PressScale(
        onTap: () => onTap(st),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? st.color : st.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CountUp(value: value, format: (v) => '${v.round()}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: selected ? Colors.white : p.text)),
            Text(st.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? Colors.white : st.color)),
          ]),
        ),
      ),
    );
  }
}

class _StatusAvatar extends StatelessWidget {
  final _Rec rec;
  final double size;
  const _StatusAvatar({required this.rec, this.size = 46});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: rec.status.color, width: 2)),
        child: InitialsAvatar(rec.name.isEmpty ? '?' : rec.name, imageUrl: rec.photo, size: size - 8),
      );
}

class _BoardCard extends StatelessWidget {
  final _Rec rec;
  final DateTime now;
  final bool showShift;
  final VoidCallback onTap;
  const _BoardCard({super.key, required this.rec, required this.now, required this.showShift, required this.onTap});

  static const _assignColors = {
    'SWAP': Color(0xFFD20A0A),
    'EXTRA': Color(0xFF30914C),
    'REPLACEMENT': Color(0xFFE76500),
  };

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final r = rec;
    final ongoing = r.ongoing;
    return GlowCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(children: [
            _StatusAvatar(rec: r),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name.isEmpty ? 'Employee #${r.employeeId}' : r.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text)),
                if (r.employeeNo.isNotEmpty) Text(r.employeeNo, style: TextStyle(fontSize: 11.5, color: p.label)),
              ]),
            ),
            PulseDot(color: r.status.color, active: ongoing, size: 7),
            const SizedBox(width: 2),
            Text(r.status.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: r.status.color)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            SoftChip(r.department, icon: Icons.account_tree_outlined),
            if (showShift && r.shiftName != '—') ShiftChip(name: r.shiftName, color: r.shiftColor, night: r.night),
            if (r.assignment != 'Regular') SoftChip(humanize(r.assignment), color: _assignColors[r.assignment] ?? p.brand),
          ]),
        ),
        Divider(height: 1, color: p.line),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _line(p, Icons.login_rounded, const Color(0xFF30914C), 'Check in', r.checkIn == null ? '--' : fmtTime(r.checkIn)),
                const SizedBox(height: 4),
                _line(p, Icons.logout_rounded, const Color(0xFFD20A0A), 'Check out', r.checkOut == null ? '--' : fmtTime(r.checkOut)),
                if (r.overtime != null) ...[
                  const SizedBox(height: 4),
                  _line(p, Icons.more_time_rounded, const Color(0xFFE76500), 'Overtime', r.overtime!, valueColor: const Color(0xFFE76500)),
                ],
                if (r.absentType != null) ...[
                  const SizedBox(height: 6),
                  StatusPill(r.absentType!, tone: r.status.tone),
                ],
              ]),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(horizontal: ongoing ? 16 : 12, vertical: ongoing ? 12 : 8),
              decoration: BoxDecoration(
                color: ongoing ? const Color(0xFF30914C).withValues(alpha: 0.13) : p.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(children: [
                Text(r.worked(now), style: TextStyle(fontSize: ongoing ? 16 : 13.5, fontWeight: FontWeight.w800, color: ongoing ? const Color(0xFF30914C) : p.text)),
                if (ongoing) Text('Working now', style: TextStyle(fontSize: 10.5, color: p.label)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _line(MarketPalette p, IconData icon, Color c, String label, String value, {Color? valueColor}) => Row(children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 6),
        Text('$label: ', style: TextStyle(fontSize: 12, color: p.label)),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: valueColor ?? p.text)),
      ]);
}
