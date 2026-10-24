import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'employee_shared.dart';

/// Employee groups — port of erp/desktop's EmployeeGroup.tsx + AssignForm:
/// group CRUD (custom ID, name, active, permanent, shift), a members view
/// per group with remove, and a multi-select assign sheet that syncs the
/// membership through `POST /api/hrm/employee-group/sync`.
class EmployeeGroupsPage extends StatefulWidget {
  const EmployeeGroupsPage({super.key});

  @override
  State<EmployeeGroupsPage> createState() => _EmployeeGroupsPageState();
}

class _EmployeeGroupsPageState extends State<EmployeeGroupsPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _shifts = [];
  Map<String, int> _memberCounts = {};
  String _q = '';
  String _status = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    try {
      final data = await batchLoad(_client, {
        'rows': 'employee_groups?\$expand=shift&\$orderby=id desc&\$top=500',
        'shifts': 'employee_shifts?\$select=id,name&\$filter=is_active eq true&\$top=200',
        'members': 'group_has_employees?\$select=id,group_id&\$top=5000',
      });
      if (!mounted) return;
      final counts = <String, int>{};
      for (final m in data['members'] ?? const <Map<String, dynamic>>[]) {
        final k = str(m['group_id']);
        counts[k] = (counts[k] ?? 0) + 1;
      }
      setState(() {
        _rows = data['rows'] ?? [];
        _shifts = data['shifts'] ?? [];
        _memberCounts = counts;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load employee groups'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    return _rows.where((r) {
      final a = asBool(r['is_active'], fallback: true);
      if (_status == 'active' && !a) return false;
      if (_status == 'inactive' && a) return false;
      if (q.isEmpty) return true;
      return [str(r['name']), str(r['custom_id']), nested(r, 'shift')].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openForm([Map<String, dynamic>? row]) async {
    final saved = await showMotionSheet<bool>(context, (_) => _GroupFormSheet(shifts: _shifts, existing: row));
    if (saved == true) {
      if (mounted) marketToast(context, row == null ? 'Employee group created' : 'Employee group updated');
      _load();
    }
  }

  Future<bool> _delete(Map<String, dynamic> row) async {
    final ok = await confirmMarket(context, title: 'Delete group?', message: 'Delete group "${str(row['name'])}"?');
    if (!ok) return false;
    try {
      await _client.delete('employee_groups', row['id']);
      if (mounted) {
        setState(() => _rows.removeWhere((r) => r['id'] == row['id']));
        marketToast(context, 'Employee group deleted');
      }
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete group'), error: true);
      return false;
    }
  }

  Future<void> _openMembers(Map<String, dynamic> row) async {
    await pushMotion(context, _GroupMembersPage(group: row));
    _load();
  }

  Future<void> _more(Map<String, dynamic> row) async {
    final key = await showActionSheet(context, title: str(row['name']), actions: [
      (key: 'members', label: 'View members', icon: Icons.groups_2_outlined, destructive: false),
      (key: 'assign', label: 'Assign employees', icon: Icons.person_add_alt_outlined, destructive: false),
      (key: 'edit', label: 'Edit', icon: Icons.edit_outlined, destructive: false),
      (key: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted) return;
    switch (key) {
      case 'members':
        _openMembers(row);
      case 'assign':
        final done = await showAssignSheet(context, row);
        if (done) _load();
      case 'edit':
        _openForm(row);
      case 'delete':
        _delete(row);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final active = _rows.where((r) => asBool(r['is_active'], fallback: true)).length;
    return MotionScaffold(
      title: 'Employee groups',
      subtitle: '${_rows.length} groups',
      icon: Icons.groups_2_outlined,
      accent: Accent.ocean,
      onRefresh: _load,
      onFab: () => _openForm(),
      fabLabel: 'New group',
      headerExtra: HeaderSearch(hint: 'Search groups', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _status,
              options: [
                (id: 'all', label: 'All', count: _rows.length),
                (id: 'active', label: 'Active', count: active),
                (id: 'inactive', label: 'Inactive', count: _rows.length - active),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton()
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.groups_2_outlined,
            title: _rows.isEmpty ? 'No groups yet' : 'No matches',
            message: _rows.isEmpty ? 'Tap new group to create the first one.' : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final a = asBool(r['is_active'], fallback: true);
              final count = _memberCounts[str(r['id'])] ?? 0;
              return MotionTile(
                key: ValueKey(r['id']),
                leading: AccentIcon(Icons.groups_2_rounded, accent: accentFor(str(r['name'])), size: 42),
                title: str(r['name']),
                subtitle: [
                  if (str(r['custom_id']).isNotEmpty) 'ID ${r['custom_id']}',
                  nested(r, 'shift').isEmpty ? 'No shift' : nested(r, 'shift'),
                  asBool(r['is_permanent']) ? 'Permanent' : 'Temporary',
                ].join(' · '),
                meta: '$count ${count == 1 ? 'member' : 'members'}',
                trailing: StatusPill(a ? 'Active' : 'Inactive', tone: a ? MarketTone.ok : MarketTone.neutral),
                onTap: () => _openMembers(r),
                onLongPress: () => _more(r),
                onDelete: () => _delete(r),
              );
            },
          ),
      ],
    );
  }
}

// ── Group form ─────────────────────────────────────────────────────────

class _GroupFormSheet extends StatefulWidget {
  final List<Map<String, dynamic>> shifts;
  final Map<String, dynamic>? existing;
  const _GroupFormSheet({required this.shifts, this.existing});

  @override
  State<_GroupFormSheet> createState() => _GroupFormSheetState();
}

class _GroupFormSheetState extends State<_GroupFormSheet> {
  late final _customId = TextEditingController(text: str(widget.existing?['custom_id']));
  late final _name = TextEditingController(text: str(widget.existing?['name']));
  late bool _active = asBool(widget.existing?['is_active'], fallback: true);
  late bool _permanent = asBool(widget.existing?['is_permanent']);
  late Object? _shiftId = widget.existing?['shift_id'];
  bool _busy = false;

  @override
  void dispose() {
    _customId.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      marketToast(context, 'Name is required', error: true);
      return;
    }
    setState(() => _busy = true);
    final body = {
      'custom_id': _customId.text.trim().isEmpty ? null : _customId.text.trim(),
      'name': _name.text.trim(),
      'is_active': _active,
      'is_permanent': _permanent,
      'shift_id': _shiftId == null ? null : int.tryParse(_shiftId.toString()),
    };
    try {
      final api = EntityApi(ApiClient(), 'employee_groups');
      if (widget.existing == null) {
        await api.create(body);
      } else {
        await api.update(widget.existing!['id'], body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(e, 'Failed to save employee group'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => FormSheet(
        title: widget.existing == null ? 'New employee group' : 'Edit employee group',
        subtitle: widget.existing == null ? null : str(widget.existing!['name']),
        busy: _busy,
        onSubmit: _save,
        submitLabel: widget.existing == null ? 'Create' : 'Save changes',
        children: [
          SwitchField(label: 'Active', value: _active, onChanged: (v) => setState(() => _active = v)),
          SwitchField(label: 'Permanent', sub: 'Members stay in this group permanently', value: _permanent, onChanged: (v) => setState(() => _permanent = v)),
          FormLabel(label: 'Custom ID', child: TextField(controller: _customId, decoration: motionInput(context, hint: 'Optional', icon: Icons.tag_rounded))),
          FormLabel(label: 'Name', required: true, child: TextField(controller: _name, decoration: motionInput(context, hint: 'Enter group name', icon: Icons.groups_2_outlined))),
          FormLabel(
            label: 'Shift',
            child: PickerField(
              value: _shiftId,
              hint: 'Select shift (optional)',
              icon: Icons.schedule_rounded,
              options: [for (final s in widget.shifts) PickOption(s['id'], str(s['name']))],
              onChanged: (v) => setState(() => _shiftId = v),
            ),
          ),
        ],
      );
}

// ── Members ────────────────────────────────────────────────────────────

class _GroupMembersPage extends StatefulWidget {
  final Map<String, dynamic> group;
  const _GroupMembersPage({required this.group});

  @override
  State<_GroupMembersPage> createState() => _GroupMembersPageState();
}

class _GroupMembersPageState extends State<_GroupMembersPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    try {
      final res = await _client.get('group_has_employees?\$filter=group_id eq ${widget.group['id']}&\$expand=employee&\$top=1000');
      if (!mounted) return;
      setState(() => _rows = unwrapList(res).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList());
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load members'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _emp(Map<String, dynamic> r) => r['employee'] is Map ? (r['employee'] as Map).cast<String, dynamic>() : <String, dynamic>{};

  Future<bool> _remove(Map<String, dynamic> row) async {
    final ok = await confirmMarket(context, title: 'Remove member?', message: 'Remove ${employeeName(_emp(row))} from this group?', confirm: 'Remove');
    if (!ok) return false;
    try {
      await _client.delete('group_has_employees', row['id']);
      await _clearCache(_client);
      if (mounted) {
        setState(() => _rows.removeWhere((r) => r['id'] == row['id']));
        marketToast(context, 'Employee removed from group');
      }
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not remove employee'), error: true);
      return false;
    }
  }

  Future<void> _assign() async {
    final done = await showAssignSheet(context, widget.group);
    if (done) _load();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final q = _q.trim().toLowerCase();
    final rows = _rows.where((r) {
      if (q.isEmpty) return true;
      final e = _emp(r);
      return '${employeeName(e)} ${str(e['employee_no'])}'.toLowerCase().contains(q);
    }).toList();
    return MotionScaffold(
      title: str(g['name']),
      subtitle: [
        '${_rows.length} ${_rows.length == 1 ? 'member' : 'members'}',
        if (nested(g, 'shift').isNotEmpty) nested(g, 'shift'),
      ].join(' · '),
      icon: Icons.groups_2_outlined,
      accent: Accent.ocean,
      onRefresh: _load,
      onFab: _assign,
      fabLabel: 'Assign',
      fabIcon: Icons.person_add_alt_1_rounded,
      headerExtra: HeaderSearch(hint: 'Search members', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        if (_loading)
          sliverSkeleton()
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.person_search_outlined,
            title: _rows.isEmpty ? 'No members yet' : 'No matches',
            message: _rows.isEmpty ? 'Assign employees to this group.' : null,
            actionLabel: _rows.isEmpty ? 'Assign employees' : null,
            onAction: _rows.isEmpty ? _assign : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final e = _emp(r);
              return MotionTile(
                key: ValueKey(r['id']),
                leading: EmployeeAvatar(e, size: 42, hero: false),
                title: employeeName(e),
                subtitle: str(e['employee_no']).isEmpty ? null : '#${e['employee_no']}',
                meta: r['joined_at'] == null ? null : 'Joined ${fmtDate(parseDate(r['joined_at']))}',
                trailing: IconButton(
                  tooltip: 'Remove',
                  onPressed: () => _remove(r),
                  icon: Icon(Icons.person_remove_outlined, color: MarketPalette.of(context).error),
                ),
                onDelete: () => _remove(r),
              );
            },
          ),
      ],
    );
  }
}

/// Desktop clears the server-side group cache after any membership change.
Future<void> _clearCache(ApiClient client) async {
  try {
    await client.delete('cache_group_has_employees', 0);
  } catch (_) {}
}

// ── Assign ─────────────────────────────────────────────────────────────

/// Opens the multi-select assign sheet; resolves true when saved.
Future<bool> showAssignSheet(BuildContext context, Map<String, dynamic> group) async {
  final r = await showMotionSheet<bool>(context, (_) => _AssignSheet(group: group));
  return r == true;
}

class _AssignSheet extends StatefulWidget {
  final Map<String, dynamic> group;
  const _AssignSheet({required this.group});

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  bool _busy = false;
  List<Map<String, dynamic>> _emps = [];
  final Set<int> _selected = {};
  String _q = '';

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
      final data = await batchLoad(_client, {
        'emps': 'employees?\$select=id,first_name,last_name,employee_no,profile_photo,is_active&\$filter=is_active eq true&\$top=500',
        'members': 'group_has_employees?\$filter=group_id eq ${widget.group['id']}&\$select=employee_id&\$top=500',
      });
      if (!mounted) return;
      setState(() {
        _emps = data['emps'] ?? [];
        _selected
          ..clear()
          ..addAll((data['members'] ?? const <Map<String, dynamic>>[]).map((m) => toInt(m['employee_id'])).where((id) => id > 0));
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load employees'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _client.post('hrm/employee-group/sync', {'group_id': widget.group['id'], 'employee_ids': _selected.toList()});
      await _clearCache(_client);
      if (!mounted) return;
      marketToast(context, '${_selected.length} employee${_selected.length > 1 ? 's' : ''} assigned');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(e, 'Failed to assign employees'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final q = _q.trim().toLowerCase();
    final list = _emps.where((e) => q.isEmpty || '${employeeName(e)} ${str(e['employee_no'])}'.toLowerCase().contains(q)).toList();
    final allVisibleSelected = list.isNotEmpty && list.every((e) => _selected.contains(toInt(e['id'])));
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.88,
      child: Column(children: [
        const SheetGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Assign employees', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
                Text(str(widget.group['name']), style: TextStyle(fontSize: 12.5, color: p.label)),
              ]),
            ),
            IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: p.label)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(onChanged: (v) => setState(() => _q = v), decoration: motionInput(context, hint: 'Search employees', icon: Icons.search_rounded)),
        ),
        if (!_loading && _error == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text('${_selected.length} selected', key: ValueKey(_selected.length), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.label)),
              ),
              const Spacer(),
              TextButton(
                onPressed: list.isEmpty
                    ? null
                    : () => setState(() {
                          final ids = list.map((e) => toInt(e['id']));
                          if (allVisibleSelected) {
                            _selected.removeAll(ids);
                          } else {
                            _selected.addAll(ids);
                          }
                        }),
                child: Text(allVisibleSelected ? 'Clear all' : 'Select all'),
              ),
            ]),
          ),
        Expanded(
          child: _loading
              ? ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: 6,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, _) => const SkeletonBox(height: 60, radius: 14),
                )
              : _error != null
                  ? MarketEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
                  : list.isEmpty
                      ? const MarketEmpty(icon: Icons.person_search_outlined, title: 'No employees found')
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: list.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final e = list[i];
                            final id = toInt(e['id']);
                            final sel = _selected.contains(id);
                            return FadeSlideIn(
                              index: i,
                              offsetY: 10,
                              child: PressScale(
                                onTap: () => setState(() => sel ? _selected.remove(id) : _selected.add(id)),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: sel ? p.brandSoft : p.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: sel ? p.brand : Colors.transparent, width: 1.4),
                                  ),
                                  child: Row(children: [
                                    EmployeeAvatar(e, size: 38, hero: false, showStatus: false),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(employeeName(e), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                                        if (str(e['employee_no']).isNotEmpty) Text('#${e['employee_no']}', style: TextStyle(fontSize: 12, color: p.label)),
                                      ]),
                                    ),
                                    AnimatedScale(
                                      scale: sel ? 1 : 0.85,
                                      duration: const Duration(milliseconds: 220),
                                      curve: Curves.easeOutBack,
                                      child: Icon(sel ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: sel ? p.brand : p.label),
                                    ),
                                  ]),
                                ),
                              ),
                            );
                          },
                        ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
            child: GradientButton(
              label: _selected.isEmpty ? 'Assign' : 'Assign (${_selected.length})',
              icon: Icons.how_to_reg_rounded,
              accent: Accent.ocean,
              busy: _busy,
              onTap: _selected.isEmpty || _loading ? null : _save,
            ),
          ),
        ),
      ]),
    );
  }
}
