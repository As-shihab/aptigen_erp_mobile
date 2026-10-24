import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'dash_common.dart';

/// Ported from desktop tabs/AttendanceTab.tsx — the employee's last 100
/// attendance logs, plus summary stats and a late / overtime filter.
class AttendanceTab extends DashSection {
  const AttendanceTab({super.key, required super.employeeId, super.refreshToken});

  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> with DashLoader<AttendanceTab> {
  List<Map<String, dynamic>> _rows = [];
  String _filter = 'all';

  @override
  Future<void> fetch() async {
    final rows = await service.getAttendance(widget.employeeId);
    if (mounted) setState(() => _rows = rows);
  }

  Duration? _worked(Map<String, dynamic> r) {
    final a = parseDate(r['check_in_time']);
    final b = parseDate(r['check_out_time']);
    if (a == null || b == null) return null;
    return b.difference(a);
  }

  @override
  Widget build(BuildContext context) {
    final state = stateSliver();
    if (state != null) return state;
    if (_rows.isEmpty) {
      return sliverEmpty(icon: Icons.event_busy_rounded, title: 'No attendance records yet', message: 'Your punches will show up here.');
    }

    final late = _rows.where((r) => asBool(r['has_late'])).length;
    final ot = _rows.where((r) => asBool(r['has_overtime'])).toList();
    final otHours = ot.fold<double>(0, (a, r) => a + toDouble(r['overtime_minutes'])) / 60;
    final worked = _rows.map(_worked).whereType<Duration>().toList();
    final avgMin = worked.isEmpty ? 0 : worked.fold<int>(0, (a, d) => a + d.inMinutes) / worked.length;

    final list = _rows.where((r) {
      switch (_filter) {
        case 'late':
          return asBool(r['has_late']);
        case 'ontime':
          return !asBool(r['has_late']);
        case 'overtime':
          return asBool(r['has_overtime']);
      }
      return true;
    }).toList();

    return SliverMainAxisGroup(slivers: [
      sliverStats([
        MiniStat(icon: Icons.event_available_rounded, label: 'Days recorded', value: _rows.length, tone: MarketTone.ok),
        MiniStat(icon: Icons.alarm_rounded, label: 'Late arrivals', value: late, tone: MarketTone.warn),
        MiniStat(icon: Icons.more_time_rounded, label: 'Overtime hours', value: otHours, format: (v) => v.toStringAsFixed(1), tone: MarketTone.info),
        MiniStat(icon: Icons.timelapse_rounded, label: 'Average worked', value: avgMin, format: (v) => hoursLabel(Duration(minutes: v.round())), tone: MarketTone.brand),
      ]),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: ChipFilter<String>(
            value: _filter,
            onChanged: (v) => setState(() => _filter = v),
            options: [
              (id: 'all', label: 'All', count: _rows.length),
              (id: 'ontime', label: 'On time', count: _rows.length - late),
              (id: 'late', label: 'Late', count: late),
              (id: 'overtime', label: 'Overtime', count: ot.length),
            ],
          ),
        ),
      ),
      if (list.isEmpty)
        sliverEmpty(icon: Icons.filter_alt_off_rounded, title: 'Nothing matches this filter')
      else
        sliverStagger(count: list.length, builder: (_, i) => _AttendanceRow(row: list[i], worked: _worked(list[i]))),
    ]);
  }
}

class _AttendanceRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final Duration? worked;
  const _AttendanceRow({required this.row, this.worked});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final date = parseDate(row['attendance_date']);
    final isLate = asBool(row['has_late']);
    final otMin = toDouble(row['overtime_minutes']);
    final inT = parseDate(row['check_in_time']);
    final outT = parseDate(row['check_out_time']);
    final today = date != null && DateUtils.isSameDay(date.toLocal(), DateTime.now());

    Widget chip(IconData icon, Color c, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: p.text, fontWeight: FontWeight.w600)),
        ]);

    return GlowCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: today ? Accent.ocean.gradient : null,
            color: today ? null : p.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            Text(date == null ? '-' : DateFormat('d').format(date.toLocal()),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: today ? Colors.white : p.text, height: 1.1)),
            Text(date == null ? '' : DateFormat('MMM, E').format(date.toLocal()),
                style: TextStyle(fontSize: 9.5, color: today ? Colors.white.withValues(alpha: 0.9) : p.label)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 12, runSpacing: 6, children: [
              chip(Icons.login_rounded, p.ok, inT == null ? '-' : fmtTime(inT)),
              chip(Icons.logout_rounded, p.error, outT == null ? 'Open' : fmtTime(outT)),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (worked != null) Text('Worked ${hoursLabel(worked!)}', style: TextStyle(fontSize: 11.5, color: p.label)),
              if (asBool(row['has_overtime']) && otMin > 0) StatusPill('Overtime ${(otMin / 60).toStringAsFixed(1)}h', tone: MarketTone.warn),
            ]),
          ]),
        ),
        StatusPill(isLate ? 'Late' : 'Present', tone: isLate ? MarketTone.warn : MarketTone.ok),
      ]),
    );
  }
}
