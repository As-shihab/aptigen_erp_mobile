import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/storage/app_storage.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../leave/hr_extras.dart';

// HR settings — port of desktop HrSettings.tsx: the workplace's hr_settings
// row (scheduling, KPI & promotion, payroll). Like desktop, every change is
// saved immediately (optimistic, rolled back on failure); number fields
// save shortly after the last tap.

Map<String, dynamic> _parseJson(dynamic raw, Map<String, dynamic> fallback) {
  if (raw == null || str(raw).isEmpty) return {...fallback};
  try {
    final d = raw is Map ? raw : jsonDecode(raw.toString());
    if (d is Map) return {...fallback, ...d.cast<String, dynamic>()};
  } catch (_) {}
  return {...fallback};
}

const _kpiDefault = {'late': true, 'best_attendance': true};
const _promoDefault = {'month_count': 6, 'from_join_date': true};

class HrSettingsPage extends StatefulWidget {
  const HrSettingsPage({super.key});

  @override
  State<HrSettingsPage> createState() => _HrSettingsPageState();
}

class _HrSettingsPageState extends State<HrSettingsPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _row;
  List<Map<String, dynamic>> _approveTypes = [];
  int _saving = 0;
  bool _savedFlash = false;
  final Map<String, Timer> _debounce = {};
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final t in _debounce.values) {
      t.cancel();
    }
    _flashTimer?.cancel();
    super.dispose();
  }

  Future<int?> _workplaceId() async {
    final user = await AppStorage.getUser();
    final wp = user?['selectedWorkplace'] ?? user?['workplace'];
    final id = wp is Map ? int.tryParse('${wp['id']}') : null;
    return id != null && id > 0 ? id : null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = _row == null;
      _error = null;
    });
    try {
      final wp = await _workplaceId();
      final d = await batchLoad(_client, {
        'settings': wp == null ? 'hr_settings?\$top=1' : 'hr_settings?\$filter=workplace_id eq $wp&\$top=1',
        'approve': 'approve_types?\$select=id,name&\$filter=is_active eq true&\$top=200',
      });
      if (!mounted) return;
      setState(() {
        final list = d['settings'] ?? [];
        _row = list.isEmpty ? null : {...list.first};
        _approveTypes = d['approve'] ?? [];
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Failed to load HR settings'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> get _kpi => _parseJson(_row?['kpi_config'], _kpiDefault);
  Map<String, dynamic> get _promo => _parseJson(_row?['promotion_config'], _promoDefault);

  Future<void> _patch(Map<String, dynamic> partial, {Map<String, dynamic>? before}) async {
    final row = _row;
    if (row == null) return;
    final previous = before ?? {for (final k in partial.keys) k: row[k]};
    setState(() {
      row.addAll(partial);
      _saving++;
    });
    try {
      await _client.put('hr_settings', row['id'], partial);
      if (mounted) {
        _flashTimer?.cancel();
        setState(() => _savedFlash = true);
        _flashTimer = Timer(const Duration(milliseconds: 1400), () {
          if (mounted) setState(() => _savedFlash = false);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => row.addAll(previous));
        marketToast(context, errorMessage(e, 'Failed to save HR settings'), error: true);
      }
    } finally {
      if (mounted) setState(() => _saving--);
    }
  }

  final Map<String, Map<String, dynamic>> _pendingBefore = {};

  void _patchLater(String key, Map<String, dynamic> partial) {
    final row = _row;
    if (row == null) return;
    _pendingBefore[key] ??= {for (final k in partial.keys) k: row[k]};
    setState(() => row.addAll(partial));
    _debounce[key]?.cancel();
    _debounce[key] = Timer(const Duration(milliseconds: 700), () => _patch(partial, before: _pendingBefore.remove(key)));
  }

  void _patchKpi(String k, bool v) => _patch({'kpi_config': jsonEncode({..._kpi, k: v})});
  void _patchPromo(String k, Object v) => _patch({'promotion_config': jsonEncode({..._promo, k: v})});

  @override
  Widget build(BuildContext context) {
    final row = _row;
    return MotionScaffold(
      title: 'HR settings',
      subtitle: 'Scheduling, KPI, promotion and payroll',
      icon: Icons.tune_rounded,
      accent: Accent.ocean,
      onRefresh: _load,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _saving > 0
                  ? const SizedBox(key: ValueKey('saving'), width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : _savedFlash
                      ? const Row(key: ValueKey('saved'), mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.cloud_done_rounded, size: 18),
                          SizedBox(width: 4),
                          Text('Saved', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ])
                      : const SizedBox.shrink(key: ValueKey('idle')),
            ),
          ),
        ),
      ],
      slivers: [
        if (_loading)
          sliverSkeleton(count: 3, height: 180)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (row == null)
          sliverEmpty(
            icon: Icons.settings_suggest_outlined,
            title: 'No HR settings yet',
            message: 'No HR settings found for this workplace yet — reinstall the HR module from the marketplace to create one.',
          )
        else ...[
          sliverBox(_scheduling(context, row)),
          sliverBox(_kpiPromotion(context, row)),
          sliverBox(_payroll(context, row)),
        ],
      ],
    );
  }

  Widget _card(BuildContext context, {required int index, required String title, required IconData icon, required Accent accent, required List<Widget> children}) {
    final p = MarketPalette.of(context);
    return FadeSlideIn(
      index: index,
      offsetY: 24,
      child: GlowCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            AccentIcon(icon, accent: accent, size: 34),
            const SizedBox(width: 10),
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
          ]),
          const SizedBox(height: 12),
          ...children,
        ]),
      ),
    );
  }

  Widget _toggle(BuildContext context, {required IconData icon, required String title, required String desc, required bool value, required ValueChanged<bool> onChanged}) {
    final p = MarketPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: value ? p.brandSoft : p.card, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: value ? p.brand : p.label),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(height: 2),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(desc, key: ValueKey(desc), style: TextStyle(fontSize: 12, color: p.label, height: 1.35)),
            ),
          ]),
        ),
        Switch.adaptive(value: value, onChanged: onChanged),
      ]),
    );
  }

  Widget _scheduling(BuildContext context, Map<String, dynamic> r) => _card(
        context,
        index: 0,
        title: 'Scheduling',
        icon: Icons.schedule_rounded,
        accent: Accent.ocean,
        children: [
          _toggle(context,
              icon: Icons.groups_rounded,
              title: 'Use shift',
              desc: 'Enable shift-based scheduling across HR management.',
              value: asBool(r['has_shift'], fallback: true),
              onChanged: (v) => _patch({'has_shift': v})),
          _toggle(context,
              icon: Icons.calendar_view_week_rounded,
              title: 'Use roster',
              desc: 'Enable roster-based scheduling as the source for shift assignment across HR management.',
              value: asBool(r['has_roster'], fallback: true),
              onChanged: (v) => _patch({'has_roster': v})),
          _toggle(context,
              icon: Icons.place_rounded,
              title: 'Use location',
              desc: 'Enable the locations map / geofence feature across HR management.',
              value: asBool(r['use_location']),
              onChanged: (v) => _patch({'use_location': v})),
        ],
      );

  Widget _kpiPromotion(BuildContext context, Map<String, dynamic> r) {
    final p = MarketPalette.of(context);
    final hasKpi = asBool(r['has_kpi'], fallback: true);
    final hasPromo = asBool(r['has_promotion'], fallback: true);
    final kpi = _kpi;
    final promo = _promo;
    final months = toInt(promo['month_count']) < 1 ? 1 : toInt(promo['month_count']);
    final fromJoin = asBool(promo['from_join_date'], fallback: true);
    return _card(
      context,
      index: 1,
      title: 'KPI and promotion',
      icon: Icons.trending_up_rounded,
      accent: Accent.emerald,
      children: [
        _toggle(context,
            icon: Icons.insights_rounded,
            title: 'Use KPI',
            desc: 'Enable the KPI list, auto-computed from attendance each month.',
            value: hasKpi,
            onChanged: (v) => _patch({'has_kpi': v})),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: !hasKpi
              ? const SizedBox(width: double.infinity)
              : _subPanel(p, 'KPI criteria', [
                  SwitchField(label: 'Track late arrivals', value: asBool(kpi['late'], fallback: true), onChanged: (v) => _patchKpi('late', v)),
                  SwitchField(label: 'Track best attendance', value: asBool(kpi['best_attendance'], fallback: true), onChanged: (v) => _patchKpi('best_attendance', v)),
                ]),
        ),
        _toggle(context,
            icon: Icons.workspace_premium_rounded,
            title: 'Use promotion',
            desc: 'Enable the promotion and promotion history pages.',
            value: hasPromo,
            onChanged: (v) => _patch({'has_promotion': v})),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: !hasPromo
              ? const SizedBox(width: double.infinity)
              : _subPanel(p, 'Promotion eligibility', [
                  FormLabel(
                    label: 'Minimum months of service',
                    child: StepperField(
                      value: months,
                      min: 1,
                      max: 240,
                      onChanged: (v) {
                        final next = {...promo, 'month_count': v};
                        _patchLater('promo_months', {'promotion_config': jsonEncode(next)});
                      },
                    ),
                  ),
                  SwitchField(
                    label: 'Count from join date',
                    sub: fromJoin ? "Counted from each employee's joining date." : "Counted from each employee's last promotion (or joining date if never promoted).",
                    value: fromJoin,
                    onChanged: (v) => _patchPromo('from_join_date', v),
                  ),
                  FormLabel(
                    label: 'Approval chain',
                    child: PickerField(
                      value: r['promotion_approver_type_id'],
                      hint: 'Select a chain',
                      icon: Icons.account_tree_outlined,
                      options: [for (final t in _approveTypes) PickOption(t['id'], str(t['name']))],
                      onChanged: (v) => _patch({'promotion_approver_type_id': v}),
                    ),
                  ),
                ]),
        ),
      ],
    );
  }

  Widget _payroll(BuildContext context, Map<String, dynamic> r) {
    final p = MarketPalette.of(context);
    final att = asBool(r['payroll_attendance_basis']);
    final auto = asBool(r['auto_payroll']);
    final one = toInt(r['pointer_one']) < 1 ? 1 : toInt(r['pointer_one']);
    final two = toInt(r['pointer_two']) < 1 ? 31 : toInt(r['pointer_two']);
    return _card(
      context,
      index: 2,
      title: 'Payroll',
      icon: Icons.account_balance_wallet_rounded,
      accent: Accent.amber,
      children: [
        _toggle(context,
            icon: Icons.fact_check_rounded,
            title: 'Attendance-based payroll',
            desc: att
                ? 'On — salary is computed from attendance (present, absent, late days, overtime) each payroll run.'
                : 'Off — employees are paid their fixed monthly salary regardless of attendance.',
            value: att,
            onChanged: (v) => _patch({'payroll_attendance_basis': v})),
        _toggle(context,
            icon: Icons.autorenew_rounded,
            title: 'Auto payroll',
            desc: auto ? 'On — payroll process runs automatically once each cycle closes.' : 'Off — payroll process must be triggered manually each cycle.',
            value: auto,
            onChanged: (v) => _patch({'auto_payroll': v})),
        _subPanel(p, 'Payroll cycle', [
          FormLabel(
            label: 'Cycle start day',
            child: StepperField(value: one, min: 1, max: 31, onChanged: (v) => _patchLater('pointer_one', {'pointer_one': v})),
          ),
          FormLabel(
            label: 'Cycle end day',
            child: StepperField(value: two, min: 1, max: 31, onChanged: (v) => _patchLater('pointer_two', {'pointer_two': v})),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Day-of-month bounds of one payroll cycle — e.g. 1 to 31 for a calendar month, or 26 to 25 for a shifted cycle.',
              style: TextStyle(fontSize: 12, color: p.label, fontStyle: FontStyle.italic, height: 1.4),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _subPanel(MarketPalette p, String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.label)),
          const SizedBox(height: 10),
          ...children,
        ]),
      );
}
