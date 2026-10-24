import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'hr_extras.dart';

// HR calendar — port of desktop Calender.tsx: workplace calendar_events,
// approved leave_requests and employee_off_days on one swipeable month grid
// with a day agenda. New entries go to calendar_events (everyone) or
// employee_off_days (one employee / a whole department), with a weekday
// quick-select for a month or a whole year.

const _leaveColor = Color(0xFFD20A0A);
const _holidayColor = Color(0xFFE76500);
const _weekendColor = Color(0xFF8B47D7);
const _offdayColor = Color(0xFF5B738B);
const _typeColors = <String, Color>{
  'leave': _leaveColor,
  'holiday': _holidayColor,
  'weekend': _weekendColor,
  'offday': _offdayColor,
  'event': Color(0xFF0070F2),
  'reminder': Color(0xFF30914C),
};

String _offDayTypeFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('weekend')) return 'WEEKEND';
  if (n.contains('holiday')) return 'HOLIDAY';
  if (n.contains('compensat')) return 'COMPENSATORY';
  return 'OFFDAY';
}

Color _typeColor(Map? t) {
  if (t == null) return _typeColors['event']!;
  return hexColor(str(t['color'])) ?? colorForEventType(toInt(t['id']));
}

class _Ev {
  final Object id;
  final String kind; // event | leave | offday
  final String title;
  final String type;
  final DateTime start;
  final DateTime end;
  final Color color;
  final String? description;
  final Map<String, dynamic> raw;
  _Ev({required this.id, required this.kind, required this.title, required this.type, required this.start, required this.end, required this.color, this.description, required this.raw});

  bool covers(DateTime d) => !d.isBefore(start) && !d.isAfter(end);
}

class HrCalendarPage extends StatefulWidget {
  const HrCalendarPage({super.key});

  @override
  State<HrCalendarPage> createState() => _HrCalendarPageState();
}

class _HrCalendarPageState extends State<HrCalendarPage> {
  final _client = ApiClient();
  final _calKey = GlobalKey<SwipeCalendarState>();
  bool _loading = true;
  String? _error;
  List<_Ev> _events = [];
  Map<DateTime, List<_Ev>> _byDay = {};
  List<Map<String, dynamic>> _types = [];
  List<Map<String, dynamic>> _emps = [];
  List<Map<String, dynamic>> _depts = [];
  DateTime _selected = dayOnly(DateTime.now());
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _events.isEmpty;
      _error = null;
    });
    try {
      final d = await batchLoad(_client, {
        'types': 'event_types?\$select=id,name,is_off,color&\$filter=is_active eq true&\$top=200',
        'emps': 'employees?\$select=id,first_name,last_name&\$filter=is_active eq true&\$top=1000',
        'depts': 'departments?\$select=id,name&\$top=500',
        'cal': 'calendar_events?\$expand=event_type(\$select=id,name,is_off,color)&\$top=2000',
        'leave': "leave_requests?\$filter=status eq 'APPROVED'&\$expand=employee(\$select=first_name,last_name),leave_type(\$select=name)&\$top=2000",
        'off': 'employee_off_days?\$filter=is_active eq true&\$expand=employee(\$select=first_name,last_name)&\$top=2000',
      });
      final evs = <_Ev>[];
      for (final e in d['cal'] ?? <Map<String, dynamic>>[]) {
        final s = apiDay(e['date']);
        if (s == null) continue;
        final et = e['event_type'] is Map ? e['event_type'] as Map : null;
        final type = str(e['type']).isEmpty ? 'event' : str(e['type']);
        evs.add(_Ev(
          id: e['id'],
          kind: 'event',
          title: str(e['title']),
          type: type,
          start: s,
          end: apiDay(e['end_date']) ?? s,
          color: et != null ? _typeColor(et) : (_typeColors[type] ?? _typeColors['event']!),
          description: str(e['description']).isEmpty ? null : str(e['description']),
          raw: e,
        ));
      }
      for (final l in d['leave'] ?? <Map<String, dynamic>>[]) {
        final s = apiDay(l['start_date']);
        if (s == null) continue;
        final name = empName(l['employee']);
        evs.add(_Ev(
          id: 'leave-${l['id']}',
          kind: 'leave',
          title: '${name.isEmpty ? 'Employee' : name} — ${nested(l, 'leave_type').isEmpty ? 'Leave' : nested(l, 'leave_type')}',
          type: 'leave',
          start: s,
          end: apiDay(l['end_date']) ?? s,
          color: _leaveColor,
          description: htmlToText(str(l['reason'])).isEmpty ? null : htmlToText(str(l['reason'])),
          raw: l,
        ));
      }
      for (final o in d['off'] ?? <Map<String, dynamic>>[]) {
        final s = apiDay(o['date']);
        if (s == null) continue;
        final name = empName(o['employee']);
        final t = str(o['type']);
        evs.add(_Ev(
          id: 'offday-${o['id']}',
          kind: 'offday',
          title: '${name.isEmpty ? 'Employee' : name} — ${humanize(t)}${str(o['note']).isNotEmpty ? ' (${o['note']})' : ''}',
          type: t == 'HOLIDAY' ? 'holiday' : (t == 'WEEKEND' ? 'weekend' : 'offday'),
          start: s,
          end: s,
          color: t == 'HOLIDAY' ? _holidayColor : (t == 'WEEKEND' ? _weekendColor : _offdayColor),
          description: str(o['note']).isEmpty ? null : str(o['note']),
          raw: o,
        ));
      }
      if (!mounted) return;
      setState(() {
        _types = d['types'] ?? [];
        _emps = d['emps'] ?? [];
        _depts = d['depts'] ?? [];
        _events = evs;
        _reindex();
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load the calendar'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _pass(_Ev e) => _filter == 'all' || e.kind == _filter;

  void _reindex() {
    final map = <DateTime, List<_Ev>>{};
    for (final e in _events.where(_pass)) {
      var d = e.start;
      var guard = 0;
      while (!d.isAfter(e.end) && guard < 370) {
        (map[d] ??= []).add(e);
        d = DateTime(d.year, d.month, d.day + 1);
        guard++;
      }
    }
    _byDay = map;
  }

  List<Color> _dots(DateTime d) {
    final list = _byDay[d];
    if (list == null) return const [];
    final seen = <int>{};
    return [for (final e in list) if (seen.add(e.color.toARGB32())) e.color];
  }

  int _monthCount(String kind) {
    final a = DateTime(_month.year, _month.month, 1);
    final b = DateTime(_month.year, _month.month + 1, 0);
    return _events.where((e) => e.kind == kind && !e.end.isBefore(a) && !e.start.isAfter(b)).length;
  }

  Future<void> _add() async {
    final ok = await showMotionSheet<bool>(context, (_) => _AddEventSheet(date: _selected, types: _types, emps: _emps, depts: _depts));
    if (ok == true) {
      if (mounted) marketToast(context, 'Saved to the calendar');
      _load();
    }
  }

  Future<bool> _delete(_Ev e) async {
    if (e.kind != 'event') return false;
    final ok = await confirmMarket(context, title: 'Delete this event?', message: '"${e.title}" will be removed from the calendar.');
    if (!ok) return false;
    try {
      await _client.delete('calendar_events', e.id);
      if (mounted) {
        setState(() {
          _events.removeWhere((x) => x.kind == 'event' && x.id == e.id);
          _reindex();
        });
        marketToast(context, 'Event deleted');
      }
      return true;
    } catch (err) {
      if (mounted) marketToast(context, errorMessage(err, 'Could not delete'), error: true);
      return false;
    }
  }

  Future<void> _open(_Ev e) async {
    final res = await showMotionSheet<String>(context, (_) => _EventDetailSheet(ev: e));
    if (!mounted || res == null) return;
    if (res == 'delete') {
      await _delete(e);
    } else if (res == 'edit') {
      final ok = await showMotionSheet<bool>(context, (_) => _EditEventSheet(ev: e, types: _types));
      if (ok == true) {
        if (mounted) marketToast(context, 'Event updated');
        _load();
      }
    }
  }

  void _today() {
    final t = dayOnly(DateTime.now());
    setState(() => _selected = t);
    _calKey.currentState?.jumpTo(DateTime(t.year, t.month));
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final dayEvents = _byDay[_selected] ?? const <_Ev>[];
    return MotionScaffold(
      title: 'HR calendar',
      subtitle: 'Events, holidays, leaves and off days',
      icon: Icons.calendar_month_rounded,
      accent: Accent.ocean,
      onRefresh: _load,
      onFab: _add,
      fabLabel: 'Add event',
      actions: [IconButton(tooltip: 'Today', icon: const Icon(Icons.today_rounded), onPressed: _today)],
      slivers: [
        if (!_loading && _error == null)
          SliverPadding(
            padding: const EdgeInsets.only(top: 16),
            sliver: SliverToBoxAdapter(
              child: KpiGrid(children: [
                KpiTile(icon: Icons.celebration_rounded, label: 'Events this month', value: _monthCount('event'), tone: MarketTone.brand),
                KpiTile(icon: Icons.flight_takeoff_rounded, label: 'Leaves this month', value: _monthCount('leave'), tone: MarketTone.info),
                KpiTile(icon: Icons.weekend_rounded, label: 'Off days this month', value: _monthCount('offday'), tone: MarketTone.brand),
              ]),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _filter,
              options: [
                (id: 'all', label: 'All', count: null),
                (id: 'event', label: 'Events', count: null),
                (id: 'leave', label: 'Leaves', count: null),
                (id: 'offday', label: 'Off days', count: null),
              ],
              onChanged: (v) => setState(() {
                _filter = v;
                _reindex();
              }),
            ),
          ),
        ),
        if (_loading)
          sliverBox(const SkeletonBox(height: 340, radius: 12))
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else ...[
          sliverBox(
            FadeSlideIn(
              child: GlowCard(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                child: SwipeCalendar(
                  key: _calKey,
                  initialMonth: _month,
                  onMonthChanged: (m) => setState(() => _month = m),
                  isSelected: (d) => d == _selected,
                  onTap: (d) => setState(() => _selected = d),
                  dotsFor: _dots,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(top: 12),
            sliver: SliverToBoxAdapter(
              child: SizedBox(
                height: 30,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final t in _types) _legend(p, _typeColor(t), str(t['name'])),
                    _legend(p, _leaveColor, 'Approved leave'),
                    _legend(p, _weekendColor, 'Weekend'),
                    _legend(p, _offdayColor, 'Off day'),
                  ],
                ),
              ),
            ),
          ),
          sliverBox(
            SectionHeader(
              DateFormat('EEEE, d MMMM').format(_selected),
              subtitle: dayEvents.isEmpty ? 'Nothing scheduled' : '${dayEvents.length} ${dayEvents.length == 1 ? 'entry' : 'entries'}',
              trailing: TextButton.icon(onPressed: _add, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add')),
            ),
          ),
          if (dayEvents.isEmpty)
            sliverBox(
              FadeSlideIn(
                key: ValueKey(_selected),
                child: GlowCard(
                  onTap: _add,
                  child: Row(children: [
                    AccentIcon(Icons.event_available_rounded, accent: Accent.ocean, size: 40),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Free day. Tap to add an event or off day.', style: TextStyle(fontSize: 13, color: p.label))),
                  ]),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            )
          else
            KeyedSubtree(
              key: ValueKey('agenda-$_selected-$_filter'),
              child: sliverStagger(
                count: dayEvents.length,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                builder: (_, i) {
                  final e = dayEvents[i];
                  return MotionTile(
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: e.color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(13)),
                      child: Icon(
                        e.kind == 'leave' ? Icons.flight_takeoff_rounded : (e.kind == 'offday' ? Icons.weekend_rounded : Icons.event_rounded),
                        color: e.color,
                        size: 21,
                      ),
                    ),
                    title: e.title,
                    subtitle: e.description,
                    meta: e.start == e.end ? fmtDay(e.start) : '${fmtDay(e.start)} – ${fmtDay(e.end)}',
                    trailing: StatusPill(e.kind == 'event' ? humanize(e.type) : (e.kind == 'leave' ? 'Leave' : humanize(e.type)), tone: MarketTone.brand),
                    onTap: () => _open(e),
                    onDelete: e.kind == 'event' ? () => _delete(e) : null,
                  );
                },
              ),
            ),
        ],
      ],
    );
  }

  Widget _legend(MarketPalette p, Color c, String label) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(15), border: Border.all(color: p.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11.5, color: p.text)),
          ]),
        ),
      );
}

// ── Event detail ────────────────────────────────────────────────────────

class _EventDetailSheet extends StatelessWidget {
  final _Ev ev;
  const _EventDetailSheet({required this.ev});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final et = ev.raw['event_type'] is Map ? ev.raw['event_type'] as Map : null;
    return SafeArea(
      top: false,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FadeSlideIn(
              child: Row(children: [
                Container(width: 6, height: 44, decoration: BoxDecoration(color: ev.color, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 12),
                Expanded(child: Text(ev.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text))),
              ]),
            ),
            const SizedBox(height: 12),
            FadeSlideIn(
              index: 1,
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                StatusPill(humanize(ev.type), tone: MarketTone.brand),
                if (et != null) StatusPill(str(et['name']), tone: MarketTone.neutral),
                if (et != null && asBool(et['is_off'])) const StatusPill('Off day', tone: MarketTone.warn),
              ]),
            ),
            const SizedBox(height: 12),
            FadeSlideIn(index: 2, child: InfoRow('Date', ev.start == ev.end ? fmtDay(ev.start) : '${fmtDay(ev.start)} – ${fmtDay(ev.end)}')),
            if (ev.description != null)
              FadeSlideIn(
                index: 3,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(ev.description!, style: TextStyle(fontSize: 13.5, height: 1.5, color: p.text)),
                ),
              ),
            if (ev.kind != 'event')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  ev.kind == 'leave' ? 'Approved leave — managed via leave requests.' : 'Official off day — managed via employee off days.',
                  style: TextStyle(fontSize: 12, color: p.label, fontStyle: FontStyle.italic),
                ),
              ),
            if (ev.kind == 'event') ...[
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.error,
                      side: BorderSide(color: p.error.withValues(alpha: 0.5)),
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context, 'delete'),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: GradientButton(label: 'Edit', icon: Icons.edit_outlined, accent: Accent.ocean, onTap: () => Navigator.pop(context, 'edit'))),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ── Edit a calendar event ───────────────────────────────────────────────

class _EditEventSheet extends StatefulWidget {
  final _Ev ev;
  final List<Map<String, dynamic>> types;
  const _EditEventSheet({required this.ev, required this.types});

  @override
  State<_EditEventSheet> createState() => _EditEventSheetState();
}

class _EditEventSheetState extends State<_EditEventSheet> {
  late Object? _type = widget.ev.raw['event_type_id'];
  late DateTime? _date = widget.ev.start;
  late DateTime? _end = widget.ev.end == widget.ev.start ? null : widget.ev.end;
  late final _title = TextEditingController(text: widget.ev.title);
  late final _desc = TextEditingController(text: widget.ev.description ?? '');
  late bool _active = asBool(widget.ev.raw['is_active'], fallback: true);
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_date == null || _title.text.trim().isEmpty) {
      marketToast(context, 'Title and date are required', error: true);
      return;
    }
    if (_end != null && _end!.isBefore(_date!)) {
      marketToast(context, 'End date must be after the start date', error: true);
      return;
    }
    final t = widget.types.where((x) => x['id'].toString() == _type?.toString()).firstOrNull;
    setState(() => _busy = true);
    try {
      await ApiClient().put('calendar_events', widget.ev.id, {
        'title': _title.text.trim(),
        'date': isoDay(_date!),
        'end_date': _end == null ? null : isoDay(_end!),
        'type': t == null ? str(widget.ev.raw['type']).isEmpty ? 'event' : widget.ev.raw['type'] : (asBool(t['is_off']) ? 'holiday' : 'event'),
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'event_type_id': _type,
        'is_active': _active,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(e, 'Could not save'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => FormSheet(
        title: 'Edit event',
        busy: _busy,
        onSubmit: _save,
        submitLabel: 'Save changes',
        children: [
          FormLabel(
            label: 'Event type',
            child: PickerField(
              value: _type,
              hint: 'Select event type',
              icon: Icons.category_outlined,
              options: [for (final t in widget.types) PickOption(t['id'], str(t['name']), sub: asBool(t['is_off']) ? 'Off day' : null)],
              onChanged: (v) {
                final t = widget.types.where((x) => x['id'].toString() == v?.toString()).firstOrNull;
                setState(() {
                  _type = v;
                  if (t != null) _title.text = str(t['name']);
                });
              },
            ),
          ),
          FormLabel(label: 'Title', required: true, child: TextField(controller: _title, decoration: motionInput(context, icon: Icons.title_rounded))),
          FormLabel(label: 'Date', required: true, child: DatePickField(value: _date, onChanged: (d) => setState(() => _date = d))),
          FormLabel(label: 'End date', help: 'Optional, for multi-day events', child: DatePickField(value: _end, hint: 'Same day', onChanged: (d) => setState(() => _end = d))),
          FormLabel(label: 'Description', child: TextField(controller: _desc, minLines: 3, maxLines: 5, decoration: motionInput(context, hint: 'Optional description'))),
          SwitchField(label: 'Active', value: _active, onChanged: (v) => setState(() => _active = v)),
        ],
      );
}

// ── Add events / off days ───────────────────────────────────────────────

class _AddEventSheet extends StatefulWidget {
  final DateTime date;
  final List<Map<String, dynamic>> types;
  final List<Map<String, dynamic>> emps;
  final List<Map<String, dynamic>> depts;
  const _AddEventSheet({required this.date, required this.types, required this.emps, required this.depts});

  @override
  State<_AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<_AddEventSheet> {
  final _client = ApiClient();
  final _desc = TextEditingController();
  String _applyTo = 'all';
  Object? _emp;
  Object? _dept;
  Object? _type;
  Object? _offType;
  late final Set<DateTime> _dates = {dayOnly(widget.date)};
  String _quickMode = 'month';
  late int _quickYear = widget.date.year;
  late int _quickMonth = widget.date.month;
  final Set<int> _dows = {};
  bool _busy = false;

  List<Map<String, dynamic>> get _offTypes => widget.types.where((t) => asBool(t['is_off'])).toList();

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  void _applyQuick() {
    if (_dows.isEmpty) return;
    final start = _quickMode == 'month' ? DateTime(_quickYear, _quickMonth, 1) : DateTime(_quickYear, 1, 1);
    final end = _quickMode == 'month' ? DateTime(_quickYear, _quickMonth + 1, 0) : DateTime(_quickYear, 12, 31);
    var added = 0;
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
      if (_dows.contains(d.weekday % 7) && _dates.add(d)) added++;
    }
    setState(() {});
    marketToast(context, '$added ${added == 1 ? 'day' : 'days'} added');
  }

  bool get _valid {
    if (_dates.isEmpty) return false;
    if (_applyTo == 'employee' && _emp == null) return false;
    if (_applyTo == 'department' && _dept == null) return false;
    if (_applyTo == 'all' && _type == null) return false;
    if (_applyTo != 'all' && _offType == null) return false;
    return true;
  }

  Future<void> _save() async {
    if (!_valid) {
      marketToast(context, 'Fill in the required fields and pick at least one date', error: true);
      return;
    }
    setState(() => _busy = true);
    final dates = _dates.toList()..sort();
    final desc = _desc.text.trim();
    try {
      final reqs = <BatchRequest>[];
      if (_applyTo == 'all') {
        final t = widget.types.firstWhere((x) => x['id'].toString() == _type.toString());
        for (var i = 0; i < dates.length; i++) {
          reqs.add(BatchRequest(id: '$i', method: 'POST', url: 'calendar_events', body: {
            'title': str(t['name']),
            'date': isoDay(dates[i]),
            'end_date': null,
            'type': asBool(t['is_off']) ? 'holiday' : 'event',
            'description': desc.isEmpty ? null : desc,
            'event_type_id': t['id'],
          }));
        }
      } else {
        List<dynamic> ids;
        if (_applyTo == 'employee') {
          ids = [_emp];
        } else {
          final res = await _client.get('employees?\$filter=department_id eq $_dept and is_active eq true&\$select=id&\$top=1000');
          ids = unwrapList(res).whereType<Map>().map((e) => e['id']).toList();
          if (ids.isEmpty) {
            if (mounted) {
              setState(() => _busy = false);
              marketToast(context, 'No active employees in this department', error: true);
            }
            return;
          }
        }
        final offName = str(_offTypes.firstWhere((t) => t['id'].toString() == _offType.toString())['name']);
        final offDayType = _offDayTypeFor(offName);
        for (var ei = 0; ei < ids.length; ei++) {
          for (var di = 0; di < dates.length; di++) {
            reqs.add(BatchRequest(id: '$ei-$di', method: 'POST', url: 'employee_off_days', body: {
              'employee_id': ids[ei],
              'date': isoDay(dates[di]),
              'type': offDayType,
              'note': desc.isEmpty ? offName : desc,
            }));
          }
        }
      }
      final res = reqs.isEmpty ? null : await _client.batch(reqs);
      final failed = res is Map && res['responses'] is List
          ? (res['responses'] as List).whereType<Map>().where((r) => toInt(r['status']) >= 400).length
          : 0;
      if (!mounted) return;
      if (failed > 0 && failed == reqs.length) {
        setState(() => _busy = false);
        marketToast(context, 'Failed to save — please try again', error: true);
        return;
      }
      if (failed > 0) marketToast(context, '$failed of ${reqs.length} entries could not be saved', error: true);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(e, 'Failed to save — please try again'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final now = DateTime.now();
    final sel = _type == null ? null : widget.types.where((t) => t['id'].toString() == _type.toString()).firstOrNull;
    return FormSheet(
      title: 'New event',
      subtitle: '${_dates.length} ${_dates.length == 1 ? 'day' : 'days'} selected',
      busy: _busy,
      onSubmit: _save,
      submitLabel: 'Save event',
      children: [
        FormLabel(
          label: 'Applies to',
          child: MarketSegmented<String>(
            value: _applyTo,
            options: const [(id: 'all', label: 'Everyone', count: null), (id: 'employee', label: 'Employee', count: null), (id: 'department', label: 'Department', count: null)],
            onChanged: (v) => setState(() => _applyTo = v),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_applyTo == 'employee')
              FormLabel(
                label: 'Employee',
                required: true,
                child: PickerField(
                  value: _emp,
                  hint: 'Select employee',
                  icon: Icons.person_outline_rounded,
                  options: [for (final e in widget.emps) PickOption(e['id'], empName(e))],
                  onChanged: (v) => setState(() => _emp = v),
                ),
              ),
            if (_applyTo == 'department')
              FormLabel(
                label: 'Department',
                required: true,
                help: 'Every employee in this department gets the selected days off.',
                child: PickerField(
                  value: _dept,
                  hint: 'Select department',
                  icon: Icons.apartment_rounded,
                  options: [for (final d in widget.depts) PickOption(d['id'], str(d['name']))],
                  onChanged: (v) => setState(() => _dept = v),
                ),
              ),
            if (_applyTo == 'all')
              FormLabel(
                label: 'Event type',
                required: true,
                help: sel != null && asBool(sel['is_off']) ? 'This event type marks the day as off. It is also used as the title.' : 'Also used as the event title.',
                child: PickerField(
                  value: _type,
                  hint: 'Select event type',
                  icon: Icons.category_outlined,
                  options: [for (final t in widget.types) PickOption(t['id'], str(t['name']), sub: asBool(t['is_off']) ? 'Off day' : null)],
                  onChanged: (v) => setState(() => _type = v),
                ),
              )
            else
              FormLabel(
                label: 'Off day type',
                required: true,
                help: _offTypes.isEmpty ? 'Add an event type with "off day" enabled first.' : null,
                child: PickerField(
                  value: _offType,
                  hint: _offTypes.isEmpty ? 'No off day event types configured' : 'Select off day type',
                  icon: Icons.weekend_outlined,
                  options: [for (final t in _offTypes) PickOption(t['id'], str(t['name']))],
                  onChanged: (v) => setState(() => _offType = v),
                ),
              ),
          ]),
        ),
        FormLabel(label: 'Description', child: TextField(controller: _desc, minLines: 2, maxLines: 4, decoration: motionInput(context, hint: 'Optional description'))),
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: p.brand),
              const SizedBox(width: 6),
              Text('Quick select', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
              const Spacer(),
              MarketSegmented<String>(
                value: _quickMode,
                options: const [(id: 'month', label: 'Month', count: null), (id: 'year', label: 'Year', count: null)],
                onChanged: (v) => setState(() => _quickMode = v),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              if (_quickMode == 'month') ...[
                Expanded(
                  child: PickerField(
                    value: _quickMonth,
                    allowClear: false,
                    hint: 'Month',
                    options: [for (var m = 1; m <= 12; m++) PickOption(m, DateFormat('MMMM').format(DateTime(2000, m)))],
                    onChanged: (v) => setState(() => _quickMonth = toInt(v)),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: PickerField(
                  value: _quickYear,
                  allowClear: false,
                  hint: 'Year',
                  options: [for (var y = now.year - 2; y < now.year + 6; y++) PickOption(y, '$y')],
                  onChanged: (v) => setState(() => _quickYear = toInt(v)),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            ToggleChips<int>(
              options: const [(0, 'Sun'), (1, 'Mon'), (2, 'Tue'), (3, 'Wed'), (4, 'Thu'), (5, 'Fri'), (6, 'Sat')],
              isOn: _dows.contains,
              onTap: (d) => setState(() => _dows.contains(d) ? _dows.remove(d) : _dows.add(d)),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _dows.isEmpty ? null : _applyQuick,
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: Text('Apply to ${_quickMode == 'month' ? DateFormat('MMMM').format(DateTime(2000, _quickMonth)) : '$_quickYear'}'),
            ),
          ]),
        ),
        FormLabel(
          label: 'Dates',
          required: true,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              SwipeCalendar(
                initialMonth: widget.date,
                cellHeight: 42,
                isSelected: _dates.contains,
                onTap: (d) => setState(() => _dates.contains(d) ? _dates.remove(d) : _dates.add(d)),
              ),
              Row(children: [
                Expanded(child: Text(_dates.isEmpty ? 'No days selected' : rangeText(_dates.toList()), style: TextStyle(fontSize: 12, color: p.label))),
                if (_dates.isNotEmpty) TextButton(onPressed: () => setState(_dates.clear), child: const Text('Clear')),
              ]),
            ]),
          ),
        ),
      ],
    );
  }
}
