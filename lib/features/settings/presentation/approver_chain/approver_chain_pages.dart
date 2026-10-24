import 'package:flutter/material.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/settings_service.dart';
import '../widgets/settings_widgets.dart';

/// Settings → Approver chain. Desktop ApproverChain.tsx shows approve types
/// on the left and the selected type's ordered approvers on the right. On
/// the phone: the approve types list (CRUD with active filter), tapping one
/// opens its chain as a reorderable step timeline.
class ApproveTypesPage extends StatelessWidget {
  const ApproveTypesPage({super.key});

  @override
  Widget build(BuildContext context) => EntityListPage(
        config: EntityConfig(
          title: 'Approver chain',
          subtitle: 'Approval flows used by requisitions, orders and more',
          endpoint: 'approve_types',
          icon: Icons.link_rounded,
          accent: Accent.emerald,
          fields: const [
            EntityField('is_active', 'Active', kind: EField.toggle, defaultValue: true),
            EntityField('name', 'Name', required: true, hint: 'e.g. SPR, SR', icon: Icons.label_outline_rounded),
            EntityField('description', 'Description', kind: EField.multiline, hint: 'Optional'),
          ],
          expand: 'approvers(\$select=id)',
          rowTitle: (r) => str(r['name']),
          rowSubtitle: (r, _) => str(r['description']).isEmpty ? null : str(r['description']),
          rowMeta: (r, _) {
            final n = r['approvers'] is List ? (r['approvers'] as List).length : 0;
            return n == 0 ? 'No approvers yet' : '$n ${n == 1 ? 'step' : 'steps'} in chain';
          },
          rowLeading: (r) => AccentIcon(Icons.account_tree_outlined, accent: accentFor(str(r['name'])), size: 40),
          searchKeys: const ['name', 'description'],
          beforeSave: (p, _) => {
            ...p,
            'description': (p['description'] as String?)?.trim().isEmpty ?? true ? null : (p['description'] as String).trim(),
          },
          detailPage: (r) => ApproverChainPage(type: r),
          rowActions: [
            RowAction('Open chain', Icons.timeline_rounded, (ctx, r) async {
              await pushMotion(ctx, ApproverChainPage(type: r));
              return true;
            }),
          ],
        ),
      );
}

String empLabel(Map e) {
  final name = '${str(e['first_name'])} ${str(e['last_name'])}'.trim();
  final no = str(e['employee_no']);
  return no.isEmpty ? name : '$name ($no)';
}

String _memberLabel(Map m) {
  final u = m['user'];
  if (u is Map) return str(u['name']).isNotEmpty ? str(u['name']) : str(u['email']);
  return 'Member #${str(m['id'])}';
}

class ApproverChainPage extends StatefulWidget {
  final JsonRow type;
  const ApproverChainPage({super.key, required this.type});

  @override
  State<ApproverChainPage> createState() => _ApproverChainPageState();
}

class _ApproverChainPageState extends State<ApproverChainPage> {
  final _svc = ApproverService();
  List<JsonRow> _rows = [];
  Map<String, List<JsonRow>>? _refs;
  bool _loading = true;
  bool _reordering = false;
  String? _error;

  int get _typeId => positiveInt(widget.type['id']) ?? 0;

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
      final rows = await _svc.approvers(_typeId);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load the approval chain'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, List<JsonRow>>> _ensureRefs() async {
    if (_refs != null) return _refs!;
    try {
      _refs = await _svc.refs();
    } catch (_) {
      _refs = {};
    }
    return _refs!;
  }

  Future<void> _form([JsonRow? row]) async {
    final refs = await _ensureRefs();
    if (!mounted) return;
    final nextSerial = _rows.isEmpty ? 1 : _rows.map((r) => toInt(r['serial'])).reduce((a, b) => a > b ? a : b) + 1;
    final ok = await showMotionSheet<bool>(context, (_) => _ApproverForm(typeId: _typeId, row: row, nextSerial: nextSerial, refs: refs, svc: _svc));
    if (ok == true) {
      if (mounted) marketToast(context, row == null ? 'Approver added' : 'Approver updated');
      _load();
    }
  }

  Future<bool> _delete(JsonRow r) async {
    final ok = await confirmMarket(context, title: 'Remove approver?', message: '"${str(r['label'])}" will be removed from this chain.', confirm: 'Remove');
    if (!ok) return false;
    try {
      await _svc.delete(positiveInt(r['id'])!);
      if (!mounted) return true;
      marketToast(context, 'Approver removed');
      _load();
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not remove approver'), error: true);
      return false;
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    if (oldIndex == newIndex) return;
    final prev = [..._rows];
    final next = [..._rows];
    next.insert(newIndex, next.removeAt(oldIndex));
    setState(() {
      _rows = next;
      _reordering = true;
    });
    try {
      await _svc.resequence(next);
      if (!mounted) return;
      marketToast(context, 'Order updated');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _rows = prev);
      marketToast(context, errorMessage(e, 'Could not reorder'), error: true);
      _load();
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  String _who(JsonRow r) {
    final parts = <String>[];
    if (r['approver_emp'] is Map) parts.add('Employee: ${empLabel(r['approver_emp'] as Map)}');
    if (r['approver_des'] is Map) parts.add('Designation: ${str((r['approver_des'] as Map)['name'])}');
    if (r['workplace_member'] is Map) parts.add('Member: ${_memberLabel(r['workplace_member'] as Map)}');
    return parts.isEmpty ? 'Anyone can approve' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final required = _rows.where((r) => asBool(r['is_required'], fallback: true)).length;
    return MotionScaffold(
      title: str(widget.type['name']),
      subtitle: _rows.isEmpty ? 'No approvers yet' : '${_rows.length} steps · $required required',
      icon: Icons.timeline_rounded,
      accent: Accent.emerald,
      onRefresh: _load,
      onFab: () => _form(),
      fabLabel: 'Add approver',
      fabIcon: Icons.person_add_alt_rounded,
      actions: [
        if (_reordering) const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
      ],
      slivers: [
        if (str(widget.type['description']).isNotEmpty)
          sliverBox(Text(str(widget.type['description']), style: TextStyle(fontSize: 13, color: p.label)), padding: const EdgeInsets.fromLTRB(18, 14, 18, 0)),
        if (_loading)
          sliverSkeleton(count: 4, height: 84)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (_rows.isEmpty)
          sliverEmpty(icon: Icons.account_tree_outlined, title: 'No approvers yet', message: 'Add the first approver. Requests move through steps in order.', actionLabel: 'Add approver', onAction: () => _form())
        else ...[
          sliverBox(
            Row(children: [
              Icon(Icons.drag_indicator_rounded, size: 16, color: p.label),
              const SizedBox(width: 6),
              Expanded(child: Text('Long-press and drag a step to change the order.', style: TextStyle(fontSize: 12, color: p.label))),
            ]),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverReorderableList(
              itemCount: _rows.length,
              onReorder: _reordering ? (_, _) {} : _reorder,
              proxyDecorator: (child, _, anim) => AnimatedBuilder(
                animation: anim,
                builder: (_, c) => Transform.scale(scale: 1 + 0.03 * anim.value, child: Material(color: Colors.transparent, child: c)),
                child: child,
              ),
              itemBuilder: (_, i) {
                final r = _rows[i];
                final isReq = asBool(r['is_required'], fallback: true);
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(r['id']),
                  index: i,
                  enabled: !_reordering,
                  child: FadeSlideIn(
                    index: i,
                    child: IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SizedBox(
                          width: 40,
                          child: Column(children: [
                            Expanded(child: Container(width: 2, color: i == 0 ? Colors.transparent : p.line)),
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(gradient: Accent.ocean.gradient, shape: BoxShape.circle, boxShadow: [
                                BoxShadow(color: Accent.emerald.primary.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3)),
                              ]),
                              child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                            ),
                            Expanded(child: Container(width: 2, color: i == _rows.length - 1 ? Colors.transparent : p.line)),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: MotionTile(
                              title: str(r['label']),
                              subtitle: _who(r),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                StatusPill(isReq ? 'Required' : 'Optional', tone: isReq ? MarketTone.ok : MarketTone.neutral),
                                const SizedBox(width: 4),
                                Icon(Icons.drag_handle_rounded, color: p.label, size: 20),
                              ]),
                              onTap: () => _form(r),
                              onDelete: () => _delete(r),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _ApproverForm extends StatefulWidget {
  final int typeId;
  final JsonRow? row;
  final int nextSerial;
  final Map<String, List<JsonRow>> refs;
  final ApproverService svc;
  const _ApproverForm({required this.typeId, this.row, required this.nextSerial, required this.refs, required this.svc});

  @override
  State<_ApproverForm> createState() => _ApproverFormState();
}

class _ApproverFormState extends State<_ApproverForm> {
  late final _serial = TextEditingController(text: '${widget.row == null ? widget.nextSerial : toInt(widget.row!['serial'])}');
  late final _label = TextEditingController(text: str(widget.row?['label']));
  late bool _required = widget.row == null ? true : asBool(widget.row!['is_required'], fallback: true);
  late Object? _emp = positiveInt(widget.row?['approver_emp_id'] ?? (widget.row?['approver_emp'] is Map ? widget.row!['approver_emp']['id'] : null));
  late Object? _des = positiveInt(widget.row?['approver_des_id'] ?? (widget.row?['approver_des'] is Map ? widget.row!['approver_des']['id'] : null));
  late Object? _member = positiveInt(widget.row?['workplace_member_id'] ?? (widget.row?['workplace_member'] is Map ? widget.row!['workplace_member']['id'] : null));
  bool _busy = false;

  @override
  void dispose() {
    _serial.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    if (label.isEmpty) {
      marketToast(context, 'Approver label is required', error: true);
      return;
    }
    final serial = int.tryParse(_serial.text.trim()) ?? 1;
    setState(() => _busy = true);
    try {
      await widget.svc.save({
        'approve_type_id': widget.typeId,
        'serial': serial < 1 ? 1 : serial,
        'label': label,
        'approver_emp_id': _emp,
        'approver_des_id': _des,
        'workplace_member_id': _member,
        'is_required': _required,
      }, id: positiveInt(widget.row?['id']));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      marketToast(context, errorMessage(e, 'Could not save approver. Each step needs a unique order number.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final emps = widget.refs['employees'] ?? const [];
    final dess = widget.refs['designations'] ?? const [];
    final members = widget.refs['members'] ?? const [];
    return FormSheet(
      title: widget.row == null ? 'Add approver' : 'Edit approver',
      subtitle: 'Leave employee, designation and member empty to let anyone approve',
      busy: _busy,
      onSubmit: _save,
      submitLabel: widget.row == null ? 'Add approver' : 'Save approver',
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 110,
            child: FormLabel(
              label: 'Order',
              required: true,
              child: TextField(controller: _serial, keyboardType: TextInputType.number, decoration: motionInput(context, icon: Icons.format_list_numbered_rounded)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FormLabel(
              label: 'Approver label',
              required: true,
              child: TextField(controller: _label, textCapitalization: TextCapitalization.sentences, decoration: motionInput(context, hint: 'e.g. Store manager')),
            ),
          ),
        ]),
        SwitchField(label: 'Required', sub: 'If off, this approval is advisory and can be skipped', value: _required, onChanged: (v) => setState(() => _required = v)),
        FormLabel(
          label: 'Fixed employee',
          child: PickerField(
            value: _emp,
            hint: 'Any employee',
            icon: Icons.badge_outlined,
            options: [for (final e in emps) PickOption(e['id'], empLabel(e))],
            onChanged: (v) => setState(() => _emp = v),
          ),
        ),
        FormLabel(
          label: 'Designation',
          child: PickerField(
            value: _des,
            hint: 'Any designation',
            icon: Icons.workspace_premium_outlined,
            options: [for (final d in dess) PickOption(d['id'], str(d['name']))],
            onChanged: (v) => setState(() => _des = v),
          ),
        ),
        FormLabel(
          label: 'Workplace member',
          help: 'For owners or admins who have no employee record.',
          child: PickerField(
            value: _member,
            hint: 'Any member',
            icon: Icons.person_outline_rounded,
            options: [for (final m in members) PickOption(m['id'], _memberLabel(m), sub: m['user'] is Map ? str(m['user']['email']) : null)],
            onChanged: (v) => setState(() => _member = v),
          ),
        ),
        if (emps.isEmpty && dess.isEmpty && members.isEmpty)
          const NoteBanner(title: 'Lookups unavailable', message: 'Employees, designations and members could not be loaded. You can still save a label-only step.', tone: MarketTone.warn),
      ],
    );
  }
}
