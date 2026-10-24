import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'roster_form_sheet.dart';
import 'shift_common.dart';

/// Roster management — mirrors erp/desktop hrm/shift/roster/Roster.tsx.
///
/// Day / week view over GET /api/hrm/roster-schedule, a week day strip,
/// month jump, create / edit roster (RosterFormSheet), and shift overrides.
/// Desktop drags an employee onto another shift column; on a phone the same
/// thing is "Move to shift" on the employee row, followed by the same three
/// choices: add as extra, swap with someone, or replace.
class RosterPage extends StatefulWidget {
  const RosterPage({super.key});

  @override
  State<RosterPage> createState() => _RosterPageState();
}

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

const _statusColors = {
  'Regular': Color(0xFF0070F2),
  'SWAP': Color(0xFFD20A0A),
  'EXTRA': Color(0xFF30914C),
  'REPLACEMENT': Color(0xFFE76500),
};

class _Day {
  final String day; // raw API date (yyyy-MM-dd)
  final DateTime date;
  final List<Map<String, dynamic>> shifts;
  const _Day(this.day, this.date, this.shifts);

  bool get hasRoster => shifts.any((s) => s['roster_id'] != null);
}

List<Map<String, dynamic>> _emps(Map<String, dynamic> shift) =>
    (shift['employees'] is List ? shift['employees'] as List : const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();

Map<String, dynamic> _det(Map<String, dynamic> emp) => (emp['employee_details'] is Map ? emp['employee_details'] as Map : const {}).cast<String, dynamic>();

int _countBy(Map<String, dynamic> shift, String type) =>
    type == 'Weekend' ? _emps(shift).where((e) => _det(e)['holiday_status'] == 'Weekend').length : _emps(shift).where((e) => e['status'] == type).length;

DateTime _weekStart(DateTime d) => dayOnly(d).subtract(Duration(days: d.weekday - 1));

class _RosterPageState extends State<RosterPage> {
  final _client = ApiClient();
  String _view = 'day';
  DateTime _current = dayOnly(DateTime.now());
  List<_Day> _schedule = [];
  bool _loading = true;
  String? _error;
  int _seq = 0;
  final Map<String, String> _search = {};
  final Set<String> _expanded = {};

  int get _span => _view == 'week' ? 7 : 1;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final seq = ++_seq;
    setState(() {
      _loading = _schedule.isEmpty;
      _error = null;
    });
    final start = ymd(_current);
    final end = ymd(_current.add(Duration(days: _span - 1)));
    try {
      final res = await _client.get('hrm/roster-schedule?start_date=$start&end_date=$end&all_employees=1', isV8: false);
      final data = res is Map && res['data'] is List ? res['data'] as List : const [];
      final days = [
        for (final d in data.whereType<Map>())
          _Day(
            str(d['date']),
            calDate(d['date']) ?? _current,
            (d['shifts'] is List ? d['shifts'] as List : const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList(),
          ),
      ];
      if (!mounted || seq != _seq) return;
      setState(() => _schedule = days);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = errorMessage(e, 'Failed to load roster schedule'));
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  void _go(DateTime d, {String? view}) {
    setState(() {
      if (view != null) _view = view;
      _current = _view == 'week' ? _weekStart(d) : dayOnly(d);
      _schedule = [];
    });
    _fetch();
  }

  void _prev() => _go(_current.subtract(Duration(days: _span)));
  void _next() => _go(_current.add(Duration(days: _span)));

  Future<void> _pickMonth() async {
    final picked = await showPickerSheet(context,
        title: 'Jump to month', selected: _current.month - 1, options: [for (var i = 0; i < 12; i++) PickOption(i, _months[i])]);
    if (picked == null) return;
    _go(DateTime(DateTime.now().year, (picked.id as int) + 1, 1));
  }

  void _reset() {
    _search.clear();
    _expanded.clear();
    _go(DateTime.now(), view: 'day');
  }

  Future<void> _openForm({String? initialDate, _Day? edit}) async {
    final saved = await showMotionSheet<bool>(
      context,
      (_) => RosterFormSheet(
        initialDate: edit == null ? initialDate : null,
        editDate: edit?.day,
        editShifts: edit?.shifts.where((s) => s['roster_id'] != null).toList(),
      ),
    );
    if (saved == true) {
      if (mounted) marketToast(context, edit == null ? 'Roster created' : 'Roster updated');
      _fetch();
    }
  }

  Future<void> _removeOverride(int id) async {
    final ok = await confirmMarket(context, title: 'Remove this override?', message: 'The employee goes back to their regular shift for this day.', confirm: 'Remove');
    if (!ok) return;
    try {
      await _client.delete('shift_overrides', id);
      if (mounted) marketToast(context, 'Override removed');
      _fetch();
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Failed to remove override'), error: true);
    }
  }

  /// Mobile stand-in for desktop's drag-and-drop between shift columns.
  Future<void> _move(_Day day, Map<String, dynamic> source, Map<String, dynamic> emp) async {
    final det = _det(emp);
    final targets = day.shifts.where((s) => s['shift_id'] != source['shift_id']).toList();
    if (targets.isEmpty) {
      marketToast(context, 'No other shift on this day', error: true);
      return;
    }
    final picked = await showPickerSheet(context,
        title: 'Move ${str(det['name'])} to',
        options: [
          for (final s in targets) PickOption(s['shift_id'], str(s['shift_name']), sub: '${clock(s['start_time'])} to ${clock(s['end_time'])} · ${_emps(s).length} people'),
        ]);
    if (picked == null || !mounted) return;
    final target = targets.firstWhere((s) => s['shift_id'].toString() == picked.id.toString());
    if (_emps(target).any((e) => _det(e)['id'] == det['id'])) {
      marketToast(context, 'Employee already in this shift', error: true);
      return;
    }
    final sourceIds = {for (final e in _emps(source)) _det(e)['id'].toString()};
    final res = await showMotionSheet<({String type, Object? swapWith})>(
      context,
      (_) => _OverrideActionSheet(employee: det, target: target, sourceIds: sourceIds),
    );
    if (res == null || !mounted) return;
    await _execute(day, source, target, det, res.type, res.swapWith);
  }

  Future<void> _execute(_Day day, Map<String, dynamic> source, Map<String, dynamic> target, Map<String, dynamic> det, String type, Object? swapWith) async {
    try {
      Object? rosterId = target['roster_id'];
      if (rosterId == null) {
        final created = await EntityApi(_client, 'rosters').create({'start_date': day.day, 'end_date': day.day, 'shift_id': target['shift_id']});
        rosterId = created['id'];
      }
      await _client.post('hrm/shift-overrides', {
        'roster_id': rosterId,
        'shift_id': target['shift_id'],
        'second_shift_id': source['shift_id'],
        'type': type,
        'replacement_employee_id': det['id'],
        'absent_employee_id': type == 'SWAP' ? swapWith : null,
        'date': day.day,
      });
      if (mounted) marketToast(context, 'Override applied');
      _fetch();
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Failed to apply override'), error: true);
    }
  }

  Future<void> _employeeActions(_Day day, Map<String, dynamic> shift, Map<String, dynamic> emp) async {
    final det = _det(emp);
    final holiday = str(det['holiday_status']).isNotEmpty;
    final override = emp['override_info'] is Map ? emp['override_info'] as Map : null;
    final key = await showActionSheet(context, title: str(det['name']), actions: [
      if (!holiday) (key: 'move', label: 'Move to another shift', icon: Icons.swap_horiz_rounded, destructive: false),
      if (override != null && emp['status'] != 'Regular') (key: 'remove', label: 'Remove override', icon: Icons.undo_rounded, destructive: true),
    ]);
    if (!mounted || key == null) return;
    if (key == 'move') await _move(day, shift, emp);
    if (key == 'remove' && override != null) await _removeOverride(int.tryParse(str(override['id'])) ?? 0);
  }

  // ── Build ──

  Widget _strip(MarketPalette p) {
    final start = _weekStart(_current);
    final today = dayOnly(DateTime.now());
    return GlowCard(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
      child: Column(children: [
        Row(children: [
          const SizedBox(width: 8),
          PressScale(
            onTap: _pickMonth,
            child: Row(children: [
              Text(DateFormat('MMMM yyyy').format(_current), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.text)),
              Icon(Icons.expand_more_rounded, color: p.label, size: 20),
            ]),
          ),
          const Spacer(),
          SegmentToggle<String>(value: _view, options: const [('day', 'Day'), ('week', 'Week')], onChanged: (v) => _go(_current, view: v)),
          const SizedBox(width: 6),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          IconButton(visualDensity: VisualDensity.compact, onPressed: _prev, icon: Icon(Icons.chevron_left_rounded, color: p.label)),
          Expanded(
            child: SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: 7,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final d = start.add(Duration(days: i));
                  final inRange = !d.isBefore(_current) && d.isBefore(_current.add(Duration(days: _span)));
                  final selected = _view == 'day' ? ymd(d) == ymd(_current) : inRange;
                  final isToday = ymd(d) == ymd(today);
                  return PressScale(
                    onTap: () => _go(d, view: 'day'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      width: 42,
                      decoration: BoxDecoration(
                        color: selected ? p.brand : (isToday ? p.brandSoft : Colors.transparent),
                        borderRadius: BorderRadius.circular(14),
                        border: !selected && isToday ? Border.all(color: p.brand.withValues(alpha: 0.4)) : null,
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(DateFormat('EEE').format(d), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: selected ? Colors.white : (isToday ? p.brand : p.label))),
                        const SizedBox(height: 2),
                        Text('${d.day}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: selected ? Colors.white : (isToday ? p.brand : p.text))),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),
          IconButton(visualDensity: VisualDensity.compact, onPressed: _next, icon: Icon(Icons.chevron_right_rounded, color: p.label)),
        ]),
      ]),
    );
  }

  Widget _dayHeader(MarketPalette p, _Day d, {bool compact = false}) {
    final isToday = ymd(d.date) == ymd(DateTime.now());
    final people = d.shifts.fold<int>(0, (a, s) => a + _emps(s).length);
    return Row(children: [
      Container(
        width: 46,
        height: 50,
        decoration: BoxDecoration(gradient: isToday ? Accent.ocean.gradient : null, color: isToday ? null : p.surface, borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(DateFormat('EEE').format(d.date), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: isToday ? Colors.white : p.label)),
          Text('${d.date.day}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: isToday ? Colors.white : p.text)),
        ]),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(DateFormat('EEEE').format(d.date), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
          Text(d.hasRoster ? '${fmtDate(d.date)} · $people people' : fmtDate(d.date), style: TextStyle(fontSize: 12, color: p.label)),
        ]),
      ),
      if (d.hasRoster)
        IconButton(tooltip: 'Edit roster', onPressed: () => _openForm(edit: d), icon: Icon(Icons.edit_calendar_outlined, color: p.brand))
      else if (!compact)
        const SizedBox.shrink()
      else
        TextButton(onPressed: () => _openForm(initialDate: d.day), child: const Text('Create roster')),
    ]);
  }

  Widget _noRoster(MarketPalette p, _Day d) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line, width: 1.5), color: p.card),
        child: Column(children: [
          Icon(Icons.event_note_outlined, size: 40, color: p.label.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text('No shift available', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
          const SizedBox(height: 4),
          Text('Plan which group works each shift on this day.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.label)),
          const SizedBox(height: 14),
          SizedBox(width: 200, child: GradientButton(label: 'Create roster', icon: Icons.add_rounded, accent: Accent.ocean, onTap: () => _openForm(initialDate: d.day))),
        ]),
      );

  Widget _badges(Map<String, dynamic> shift) {
    final items = [
      ('Swap', _countBy(shift, 'SWAP'), const Color(0xFF5D36FF)),
      ('Weekend', _countBy(shift, 'Weekend'), const Color(0xFFD20A0A)),
      ('Extra', _countBy(shift, 'EXTRA'), const Color(0xFF30914C)),
      ('Replace', _countBy(shift, 'REPLACEMENT'), const Color(0xFFE76500)),
    ].where((e) => e.$2 > 0).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 5, runSpacing: 5, children: [
      for (final e in items)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: e.$3, borderRadius: BorderRadius.circular(6)),
          child: Text('${e.$1} ${e.$2}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
    ]);
  }

  Widget _shiftCard(MarketPalette p, _Day day, Map<String, dynamic> shift) {
    final color = hexColor(shift['color']);
    final key = '${day.day}-${shift['shift_id']}';
    final q = (_search[key] ?? '').trim().toLowerCase();
    final all = _emps(shift);
    final list = q.isEmpty ? all : all.where((e) => str(_det(e)['name']).toLowerCase().contains(q) || str(_det(e)['employee_no']).toLowerCase().contains(q)).toList();
    final expanded = _expanded.contains(key) || q.isNotEmpty;
    final shown = expanded ? list : list.take(6).toList();
    return GlowCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 4,
          decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: str(shift['shift_name']), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
                    TextSpan(text: '  (${all.length})', style: TextStyle(color: p.label, fontSize: 13)),
                  ]),
                ),
              ),
              Icon(wrapsMidnight(shift['start_time'], shift['end_time']) ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded, size: 16, color: color),
            ]),
            const SizedBox(height: 3),
            Text(
              [
                '${clock(shift['start_time'])} to ${clock(shift['end_time'])}',
                if (str(shift['group']).isNotEmpty) str(shift['group']),
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: p.label),
            ),
            const SizedBox(height: 8),
            _badges(shift),
            if (all.length > 6) ...[
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => setState(() => _search[key] = v),
                decoration: motionInput(context, hint: 'Search employee', icon: Icons.search_rounded),
              ),
            ],
          ]),
        ),
        Divider(height: 1, color: p.line),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(all.isEmpty ? 'Nobody on this shift yet. Move someone here from another shift.' : 'No matches',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.label)),
                  )
                : Column(children: [
                    for (var i = 0; i < shown.length; i++) FadeSlideIn(index: i, offsetY: 8, child: _empRow(p, day, shift, shown[i])),
                    if (list.length > 6 && q.isEmpty)
                      TextButton.icon(
                        onPressed: () => setState(() => expanded ? _expanded.remove(key) : _expanded.add(key)),
                        icon: AnimatedRotation(turns: expanded ? 0.5 : 0, duration: const Duration(milliseconds: 240), child: const Icon(Icons.expand_more_rounded)),
                        label: Text(expanded ? 'Show less' : 'Show all ${list.length}'),
                      ),
                  ]),
          ),
        ),
      ]),
    );
  }

  Widget _empRow(MarketPalette p, _Day day, Map<String, dynamic> shift, Map<String, dynamic> emp) {
    final det = _det(emp);
    final name = str(det['name']);
    final status = str(emp['status']).isEmpty ? 'Regular' : str(emp['status']);
    final holiday = str(det['holiday_status']);
    final isHol = holiday == 'Weekend' || holiday == 'Leave';
    final override = emp['override_info'] is Map ? emp['override_info'] as Map : null;
    final sc = _statusColors[status] ?? p.brand;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: PressScale(
        onTap: () => _employeeActions(day, shift, emp),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isHol ? const Color(0xFFD20A0A).withValues(alpha: 0.08) : p.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            InitialsAvatar(name.isEmpty ? '?' : name, imageUrl: str(det['profile_photo']), size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                Text(
                  [if (str(det['employee_no']).isNotEmpty) str(det['employee_no']), if (str(det['group']).isNotEmpty) str(det['group'])].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: p.label),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: sc.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Text(humanize(status), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: sc)),
              ),
              if (isHol) ...[
                const SizedBox(height: 3),
                Text(humanize(holiday), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFFD20A0A))),
              ],
            ]),
            if (status != 'Regular' && override != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove override',
                onPressed: () => _removeOverride(int.tryParse(str(override['id'])) ?? 0),
                icon: Icon(Icons.close_rounded, size: 18, color: p.label),
              )
            else if (!isHol)
              Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.more_vert_rounded, size: 18, color: p.label.withValues(alpha: 0.6))),
          ]),
        ),
      ),
    );
  }

  Widget _weekDay(MarketPalette p, _Day d) => GlowCard(
        onTap: () => _go(d.date, view: 'day'),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _dayHeader(p, d, compact: true),
          if (d.hasRoster) ...[
            const SizedBox(height: 10),
            for (final s in d.shifts)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Container(width: 4, height: 30, decoration: BoxDecoration(color: hexColor(s['color']), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(str(s['shift_name']), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text)),
                      Text(
                        ['${clock(s['start_time'])} to ${clock(s['end_time'])}', if (str(s['group']).isNotEmpty) str(s['group'])].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: p.label),
                      ),
                    ]),
                  ),
                  _badges(s),
                  const SizedBox(width: 8),
                  Text('${_emps(s).length}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: hexColor(s['color']))),
                ]),
              ),
          ] else ...[
            const SizedBox(height: 8),
            Text('No roster yet', style: TextStyle(fontSize: 12, color: p.label)),
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final slivers = <Widget>[sliverBox(_strip(p))];
    if (_loading) {
      slivers.add(sliverSkeleton(count: 3, height: 220));
    } else if (_error != null) {
      slivers.add(sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _fetch));
    } else if (_schedule.isEmpty) {
      slivers.add(sliverEmpty(icon: Icons.calendar_view_week_outlined, title: 'No roster data for this period', actionLabel: 'Create roster', onAction: () => _openForm()));
    } else if (_view == 'week') {
      slivers.add(sliverStagger(count: _schedule.length, builder: (_, i) => _weekDay(p, _schedule[i])));
    } else {
      final d = _schedule.first;
      slivers.add(sliverBox(FadeSlideIn(child: _dayHeader(p, d))));
      if (!d.hasRoster) {
        slivers.add(sliverBox(_noRoster(p, d), padding: const EdgeInsets.fromLTRB(16, 0, 16, 0)));
      } else {
        slivers.add(sliverStagger(count: d.shifts.length, gap: 14, builder: (_, i) => _shiftCard(p, d, d.shifts[i])));
      }
    }
    return MotionScaffold(
      title: 'Roster',
      subtitle: 'Who works which shift, day by day',
      icon: Icons.calendar_view_week_outlined,
      accent: Accent.ocean,
      onRefresh: _fetch,
      onFab: () => _openForm(),
      fabLabel: 'New roster',
      actions: [
        IconButton(tooltip: 'Today', onPressed: _reset, icon: const Icon(Icons.today_rounded)),
      ],
      slivers: slivers,
    );
  }
}

/// Desktop's ActionOverlay: add as extra, swap with someone in the target
/// shift, or replace.
class _OverrideActionSheet extends StatefulWidget {
  final Map<String, dynamic> employee;
  final Map<String, dynamic> target;
  final Set<String> sourceIds;
  const _OverrideActionSheet({required this.employee, required this.target, required this.sourceIds});

  @override
  State<_OverrideActionSheet> createState() => _OverrideActionSheetState();
}

class _OverrideActionSheetState extends State<_OverrideActionSheet> {
  Object? _swapWith;

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final color = hexColor(widget.target['color']);
    final swapOptions = [
      for (final e in _emps(widget.target))
        if (str(_det(e)['holiday_status']).isEmpty && !widget.sourceIds.contains(_det(e)['id'].toString()))
          PickOption(_det(e)['id'], str(_det(e)['name']), sub: str(_det(e)['employee_no']).isEmpty ? null : str(_det(e)['employee_no'])),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetGrabber(),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Assign '),
              TextSpan(text: str(widget.employee['name']), style: TextStyle(color: color)),
              const TextSpan(text: ' to '),
              TextSpan(text: str(widget.target['shift_name']), style: TextStyle(color: color)),
            ]),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text),
          ),
          const SizedBox(height: 4),
          Text('Choose how to assign this employee to the shift', style: TextStyle(fontSize: 12.5, color: p.label)),
          const SizedBox(height: 16),
          FadeSlideIn(
            child: GradientButton(
              label: 'Add to this shift',
              icon: Icons.person_add_alt_1_rounded,
              accent: Accent.emerald,
              onTap: () => Navigator.pop(context, (type: 'EXTRA', swapWith: null)),
            ),
          ),
          const SizedBox(height: 16),
          FadeSlideIn(
            index: 1,
            child: FormLabel(
              label: 'Select employee to swap',
              child: PickerField(value: _swapWith, hint: 'Select employee', icon: Icons.swap_horiz_rounded, options: swapOptions, onChanged: (v) => setState(() => _swapWith = v)),
            ),
          ),
          FadeSlideIn(
            index: 2,
            child: Row(children: [
              Expanded(
                child: GradientButton(
                  label: 'Swap',
                  accent: Accent.ocean,
                  onTap: _swapWith == null ? null : () => Navigator.pop(context, (type: 'SWAP', swapWith: _swapWith)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GradientButton(
                  label: 'Replace',
                  accent: Accent.sunset,
                  onTap: () => Navigator.pop(context, (type: 'REPLACEMENT', swapWith: null)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ]),
      ),
    );
  }
}
