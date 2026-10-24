import 'package:flutter/material.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/supplier_service.dart';

// Supplier groups — port of desktop SupplierGroup.tsx: status / group code /
// group name / description, search, create, edit and delete (suppliers in a
// deleted group are ungrouped, not deleted).

const _statuses = [('ACTIVE', 'Active'), ('INACTIVE', 'Inactive')];

String _statusLabel(String s) => s == 'ACTIVE' ? 'Active' : (s == 'INACTIVE' ? 'Inactive' : humanize(s));

class SupplierGroupsPage extends StatefulWidget {
  const SupplierGroupsPage({super.key});

  @override
  State<SupplierGroupsPage> createState() => _SupplierGroupsPageState();
}

class _SupplierGroupsPageState extends State<SupplierGroupsPage> {
  final _service = SupplierService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _q = '';
  String _chip = 'All';

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
      final rows = await _service.loadGroups();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load supplier groups'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, bool Function(Map<String, dynamic>)> get _chips => {
        'All': (_) => true,
        'Active': (r) => str(r['status']) == 'ACTIVE',
        'Inactive': (r) => str(r['status']) != 'ACTIVE',
      };

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    final pred = _chips[_chip]!;
    return _rows.where((r) {
      if (!pred(r)) return false;
      if (q.isEmpty) return true;
      return [r['group_code'], r['group_name'], r['description']].map(str).join(' ').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openForm([Map<String, dynamic>? row]) async {
    final saved = await showMotionSheet<bool>(context, (_) => _GroupForm(service: _service, existing: row));
    if (saved == true) {
      if (mounted) marketToast(context, row == null ? 'Supplier group created' : 'Supplier group updated');
      _load();
    }
  }

  Future<bool> _delete(Map<String, dynamic> row) async {
    final ok = await confirmMarket(
      context,
      title: 'Delete supplier group?',
      message: 'Delete supplier group "${str(row['group_name'])}"? Suppliers in this group will be ungrouped, not deleted.',
    );
    if (!ok) return false;
    try {
      await _service.deleteGroup(row['id']);
      if (mounted) {
        setState(() => _rows.removeWhere((r) => r['id'] == row['id']));
        marketToast(context, 'Supplier group deleted');
      }
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete supplier group'), error: true);
      return false;
    }
  }

  Future<void> _more(Map<String, dynamic> row) async {
    final key = await showActionSheet(context, title: str(row['group_name']), actions: [
      (key: 'edit', label: 'Edit', icon: Icons.edit_outlined, destructive: false),
      (key: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted || key == null) return;
    if (key == 'edit') _openForm(row);
    if (key == 'delete') _delete(row);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final chips = _chips;
    return MotionScaffold(
      title: 'Supplier groups',
      subtitle: '${_rows.length} ${_rows.length == 1 ? 'group' : 'groups'}',
      icon: Icons.folder_outlined,
      onRefresh: _load,
      onFab: () => _openForm(),
      fabLabel: 'New',
      headerExtra: HeaderSearch(hint: 'Search code, name, description', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _chip,
              options: [for (final k in chips.keys) (id: k, label: k, count: _rows.where(chips[k]!).length)],
              onChanged: (v) => setState(() => _chip = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton()
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.folder_outlined,
            title: _rows.isEmpty ? 'No supplier groups yet' : 'No matches',
            message: _rows.isEmpty ? 'Group suppliers by what they supply.' : null,
            actionLabel: _rows.isEmpty ? 'New group' : null,
            onAction: _rows.isEmpty ? () => _openForm() : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final st = str(r['status']);
              return MotionTile(
                key: ValueKey(r['id']),
                leading: AccentIcon(Icons.folder_outlined, accent: accentFor(str(r['group_name'])), size: 40),
                title: str(r['group_name']),
                subtitle: str(r['description']).isEmpty ? null : str(r['description']),
                meta: str(r['group_code']),
                trailing: StatusPill(_statusLabel(st), tone: st == 'ACTIVE' ? MarketTone.ok : MarketTone.error),
                onTap: () => _openForm(r),
                onLongPress: () => _more(r),
                onDelete: () => _delete(r),
              );
            },
          ),
      ],
    );
  }
}

class _GroupForm extends StatefulWidget {
  final SupplierService service;
  final Map<String, dynamic>? existing;
  const _GroupForm({required this.service, this.existing});

  @override
  State<_GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends State<_GroupForm> {
  late final _code = TextEditingController(text: str(widget.existing?['group_code']));
  late final _name = TextEditingController(text: str(widget.existing?['group_name']));
  late final _desc = TextEditingController(text: str(widget.existing?['description']));
  late String _status = str(widget.existing?['status']).isEmpty ? 'ACTIVE' : str(widget.existing?['status']);
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_code.text.trim().isEmpty || _name.text.trim().isEmpty) {
      marketToast(context, 'Group code and group name are required', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.saveGroup({
        'group_code': _code.text.trim(),
        'group_name': _name.text.trim(),
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'status': _status,
      }, id: widget.existing?['id']);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, supplierErrorMessage(e, 'Failed to save supplier group', codeColumn: 'group_code', codeLabel: 'group code'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.existing != null;
    return FormSheet(
      title: edit ? 'Edit supplier group' : 'New supplier group',
      subtitle: edit ? str(widget.existing!['group_name']) : null,
      busy: _busy,
      submitLabel: edit ? 'Save changes' : 'Create',
      onSubmit: _save,
      children: [
        FormLabel(label: 'Group code', required: true, child: TextField(controller: _code, decoration: motionInput(context, hint: 'e.g. SG-001', icon: Icons.tag_rounded))),
        FormLabel(
          label: 'Group name',
          required: true,
          child: TextField(controller: _name, textCapitalization: TextCapitalization.sentences, decoration: motionInput(context, hint: 'Enter group name', icon: Icons.folder_outlined)),
        ),
        FormLabel(
          label: 'Status',
          child: Wrap(spacing: 8, children: [
            for (final s in _statuses) ChoiceChip(label: Text(s.$2), selected: _status == s.$1, onSelected: (_) => setState(() => _status = s.$1)),
          ]),
        ),
        FormLabel(label: 'Description', child: TextField(controller: _desc, minLines: 3, maxLines: 6, decoration: motionInput(context, hint: 'Optional'))),
      ],
    );
  }
}
