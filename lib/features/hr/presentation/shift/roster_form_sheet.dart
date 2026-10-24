import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'shift_common.dart';

/// Roster planning sheet — mirrors erp/desktop hrm/shift/roster/RosterForm.tsx.
/// One card per active shift; picking an employee group for a shift loads its
/// members (group_has_employees). Saves through POST /api/hrm/rosters with
/// `{rosters: [{roster_id, shift_id, group_id, start_date, end_date}]}`.
///
/// Open modes (same as desktop):
/// * plain create — dates editable, suggests the day after the latest roster
/// * [initialDate] — locked to that day
/// * [editShifts] — groups / roster ids pre-filled from that day's schedule
class RosterFormSheet extends StatefulWidget {
  final String? initialDate;
  final String? editDate;
  final List<Map<String, dynamic>>? editShifts;
  const RosterFormSheet({super.key, this.initialDate, this.editDate, this.editShifts});

  @override
  State<RosterFormSheet> createState() => _RosterFormSheetState();
}

class _ShiftEntry {
  final int id;
  final String name;
  final Color color;
  final String start;
  final String end;
  Object? groupId;
  String groupName = '';
  Object? rosterId;
  List<Map<String, dynamic>> employees = [];
  bool loadingEmps = false;
  String search = '';
  _ShiftEntry({required this.id, required this.name, required this.color, required this.start, required this.end});
}

class _RosterFormSheetState extends State<RosterFormSheet> {
  final _client = ApiClient();
  List<_ShiftEntry> _shifts = [];
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;
  String? _error;
  bool _saving = false;
  DateTime? _from;
  DateTime? _to;

  bool get _isEdit => widget.editShifts != null;
  bool get _locked => widget.initialDate != null && widget.initialDate!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final lockedDate = (widget.editDate?.isNotEmpty ?? false) ? widget.editDate : widget.initialDate;
    final d = calDate(lockedDate);
    if (d != null) {
      _from = d;
      _to = d;
    } else {
      _suggestDate();
    }
    _load();
  }

  Future<void> _suggestDate() async {
    final today = dayOnly(DateTime.now());
    try {
      final res = await _client.get('hrm/rosters/latest', isV8: false);
      final latest = res is Map ? res['latest_roster'] : null;
      final end = latest is Map ? calDate(latest['end_date']) : null;
      final next = end == null ? today : end.add(const Duration(days: 1));
      final suggested = next.isAfter(today) ? next : today;
      if (mounted && _from == null) {
        setState(() {
          _from = suggested;
          _to = suggested;
        });
      }
    } catch (_) {
      // Fall back to today so submit never stays silently disabled.
      if (mounted && _from == null) {
        setState(() {
          _from = today;
          _to = today;
        });
      }
    }
  }

  static String _membersQuery(Object groupId) => 'group_has_employees?\$filter=${Uri.encodeComponent('group_id eq $groupId')}'
      '&\$expand=employee(\$select=id,first_name,last_name,employee_no,profile_photo)&\$top=500';

  static List<Map<String, dynamic>> _members(List<Map<String, dynamic>> rows) =>
      [for (final m in rows) if (m['employee'] is Map) (m['employee'] as Map).cast<String, dynamic>()];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await batchLoad(_client, {
        'shifts': 'employee_shifts?\$select=id,name,color,start_time,end_time&\$filter=${Uri.encodeComponent('is_active eq true')}&\$top=200',
        'groups': 'employee_groups?\$select=id,name&\$filter=${Uri.encodeComponent('is_active eq true')}&\$top=500',
      });
      final entries = [
        for (final s in data['shifts'] ?? <Map<String, dynamic>>[])
          _ShiftEntry(
            id: int.tryParse(str(s['id'])) ?? 0,
            name: str(s['name']),
            color: hexColor(s['color'], const Color(0xFF0070F2)),
            start: str(s['start_time']),
            end: str(s['end_time']),
          ),
      ];
      // Pre-fill groups / roster ids from the day being edited.
      final prefill = <String, String>{};
      for (final ed in widget.editShifts ?? const <Map<String, dynamic>>[]) {
        final entry = entries.where((e) => e.id.toString() == str(ed['shift_id'])).firstOrNull;
        if (entry == null) continue;
        entry.groupId = ed['group_id'];
        entry.groupName = str(ed['group']);
        entry.rosterId = ed['roster_id'];
        if (ed['group_id'] != null) {
          entry.loadingEmps = true;
          prefill['${entry.id}'] = _membersQuery(ed['group_id'] as Object);
        }
      }
      if (!mounted) return;
      setState(() {
        _shifts = entries;
        _groups = data['groups'] ?? [];
        _loading = false;
      });
      if (prefill.isNotEmpty) {
        try {
          final members = await batchLoad(_client, prefill);
          if (!mounted) return;
          setState(() {
            for (final e in _shifts) {
              if (members.containsKey('${e.id}')) e.employees = _members(members['${e.id}']!);
              e.loadingEmps = false;
            }
          });
        } catch (_) {
          if (mounted) {
            setState(() {
              for (final e in _shifts) {
                e.loadingEmps = false;
              }
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = errorMessage(e, 'Could not load shifts and groups');
        });
      }
    }
  }

  Future<void> _pickGroup(_ShiftEntry s, Object? id) async {
    if (id == null) {
      setState(() {
        s.groupId = null;
        s.groupName = '';
        s.employees = [];
      });
      return;
    }
    setState(() {
      s.groupId = id;
      s.groupName = lookupName(_groups, id);
      s.loadingEmps = true;
      s.employees = [];
    });
    try {
      final res = await _client.get(_membersQuery(id));
      if (mounted) setState(() => s.employees = _members(rowsOf(res)));
    } catch (_) {
      // keep empty
    } finally {
      if (mounted) setState(() => s.loadingEmps = false);
    }
  }

  Future<void> _save() async {
    if (_from == null || _to == null) {
      marketToast(context, 'Select a date range', error: true);
      return;
    }
    if (_from!.isAfter(_to!)) {
      marketToast(context, 'Start date must be before end date', error: true);
      return;
    }
    final items = _shifts.where((s) => _isEdit ? (s.groupId != null || s.rosterId != null) : s.groupId != null).toList();
    if (items.isEmpty) {
      marketToast(context, 'Select at least one group', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _client.post('hrm/rosters', {
        'rosters': [
          for (final s in items)
            {
              'roster_id': s.rosterId,
              'shift_id': s.id,
              'group_id': s.groupId,
              'start_date': ymd(_from!),
              'end_date': ymd(_to!),
            },
        ],
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        marketToast(context, errorMessage(e, _isEdit ? 'Failed to update roster' : 'Failed to create roster'), error: true);
      }
    }
  }

  Widget _dates(MarketPalette p) {
    if (_locked) {
      return GlowCard(
        color: p.surface,
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(Icons.lock_clock_outlined, color: p.brand, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text('Roster for ${fmtDate(_from)}', style: TextStyle(fontWeight: FontWeight.w700, color: p.text))),
        ]),
      );
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: FormLabel(
          label: 'From',
          required: true,
          child: DatePickField(
            value: _from,
            onChanged: (d) => setState(() {
              _from = d;
              if (d != null && (_to == null || _to!.isBefore(d))) _to = d;
            }),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: FormLabel(label: 'To', required: true, child: DatePickField(value: _to, firstDate: _from, onChanged: (d) => setState(() => _to = d)))),
    ]);
  }

  Widget _shiftCard(MarketPalette p, _ShiftEntry s) {
    final q = s.search.trim().toLowerCase();
    final emps = q.isEmpty
        ? s.employees
        : s.employees.where((e) => personName(e).toLowerCase().contains(q) || str(e['employee_no']).toLowerCase().contains(q)).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlowCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: s.color.withValues(alpha: 0.08),
              border: Border(bottom: BorderSide(color: s.color.withValues(alpha: 0.25), width: 2)),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(s.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: s.color))),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    key: ValueKey(s.employees.length),
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                    decoration: BoxDecoration(color: s.color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                    child: Text('${s.employees.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: s.color)),
                  ),
                ),
              ]),
              const SizedBox(height: 2),
              Text('${clock(s.start)} to ${clock(s.end)}', style: TextStyle(fontSize: 11.5, color: p.label)),
              const SizedBox(height: 10),
              PickerField(
                value: s.groupId,
                hint: 'Select group',
                icon: Icons.groups_2_outlined,
                options: [for (final g in _groups) PickOption(g['id'], str(g['name']))],
                onChanged: (v) => _pickGroup(s, v),
              ),
              if (s.employees.length > 6) ...[
                const SizedBox(height: 8),
                TextField(
                  onChanged: (v) => setState(() => s.search = v),
                  decoration: motionInput(context, hint: 'Search employee', icon: Icons.search_rounded),
                ),
              ],
            ]),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: s.loadingEmps
                  ? const Column(children: [SkeletonBox(height: 44, radius: 12), SizedBox(height: 8), SkeletonBox(height: 44, radius: 12)])
                  : s.groupId == null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(children: [
                            Icon(Icons.group_add_outlined, color: p.label.withValues(alpha: 0.5), size: 28),
                            const SizedBox(height: 4),
                            Text('Select a group to assign', style: TextStyle(fontSize: 12, color: p.label)),
                          ]),
                        )
                      : emps.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text(s.employees.isEmpty ? 'This group has no members' : 'No matches', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.label)),
                            )
                          : Wrap(spacing: 6, runSpacing: 6, children: [
                              for (var i = 0; i < emps.length; i++)
                                FadeSlideIn(
                                  index: i,
                                  offsetY: 6,
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                                    decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      InitialsAvatar(personName(emps[i]).isEmpty ? '?' : personName(emps[i]), imageUrl: str(emps[i]['profile_photo']), size: 24),
                                      const SizedBox(width: 6),
                                      Text(personName(emps[i]), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text)),
                                      if (str(emps[i]['employee_no']).isNotEmpty) Text('  ${emps[i]['employee_no']}', style: TextStyle(fontSize: 11, color: p.label)),
                                    ]),
                                  ),
                                ),
                            ]),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final canSubmit = _from != null && _to != null && _shifts.any((s) => s.groupId != null || (_isEdit && s.rosterId != null));
    return FormSheet(
      title: _isEdit ? 'Edit roster' : 'Roster planning',
      subtitle: _isEdit ? 'Change the group working each shift' : 'Assign an employee group to each shift',
      busy: _saving,
      submitLabel: _isEdit ? 'Update roster' : 'Create roster',
      onSubmit: canSubmit && !_loading ? _save : null,
      children: [
        _dates(p),
        if (_loading) ...[
          const SkeletonBox(height: 150, radius: 12),
          const SizedBox(height: 12),
          const SkeletonBox(height: 150, radius: 12),
        ] else if (_error != null)
          MarketEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (_shifts.isEmpty)
          const MarketEmpty(icon: Icons.schedule_rounded, title: 'No active shifts', message: 'Create a shift first, then plan the roster.')
        else
          for (final s in _shifts) _shiftCard(p, s),
      ],
    );
  }
}
