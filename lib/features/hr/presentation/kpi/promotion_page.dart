import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../leave/hr_extras.dart';

// Promotion — port of desktop Promotion.tsx. One list merging employees
// who are past the promotion_config eligibility window (pending, from
// /api/hrm/promotion-eligibility) and the append-only promotions log
// (approved). Creating a promotion also moves the employee's designation
// and, with a raise, scales every employee_salaries component.

class _Emp {
  final Object id;
  final String label;
  final Object? designationId;
  final String designationName;
  final Object? salaryId;
  final Map<String, double>? components;
  _Emp(this.id, this.label, this.designationId, this.designationName, this.salaryId, this.components);
  double get gross => components == null ? 0 : components!.values.fold(0.0, (a, b) => a + b);
}

const _salaryKeys = ['basic', 'house_rent', 'medical_allowance', 'transport_allowance', 'other_allowance'];

double _r2(double n) => (n * 100).roundToDouble() / 100;

class PromotionPage extends StatefulWidget {
  const PromotionPage({super.key});

  @override
  State<PromotionPage> createState() => _PromotionPageState();
}

class _PromotionPageState extends State<PromotionPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  bool _hasPromotion = true;
  List<Map<String, dynamic>> _promotions = [];
  List<Map<String, dynamic>> _eligible = [];
  List<_Emp> _emps = [];
  List<Map<String, dynamic>> _des = [];
  String _chip = 'all';
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _promotions.isEmpty && _eligible.isEmpty;
      _error = null;
    });
    try {
      final results = await Future.wait([
        batchLoad(_client, {
          'promotions': 'promotions?\$expand=employee,from_designation,to_designation&\$orderby=id desc&\$top=1000',
          'emps': 'employees?\$select=id,employee_no,first_name,last_name,designation_id&\$filter=is_active eq true&\$expand=designation,salary&\$top=2000',
          'des': 'designations?\$select=id,name&\$filter=is_active eq true&\$top=500',
        }),
        _client.get('hrm/promotion-eligibility', isV8: false),
      ]);
      final d = results[0] as Map<String, List<Map<String, dynamic>>>;
      final elig = results[1];
      if (!mounted) return;
      setState(() {
        _promotions = d['promotions'] ?? [];
        _des = d['des'] ?? [];
        _emps = [
          for (final e in d['emps'] ?? <Map<String, dynamic>>[])
            _Emp(
              e['id'],
              '${str(e['employee_no']).isEmpty ? '' : '${e['employee_no']} - '}${empName(e)}',
              e['designation_id'],
              nested(e, 'designation'),
              e['salary'] is Map ? (e['salary'] as Map)['id'] : null,
              e['salary'] is Map ? {for (final k in _salaryKeys) k: toDouble((e['salary'] as Map)[k])} : null,
            ),
        ];
        _hasPromotion = elig is Map ? asBool(elig['has_promotion'], fallback: true) : true;
        _eligible = elig is Map && elig['rows'] is List ? (elig['rows'] as List).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList() : [];
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load promotions'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<({bool eligible, Map<String, dynamic> row})> get _items {
    final q = _q.trim().toLowerCase();
    final all = [
      if (_chip != 'approved') for (final e in _eligible) (eligible: true, row: e),
      if (_chip != 'pending') for (final p in _promotions) (eligible: false, row: p),
    ];
    if (q.isEmpty) return all;
    return all.where((i) {
      final r = i.row;
      final hay = i.eligible
          ? '${r['employee_no'] ?? ''} ${r['employee_name'] ?? ''} ${r['designation_name'] ?? ''}'
          : '${empName(r['employee'])} ${nested(r, 'from_designation')} ${nested(r, 'to_designation')} ${r['remarks'] ?? ''}';
      return hay.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _create([Map<String, dynamic>? eligibleRow]) async {
    final ok = await showMotionSheet<bool>(
      context,
      (_) => _PromotionForm(
        emps: _emps,
        des: _des,
        eligibleIds: {for (final e in _eligible) e['employee_id'].toString()},
        preselect: eligibleRow?['employee_id'],
      ),
    );
    if (ok == true) {
      if (mounted) marketToast(context, 'Promotion recorded');
      _load();
    }
  }

  Future<bool> _delete(Map<String, dynamic> row) async {
    final ok = await confirmMarket(
      context,
      title: 'Delete promotion record?',
      message: "The employee's designation and salary will not be reverted automatically.",
    );
    if (!ok) return false;
    try {
      await _client.delete('promotions', row['id']);
      if (mounted) {
        setState(() => _promotions.removeWhere((r) => r['id'] == row['id']));
        marketToast(context, 'Promotion record deleted');
      }
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete'), error: true);
      return false;
    }
  }

  Future<void> _detail(Map<String, dynamic> r) async {
    final res = await showMotionSheet<String>(context, (_) => _PromotionDetail(row: r));
    if (res == 'delete' && mounted) await _delete(r);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final thisYear = _promotions.where((p) => parseDate(p['effective_date'])?.year == DateTime.now().year).length;
    return MotionScaffold(
      title: 'Promotion',
      subtitle: '${_eligible.length} eligible · ${_promotions.length} promoted',
      icon: Icons.trending_up_rounded,
      accent: Accent.emerald,
      onRefresh: _load,
      onFab: () => _create(),
      fabLabel: 'New promotion',
      headerExtra: HeaderSearch(hint: 'Search employee or designation', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        if (!_loading && _error == null) ...[
          SliverPadding(
            padding: const EdgeInsets.only(top: 16),
            sliver: SliverToBoxAdapter(
              child: KpiGrid(children: [
                KpiTile(icon: Icons.hourglass_top_rounded, label: 'Eligible now', value: _eligible.length, tone: MarketTone.warn, onTap: () => setState(() => _chip = 'pending')),
                KpiTile(icon: Icons.workspace_premium_rounded, label: 'Promotions', value: _promotions.length, tone: MarketTone.ok, onTap: () => setState(() => _chip = 'approved')),
                KpiTile(icon: Icons.event_repeat_rounded, label: 'This year', value: thisYear, tone: MarketTone.brand),
              ]),
            ),
          ),
          if (!_hasPromotion)
            sliverBox(
              GlowCard(
                child: Row(children: [
                  const AccentIcon(Icons.info_outline_rounded, accent: Accent.amber, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Promotion is turned off in HR settings, so no one is listed as eligible.',
                        style: TextStyle(fontSize: 12.5, color: MarketPalette.of(context).label)),
                  ),
                ]),
              ),
            ),
        ],
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _chip,
              options: [
                (id: 'all', label: 'All', count: _eligible.length + _promotions.length),
                (id: 'pending', label: 'Pending', count: _eligible.length),
                (id: 'approved', label: 'Approved', count: _promotions.length),
              ],
              onChanged: (v) => setState(() => _chip = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton()
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (items.isEmpty)
          sliverEmpty(icon: Icons.trending_up_rounded, title: 'Nothing here', message: 'No eligible employees or promotions match.', actionLabel: 'New promotion', onAction: _create)
        else
          sliverStagger(
            count: items.length,
            builder: (ctx, i) {
              final it = items[i];
              final r = it.row;
              if (it.eligible) {
                final name = str(r['employee_name']);
                return MotionTile(
                  key: ValueKey('e-${r['employee_id']}'),
                  leading: InitialsAvatar(name.isEmpty ? '?' : name),
                  title: name,
                  subtitle: [str(r['employee_no']), str(r['designation_name'])].where((s) => s.isNotEmpty).join(' · '),
                  meta: '${r['months_of_service'] ?? 0} months since last move',
                  trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const StatusPill('Pending', tone: MarketTone.warn),
                    const SizedBox(height: 6),
                    PressScale(
                      onTap: () => _create(r),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(gradient: Accent.ocean.gradient, borderRadius: BorderRadius.circular(10)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.trending_up_rounded, size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text('Promote', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ]),
                  onTap: () => _create(r),
                );
              }
              final name = empName(r['employee']);
              final from = nested(r, 'from_designation');
              final to = nested(r, 'to_designation');
              final newSal = toNum(r['new_salary']);
              return MotionTile(
                key: ValueKey('p-${r['id']}'),
                leading: InitialsAvatar(name.isEmpty ? '?' : name),
                title: name.isEmpty ? 'Employee' : name,
                subtitle: '${from.isEmpty ? '—' : from} → ${to.isEmpty ? (from.isEmpty ? '—' : from) : to}',
                meta: [
                  fmtDate(parseDate(r['effective_date'])),
                  if (newSal != null) 'New salary ${fmtNum(newSal)}',
                  if (toNum(r['raise_value']) != null && toNum(r['raise_value'])! > 0) r['raise_type'] == 'PERCENTAGE' ? '+${fmtNum(toNum(r['raise_value']))}%' : '+${fmtNum(toNum(r['raise_value']))}',
                ].join(' · '),
                trailing: const StatusPill('Approved', tone: MarketTone.ok),
                onTap: () => _detail(r),
                onDelete: () => _delete(r),
              );
            },
          ),
      ],
    );
  }
}

class _PromotionDetail extends StatelessWidget {
  final Map<String, dynamic> row;
  const _PromotionDetail({required this.row});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final r = row;
    final name = empName(r['employee']);
    final raise = toNum(r['raise_value']);
    return FormSheet(
      title: 'Promotion',
      subtitle: name,
      extraAction: IconButton(tooltip: 'Delete', onPressed: () => Navigator.pop(context, 'delete'), icon: Icon(Icons.delete_outline_rounded, color: p.error)),
      children: [
        Row(children: [
          Expanded(child: _desCard(p, 'From', nested(r, 'from_designation'), p.surface, p.text)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward_rounded, color: p.brand)),
          Expanded(child: _desCard(p, 'To', nested(r, 'to_designation').isEmpty ? nested(r, 'from_designation') : nested(r, 'to_designation'), p.okBg, p.ok)),
        ]),
        const SizedBox(height: 14),
        reviewGrid([
          ('Effective date', fmtDate(parseDate(r['effective_date']))),
          ('Raise', raise == null || raise == 0 ? '—' : (r['raise_type'] == 'PERCENTAGE' ? '${fmtNum(raise)}% of gross' : '+${fmtNum(raise)} flat')),
          ('Last salary', fmtNum(toNum(r['last_salary']))),
          ('New salary', fmtNum(toNum(r['new_salary']))),
        ]),
        if (str(r['remarks']).isNotEmpty) ...[
          const SizedBox(height: 14),
          FormLabel(
            label: 'Remarks',
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
              child: Text(str(r['remarks']), style: TextStyle(fontSize: 13.5, height: 1.45, color: p.text)),
            ),
          ),
        ],
        SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
      ],
    );
  }

  Widget _desCard(MarketPalette p, String label, String value, Color bg, Color fg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: p.label)),
          const SizedBox(height: 3),
          Text(value.isEmpty ? '—' : value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
        ]),
      );
}

class _PromotionForm extends StatefulWidget {
  final List<_Emp> emps;
  final List<Map<String, dynamic>> des;
  final Set<String> eligibleIds;
  final Object? preselect;
  const _PromotionForm({required this.emps, required this.des, required this.eligibleIds, this.preselect});

  @override
  State<_PromotionForm> createState() => _PromotionFormState();
}

class _PromotionFormState extends State<_PromotionForm> {
  final _client = ApiClient();
  late Object? _empId = widget.preselect;
  Object? _toDes;
  DateTime? _date = DateTime.now();
  String _raiseType = 'PERCENTAGE';
  final _raise = TextEditingController();
  final _remarks = TextEditingController();
  bool _busy = false;

  _Emp? get _emp => widget.emps.where((e) => e.id.toString() == _empId?.toString()).firstOrNull;
  double get _raiseNum => double.tryParse(_raise.text.trim()) ?? 0;
  double get _last => _emp?.gross ?? 0;
  double get _new => _raiseNum > 0 ? (_raiseType == 'PERCENTAGE' ? _last * (1 + _raiseNum / 100) : _last + _raiseNum) : _last;

  @override
  void initState() {
    super.initState();
    _raise.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _raise.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_empId == null || _date == null) {
      marketToast(context, 'Employee and effective date are required', error: true);
      return;
    }
    if (_toDes == null && _raiseNum <= 0) {
      marketToast(context, 'Pick a new designation, enter a raise, or both', error: true);
      return;
    }
    final withRaise = _raiseNum > 0;
    if (withRaise) {
      final ok = await confirmMarket(
        context,
        title: 'Confirm salary update',
        message: "${_emp?.label ?? 'This employee'}'s gross salary will change from ${fmtNum(_last)} to ${fmtNum(_r2(_new))} "
            '(${_raiseType == 'PERCENTAGE' ? '+${fmtNum(_raiseNum)}%' : '+${fmtNum(_raiseNum)} flat'}). '
            'Every salary structure component (basic, house rent, medical, transport, other) will be scaled by the same ratio.',
        confirm: 'Confirm and update',
        destructive: false,
      );
      if (!ok) return;
    }
    await _save(withRaise);
  }

  Future<void> _save(bool withRaise) async {
    final emp = _emp;
    setState(() => _busy = true);
    try {
      await _client.post(
        'promotions',
        {
          'employee_id': _empId,
          'from_designation_id': emp?.designationId,
          'to_designation_id': _toDes,
          'effective_date': DateTime.utc(_date!.year, _date!.month, _date!.day).toIso8601String(),
          'raise_type': withRaise ? _raiseType : null,
          'raise_value': withRaise ? _raiseNum : null,
          'last_salary': withRaise ? _last : null,
          'new_salary': withRaise ? _new : null,
          'remarks': _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
        },
        isV8: true,
      );
      if (_toDes != null) await _client.put('employees', _empId!, {'designation_id': _toDes});
      var salaryNote = false;
      if (withRaise) {
        if (emp?.salaryId == null || emp?.components == null) {
          salaryNote = true;
        } else {
          final c = emp!.components!;
          final factor = _last > 0 ? _new / _last : null;
          final scaled = factor != null ? {for (final k in _salaryKeys) k: _r2(c[k]! * factor)} : {...c, 'basic': _new};
          await _client.put('employee_salaries', emp.salaryId!, scaled);
        }
      }
      if (!mounted) return;
      if (salaryNote) marketToast(context, 'No salary structure found — designation applied without a salary update', error: true);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(e, 'Failed to save promotion'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final emp = _emp;
    return FormSheet(
      title: 'New promotion',
      subtitle: 'Applied immediately to the employee',
      busy: _busy,
      onSubmit: _submit,
      submitLabel: 'Submit',
      children: [
        FormLabel(
          label: 'Employee',
          required: true,
          child: PickerField(
            value: _empId,
            hint: 'Select employee',
            icon: Icons.person_search_rounded,
            options: [for (final e in widget.emps) PickOption(e.id, e.label, sub: widget.eligibleIds.contains(e.id.toString()) ? 'Eligible' : null)],
            onChanged: (v) => setState(() => _empId = v),
          ),
        ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: FormLabel(
              label: 'Current designation',
              child: InputDecorator(
                decoration: motionInput(context, icon: Icons.work_outline_rounded),
                child: Text(emp == null || emp.designationName.isEmpty ? '—' : emp.designationName,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.text)),
              ),
            ),
          ),
        ]),
        FormLabel(
          label: 'To designation',
          child: PickerField(
            value: _toDes,
            hint: 'Optional',
            icon: Icons.upgrade_rounded,
            options: [for (final d in widget.des) PickOption(d['id'], str(d['name']))],
            onChanged: (v) => setState(() => _toDes = v),
          ),
        ),
        FormLabel(label: 'Effective date', required: true, child: DatePickField(value: _date, onChanged: (d) => setState(() => _date = d))),
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Salary raise (optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _salaryBox(p, 'Current gross', emp == null ? '—' : fmtNum(_r2(_last)), p.text)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward_rounded, size: 18, color: p.label)),
              Expanded(
                child: _salaryBox(
                  p,
                  'New gross',
                  emp == null ? '—' : fmtNum(_r2(_new)),
                  _raiseNum > 0 ? p.ok : p.text,
                  animate: emp != null,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            MarketSegmented<String>(
              value: _raiseType,
              options: const [(id: 'PERCENTAGE', label: 'Percentage of gross', count: null), (id: 'FIXED', label: 'Fixed amount', count: null)],
              onChanged: (v) => setState(() => _raiseType = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _raise,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: motionInput(context, hint: _raiseType == 'PERCENTAGE' ? 'Raise % (optional)' : 'Raise amount (optional)', icon: Icons.add_chart_rounded),
            ),
          ]),
        ),
        FormLabel(label: 'Remarks', child: TextField(controller: _remarks, minLines: 2, maxLines: 4, decoration: motionInput(context, hint: 'Optional'))),
      ],
    );
  }

  Widget _salaryBox(MarketPalette p, String label, String value, Color color, {bool animate = false}) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: p.label)),
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a), child: c)),
            child: Text(value, key: ValueKey(value), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
          ),
        ]),
      );
}
