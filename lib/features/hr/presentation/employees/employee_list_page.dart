import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'employee_detail_page.dart';
import 'employee_form_page.dart';
import 'employee_shared.dart';

/// Employee directory — port of erp/desktop's EmployeeList.tsx: avatar
/// cards, search (name / email / employee ID), active filter, department /
/// designation / type / section filters, view / edit / delete and a
/// multi-step create form.
class EmployeeListPage extends StatefulWidget {
  const EmployeeListPage({super.key});

  @override
  State<EmployeeListPage> createState() => _EmployeeListPageState();
}

class _EmployeeListPageState extends State<EmployeeListPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  Map<String, List<Map<String, dynamic>>> _lookups = {};
  String _q = '';
  String _status = 'all';
  int? _deptId;
  int? _desgId;
  int? _typeId;
  int? _sectionId;

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
    const q = '\$select=id,name&\$top=500';
    try {
      final data = await batchLoad(_client, {
        'rows': 'employees?\$expand=$employeeExpand&\$orderby=id desc&\$top=2000',
        'departments': 'departments?$q',
        'designations': 'designations?$q',
        'types': 'employee_types?$q',
        'sections': 'employee_sections?$q',
      });
      if (!mounted) return;
      setState(() {
        _rows = data.remove('rows') ?? [];
        _lookups = data;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load employees'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _filterCount => [_deptId, _desgId, _typeId, _sectionId].where((v) => v != null).length;

  bool _matchStatus(Map<String, dynamic> r) => switch (_status) {
        'active' => asBool(r['is_active'], fallback: true),
        'inactive' => !asBool(r['is_active'], fallback: true),
        _ => true,
      };

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    bool eq(dynamic a, int? b) => b == null || a?.toString() == b.toString();
    return _rows.where((r) {
      if (!_matchStatus(r)) return false;
      if (!eq(r['department_id'], _deptId) || !eq(r['designation_id'], _desgId) || !eq(r['employee_type_id'], _typeId) || !eq(r['employee_section_id'], _sectionId)) {
        return false;
      }
      if (q.isEmpty) return true;
      final hay = [employeeName(r), str(r['email']), str(r['employee_no']), str(r['contact_number']), nested(r, 'designation'), nested(r, 'department')].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _openFilters() async {
    final res = await showMotionSheet<Map<String, int?>>(
      context,
      (_) => _FilterSheet(lookups: _lookups, initial: {'dept': _deptId, 'desg': _desgId, 'type': _typeId, 'section': _sectionId}),
    );
    if (res == null) return;
    setState(() {
      _deptId = res['dept'];
      _desgId = res['desg'];
      _typeId = res['type'];
      _sectionId = res['section'];
    });
  }

  Future<void> _create() async {
    final saved = await pushMotion<bool>(context, const EmployeeFormPage());
    if (saved == true) _load();
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final saved = await pushMotion<bool>(context, EmployeeFormPage(existing: row));
    if (saved == true) _load();
  }

  Future<void> _view(Map<String, dynamic> row) async {
    await pushMotion(context, EmployeeDetailPage(employee: row));
    _load();
  }

  Future<bool> _delete(Map<String, dynamic> row) async {
    final ok = await confirmMarket(context,
        title: 'Delete employee?', message: 'Delete employee "${employeeName(row)}" (${str(row['employee_no']).isEmpty ? row['id'] : row['employee_no']})?');
    if (!ok) return false;
    try {
      await _client.delete('employees', row['id']);
      if (mounted) {
        setState(() => _rows.removeWhere((r) => r['id'] == row['id']));
        marketToast(context, 'Employee deleted');
      }
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete employee'), error: true);
      return false;
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> row) async {
    final next = !asBool(row['is_active'], fallback: true);
    try {
      await _client.put('employees', row['id'], {'is_active': next});
      if (!mounted) return;
      setState(() => row['is_active'] = next);
      marketToast(context, next ? 'Employee activated' : 'Employee deactivated');
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not update employee'), error: true);
    }
  }

  Future<void> _more(Map<String, dynamic> row) async {
    final active = asBool(row['is_active'], fallback: true);
    final key = await showActionSheet(context, title: employeeName(row), actions: [
      (key: 'view', label: 'View profile', icon: Icons.visibility_outlined, destructive: false),
      (key: 'edit', label: 'Edit', icon: Icons.edit_outlined, destructive: false),
      (key: 'toggle', label: active ? 'Deactivate' : 'Activate', icon: active ? Icons.person_off_outlined : Icons.person_outline, destructive: false),
      (key: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted) return;
    switch (key) {
      case 'view':
        _view(row);
      case 'edit':
        _edit(row);
      case 'toggle':
        _toggleActive(row);
      case 'delete':
        _delete(row);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final rows = _visible;
    final active = _rows.where((r) => asBool(r['is_active'], fallback: true)).length;
    return MotionScaffold(
      title: 'Employee list',
      subtitle: '${_rows.length} employees, $active active',
      icon: Icons.people_alt_outlined,
      accent: Accent.ocean,
      onRefresh: _load,
      onFab: _create,
      fabLabel: 'Add employee',
      fabIcon: Icons.person_add_alt_1_rounded,
      actions: [
        IconButton(
          tooltip: 'Filters',
          onPressed: _openFilters,
          icon: Badge(isLabelVisible: _filterCount > 0, label: Text('$_filterCount'), child: const Icon(Icons.tune_rounded)),
        ),
      ],
      headerExtra: HeaderSearch(hint: 'Search name, email or ID', onChanged: (v) => setState(() => _q = v)),
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
        if (_filterCount > 0)
          sliverBox(
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (_deptId != null) _activeFilter(lookupName(_lookups['departments'], _deptId), () => setState(() => _deptId = null)),
              if (_desgId != null) _activeFilter(lookupName(_lookups['designations'], _desgId), () => setState(() => _desgId = null)),
              if (_typeId != null) _activeFilter(lookupName(_lookups['types'], _typeId), () => setState(() => _typeId = null)),
              if (_sectionId != null) _activeFilter(lookupName(_lookups['sections'], _sectionId), () => setState(() => _sectionId = null)),
            ]),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          ),
        if (_loading)
          sliverSkeleton(height: 86)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.people_alt_outlined,
            title: _rows.isEmpty ? 'No employees yet' : 'No matches',
            message: _rows.isEmpty ? 'Tap add employee to create the first one.' : 'Try another search or clear the filters.',
            actionLabel: _rows.isEmpty ? 'Add employee' : null,
            onAction: _rows.isEmpty ? _create : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final desg = nested(r, 'designation');
              final dept = nested(r, 'department');
              final active = asBool(r['is_active'], fallback: true);
              return MotionTile(
                key: ValueKey(r['id']),
                leading: EmployeeAvatar(r),
                title: employeeName(r),
                subtitle: [desg, dept].where((s) => s.isNotEmpty).join(' · '),
                meta: [if (str(r['employee_no']).isNotEmpty) '#${r['employee_no']}', str(r['email'])].where((s) => s.isNotEmpty).join('  '),
                trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  StatusPill(active ? 'Active' : 'Inactive', tone: active ? MarketTone.ok : MarketTone.neutral),
                  const SizedBox(height: 6),
                  Icon(Icons.chevron_right_rounded, color: p.label, size: 20),
                ]),
                onTap: () => _view(r),
                onLongPress: () => _more(r),
                onDelete: () => _delete(r),
              );
            },
          ),
      ],
    );
  }

  Widget _activeFilter(String label, VoidCallback onClear) {
    final p = MarketPalette.of(context);
    return FadeSlideIn(
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label.isEmpty ? 'Filter' : label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.brand)),
          IconButton(visualDensity: VisualDensity.compact, iconSize: 16, onPressed: onClear, icon: Icon(Icons.close_rounded, color: p.brand)),
        ]),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final Map<String, List<Map<String, dynamic>>> lookups;
  final Map<String, int?> initial;
  const _FilterSheet({required this.lookups, required this.initial});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final Map<String, int?> _v = Map.of(widget.initial);

  List<PickOption> _opts(String key) => [for (final r in widget.lookups[key] ?? const <Map<String, dynamic>>[]) PickOption(r['id'], str(r['name']))];

  Widget _picker(String label, String key, String lookup, IconData icon) => FormLabel(
        label: label,
        child: PickerField(
          value: _v[key],
          hint: 'Any ${label.toLowerCase()}',
          icon: icon,
          options: _opts(lookup),
          onChanged: (v) => setState(() => _v[key] = v == null ? null : int.tryParse(v.toString())),
        ),
      );

  @override
  Widget build(BuildContext context) => FormSheet(
        title: 'Filter employees',
        submitLabel: 'Apply filters',
        onSubmit: () => Navigator.pop(context, _v),
        extraAction: TextButton(onPressed: () => Navigator.pop(context, <String, int?>{}), child: const Text('Clear')),
        children: [
          _picker('Department', 'dept', 'departments', Icons.account_tree_outlined),
          _picker('Designation', 'desg', 'designations', Icons.workspace_premium_outlined),
          _picker('Employee type', 'type', 'types', Icons.category_outlined),
          _picker('Section', 'section', 'sections', Icons.view_module_outlined),
        ],
      );
}
