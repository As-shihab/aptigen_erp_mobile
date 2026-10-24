import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'dash_common.dart';
import 'hr_charts.dart';

const _statusLabel = {'present': 'Present', 'absent': 'Absent', 'leave': 'On leave', 'off': 'Day off', 'upcoming': 'Upcoming'};
const _statusColor = {
  'present': Color(0xFF30914C),
  'absent': Color(0xFFD20A0A),
  'leave': Color(0xFFE76500),
  'off': Color(0xFF5B738B),
  'upcoming': Color(0xFF5D36FF),
};

class _CalEvent {
  final String title;
  final String? description;
  final DateTime start;
  final DateTime end;
  final Color color;
  final IconData icon;
  const _CalEvent(this.title, this.description, this.start, this.end, this.color, this.icon);

  bool covers(DateTime d) => !d.isBefore(start) && !d.isAfter(end);
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Ported from desktop tabs/MyCalendarTab.tsx — a read-only month calendar
/// combining the employee's roster (only when the workplace uses shifts
/// and rosters) with workplace calendar events, coloured by event type.
class MyCalendarTab extends DashSection {
  const MyCalendarTab({super.key, required super.employeeId, super.refreshToken});

  @override
  State<MyCalendarTab> createState() => _MyCalendarTabState();
}

class _MyCalendarTabState extends State<MyCalendarTab> with DashLoader<MyCalendarTab> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = _day(DateTime.now());
  bool _showSchedule = true;
  List<Map<String, dynamic>> _roster = [];
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _eventTypes = [];
  bool _rosterLoading = false;

  @override
  Future<void> fetch() async {
    final refs = await service.getCalendarRefs();
    final s = refs['settings']!.isEmpty ? const <String, dynamic>{} : refs['settings']!.first;
    final show = asBool(s['has_roster'], fallback: true) && asBool(s['has_shift'], fallback: true);
    if (!mounted) return;
    setState(() {
      _events = refs['events']!;
      _eventTypes = refs['eventTypes']!;
      _showSchedule = show;
    });
    await _loadRoster();
  }

  Future<void> _loadRoster() async {
    if (!_showSchedule) {
      setState(() => _roster = []);
      return;
    }
    setState(() => _rosterLoading = true);
    try {
      final rows = await service.getRoster(DateTime(_month.year, _month.month - 1, 1), DateTime(_month.year, _month.month + 2, 0));
      if (mounted) setState(() => _roster = rows);
    } catch (_) {
      if (mounted) setState(() => _roster = []);
    } finally {
      if (mounted) setState(() => _rosterLoading = false);
    }
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _loadRoster();
  }

  List<_CalEvent> get _all {
    final out = <_CalEvent>[];
    if (_showSchedule) {
      for (final r in _roster) {
        final d = parseDate(r['date']);
        if (d == null) continue;
        final status = '${r['status'] ?? ''}';
        final label = _statusLabel[status] ?? humanize(status);
        final isOff = status == 'off' || status == 'leave';
        final color = (status == 'present' || status == 'upcoming') && r['color'] != null ? hexColor(r['color'], _statusColor[status]!) : (_statusColor[status] ?? const Color(0xFF5B738B));
        out.add(_CalEvent(
          isOff ? label : '${r['shift'] ?? 'Shift'}',
          isOff ? null : '${r['time'] ?? ''} · $label',
          _day(d),
          _day(d),
          color,
          status == 'leave' ? Icons.flight_takeoff_rounded : (status == 'off' ? Icons.weekend_rounded : Icons.schedule_rounded),
        ));
      }
    }
    for (final e in _events) {
      final d = parseDate(e['date']);
      if (d == null) continue;
      final end = parseDate(e['end_date']);
      final typeId = e['event_type_id'];
      out.add(_CalEvent(
        '${e['title'] ?? 'Event'}',
        (e['description'] ?? '').toString().trim().isEmpty ? null : stripHtml('${e['description']}'),
        _day(d.toLocal()),
        _day((end ?? d).toLocal()),
        typeId != null ? chartColorAt(asInt(typeId)) : (e['type'] == 'holiday' ? const Color(0xFFD20A0A) : const Color(0xFF168EFF)),
        e['type'] == 'holiday' ? Icons.celebration_rounded : Icons.event_rounded,
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final state = stateSliver(skeletons: 2, height: 220);
    if (state != null) return state;
    final p = MarketPalette.of(context);
    final all = _all;
    final dayEvents = all.where((e) => e.covers(_selected)).toList();

    final first = DateTime(_month.year, _month.month, 1);
    final lead = first.weekday % 7; // Sunday-first grid
    final daysIn = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = ((lead + daysIn) / 7).ceil() * 7;
    final today = _day(DateTime.now());

    return SliverMainAxisGroup(slivers: [
      sliverBox(GlowCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
        child: Column(children: [
          Row(children: [
            IconButton(onPressed: () => _shiftMonth(-1), icon: Icon(Icons.chevron_left_rounded, color: p.text)),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(DateFormat('MMMM yyyy').format(_month),
                    key: ValueKey(_month), textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
              ),
            ),
            if (_rosterLoading) SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.brand)),
            IconButton(onPressed: () => _shiftMonth(1), icon: Icon(Icons.chevron_right_rounded, color: p.text)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            for (final d in const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'])
              Expanded(child: Center(child: Text(d, style: TextStyle(fontSize: 11, color: p.label, fontWeight: FontWeight.w600)))),
          ]),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), child: c)),
            child: GridView.builder(
              key: ValueKey(_month),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 0.82),
              itemCount: cells,
              itemBuilder: (_, i) {
                final n = i - lead + 1;
                if (n < 1 || n > daysIn) return const SizedBox.shrink();
                final date = DateTime(_month.year, _month.month, n);
                final evs = all.where((e) => e.covers(date)).toList();
                final sel = date == _selected;
                final isToday = date == today;
                return PressScale(
                  onTap: () => setState(() => _selected = date),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    decoration: BoxDecoration(
                      gradient: sel ? Accent.ocean.gradient : null,
                      color: sel ? null : (evs.isNotEmpty ? evs.first.color.withValues(alpha: 0.08) : Colors.transparent),
                      borderRadius: BorderRadius.circular(12),
                      border: isToday && !sel ? Border.all(color: p.brand, width: 1.5) : null,
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('$n', style: TextStyle(fontSize: 13.5, fontWeight: isToday || sel ? FontWeight.w800 : FontWeight.w600, color: sel ? Colors.white : p.text)),
                      const SizedBox(height: 3),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        for (final e in evs.take(3))
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(color: sel ? Colors.white : e.color, shape: BoxShape.circle),
                          ),
                      ]),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      )),
      if (_eventTypes.isNotEmpty || _showSchedule)
        sliverBox(Wrap(spacing: 12, runSpacing: 6, children: [
          if (_showSchedule)
            for (final s in _statusLabel.entries) _legend(p, _statusColor[s.key]!, s.value),
          for (final t in _eventTypes) _legend(p, chartColorAt(asInt(t['id'])), '${t['name'] ?? ''}'),
        ]), padding: const EdgeInsets.fromLTRB(20, 12, 16, 0)),
      sliverBox(SectionHeader(DateFormat('EEEE, d MMMM').format(_selected), subtitle: dayEvents.isEmpty ? 'Nothing scheduled' : '${dayEvents.length} item${dayEvents.length == 1 ? '' : 's'}')),
      if (dayEvents.isNotEmpty)
        sliverStagger(
          count: dayEvents.length,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          builder: (_, i) {
            final e = dayEvents[i];
            return MotionTile(
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: e.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
                child: Icon(e.icon, color: e.color, size: 21),
              ),
              title: e.title,
              subtitle: e.description,
              meta: e.start == e.end ? null : '${fmtDate(e.start)} to ${fmtDate(e.end)}',
            );
          },
        ),
    ]);
  }

  Widget _legend(MarketPalette p, Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11.5, color: p.label)),
      ]);
}
