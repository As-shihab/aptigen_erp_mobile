import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'hr_extras.dart';

// Leave types — port of desktop LeaveType.tsx: leave_types CRUD plus each
// type's approval chain (leave_type_has_middleman), opened by tapping a type.

EntityConfig _leaveTypeConfig() => EntityConfig(
      title: 'Leave types',
      endpoint: 'leave_types',
      icon: Icons.beach_access_rounded,
      accent: Accent.ocean,
      searchKeys: const ['name', 'code'],
      fields: const [
        EntityField('name', 'Name', required: true, hint: 'e.g. Annual leave'),
        EntityField('code', 'Code', hint: 'e.g. AL'),
        EntityField('max_days_per_year', 'Max days per year', kind: EField.number, defaultValue: 0, icon: Icons.event_available_rounded),
        EntityField('is_paid', 'Paid leave', kind: EField.toggle, defaultValue: true),
        EntityField('requires_document', 'Requires document', kind: EField.toggle, defaultValue: false),
        EntityField('carry_forward', 'Carry forward', kind: EField.toggle, defaultValue: false, hint: 'Unused days move to next year'),
        EntityField('carry_forward_max', 'Max carry forward days',
            kind: EField.number, hint: 'Leave blank for unlimited', visibleWhen: _carry),
        EntityField('is_active', 'Active', kind: EField.toggle, defaultValue: true),
      ],
      beforeSave: (body, _) => {
        ...body,
        'max_days_per_year': body['max_days_per_year'] ?? 0,
        'carry_forward_max': body['carry_forward'] == true ? body['carry_forward_max'] : null,
      },
      rowSubtitle: (r, _) => [
        if (str(r['code']).isNotEmpty) str(r['code']),
        '${str(r['max_days_per_year']).isEmpty ? 0 : r['max_days_per_year']} days per year',
      ].join(' · '),
      rowMeta: (r, _) => [
        asBool(r['is_paid'], fallback: true) ? 'Paid' : 'Unpaid',
        if (asBool(r['carry_forward'])) 'Carry forward${r['carry_forward_max'] != null ? ' up to ${r['carry_forward_max']}' : ''}',
        if (asBool(r['requires_document'])) 'Document required',
      ].join(' · '),
      rowTitle: _rowName,
      chipFilters: {
        'Paid': (r) => asBool(r['is_paid'], fallback: true),
        'Unpaid': (r) => !asBool(r['is_paid'], fallback: true),
      },
      detailPage: (r) => _ApprovalChainPage(leaveType: r),
    );

bool _carry(Map<String, dynamic> v) => asBool(v['carry_forward']);
String _rowName(Map<String, dynamic> r) => str(r['name']);

class LeaveTypesPage extends StatelessWidget {
  const LeaveTypesPage({super.key});

  @override
  Widget build(BuildContext context) => EntityListPage(config: _leaveTypeConfig());
}

// ── Approval chain ──────────────────────────────────────────────────────

class _ApprovalChainPage extends StatefulWidget {
  final Map<String, dynamic> leaveType;
  const _ApprovalChainPage({required this.leaveType});

  @override
  State<_ApprovalChainPage> createState() => _ApprovalChainPageState();
}

class _ApprovalChainPageState extends State<_ApprovalChainPage> {
  final _client = ApiClient();
  late final _api = EntityApi(_client, 'leave_type_has_middleman');
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _chain = [];
  List<Map<String, dynamic>> _emps = [];
  List<Map<String, dynamic>> _des = [];

  Map<String, dynamic> get lt => widget.leaveType;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _chain.isEmpty;
      _error = null;
    });
    try {
      final d = await batchLoad(_client, {
        'chain':
            'leave_type_has_middleman?\$filter=leave_type_id eq ${lt['id']}&\$expand=approver_emp(\$select=id,first_name,last_name),approver_des(\$select=id,name)&\$orderby=serial asc&\$top=50',
        'emps': 'employees?\$select=id,first_name,last_name,employee_no&\$filter=is_active eq true&\$top=500',
        'des': 'designations?\$select=id,name&\$filter=is_active eq true&\$top=200',
      });
      if (!mounted) return;
      setState(() {
        _chain = d['chain'] ?? [];
        _emps = d['emps'] ?? [];
        _des = d['des'] ?? [];
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load approval chain'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _form([Map<String, dynamic>? row]) async {
    final next = _chain.isEmpty ? 1 : _chain.map((m) => toInt(m['serial'])).reduce((a, b) => a > b ? a : b) + 1;
    final ok = await showMotionSheet<bool>(
      context,
      (_) => _ApproverSheet(leaveTypeId: lt['id'], existing: row, nextSerial: next, emps: _emps, des: _des),
    );
    if (ok == true) {
      if (mounted) marketToast(context, row == null ? 'Approver added' : 'Approver updated');
      _load();
    }
  }

  Future<bool> _delete(Map<String, dynamic> row) async {
    final ok = await confirmMarket(context, title: 'Remove approver?', message: 'Remove "${str(row['label'])}" from the approval chain?', confirm: 'Remove');
    if (!ok) return false;
    try {
      await _api.delete(row['id']);
      if (mounted) {
        setState(() => _chain.removeWhere((r) => r['id'] == row['id']));
        marketToast(context, 'Approver removed');
      }
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not remove'), error: true);
      return false;
    }
  }

  Future<void> _editType() async {
    final ok = await showMotionSheet<bool>(context, (_) => EntityFormSheet(config: _leaveTypeConfig(), lookups: const {}, existing: lt));
    if (ok == true && mounted) {
      marketToast(context, 'Leave type updated');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MotionScaffold(
      title: str(lt['name']),
      subtitle: 'Approval chain · ${_chain.length} ${_chain.length == 1 ? 'step' : 'steps'}',
      icon: Icons.account_tree_rounded,
      accent: Accent.ocean,
      onRefresh: _load,
      onFab: () => _form(),
      fabLabel: 'Add approver',
      fabIcon: Icons.person_add_alt_1_rounded,
      actions: [IconButton(tooltip: 'Edit leave type', icon: const Icon(Icons.edit_outlined), onPressed: _editType)],
      slivers: [
        sliverBox(
          GlowCard(
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              StatusPill(asBool(lt['is_active'], fallback: true) ? 'Active' : 'Inactive',
                  tone: asBool(lt['is_active'], fallback: true) ? MarketTone.ok : MarketTone.neutral),
              StatusPill(asBool(lt['is_paid'], fallback: true) ? 'Paid' : 'Unpaid', tone: MarketTone.info),
              StatusPill('${lt['max_days_per_year'] ?? 0} days per year', tone: MarketTone.brand),
              if (asBool(lt['carry_forward'])) StatusPill('Carry forward', tone: MarketTone.ok),
              if (asBool(lt['requires_document'])) StatusPill('Document required', tone: MarketTone.warn),
            ]),
          ),
        ),
        sliverBox(SectionHeader('Approvers', subtitle: 'Requests move through these steps in order')),
        if (_loading)
          sliverSkeleton(count: 3)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (_chain.isEmpty)
          sliverEmpty(icon: Icons.account_tree_outlined, title: 'No approvers yet', message: 'Add the first approval step for this leave type.', actionLabel: 'Add approver', onAction: _form)
        else
          sliverStagger(
            count: _chain.length,
            gap: 0,
            builder: (_, i) {
              final m = _chain[i];
              final emp = empName(m['approver_emp']);
              final des = nested(m, 'approver_des');
              return IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(
                    width: 40,
                    child: Column(children: [
                      Expanded(child: Container(width: 2, color: i == 0 ? Colors.transparent : p.line)),
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(gradient: Accent.ocean.gradient, shape: BoxShape.circle),
                        child: Text('${m['serial']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                      Expanded(child: Container(width: 2, color: i == _chain.length - 1 ? Colors.transparent : p.line)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: MotionTile(
                        title: str(m['label']),
                        subtitle: emp.isNotEmpty ? emp : (des.isNotEmpty ? 'Any $des' : 'Any approver'),
                        meta: [if (emp.isNotEmpty && des.isNotEmpty) 'Designation: $des'].join(),
                        trailing: StatusPill(asBool(m['is_required'], fallback: true) ? 'Required' : 'Optional',
                            tone: asBool(m['is_required'], fallback: true) ? MarketTone.brand : MarketTone.neutral),
                        onTap: () => _form(m),
                        onDelete: () => _delete(m),
                      ),
                    ),
                  ),
                ]),
              );
            },
          ),
      ],
    );
  }
}

class _ApproverSheet extends StatefulWidget {
  final dynamic leaveTypeId;
  final Map<String, dynamic>? existing;
  final int nextSerial;
  final List<Map<String, dynamic>> emps;
  final List<Map<String, dynamic>> des;
  const _ApproverSheet({required this.leaveTypeId, this.existing, required this.nextSerial, required this.emps, required this.des});

  @override
  State<_ApproverSheet> createState() => _ApproverSheetState();
}

class _ApproverSheetState extends State<_ApproverSheet> {
  late int _serial = toInt(widget.existing?['serial'] ?? widget.nextSerial);
  late bool _required = asBool(widget.existing?['is_required'], fallback: true);
  late final _label = TextEditingController(text: str(widget.existing?['label']));
  late Object? _emp = widget.existing?['approver_emp_id'] ?? (widget.existing?['approver_emp'] as Map?)?['id'];
  late Object? _des = widget.existing?['approver_des_id'] ?? (widget.existing?['approver_des'] as Map?)?['id'];
  bool _busy = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_label.text.trim().isEmpty) {
      marketToast(context, 'Approver label is required', error: true);
      return;
    }
    setState(() => _busy = true);
    final body = {
      'leave_type_id': widget.leaveTypeId,
      'serial': _serial,
      'label': _label.text.trim(),
      'approver_emp_id': _emp,
      'approver_des_id': _des,
      'is_required': _required,
    };
    try {
      final api = EntityApi(ApiClient(), 'leave_type_has_middleman');
      if (widget.existing == null) {
        await api.create(body);
      } else {
        await api.update(widget.existing!['id'], body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(e, 'Could not save approver'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => FormSheet(
        title: widget.existing == null ? 'Add approver' : 'Edit approver',
        busy: _busy,
        onSubmit: _save,
        submitLabel: widget.existing == null ? 'Add approver' : 'Update approver',
        children: [
          FormLabel(label: 'Serial (order)', required: true, child: StepperField(value: _serial, min: 1, max: 99, onChanged: (v) => setState(() => _serial = v))),
          FormLabel(
            label: 'Approver label',
            required: true,
            child: TextField(controller: _label, decoration: motionInput(context, hint: 'e.g. Line manager, HR head', icon: Icons.badge_outlined)),
          ),
          SwitchField(label: 'Required', sub: 'Optional steps are advisory only', value: _required, onChanged: (v) => setState(() => _required = v)),
          FormLabel(
            label: 'Fixed employee (optional)',
            child: PickerField(
              value: _emp,
              hint: 'Any employee',
              icon: Icons.person_outline_rounded,
              options: [for (final e in widget.emps) PickOption(e['id'], empLabel(e))],
              onChanged: (v) => setState(() => _emp = v),
            ),
          ),
          FormLabel(
            label: 'Designation (optional)',
            child: PickerField(
              value: _des,
              hint: 'Any designation',
              icon: Icons.work_outline_rounded,
              options: [for (final d in widget.des) PickOption(d['id'], str(d['name']))],
              onChanged: (v) => setState(() => _des = v),
            ),
          ),
        ],
      );
}
