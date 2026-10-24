import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../leave/hr_extras.dart';

// Shared screen for hr_policies and hr_notices (desktop PolicyList.tsx and
// NoticeList.tsx are identical apart from the entity): title + content,
// active flag and an audience of everyone, chosen departments or chosen
// employees.

const _targets = ['ALL', 'DEPARTMENTS', 'EMPLOYEES'];
const _targetColors = {'ALL': Color(0xFF30914C), 'DEPARTMENTS': Color(0xFF0070F2), 'EMPLOYEES': Color(0xFFCC00DC)};

String _targetLabel(Map<String, dynamic> r) {
  final t = str(r['target_type']).isEmpty ? 'ALL' : str(r['target_type']);
  if (t == 'DEPARTMENTS') {
    final n = jsonList(r['department_ids']).length;
    return '$n ${n == 1 ? 'department' : 'departments'}';
  }
  if (t == 'EMPLOYEES') {
    final n = jsonList(r['employee_ids']).length;
    return '$n ${n == 1 ? 'employee' : 'employees'}';
  }
  return 'Everyone';
}

class TargetedPostList extends StatefulWidget {
  final String endpoint;
  final String title;
  final String singular;
  final IconData icon;
  final Accent accent;
  const TargetedPostList({super.key, required this.endpoint, required this.title, required this.singular, required this.icon, required this.accent});

  @override
  State<TargetedPostList> createState() => _TargetedPostListState();
}

class _TargetedPostListState extends State<TargetedPostList> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _depts = [];
  List<Map<String, dynamic>> _emps = [];
  String _chip = 'all';
  String _q = '';

  String get _s => widget.singular;

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
      final d = await batchLoad(_client, {
        'rows': '${widget.endpoint}?\$select=id,title,content,target_type,department_ids,employee_ids,is_active,created_at&\$orderby=id desc&\$top=500',
        'depts': 'departments?\$select=id,name&\$top=500',
        'emps': 'employees?\$select=id,first_name,last_name,employee_no&\$filter=is_active eq true&\$top=500',
      });
      if (!mounted) return;
      setState(() {
        _rows = d['rows'] ?? [];
        _depts = d['depts'] ?? [];
        _emps = d['emps'] ?? [];
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load ${widget.title.toLowerCase()}'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _match(Map<String, dynamic> r, String k) => switch (k) {
        'active' => asBool(r['is_active'], fallback: true),
        'inactive' => !asBool(r['is_active'], fallback: true),
        'ALL' || 'DEPARTMENTS' || 'EMPLOYEES' => (str(r['target_type']).isEmpty ? 'ALL' : str(r['target_type'])) == k,
        _ => true,
      };

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    return _rows.where((r) => _match(r, _chip)).where((r) => q.isEmpty || '${r['title']} ${r['content']}'.toLowerCase().contains(q)).toList();
  }

  Future<void> _form([Map<String, dynamic>? row]) async {
    final ok = await showMotionSheet<bool>(
      context,
      (_) => _PostForm(endpoint: widget.endpoint, singular: _s, existing: row, depts: _depts, emps: _emps),
    );
    if (ok == true) {
      if (mounted) marketToast(context, row == null ? '${humanize(_s)} created' : '${humanize(_s)} updated');
      _load();
    }
  }

  Future<bool> _delete(Map<String, dynamic> row) async {
    final ok = await confirmMarket(context, title: 'Delete $_s?', message: 'Delete $_s "${str(row['title'])}"?');
    if (!ok) return false;
    try {
      await _client.delete(widget.endpoint, row['id']);
      if (mounted) {
        setState(() => _rows.removeWhere((r) => r['id'] == row['id']));
        marketToast(context, '${humanize(_s)} deleted');
      }
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Failed to delete $_s'), error: true);
      return false;
    }
  }

  Future<void> _detail(Map<String, dynamic> row) async {
    final res = await showMotionSheet<String>(context, (_) => _PostDetail(row: row, depts: _depts, emps: _emps, accent: widget.accent, icon: widget.icon));
    if (!mounted) return;
    if (res == 'edit') _form(row);
    if (res == 'delete') _delete(row);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final chips = const [('all', 'All'), ('active', 'Active'), ('inactive', 'Inactive'), ('ALL', 'Everyone'), ('DEPARTMENTS', 'Departments'), ('EMPLOYEES', 'Employees')];
    return MotionScaffold(
      title: widget.title,
      subtitle: '${_rows.where((r) => asBool(r['is_active'], fallback: true)).length} active · ${_rows.length} total',
      icon: widget.icon,
      accent: widget.accent,
      onRefresh: _load,
      onFab: () => _form(),
      fabLabel: 'New $_s',
      headerExtra: HeaderSearch(hint: 'Search ${widget.title.toLowerCase()}', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _chip,
              options: [for (final c in chips) (id: c.$1, label: c.$2, count: _rows.where((r) => _match(r, c.$1)).length)],
              onChanged: (v) => setState(() => _chip = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton(height: 96)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: widget.icon,
            title: _rows.isEmpty ? 'No ${widget.title.toLowerCase()} yet' : 'No matches',
            message: _rows.isEmpty ? 'Publish the first $_s for your team.' : null,
            actionLabel: _rows.isEmpty ? 'New $_s' : null,
            onAction: _rows.isEmpty ? _form : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final t = str(r['target_type']).isEmpty ? 'ALL' : str(r['target_type']);
              final active = asBool(r['is_active'], fallback: true);
              final c = _targetColors[t] ?? _targetColors['ALL']!;
              return MotionTile(
                key: ValueKey(r['id']),
                leading: AccentIcon(widget.icon, accent: active ? widget.accent : Accent.ocean, size: 42),
                title: str(r['title']),
                subtitle: str(r['content']).replaceAll(RegExp(r'\s+'), ' '),
                meta: [_targetLabel(r), if (parseDate(r['created_at']) != null) fmtDate(parseDate(r['created_at']))].join(' · '),
                trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  StatusPill(active ? 'Active' : 'Inactive', tone: active ? MarketTone.ok : MarketTone.neutral),
                  const SizedBox(height: 6),
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                ]),
                onTap: () => _detail(r),
                onLongPress: () => _form(r),
                onDelete: () => _delete(r),
              );
            },
          ),
      ],
    );
  }
}

class _PostDetail extends StatelessWidget {
  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> depts;
  final List<Map<String, dynamic>> emps;
  final Accent accent;
  final IconData icon;
  const _PostDetail({required this.row, required this.depts, required this.emps, required this.accent, required this.icon});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final t = str(row['target_type']).isEmpty ? 'ALL' : str(row['target_type']);
    final names = t == 'DEPARTMENTS'
        ? [for (final id in jsonList(row['department_ids'])) lookupName(depts, id).isEmpty ? '#$id' : lookupName(depts, id)]
        : t == 'EMPLOYEES'
            ? [
                for (final id in jsonList(row['employee_ids']))
                  () {
                    final e = emps.where((x) => x['id'].toString() == id.toString()).firstOrNull;
                    return e == null ? '#$id' : empName(e);
                  }(),
              ]
            : <String>[];
    final active = asBool(row['is_active'], fallback: true);
    return FormSheet(
      title: str(row['title']),
      subtitle: parseDate(row['created_at']) == null ? null : 'Created ${fmtDate(parseDate(row['created_at']))}',
      extraAction: IconButton(tooltip: 'Edit', onPressed: () => Navigator.pop(context, 'edit'), icon: Icon(Icons.edit_outlined, color: p.label)),
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          StatusPill(active ? 'Active' : 'Inactive', tone: active ? MarketTone.ok : MarketTone.neutral),
          StatusPill(_targetLabel(row), tone: MarketTone.brand, icon: Icons.groups_rounded),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
          child: SelectableText(str(row['content']), style: TextStyle(fontSize: 14, height: 1.55, color: p.text)),
        ),
        if (names.isNotEmpty) ...[
          const SizedBox(height: 14),
          SectionHeader(t == 'DEPARTMENTS' ? 'Departments' : 'Employees'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < names.length; i++)
              FadeSlideIn(
                index: i,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (_targetColors[t] ?? p.brand).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(names[i], style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _targetColors[t] ?? p.brand)),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: p.error,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(context, 'delete'),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: GradientButton(label: 'Edit', icon: Icons.edit_outlined, accent: accent, onTap: () => Navigator.pop(context, 'edit'))),
        ]),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 10),
      ],
    );
  }
}

class _PostForm extends StatefulWidget {
  final String endpoint;
  final String singular;
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> depts;
  final List<Map<String, dynamic>> emps;
  const _PostForm({required this.endpoint, required this.singular, this.existing, required this.depts, required this.emps});

  @override
  State<_PostForm> createState() => _PostFormState();
}

class _PostFormState extends State<_PostForm> {
  Map<String, dynamic>? get e => widget.existing;
  late final _title = TextEditingController(text: str(e?['title']));
  late final _content = TextEditingController(text: str(e?['content']));
  late bool _active = asBool(e?['is_active'], fallback: true);
  late String _target = str(e?['target_type']).isEmpty ? 'ALL' : str(e?['target_type']);
  late final Set<String> _deptIds = {for (final id in jsonList(e?['department_ids'])) id.toString()};
  late final Set<String> _empIds = {for (final id in jsonList(e?['employee_ids'])) id.toString()};
  String _q = '';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _content.text.trim().isEmpty) {
      marketToast(context, 'Title and content are required', error: true);
      return;
    }
    setState(() => _busy = true);
    List<Object> ids(Set<String> s) => [for (final x in s) int.tryParse(x) ?? x];
    final body = {
      'title': _title.text.trim(),
      'content': _content.text.trim(),
      'target_type': _target,
      'department_ids': _target == 'DEPARTMENTS' ? ids(_deptIds) : <Object>[],
      'employee_ids': _target == 'EMPLOYEES' ? ids(_empIds) : <Object>[],
      'is_active': _active,
    };
    try {
      final api = EntityApi(ApiClient(), widget.endpoint);
      if (e == null) {
        await api.create(body);
      } else {
        await api.update(e!['id'], body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(err, 'Failed to save ${widget.singular}'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final isDept = _target == 'DEPARTMENTS';
    final list = isDept ? widget.depts : widget.emps;
    final sel = isDept ? _deptIds : _empIds;
    final q = _q.trim().toLowerCase();
    final shown = list.where((r) => q.isEmpty || (isDept ? str(r['name']) : empLabel(r)).toLowerCase().contains(q)).toList();
    final color = _targetColors[_target]!;
    return FormSheet(
      title: e == null ? 'New ${widget.singular}' : 'Edit ${widget.singular}',
      busy: _busy,
      onSubmit: _save,
      submitLabel: e == null ? 'Publish' : 'Save changes',
      children: [
        SwitchField(label: 'Active', sub: 'Inactive items are hidden from employees', value: _active, onChanged: (v) => setState(() => _active = v)),
        FormLabel(label: 'Title', required: true, child: TextField(controller: _title, decoration: motionInput(context, hint: '${humanize(widget.singular)} title', icon: Icons.title_rounded))),
        FormLabel(
          label: 'Content',
          required: true,
          child: TextField(controller: _content, minLines: 5, maxLines: 12, decoration: motionInput(context, hint: '${humanize(widget.singular)} content')),
        ),
        FormLabel(
          label: 'Send to',
          child: Row(children: [
            for (final t in _targets) ...[
              Expanded(
                child: PressScale(
                  onTap: () => setState(() {
                    _target = t;
                    _q = '';
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _target == t ? _targetColors[t] : p.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(t == 'ALL' ? 'All' : humanize(t),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _target == t ? Colors.white : p.label)),
                  ),
                ),
              ),
              if (t != _targets.last) const SizedBox(width: 8),
            ],
          ]),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: _target == 'ALL'
              ? const SizedBox(width: double.infinity)
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Text(isDept ? 'Select departments' : 'Select employees', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.label)),
                    const SizedBox(width: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                      child: sel.isEmpty
                          ? const SizedBox.shrink()
                          : Container(
                              key: ValueKey(sel.length),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                              child: Text('${sel.length} selected', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
                            ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() {
                        final all = shown.map((r) => r['id'].toString()).toSet();
                        if (all.every(sel.contains)) {
                          sel.removeAll(all);
                        } else {
                          sel.addAll(all);
                        }
                      }),
                      child: Text(shown.isNotEmpty && shown.every((r) => sel.contains(r['id'].toString())) ? 'Clear' : 'Select all'),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  if (list.length > 6)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        key: ValueKey('search-$_target'),
                        onChanged: (v) => setState(() => _q = v),
                        decoration: motionInput(context, hint: 'Search', icon: Icons.search_rounded),
                      ),
                    ),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
                    child: shown.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(20),
                            child: Center(child: Text(isDept ? 'No departments found' : 'No employees found', style: TextStyle(fontSize: 12.5, color: p.label))),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: shown.length,
                            itemBuilder: (_, i) {
                              final r = shown[i];
                              final id = r['id'].toString();
                              final on = sel.contains(id);
                              return InkWell(
                                onTap: () => setState(() => on ? sel.remove(id) : sel.add(id)),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  decoration: BoxDecoration(color: on ? color.withValues(alpha: 0.10) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                                  child: Row(children: [
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: on ? color : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: on ? color : p.line, width: 1.6),
                                      ),
                                      child: on ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(isDept ? str(r['name']) : empLabel(r),
                                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: on ? color : p.text)),
                                    ),
                                  ]),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                ]),
        ),
      ],
    );
  }
}
