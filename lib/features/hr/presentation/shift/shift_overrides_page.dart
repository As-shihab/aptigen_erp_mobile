import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'shift_common.dart';

/// Shift override log — mirrors erp/desktop hrm/shift/shift-replacement/
/// ShiftReplacement.tsx: list of shift_overrides (date, type, shift, absent
/// and replacement employee), log a new override through
/// POST /api/hrm/shift-overrides, delete through OData.
class ShiftOverridesPage extends StatefulWidget {
  const ShiftOverridesPage({super.key});

  @override
  State<ShiftOverridesPage> createState() => _ShiftOverridesPageState();
}

const _types = ['REPLACEMENT', 'SWAP', 'EXTRA'];

MarketTone _typeTone(String t) => switch (t) {
      'REPLACEMENT' => MarketTone.warn,
      'SWAP' => MarketTone.brand,
      'EXTRA' => MarketTone.ok,
      _ => MarketTone.neutral,
    };

IconData _typeIcon(String t) => switch (t) {
      'SWAP' => Icons.swap_horiz_rounded,
      'EXTRA' => Icons.person_add_alt_1_rounded,
      _ => Icons.sync_alt_rounded,
    };

Accent _typeAccent(String t) => switch (t) {
      'SWAP' => Accent.ocean,
      'EXTRA' => Accent.emerald,
      _ => Accent.sunset,
    };

class _ShiftOverridesPageState extends State<ShiftOverridesPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _shifts = [];
  List<Map<String, dynamic>> _employees = [];
  String _q = '';
  String _type = 'All';

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
        'rows': 'shift_overrides?\$expand=shift(\$select=id,name,color),second_shift(\$select=id,name,color),'
            'absent_employee(\$select=id,first_name,last_name,employee_no,profile_photo),'
            'replacement_employee(\$select=id,first_name,last_name,employee_no,profile_photo)&\$orderby=${Uri.encodeComponent('id desc')}&\$top=500',
        'shifts': 'employee_shifts?\$select=id,name,color,start_time,end_time&\$filter=${Uri.encodeComponent('is_active eq true')}&\$top=200',
        'employees': 'employees?\$select=id,first_name,last_name,employee_no&\$filter=${Uri.encodeComponent('is_active eq true')}&\$top=500',
      });
      if (!mounted) return;
      setState(() {
        _rows = data['rows'] ?? [];
        _shifts = data['shifts'] ?? [];
        _employees = data['employees'] ?? [];
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load shift overrides'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    return _rows.where((r) {
      if (_type != 'All' && str(r['type']) != _type) return false;
      if (q.isEmpty) return true;
      final hay = [
        str(nested(r, 'shift')),
        personName(r['absent_employee']),
        personName(r['replacement_employee']),
        str((r['absent_employee'] as Map?)?['employee_no']),
        str((r['replacement_employee'] as Map?)?['employee_no']),
        str(r['type']),
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<bool> _delete(Map<String, dynamic> row) async {
    final ok = await confirmMarket(context, title: 'Remove this shift override?', message: 'The roster goes back to its regular assignment for that day.', confirm: 'Remove');
    if (!ok) return false;
    try {
      await _client.delete('shift_overrides', row['id']);
      if (mounted) {
        setState(() => _rows.removeWhere((r) => r['id'] == row['id']));
        marketToast(context, 'Override removed');
      }
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not remove override'), error: true);
      return false;
    }
  }

  Future<void> _create() async {
    final saved = await showMotionSheet<bool>(context, (_) => _OverrideForm(client: _client, shifts: _shifts, employees: _employees));
    if (saved == true) {
      if (mounted) marketToast(context, 'Override logged');
      _load();
    }
  }

  Future<void> _details(Map<String, dynamic> r) async {
    final type = str(r['type']);
    final remove = await showMotionSheet<bool>(context, (ctx) {
      final p = MarketPalette.of(ctx);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetGrabber(),
            Row(children: [
              AccentIcon(_typeIcon(type), accent: _typeAccent(type)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(humanize(type), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
                  Text(fmtDate(calDate(r['date'])), style: TextStyle(fontSize: 12.5, color: p.label)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            InfoRow('Shift', nested(r, 'shift').isEmpty ? '—' : nested(r, 'shift')),
            if (r['second_shift'] is Map) InfoRow('From shift', nested(r, 'second_shift')),
            InfoRow('Absent employee', personName(r['absent_employee']).isEmpty ? '—' : personName(r['absent_employee'])),
            InfoRow('Replacement', personName(r['replacement_employee']).isEmpty ? '—' : personName(r['replacement_employee'])),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: Icon(Icons.delete_outline_rounded, color: p.error),
              label: Text('Remove override', style: TextStyle(color: p.error, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                side: BorderSide(color: p.error.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ]),
        ),
      );
    });
    if (remove == true) await _delete(r);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    return MotionScaffold(
      title: 'Shift overrides',
      subtitle: '${_rows.length} logged ${_rows.length == 1 ? 'override' : 'overrides'}',
      icon: Icons.swap_horiz_rounded,
      accent: Accent.ocean,
      onRefresh: _load,
      onFab: _create,
      fabLabel: 'Log override',
      headerExtra: HeaderSearch(hint: 'Search shift or employee', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _type,
              options: [
                (id: 'All', label: 'All', count: _rows.length),
                for (final t in _types) (id: t, label: humanize(t), count: _rows.where((r) => r['type'] == t).length),
              ],
              onChanged: (v) => setState(() => _type = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton()
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.swap_horiz_rounded,
            title: _rows.isEmpty ? 'No overrides yet' : 'No matches',
            message: _rows.isEmpty ? 'Log a replacement, swap or extra assignment.' : null,
            actionLabel: _rows.isEmpty ? 'Log override' : null,
            onAction: _rows.isEmpty ? _create : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final type = str(r['type']);
              final absent = personName(r['absent_employee']);
              final repl = personName(r['replacement_employee']);
              final shiftName = nested(r, 'shift');
              return MotionTile(
                key: ValueKey(r['id']),
                leading: AccentIcon(_typeIcon(type), accent: _typeAccent(type), size: 40),
                title: shiftName.isEmpty ? 'No shift' : shiftName,
                subtitle: [
                  if (absent.isNotEmpty) 'Absent: $absent',
                  if (repl.isNotEmpty) 'Covered by: $repl',
                ].join('  ·  '),
                meta: fmtDate(calDate(r['date'])),
                trailing: StatusPill(humanize(type), tone: _typeTone(type)),
                onTap: () => _details(r),
                onDelete: () => _delete(r),
              );
            },
          ),
      ],
    );
  }
}

class _OverrideForm extends StatefulWidget {
  final ApiClient client;
  final List<Map<String, dynamic>> shifts;
  final List<Map<String, dynamic>> employees;
  const _OverrideForm({required this.client, required this.shifts, required this.employees});

  @override
  State<_OverrideForm> createState() => _OverrideFormState();
}

class _OverrideFormState extends State<_OverrideForm> {
  DateTime? _date = DateTime.now();
  String _type = 'REPLACEMENT';
  Object? _shift;
  Object? _absent;
  Object? _replacement;
  bool _busy = false;

  Future<void> _save() async {
    if (_date == null || _shift == null) {
      marketToast(context, 'Date and shift are required', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.client.post('hrm/shift-overrides', {
        'shift_id': _shift,
        'type': _type,
        'absent_employee_id': _absent,
        'replacement_employee_id': _replacement,
        'date': ymd(_date!),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(e, 'Could not save override'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final emps = [for (final e in widget.employees) employeeOption(e)];
    return FormSheet(
      title: 'Log shift override',
      subtitle: 'Record a replacement, swap or extra hand',
      busy: _busy,
      onSubmit: _date != null && _shift != null ? _save : null,
      submitLabel: 'Save override',
      children: [
        FormLabel(label: 'Date', required: true, child: DatePickField(value: _date, onChanged: (d) => setState(() => _date = d))),
        FormLabel(
          label: 'Type',
          required: true,
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in _types)
              ChoiceChip(
                avatar: Icon(_typeIcon(t), size: 16),
                label: Text(humanize(t)),
                selected: _type == t,
                onSelected: (_) => setState(() => _type = t),
              ),
          ]),
        ),
        FormLabel(
          label: 'Shift',
          required: true,
          child: PickerField(
            value: _shift,
            hint: 'Select shift',
            icon: Icons.schedule_rounded,
            options: [for (final s in widget.shifts) PickOption(s['id'], str(s['name']), sub: '${clock(s['start_time'])} to ${clock(s['end_time'])}')],
            onChanged: (v) => setState(() => _shift = v),
          ),
        ),
        FormLabel(
          label: 'Absent employee',
          child: PickerField(value: _absent, hint: 'Select absent employee', icon: Icons.person_off_outlined, options: emps, onChanged: (v) => setState(() => _absent = v)),
        ),
        FormLabel(
          label: 'Replacement employee',
          child: PickerField(value: _replacement, hint: 'Select replacement', icon: Icons.person_add_alt_outlined, options: emps, onChanged: (v) => setState(() => _replacement = v)),
        ),
      ],
    );
  }
}
