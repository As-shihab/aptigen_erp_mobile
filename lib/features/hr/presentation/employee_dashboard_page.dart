import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/network/http_client.dart';
import '../../../core/network/socket_client.dart';
import '../../../shared/ui/motion_kit.dart';
import '../data/employee_dashboard_service.dart';
import 'tabs/asset_tab.dart';
import 'tabs/attendance_tab.dart';
import 'tabs/dash_common.dart';
import 'tabs/employee_request_tab.dart';
import 'tabs/hr_charts.dart';
import 'tabs/my_calendar_tab.dart';
import 'tabs/my_leave_tab.dart';
import 'tabs/notice_tab.dart';
import 'tabs/payroll_tab.dart';
import 'tabs/profile_tab.dart';

enum _Sec { profile, attendance, leave, calendar, requests, payroll, assets, notices }

extension on _Sec {
  String get label => switch (this) {
        _Sec.profile => 'Profile',
        _Sec.attendance => 'Attendance',
        _Sec.leave => 'My leave',
        _Sec.calendar => 'Calendar',
        _Sec.requests => 'Requests',
        _Sec.payroll => 'Payroll',
        _Sec.assets => 'Assets',
        _Sec.notices => 'Notices',
      };
  IconData get icon => switch (this) {
        _Sec.profile => Icons.person_outline_rounded,
        _Sec.attendance => Icons.schedule_rounded,
        _Sec.leave => Icons.flight_takeoff_rounded,
        _Sec.calendar => Icons.calendar_month_rounded,
        _Sec.requests => Icons.fact_check_outlined,
        _Sec.payroll => Icons.account_balance_wallet_outlined,
        _Sec.assets => Icons.laptop_mac_rounded,
        _Sec.notices => Icons.notifications_none_rounded,
      };
}

/// Personal employee dashboard — ported from desktop EmployeeDashboard.tsx
/// and its tabs: brand hero with punch in / out, KPIs, leave balance
/// rings, then one section at a time (profile, attendance, leave, calendar,
/// approvals, payroll, assets, notices) under a pinned section bar.
class EmployeeDashboardPage extends StatefulWidget {
  const EmployeeDashboardPage({super.key});

  @override
  State<EmployeeDashboardPage> createState() => _EmployeeDashboardPageState();
}

class _EmployeeDashboardPageState extends State<EmployeeDashboardPage> {
  final _service = EmployeeDashboardService(ApiClient());
  final _leaveKey = GlobalKey<MyLeaveTabState>();

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _employee = {};
  Map<String, dynamic> _kpi = {};
  List<Map<String, dynamic>> _balances = [];
  _Sec _sec = _Sec.profile;
  int _token = 0;
  bool _punching = false;
  int _unread = 0;
  int _approvals = 0;
  void Function(dynamic)? _listener;

  int get _employeeId => asInt(_employee['id']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    final l = _listener;
    if (l != null) AppSocket.instance?.off('attendance:recorded', l);
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await _service.getMyDashboard();
      if (!mounted) return;
      if (data == null || data['employee'] is! Map) throw ApiException(404, '');
      setState(() {
        _employee = (data['employee'] as Map).cast<String, dynamic>();
        _kpi = Map<String, dynamic>.from((data['kpi'] as Map?) ?? const {});
        _balances = ((data['leaveBalances'] as List?) ?? const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
        _error = null;
      });
      if (_listener == null) _connectRealtime();
      _loadBadges();
    } catch (_) {
      if (mounted && !silent) setState(() => _error = 'No employee record is linked to this account, or the request failed.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Unread notices + approvals waiting on me, for the section badges.
  Future<void> _loadBadges() async {
    final id = _employeeId;
    final dept = int.tryParse('${_employee['department_id'] ?? ''}');
    final des = int.tryParse('${_employee['designation_id'] ?? ''}');
    try {
      final r = await Future.wait([
        countUnreadNotices(_service, employeeId: id, departmentId: dept),
        _service.getPendingApprovals(employeeId: id, designationId: des).then((v) => v.pending.length),
      ]);
      if (mounted) {
        setState(() {
          _unread = r[0];
          _approvals = r[1];
        });
      }
    } catch (_) {
      // Badges are optional.
    }
  }

  Future<void> _refresh() async {
    await _load(silent: true);
    if (mounted) setState(() => _token++);
  }

  Future<void> _connectRealtime() async {
    try {
      final ctx = await resolveSocketContext(ApiClient());
      if (ctx == null || !mounted) return;
      final socket = AppSocket.connect(ctx);
      void listener(dynamic payload) {
        if (payload is! Map || asInt(payload['employee_id']) != _employeeId || !mounted) return;
        setState(() {
          _kpi['checkIn'] = payload['check_in_time'];
          _kpi['checkOut'] = payload['check_out_time'];
        });
      }

      _listener = listener;
      socket.on('attendance:recorded', listener);
    } catch (_) {
      // Live updates are optional.
    }
  }

  Future<void> _punch() async {
    final checkingOut = _kpi['checkIn'] != null && _kpi['checkOut'] == null;
    if (checkingOut) {
      final ok = await confirmMarket(context, title: 'Punch out now?', message: 'This closes your attendance for today.', confirm: 'Punch out', destructive: false);
      if (!ok) return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _punching = true);
    try {
      final res = await _service.punchAttendance();
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _kpi['checkIn'] = res['checkInTime'] ?? _kpi['checkIn'];
        _kpi['checkOut'] = res['checkOutTime'];
      });
      marketToast(context, res['action'] == 'check-in' ? 'Punched in. Have a great day' : 'Punched out. See you tomorrow');
      if (_sec == _Sec.attendance || _sec == _Sec.profile) setState(() => _token++);
    } catch (e) {
      HapticFeedback.vibrate();
      if (mounted) marketToast(context, errorMessage(e, 'Could not record attendance'), error: true);
    } finally {
      if (mounted) setState(() => _punching = false);
    }
  }

  void _select(_Sec s) {
    if (s == _sec) return;
    setState(() => _sec = s);
  }

  @override
  Widget build(BuildContext context) {
    final first = '${_employee['first_name'] ?? ''}'.trim();
    return MotionScaffold(
      title: 'My dashboard',
      subtitle: first.isEmpty ? 'Your day at a glance' : 'Hello $first, here is your day at a glance',
      icon: Icons.badge_outlined,
      accent: Accent.ocean,
      expandedHeight: 130,
      onRefresh: _loading || _error != null ? null : _refresh,
      fabLabel: 'Apply leave',
      fabIcon: Icons.flight_takeoff_rounded,
      onFab: !_loading && _error == null && _sec == _Sec.leave ? () => _leaveKey.currentState?.openApply() : null,
      slivers: _loading
          ? [
              sliverBox(const SkeletonBox(height: 300, radius: 12)),
              sliverBox(const SkeletonBox(height: 110, radius: 12)),
              sliverSkeleton(count: 3),
            ]
          : _error != null
              ? [sliverEmpty(icon: Icons.person_off_outlined, title: "Couldn't load your dashboard", message: _error, actionLabel: 'Retry', onAction: _load)]
              : _content(),
    );
  }

  List<Widget> _content() {
    final p = MarketPalette.of(context);
    final leaveLeft = _balances.fold<double>(0, (a, b) => a + math.max(0, toDouble(b['total']) - toDouble(b['used'])));
    return [
      sliverBox(FadeSlideIn(child: _Hero(employee: _employee, kpi: _kpi, punching: _punching, onPunch: _punch))),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: KpiGrid(children: [
            KpiTile(icon: Icons.event_available_rounded, label: 'Present this month', value: toInt(_kpi['presentDaysThisMonth']), tone: MarketTone.ok, onTap: () => _select(_Sec.attendance)),
            KpiTile(icon: Icons.beach_access_rounded, label: 'Leave days left', value: leaveLeft, tone: MarketTone.brand, onTap: () => _select(_Sec.leave)),
            KpiTile(icon: Icons.payments_rounded, label: 'Salary', value: toDouble(_kpi['salary']), format: (v) => money(v), tone: MarketTone.brand, onTap: () => _select(_Sec.payroll)),
            KpiTile(icon: Icons.notifications_active_rounded, label: 'Unread notices', value: _unread, tone: MarketTone.info, onTap: () => _select(_Sec.notices)),
          ]),
        ),
      ),
      if (_balances.isNotEmpty) ...[
        sliverBox(SectionHeader('Leave balances', subtitle: '${_balances.fold<double>(0, (a, b) => a + toDouble(b['used'])).round()} of ${_balances.fold<double>(0, (a, b) => a + toDouble(b['total'])).round()} days used')),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 128,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _balances.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final b = _balances[i];
                final used = toDouble(b['used']);
                final total = toDouble(b['total']);
                final color = hexColor(b['color'], chartColorAt(i));
                final done = total > 0 && used >= total;
                return FadeSlideIn(
                  index: i,
                  child: GlowCard(
                    onTap: () => _select(_Sec.leave),
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 92,
                      child: Column(children: [
                        ProgressRing(
                          value: total > 0 ? used / total : 0,
                          size: 58,
                          stroke: 6,
                          color: color,
                          center: done
                              ? Icon(Icons.check_rounded, color: color, size: 22)
                              : CountUp(value: math.max(0, total - used), format: (v) => '${v.round()}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.text)),
                        ),
                        const SizedBox(height: 8),
                        Text('${b['name'] ?? '-'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.text)),
                        Text('${used.round()}/${total.round()} used', style: TextStyle(fontSize: 10.5, color: p.label)),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
      SliverPersistentHeader(
        pinned: true,
        delegate: _SectionBar(
          value: _sec,
          bg: p.bg,
          badges: {_Sec.notices: _unread, _Sec.requests: _approvals},
          onChanged: (s) {
            HapticFeedback.selectionClick();
            _select(s);
          },
        ),
      ),
      KeyedSubtree(key: ValueKey(_sec), child: _section()),
    ];
  }

  Widget _section() {
    final id = _employeeId;
    final dept = int.tryParse('${_employee['department_id'] ?? ''}');
    final des = int.tryParse('${_employee['designation_id'] ?? ''}');
    return switch (_sec) {
      _Sec.profile => ProfileTab(employeeId: id, employee: _employee, kpi: _kpi, refreshToken: _token),
      _Sec.attendance => AttendanceTab(employeeId: id, refreshToken: _token),
      _Sec.leave => MyLeaveTab(key: _leaveKey, employeeId: id, refreshToken: _token),
      _Sec.calendar => MyCalendarTab(employeeId: id, refreshToken: _token),
      _Sec.requests => EmployeeRequestTab(employeeId: id, designationId: des, refreshToken: _token, onCountChanged: (n) => setState(() => _approvals = n)),
      _Sec.payroll => PayrollTab(employeeId: id, refreshToken: _token),
      _Sec.assets => AssetTab(employeeId: id, refreshToken: _token),
      _Sec.notices => NoticeTab(employeeId: id, departmentId: dept, refreshToken: _token, onUnreadChanged: (n) => setState(() => _unread = n)),
    };
  }
}

// ── Hero with punch ─────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  final Map<String, dynamic> employee;
  final Map<String, dynamic> kpi;
  final bool punching;
  final VoidCallback onPunch;
  const _Hero({required this.employee, required this.kpi, required this.punching, required this.onPunch});

  @override
  Widget build(BuildContext context) {
    final name = fullName(employee);
    final designation = (employee['designation'] as Map?)?['name'];
    final department = (employee['department'] as Map?)?['name'];
    final shift = employee['shift'] as Map?;
    final active = asBool(employee['is_active'], fallback: true);
    final photo = '${employee['profile_photo'] ?? ''}';
    final checkIn = parseDate(kpi['checkIn']);
    final checkOut = parseDate(kpi['checkOut']);

    Widget chip(String text, [IconData? icon]) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 13, color: Colors.white), const SizedBox(width: 4)],
            Text(text, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ]),
        );

    return GlowCard(
      gradient: Accent.ocean.gradient,
      radius: 12,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(children: [
        Row(children: [
          Stack(children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2)),
              child: InitialsAvatar(name.isEmpty ? '?' : name, imageUrl: photo.isEmpty ? null : photo, size: 58),
            ),
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? const Color(0xFF30914C) : const Color(0xFF8396A8),
                  border: Border.all(color: Colors.white, width: 2.4),
                ),
              ),
            ),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name.isEmpty ? '-' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
              if (designation != null) Text('$designation', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 13)),
              const SizedBox(height: 4),
              const _Clock(),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            if ('${employee['employee_no'] ?? ''}'.isNotEmpty) chip('${employee['employee_no']}', Icons.tag_rounded),
            if (department != null) chip('$department', Icons.apartment_rounded),
            if (shift != null) chip('${shift['name']} · ${_shiftTime(shift['start_time'])} to ${_shiftTime(shift['end_time'])}', Icons.schedule_rounded),
            if (employee['joining_date'] != null) chip('Joined ${fmtDate(parseDate(employee['joining_date']))}', Icons.celebration_outlined),
          ]),
        ),
        const SizedBox(height: 20),
        _PunchButton(checkIn: checkIn, checkOut: checkOut, busy: punching, onPunch: onPunch),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _timeCell('Punched in', checkIn == null ? '--:--' : fmtTime(checkIn), Icons.login_rounded)),
          Container(width: 1, height: 34, color: Colors.white.withValues(alpha: 0.25)),
          Expanded(child: _timeCell('Punched out', checkOut == null ? '--:--' : fmtTime(checkOut), Icons.logout_rounded)),
        ]),
      ]),
    );
  }

  static String _shiftTime(dynamic v) {
    final s = '${v ?? ''}';
    final parts = s.split(':');
    if (parts.length < 2) return s;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return DateFormat('h:mm a').format(DateTime(2000, 1, 1, h, m));
  }

  Widget _timeCell(String label, String value, IconData icon) => Column(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.8)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11.5)),
        ]),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      ]);
}

/// Live clock line in the hero.
class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late Timer _t;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        '${DateFormat('EEEE, d MMM').format(_now)} · ${DateFormat('h:mm:ss a').format(_now)}',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 11.5, fontFeatures: const [FontFeature.tabularFigures()]),
      );
}

/// Big circular punch button: pulsing rings while it waits for you (or
/// while you're on the clock), live elapsed time since punch in, and a
/// spring press.
class _PunchButton extends StatefulWidget {
  final DateTime? checkIn;
  final DateTime? checkOut;
  final bool busy;
  final VoidCallback onPunch;
  const _PunchButton({required this.checkIn, required this.checkOut, required this.busy, required this.onPunch});

  @override
  State<_PunchButton> createState() => _PunchButtonState();
}

class _PunchButtonState extends State<_PunchButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
  Timer? _tick;
  DateTime _now = DateTime.now();

  bool get _open => widget.checkIn != null && widget.checkOut == null;
  bool get _done => widget.checkIn != null && widget.checkOut != null;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _PunchButton old) {
    super.didUpdateWidget(old);
    _syncTimer();
  }

  void _syncTimer() {
    if (_open && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
    } else if (!_open) {
      _tick?.cancel();
      _tick = null;
    }
    if (_done) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  String _elapsed(Duration d) {
    if (d.isNegative) d = Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = _done
        ? const [Color(0xFF5B738B), Color(0xFF8396A8)]
        : _open
            ? const [Color(0xFFD20A0A), Color(0xFFD20A0A)]
            : const [Color(0xFF30914C), Color(0xFF30914C)];
    final label = _done ? 'Done for today' : (_open ? 'Punch out' : 'Punch in');
    final icon = _done ? Icons.verified_rounded : (_open ? Icons.logout_rounded : Icons.fingerprint_rounded);
    final worked = widget.checkIn == null ? null : ((_done ? widget.checkOut! : _now).difference(widget.checkIn!));
    const size = 148.0;

    return SizedBox(
      width: size + 60,
      height: size + 60,
      child: Stack(alignment: Alignment.center, children: [
        if (!_done)
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, _) => Stack(alignment: Alignment.center, children: [
              for (final offset in const [0.0, 0.5])
                Builder(builder: (_) {
                  final t = (_pulse.value + offset) % 1.0;
                  return Container(
                    width: size + 56 * t,
                    height: size + 56 * t,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.45 * (1 - t)), width: 2)),
                  );
                }),
            ]),
          ),
        PressScale(
          scale: 0.93,
          onTap: widget.busy || _done ? null : widget.onPunch,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.first,
              border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 4),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
              child: widget.busy
                  ? const SizedBox(key: ValueKey('busy'), width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                  : Column(key: ValueKey(label), mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(icon, color: Colors.white, size: 40),
                      const SizedBox(height: 4),
                      Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                      if (worked != null)
                        Text(_elapsed(worked),
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92), fontSize: 13, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
                    ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Pinned section bar ──────────────────────────────────────────────────

class _SectionBar extends SliverPersistentHeaderDelegate {
  final _Sec value;
  final Color bg;
  final Map<_Sec, int> badges;
  final ValueChanged<_Sec> onChanged;
  _SectionBar({required this.value, required this.bg, required this.badges, required this.onChanged});

  @override
  double get minExtent => 62;
  @override
  double get maxExtent => 62;

  @override
  bool shouldRebuild(_SectionBar old) => old.value != value || old.bg != bg || old.badges.toString() != badges.toString();

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final p = MarketPalette.of(context);
    return Container(
      color: bg,
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: overlapsContent ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 4))] : null,
        ),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _Sec.values.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final s = _Sec.values[i];
            final sel = s == value;
            final badge = badges[s] ?? 0;
            return PressScale(
              onTap: () => onChanged(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: sel ? p.brandSoft : p.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sel ? p.brand : p.line),
                ),
                child: Row(children: [
                  Icon(s.icon, size: 17, color: sel ? p.brand : p.label),
                  const SizedBox(width: 6),
                  Text(s.label, style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w600, color: sel ? p.brand : p.text)),
                  if (badge > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: p.error, borderRadius: BorderRadius.circular(10)),
                      child: Text('$badge', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                  ],
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}
