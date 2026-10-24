import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'employee_form_page.dart';
import 'employee_shared.dart';

/// Employee profile — port of erp/desktop's EmployeeDetailPanel.tsx: hero
/// header, section switcher (personal, organization, attendance & leave,
/// payroll, learning, benefits) and the monthly attendance summary with
/// attendance / leaves / job card sub tabs. Adds edit, activate /
/// deactivate and delete actions.
class EmployeeDetailPage extends StatefulWidget {
  final Map<String, dynamic> employee;
  const EmployeeDetailPage({super.key, required this.employee});

  @override
  State<EmployeeDetailPage> createState() => _EmployeeDetailPageState();
}

enum _Section { personal, organization, attendance, payroll, learning, benefits }

extension on _Section {
  String get label => switch (this) {
        _Section.personal => 'Personal',
        _Section.organization => 'Organization',
        _Section.attendance => 'Attendance and leave',
        _Section.payroll => 'Payroll and finance',
        _Section.learning => 'Learning and development',
        _Section.benefits => 'Benefits',
      };
}

class _EmployeeDetailPageState extends State<EmployeeDetailPage> {
  final _client = ApiClient();
  late Map<String, dynamic> _e = Map.of(widget.employee);
  _Section _section = _Section.attendance;
  String _subTab = 'attendance';
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loadingAtt = false;
  String? _attError;
  List<Map<String, dynamic>> _att = [];
  List<Map<String, dynamic>> _leaves = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _reloadEmployee() async {
    try {
      final res = await _client.get('employees?\$filter=id eq ${_e['id']}&\$expand=$employeeExpand&\$top=1');
      final rows = unwrapList(res);
      if (rows.isNotEmpty && rows.first is Map && mounted) setState(() => _e = (rows.first as Map).cast<String, dynamic>());
    } catch (_) {}
  }

  Future<void> _refresh() async {
    await Future.wait([_reloadEmployee(), _loadAttendance()]);
  }

  String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _loadAttendance() async {
    final id = _e['id'];
    if (id == null) return;
    final start = _ymd(DateTime(_month.year, _month.month, 1));
    final end = _ymd(DateTime(_month.year, _month.month + 1, 0));
    setState(() {
      _loadingAtt = true;
      _attError = null;
    });
    try {
      final data = await batchLoad(_client, {
        'att': "attendance_logs?\$filter=employee_id eq $id and attendance_date ge '$start' and attendance_date le '$end'"
            '&\$expand=shift(\$select=id,name,start_time,end_time)'
            '&\$select=id,attendance_date,check_in_time,check_out_time,has_late,late_minutes,has_overtime,overtime_minutes,overtime_status,status'
            '&\$orderby=attendance_date asc&\$top=200',
        'leaves': "leave_requests?\$filter=employee_id eq $id and start_date le '$end' and end_date ge '$start'"
            '&\$expand=leave_type(\$select=id,name)&\$orderby=start_date desc&\$top=100',
      });
      if (!mounted) return;
      setState(() {
        _att = data['att'] ?? [];
        _leaves = data['leaves'] ?? [];
      });
    } catch (e) {
      if (mounted) setState(() => _attError = errorMessage(e, 'Could not load attendance'));
    } finally {
      if (mounted) setState(() => _loadingAtt = false);
    }
  }

  void _shiftMonth(int delta) {
    HapticFeedback.selectionClick();
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _loadAttendance();
  }

  // ── Actions ──────────────────────────────────────────────────────────

  Future<void> _edit() async {
    final saved = await pushMotion<bool>(context, EmployeeFormPage(existing: _e));
    if (saved == true) _reloadEmployee();
  }

  Future<void> _toggleActive() async {
    final next = !asBool(_e['is_active'], fallback: true);
    final ok = await confirmMarket(context,
        title: next ? 'Activate employee?' : 'Deactivate employee?',
        message: next ? '${employeeName(_e)} will be marked active again.' : '${employeeName(_e)} will be marked inactive.',
        confirm: next ? 'Activate' : 'Deactivate',
        destructive: !next);
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _client.put('employees', _e['id'], {'is_active': next});
      if (!mounted) return;
      setState(() => _e['is_active'] = next);
      marketToast(context, next ? 'Employee activated' : 'Employee deactivated');
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not update employee'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmMarket(context,
        title: 'Delete employee?', message: 'Delete employee "${employeeName(_e)}" (${str(_e['employee_no']).isEmpty ? _e['id'] : _e['employee_no']})?');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _client.delete('employees', _e['id']);
      if (!mounted) return;
      marketToast(context, 'Employee deleted');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(e, 'Could not delete employee'), error: true);
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final active = asBool(_e['is_active'], fallback: true);
    return Scaffold(
      backgroundColor: p.bg,
      floatingActionButton: FadeSlideIn(
        index: 4,
        child: FloatingActionButton.extended(
          onPressed: _busy ? null : _edit,
          backgroundColor: Accent.ocean.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.edit_rounded),
          label: const Text('Edit'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: 100,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverAppBar(
              pinned: true,
              stretch: true,
              expandedHeight: 290,
              backgroundColor: Accent.ocean.primary,
              foregroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              systemOverlayStyle: SystemUiOverlayStyle.light,
              title: Text(employeeName(_e), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (k) => switch (k) {
                    'edit' => _edit(),
                    'toggle' => _toggleActive(),
                    _ => _delete(),
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'toggle', child: Text(active ? 'Deactivate' : 'Activate')),
                    PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: p.error))),
                  ],
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: _hero(context, active),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.only(top: 14),
              sliver: SliverToBoxAdapter(
                child: ChipFilter<_Section>(
                  value: _section,
                  options: [for (final s in _Section.values) (id: s, label: s.label, count: null)],
                  onChanged: (s) => setState(() => _section = s),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              sliver: SliverToBoxAdapter(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a), child: child),
                  ),
                  child: KeyedSubtree(key: ValueKey(_section), child: _sectionBody(context)),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context, bool active) {
    final type = nested(_e, 'employee_type');
    final desg = nested(_e, 'designation');
    final joined = parseDate(_e['joining_date']);
    return Stack(fit: StackFit.expand, children: [
      DecoratedBox(decoration: BoxDecoration(gradient: Accent.ocean.gradient)),
      Positioned(right: -50, top: -40, child: _orb(190, 0.12)),
      Positioned(left: -40, bottom: -60, child: _orb(150, 0.08)),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.35)),
              child: EmployeeAvatar(_e, size: 84),
            ),
            const SizedBox(height: 10),
            FadeSlideIn(
              child: Text(employeeName(_e),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
            ),
            Text(desg.isEmpty ? '—' : desg, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
            const SizedBox(height: 8),
            FadeSlideIn(
              index: 1,
              child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                _glassPill(active ? 'Active' : 'Inactive', active ? Icons.check_circle_rounded : Icons.pause_circle_rounded),
                if (type.isNotEmpty) _glassPill(type, Icons.category_outlined),
                if (str(_e['employee_no']).isNotEmpty) _glassPill('#${_e['employee_no']}', Icons.tag_rounded),
              ]),
            ),
            const SizedBox(height: 8),
            FadeSlideIn(
              index: 2,
              child: Wrap(alignment: WrapAlignment.center, spacing: 14, runSpacing: 4, children: [
                if (str(_e['contact_number']).isNotEmpty) _heroLine(Icons.phone_outlined, str(_e['contact_number'])),
                if (str(_e['email']).isNotEmpty) _heroLine(Icons.mail_outline_rounded, str(_e['email'])),
                if (joined != null) _heroLine(Icons.event_outlined, 'Joined ${fmtDate(joined)}'),
              ]),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _orb(double size, double opacity) =>
      Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: opacity)));

  Widget _glassPill(String label, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _heroLine(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.85)),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
      ]);

  Widget _sectionBody(BuildContext context) {
    String d(String k) => fmtDate(parseDate(_e[k]));
    switch (_section) {
      case _Section.personal:
        return FieldGrid([
          ('First name', str(_e['first_name']), Icons.person_outline_rounded),
          ('Last name', str(_e['last_name']), Icons.person_outline_rounded),
          ('Gender', str(_e['gender']), Icons.wc_rounded),
          ('Date of birth', d('date_of_birth'), Icons.cake_outlined),
          ('Blood group', str(_e['blood_group']), Icons.bloodtype_outlined),
          ('Religion', str(_e['religion']), Icons.auto_awesome_outlined),
          ('NID number', str(_e['nid']), Icons.credit_card_outlined),
          ('Referred by', str(_e['referred_by']), Icons.record_voice_over_outlined),
          ('Present address', str(_e['present_address']), Icons.home_outlined),
          ('Permanent address', str(_e['permanent_address']), Icons.house_outlined),
          ('Emergency contact', str(_e['emergency_contact_name']), Icons.contact_emergency_outlined),
          ('Emergency number', str(_e['emergency_contact_number']), Icons.phone_in_talk_outlined),
          ('Relation', str(_e['emergency_contact_relation']), Icons.family_restroom_outlined),
        ]);
      case _Section.organization:
        return FieldGrid([
          ('Employee ID', str(_e['employee_no']), Icons.tag_rounded),
          ('Department', nested(_e, 'department'), Icons.account_tree_outlined),
          ('Designation', nested(_e, 'designation'), Icons.workspace_premium_outlined),
          ('Employee type', nested(_e, 'employee_type'), Icons.category_outlined),
          ('Section', nested(_e, 'section'), Icons.view_module_outlined),
          ('Shift', nested(_e, 'shift'), Icons.schedule_rounded),
          ('Joining date', d('joining_date'), Icons.event_outlined),
          ('Status', asBool(_e['is_active'], fallback: true) ? 'Active' : 'Inactive', Icons.toggle_on_outlined),
          ('Shift fixed', asBool(_e['is_shift_fixed']) ? 'Yes' : 'No', Icons.lock_clock_outlined),
          ('Fingerprint', asBool(_e['enable_fingerprint']) ? 'Enabled' : 'Disabled', Icons.fingerprint_rounded),
        ]);
      case _Section.payroll:
        return const MarketEmpty(icon: Icons.account_balance_wallet_outlined, title: 'Nothing here yet', message: 'Payroll and finance details are not available yet.');
      case _Section.learning:
        return const MarketEmpty(icon: Icons.school_outlined, title: 'Nothing here yet', message: 'Learning and development records are not available yet.');
      case _Section.benefits:
        return const MarketEmpty(icon: Icons.card_giftcard_outlined, title: 'Nothing here yet', message: 'Benefits information is not available yet.');
      case _Section.attendance:
        return _attendance(context);
    }
  }

  // ── Attendance & leave ───────────────────────────────────────────────

  Widget _attendance(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GlowCard(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(children: [
          IconButton(onPressed: () => _shiftMonth(-1), icon: Icon(Icons.chevron_left_rounded, color: p.text)),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Row(key: ValueKey(_month), mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.calendar_month_rounded, size: 17, color: Accent.ocean.primary),
                const SizedBox(width: 6),
                Text(DateFormat('MMMM yyyy').format(_month), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text)),
              ]),
            ),
          ),
          IconButton(onPressed: () => _shiftMonth(1), icon: Icon(Icons.chevron_right_rounded, color: p.text)),
        ]),
      ),
      const SizedBox(height: 12),
      Center(
        child: MarketSegmented<String>(
          value: _subTab,
          options: [
            (id: 'attendance', label: 'Attendance', count: _att.length),
            (id: 'leaves', label: 'Leaves', count: _leaves.length),
            (id: 'jobcard', label: 'Job card', count: null),
          ],
          onChanged: (v) => setState(() => _subTab = v),
        ),
      ),
      const SizedBox(height: 12),
      if (_loadingAtt)
        Column(children: [for (var i = 0; i < 4; i++) const Padding(padding: EdgeInsets.only(bottom: 10), child: SkeletonBox(height: 70, radius: 12))])
      else if (_attError != null)
        MarketEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _attError, actionLabel: 'Retry', onAction: _loadAttendance)
      else
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: KeyedSubtree(
            key: ValueKey('$_subTab-${_month.month}'),
            child: switch (_subTab) {
              'attendance' => _attendanceTab(context),
              'leaves' => _leavesTab(context),
              _ => const MarketEmpty(icon: Icons.assignment_late_outlined, title: 'No job card', message: 'No job card assigned for this employee.'),
            },
          ),
        ),
    ]);
  }

  static int _shiftMinutes(dynamic shift) {
    if (shift is! Map) return 0;
    int? parse(dynamic v) {
      final parts = str(v).split(':');
      if (parts.length < 2) return null;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      return h == null || m == null ? null : h * 60 + m;
    }

    final s = parse(shift['start_time']);
    var e = parse(shift['end_time']);
    if (s == null || e == null) return 0;
    if (e <= s) e += 24 * 60;
    return e - s;
  }

  static int? _workedMinutes(Map<String, dynamic> r) {
    final a = parseDate(r['check_in_time']);
    final b = parseDate(r['check_out_time']);
    if (a == null || b == null) return null;
    final m = b.difference(a).inMinutes;
    return m >= 0 ? m : null;
  }

  static String _dur(num minutes, {bool sign = false}) {
    final s = sign ? (minutes < 0 ? '-' : (minutes > 0 ? '+' : '')) : '';
    final abs = minutes.abs().round();
    return '$s${abs ~/ 60} hr ${abs % 60} min';
  }

  int _overlapDays(Map<String, dynamic> r) {
    final ms = DateTime(_month.year, _month.month, 1);
    final me = DateTime(_month.year, _month.month + 1, 0);
    final rs = parseDate(r['start_date']);
    final re = parseDate(r['end_date']);
    if (rs == null || re == null) return 0;
    final s = DateTime(rs.year, rs.month, rs.day).isAfter(ms) ? DateTime(rs.year, rs.month, rs.day) : ms;
    final e = DateTime(re.year, re.month, re.day).isBefore(me) ? DateTime(re.year, re.month, re.day) : me;
    if (e.isBefore(s)) return 0;
    return e.difference(s).inDays + 1;
  }

  Widget _attendanceTab(BuildContext context) {
    final p = MarketPalette.of(context);
    var scheduled = 0, worked = 0, lateCount = 0, lateMin = 0, incomplete = 0, ot = 0, absent = 0;
    for (final r in _att) {
      scheduled += _shiftMinutes(r['shift']);
      final w = _workedMinutes(r);
      if (w != null) {
        worked += w;
      } else if (r['check_in_time'] != null) {
        incomplete++;
      }
      if (asBool(r['has_late'])) {
        lateCount++;
        lateMin += toInt(r['late_minutes']);
      }
      if (str(r['overtime_status']).toLowerCase() == 'approved') ot += toInt(r['overtime_minutes']);
      if (str(r['status']).toLowerCase() == 'absent') absent++;
    }
    final leaveDays = _leaves.where((r) => str(r['status']).toUpperCase() == 'APPROVED').fold<int>(0, (s, r) => s + _overlapDays(r));
    final diff = worked - scheduled;
    final tiles = <(String, String, Color?, String?)>[
      ('Scheduled', _dur(scheduled), null, null),
      ('Worked', _dur(worked), null, null),
      ('Difference', _dur(diff, sign: true), diff < 0 ? p.error : (diff > 0 ? p.ok : null), null),
      ('Incomplete records', '$incomplete', incomplete > 0 ? p.error : null, null),
      ('Late ins', '$lateCount', null, lateMin > 0 ? '${_dur(lateMin)} delay' : null),
      ('Approved overtime', _dur(ot), null, null),
      ('Absences', '$absent', absent > 0 ? p.error : null, null),
      ('Approved leave days', '$leaveDays', null, null),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Summary'),
      LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < tiles.length; i++)
            SizedBox(
              width: w,
              child: FadeSlideIn(
                index: i,
                child: GlowCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tiles[i].$2, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: tiles[i].$3 ?? p.text)),
                    const SizedBox(height: 3),
                    Text(tiles[i].$1, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.label)),
                    if (tiles[i].$4 != null) Text(tiles[i].$4!, style: TextStyle(fontSize: 11, color: p.label.withValues(alpha: 0.8))),
                  ]),
                ),
              ),
            ),
        ]);
      }),
      const SectionHeader('Daily records'),
      if (_att.isEmpty)
        const MarketEmpty(icon: Icons.event_busy_outlined, title: 'No records', message: 'No attendance records for this month.')
      else
        for (var i = 0; i < _att.length; i++) Padding(padding: const EdgeInsets.only(bottom: 10), child: FadeSlideIn(index: i, child: _attRow(context, _att[i]))),
    ]);
  }

  Widget _attRow(BuildContext context, Map<String, dynamic> r) {
    final p = MarketPalette.of(context);
    final status = str(r['status']).isEmpty ? (asBool(r['has_late']) ? 'late' : 'present') : str(r['status']);
    final shift = r['shift'];
    final sMin = _shiftMinutes(shift);
    final wMin = _workedMinutes(r);
    final diff = wMin != null && sMin > 0 ? wMin - sMin : null;
    final date = parseDate(r['attendance_date']);
    final inT = parseDate(r['check_in_time']);
    final outT = parseDate(r['check_out_time']);
    return GlowCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(date == null ? '—' : DateFormat('EEE, d MMM yyyy').format(date),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
          ),
          StatusPill(humanize(status), tone: status.toLowerCase() == 'on_leave' || status.toLowerCase() == 'holiday' ? MarketTone.info : toneForStatus(status)),
        ]),
        const SizedBox(height: 4),
        Text(shift is Map ? 'Scheduled ${str(shift['start_time'])} - ${str(shift['end_time'])}' : 'No shift',
            style: TextStyle(fontSize: 12, color: p.label)),
        const SizedBox(height: 10),
        Row(children: [
          _punch(context, Icons.login_rounded, p.ok, inT == null ? 'No record' : fmtTime(inT)),
          const SizedBox(width: 14),
          _punch(context, Icons.logout_rounded, p.error, outT == null ? 'No record' : fmtTime(outT)),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(wMin == null ? '—' : _dur(wMin), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.text)),
            if (diff != null)
              Text(_dur(diff, sign: true),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: diff < 0 ? p.error : (diff > 0 ? p.ok : p.label))),
          ]),
        ]),
      ]),
    );
  }

  Widget _punch(BuildContext context, IconData icon, Color color, String text) {
    final p = MarketPalette.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 12.5, color: p.label)),
    ]);
  }

  Widget _leavesTab(BuildContext context) {
    final p = MarketPalette.of(context);
    if (_leaves.isEmpty) {
      return const MarketEmpty(icon: Icons.event_busy_outlined, title: 'No leave requests', message: 'No leave requests overlapping this month.');
    }
    return Column(children: [
      for (var i = 0; i < _leaves.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: FadeSlideIn(
            index: i,
            child: Builder(builder: (_) {
              final r = _leaves[i];
              final status = str(r['status']);
              return GlowCard(
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AccentIcon(Icons.beach_access_outlined, accent: Accent.rose, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(nested(r, 'leave_type').isEmpty ? '—' : nested(r, 'leave_type'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                      const SizedBox(height: 2),
                      Text('${fmtDate(parseDate(r['start_date']))} - ${fmtDate(parseDate(r['end_date']))} · ${str(r['days_count'])} days',
                          style: TextStyle(fontSize: 12, color: p.label)),
                      if (str(r['reason']).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(str(r['reason']), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
                      ],
                    ]),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(humanize(status), tone: status.toUpperCase() == 'CANCELLED' ? MarketTone.neutral : toneForStatus(status)),
                ]),
              );
            }),
          ),
        ),
    ]);
  }
}
