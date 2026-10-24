import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/network/http_client.dart';
import '../../../core/network/socket_client.dart';
import '../../../core/utils/currency.dart';
import '../../../shared/ui/motion_kit.dart';
import '../data/hr_analytics_service.dart';
import 'tabs/hr_charts.dart';

enum _Seg { attendance, payroll, workforce }

extension on _Seg {
  String get label => switch (this) {
        _Seg.attendance => 'Attendance and leave',
        _Seg.payroll => 'Payroll',
        _Seg.workforce => 'Workforce',
      };
}

const _genders = ['Male', 'Female', 'Other'];

/// HR analytics — ported from desktop HrmAnalytics.tsx: KPI strip (shift
/// metrics only when the workplace uses shifts), three chart segments and
/// the full filter set (date range, shift, department, designation,
/// employee type, section, gender). Refreshes live on attendance punches.
class HrAnalyticsPage extends StatefulWidget {
  const HrAnalyticsPage({super.key});

  @override
  State<HrAnalyticsPage> createState() => _HrAnalyticsPageState();
}

class _HrAnalyticsPageState extends State<HrAnalyticsPage> {
  final _service = HrAnalyticsService(ApiClient());

  HrAnalyticsFilters _applied = HrAnalyticsFilters.defaults();
  _Seg _seg = _Seg.attendance;
  bool _hasShift = true;
  Map<String, List<Map<String, dynamic>>> _opts = const {};

  bool _loading = true;
  bool _loadedOnce = false;
  String? _error;
  Map<String, dynamic> _a = {};
  void Function(dynamic)? _listener;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    final l = _listener;
    if (l != null) AppSocket.instance?.off('attendance:recorded', l);
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final o = await _service.getFilterOptions();
      if (!mounted) return;
      final s = o['settings']!.isEmpty ? const <String, dynamic>{} : o['settings']!.first;
      final hasShift = asBool(s['has_shift'], fallback: true);
      final shifts = o['shifts']!;
      setState(() {
        _opts = o;
        _hasShift = hasShift;
        // Desktop auto-selects the first shift when shifts are on.
        if (hasShift && shifts.isNotEmpty) _applied = _applied.copyWith(shiftId: toInt(shifts.first['id']));
      });
    } catch (_) {
      // Filters are optional — analytics still loads without them.
    }
    await _load();
    _connectRealtime();
  }

  Future<void> _connectRealtime() async {
    try {
      final ctx = await resolveSocketContext(ApiClient());
      if (ctx == null || !mounted) return;
      void listener(dynamic _) {
        if (mounted && !_loading) _load();
      }

      _listener = listener;
      AppSocket.connect(ctx).on('attendance:recorded', listener);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _service.getDashboardAnalytics(_applied, hasShift: _hasShift);
      if (!mounted) return;
      setState(() => _a = res);
    } catch (e) {
      // Keep whatever is on screen after the first load; only show the error
      // state when there is nothing to show yet.
      if (mounted) {
        if (_loadedOnce) {
          marketToast(context, errorMessage(e, 'Could not refresh analytics'), error: true);
        } else {
          setState(() => _error = errorMessage(e, 'Could not load analytics'));
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadedOnce = _loadedOnce || _error == null;
        });
      }
    }
  }

  // ── Parsing (tolerant of an older backend missing sections) ──

  Map<String, dynamic> _m(dynamic v) => v is Map ? v.cast<String, dynamic>() : const {};
  Map<String, dynamic> get _metrics => _m(_a['metrics']);
  num _metric(String k) => toDouble(_metrics[k]);

  int get _activeFilters {
    final d = HrAnalyticsFilters.defaults();
    final f = _applied;
    return [
      !DateUtils.isSameDay(f.start, d.start) || !DateUtils.isSameDay(f.end, d.end),
      f.departmentId != null,
      f.designationId != null,
      f.employeeTypeId != null,
      f.employeeSectionId != null,
      f.gender.isNotEmpty,
    ].where((x) => x).length;
  }

  String get _rangeLabel => '${DateFormat('d MMM').format(_applied.start)} to ${DateFormat('d MMM yyyy').format(_applied.end)}';

  String _short(num v) => '${currencySymbol()}${v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.round()}';

  Future<void> _openFilters() async {
    final res = await showMotionSheet<HrAnalyticsFilters>(
      context,
      (_) => _FilterSheet(initial: _applied, opts: _opts, hasShift: _hasShift),
    );
    if (res != null) {
      setState(() => _applied = res);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final badge = _activeFilters;
    final panels = _loadedOnce ? _panels() : const <Widget>[];
    return MotionScaffold(
      title: 'HR analytics',
      subtitle: _rangeLabel,
      icon: Icons.insights_rounded,
      accent: Accent.ocean,
      onRefresh: _load,
      actions: [
        Stack(alignment: Alignment.topRight, children: [
          IconButton(onPressed: _openFilters, icon: const Icon(Icons.tune_rounded), tooltip: 'Filters'),
          if (badge > 0)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Text('$badge', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Accent.ocean.primary)),
              ),
            ),
        ]),
      ],
      slivers: !_loadedOnce && _loading
          ? [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: KpiGrid(children: List.generate(4, (_) => const SkeletonBox(height: 118, radius: 12))),
                ),
              ),
              sliverSkeleton(count: 3, height: 260),
            ]
          : _error != null && !_loadedOnce
              ? [sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load analytics', message: _error, actionLabel: 'Retry', onAction: _load)]
              : [
                  SliverToBoxAdapter(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _loading ? 0.55 : 1,
                      child: Padding(padding: const EdgeInsets.only(top: 16), child: KpiGrid(children: _kpis())),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: ChipFilter<_Seg>(
                        value: _seg,
                        options: [for (final s in _Seg.values) (id: s, label: s.label, count: null)],
                        onChanged: (s) => setState(() => _seg = s),
                      ),
                    ),
                  ),
                  if (badge > 0)
                    sliverBox(
                      Wrap(spacing: 6, runSpacing: 6, children: _filterChips(p)),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    ),
                  KeyedSubtree(
                    key: ValueKey(_seg),
                    child: SliverOpacity(
                      opacity: _loading ? 0.55 : 1,
                      sliver: sliverStagger(
                        count: panels.length,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        gap: 12,
                        builder: (_, i) => panels[i],
                      ),
                    ),
                  ),
                ],
    );
  }

  List<Widget> _filterChips(MarketPalette p) {
    String name(String key, int? id) => id == null ? '' : '${(_opts[key] ?? const []).where((o) => toInt(o['id']) == id).firstOrNull?['name'] ?? ''}';
    final f = _applied;
    final chips = <String>[
      if (f.departmentId != null) name('departments', f.departmentId),
      if (f.designationId != null) name('designations', f.designationId),
      if (f.employeeTypeId != null) name('employeeTypes', f.employeeTypeId),
      if (f.employeeSectionId != null) name('sections', f.employeeSectionId),
      if (f.gender.isNotEmpty) f.gender,
    ].where((s) => s.isNotEmpty).toList();
    return [
      for (final c in chips) StatusPill(c, tone: MarketTone.brand),
      PressScale(
        onTap: () {
          setState(() => _applied = HrAnalyticsFilters.defaults(shiftId: _applied.shiftId));
          _load();
        },
        child: StatusPill('Clear filters', tone: MarketTone.neutral, icon: Icons.close_rounded),
      ),
    ];
  }

  List<Widget> _kpis() {
    final shift = [
      KpiTile(icon: Icons.groups_rounded, label: 'People on shift', value: _metric('shiftEmployees'), tone: MarketTone.brand),
      KpiTile(icon: Icons.login_rounded, label: 'Checked in', value: _metric('totalInShift'), tone: MarketTone.brand),
      KpiTile(icon: Icons.more_time_rounded, label: 'Total overtime', value: _metric('totalOvertime'), tone: MarketTone.warn),
      KpiTile(icon: Icons.check_circle_rounded, label: 'Present on shift', value: _metric('shiftPresents'), tone: MarketTone.ok),
      KpiTile(icon: Icons.cancel_rounded, label: 'Absent on shift', value: _metric('shiftAbsents'), tone: MarketTone.error),
    ];
    final workforce = [
      KpiTile(icon: Icons.groups_2_rounded, label: 'People in total', value: _metric('totalEmployees'), tone: MarketTone.brand),
      KpiTile(icon: Icons.how_to_reg_rounded, label: 'Present today', value: _metric('totalPresents'), tone: MarketTone.brand),
      KpiTile(icon: Icons.person_off_rounded, label: 'Absent today', value: _metric('totalAbsents'), tone: MarketTone.error),
      KpiTile(icon: Icons.event_busy_rounded, label: 'On leave', value: _metric('totalOnLeave'), tone: MarketTone.info),
    ];
    return _hasShift ? [...shift, ...workforce] : workforce;
  }

  List<Widget> _panels() {
    final a = _a;
    double sum(List<double> l) => l.fold(0, (x, y) => x + y);
    switch (_seg) {
      case _Seg.attendance:
        final att = _m(a['attendance']);
        final attData = parseNums(att['data']);
        final punct = _m(a['punctuality']);
        final punctSeries = parseSeries(punct['series']);
        final leave = parseSlices(a['leave']);
        final leaveStatus = parseSlices(a['leaveStatus']);
        final group = _m(a['group']);
        final gLabels = parseStrings(group['labels']);
        final gData = parseNums(group['data']);
        final gColors = parseStrings(group['colors']);
        final today = [
          ChartSlice('Present', _metric('totalPresents').toDouble(), const Color(0xFF30914C)),
          ChartSlice('Absent', _metric('totalAbsents').toDouble(), const Color(0xFFD20A0A)),
          ChartSlice('On leave', _metric('totalOnLeave').toDouble(), const Color(0xFFE76500)),
        ];
        return [
          ChartPanel(
            title: 'Attendance trend',
            subtitle: 'People present during the selected range',
            icon: Icons.date_range_rounded,
            accent: Accent.ocean,
            empty: sum(attData) == 0,
            child: TrendLineChart(categories: parseStrings(att['dates']), series: [ChartSeries('Present', attData, const Color(0xFF049F9A))]),
          ),
          ChartPanel(
            title: 'Late arrivals and overtime',
            subtitle: 'Check-ins per day in range',
            icon: Icons.alarm_rounded,
            accent: Accent.amber,
            empty: !punctSeries.any((s) => sum(s.data) > 0),
            child: TrendLineChart(categories: parseStrings(punct['categories']), series: punctSeries),
          ),
          ChartPanel(
            title: 'Workforce today',
            subtitle: 'Present, absent and on leave',
            icon: Icons.groups_rounded,
            accent: Accent.emerald,
            height: 180,
            empty: sum(today.map((s) => s.value).toList()) == 0,
            child: DonutLegend(slices: today, centerLabel: 'People'),
          ),
          ChartPanel(
            title: 'Leave days by type',
            subtitle: 'Approved leave in range',
            icon: Icons.event_busy_rounded,
            accent: Accent.ocean,
            height: 180,
            empty: leave.isEmpty,
            child: DonutLegend(slices: leave, centerLabel: 'Days'),
          ),
          ChartPanel(
            title: 'Leave requests',
            subtitle: 'By approval status',
            icon: Icons.fact_check_rounded,
            accent: Accent.ocean,
            height: 180,
            empty: leaveStatus.isEmpty,
            child: DonutLegend(slices: leaveStatus, centerLabel: 'Requests'),
          ),
          ChartPanel(
            title: 'People by group',
            icon: Icons.layers_rounded,
            accent: Accent.ocean,
            height: 180,
            empty: gData.isEmpty,
            child: DonutLegend(
              centerLabel: 'People',
              slices: [for (var i = 0; i < gLabels.length; i++) ChartSlice(gLabels[i], i < gData.length ? gData[i] : 0, hexColor(i < gColors.length ? gColors[i] : null, chartColorAt(i)))],
            ),
          ),
        ];
      case _Seg.payroll:
        final pay = _m(a['payroll']);
        final stats = _m(pay['stats']);
        final bar = _m(pay['bar']);
        final barSeries = parseSeries(bar['series']);
        final donut = parseSlices(pay['donut']);
        final bonus = _m(a['bonus']);
        final bonusData = parseNums(bonus['data']);
        final asset = _m(a['asset']);
        final assetCats = parseStrings(asset['categories']);
        return [
          _PayrollStats(stats: stats),
          ChartPanel(
            title: 'Payroll overview',
            subtitle: _rangeLabel,
            icon: Icons.bar_chart_rounded,
            accent: Accent.amber,
            empty: !barSeries.any((s) => sum(s.data) > 0),
            child: GroupedBarChart(categories: parseStrings(bar['categories']), series: barSeries, format: _short),
          ),
          ChartPanel(
            title: 'Payroll breakdown',
            icon: Icons.donut_large_rounded,
            accent: Accent.emerald,
            height: 180,
            empty: sum(donut.map((s) => s.value).toList()) == 0,
            child: DonutLegend(slices: donut, format: _short),
          ),
          ChartPanel(
            title: 'Bonuses by type',
            subtitle: 'Amount given in range',
            icon: Icons.card_giftcard_rounded,
            accent: Accent.sunset,
            empty: bonusData.isEmpty,
            child: GroupedBarChart(categories: parseStrings(bonus['categories']), series: [ChartSeries('Amount', bonusData, const Color(0xFFE76500))], format: _short),
          ),
          ChartPanel(
            title: 'Assigned assets',
            icon: Icons.inventory_2_rounded,
            accent: Accent.ocean,
            empty: assetCats.isEmpty,
            child: GroupedBarChart(categories: assetCats, series: parseSeries(asset['series'])),
          ),
        ];
      case _Seg.workforce:
        final wf = _m(a['workforce']);
        final dept = _m(wf['department']);
        final deptData = parseNums(dept['data']);
        final age = _m(wf['age']);
        final ageData = parseNums(age['data']);
        final gender = parseSlices(wf['gender']);
        final types = parseSlices(wf['employeeType']);
        final mv = _m(a['movement']);
        final mvSeries = parseSeries(mv['series']);
        return [
          ChartPanel(
            title: 'Headcount by department',
            subtitle: 'Active people, largest first',
            icon: Icons.apartment_rounded,
            accent: Accent.ocean,
            height: (deptData.length * 40.0).clamp(80.0, 320.0),
            empty: deptData.isEmpty,
            child: HBarList(categories: parseStrings(dept['categories']), data: deptData),
          ),
          ChartPanel(
            title: 'Joiners and promotions',
            subtitle: 'Last 6 months',
            icon: Icons.trending_up_rounded,
            accent: Accent.emerald,
            empty: !mvSeries.any((s) => sum(s.data) > 0),
            child: GroupedBarChart(categories: parseStrings(mv['categories']), series: mvSeries),
          ),
          ChartPanel(
            title: 'Gender split',
            icon: Icons.wc_rounded,
            accent: Accent.rose,
            height: 170,
            empty: gender.isEmpty,
            child: DonutLegend(slices: gender, centerLabel: 'People'),
          ),
          ChartPanel(
            title: 'Employee types',
            icon: Icons.verified_user_rounded,
            accent: Accent.ocean,
            height: 170,
            empty: types.isEmpty,
            child: DonutLegend(slices: types, centerLabel: 'People'),
          ),
          ChartPanel(
            title: 'Age bands',
            subtitle: 'People with a date of birth',
            icon: Icons.cake_rounded,
            accent: Accent.ocean,
            empty: sum(ageData) == 0,
            child: GroupedBarChart(categories: parseStrings(age['categories']), series: [ChartSeries('People', ageData, const Color(0xFF8B47D7))]),
          ),
        ];
    }
  }
}

class _PayrollStats extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _PayrollStats({required this.stats});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final items = [
      ('Outstanding', toDouble(stats['totalOutstanding']), true, Icons.hourglass_bottom_rounded, MarketTone.warn),
      ('Salary total', toDouble(stats['totalSalary']), true, Icons.payments_rounded, MarketTone.ok),
      ('Payable days', toDouble(stats['payableDays']), false, Icons.calendar_today_rounded, MarketTone.info),
      ('Generated', toDouble(stats['totalGenerated']), false, Icons.receipt_long_rounded, MarketTone.brand),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.2,
      children: [
        for (final it in items)
          GlowCard(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: p.tone(it.$5).bg, borderRadius: BorderRadius.circular(11)),
                child: Icon(it.$4, size: 18, color: p.tone(it.$5).fg),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CountUp(
                    value: it.$2,
                    format: (v) => it.$3 ? money(v) : NumberFormat.decimalPattern().format(v.round()),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.text),
                  ),
                  Text(it.$1, style: TextStyle(fontSize: 11, color: p.label)),
                ]),
              ),
            ]),
          ),
      ],
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final HrAnalyticsFilters initial;
  final Map<String, List<Map<String, dynamic>>> opts;
  final bool hasShift;
  const _FilterSheet({required this.initial, required this.opts, required this.hasShift});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late HrAnalyticsFilters _f = widget.initial;

  List<PickOption> _o(String key) => [for (final r in widget.opts[key] ?? const <Map<String, dynamic>>[]) PickOption(toInt(r['id']), '${r['name'] ?? ''}')];

  int? _id(Object? v) => v == null ? null : toInt(v);

  @override
  Widget build(BuildContext context) {
    final shifts = widget.opts['shifts'] ?? const [];
    return FormSheet(
      title: 'Filters',
      subtitle: 'Narrow the analytics down',
      submitLabel: 'Apply',
      onSubmit: () => Navigator.pop(context, _f),
      extraAction: TextButton(
        onPressed: () => Navigator.pop(context, HrAnalyticsFilters.defaults(shiftId: widget.hasShift && shifts.isNotEmpty ? toInt(shifts.first['id']) : null)),
        child: const Text('Reset'),
      ),
      children: [
        Row(children: [
          Expanded(
            child: FormLabel(
              label: 'From',
              child: DatePickField(
                value: _f.start,
                lastDate: _f.end,
                onChanged: (d) {
                  if (d != null) setState(() => _f = _f.copyWith(start: d));
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FormLabel(
              label: 'To',
              child: DatePickField(
                value: _f.end,
                firstDate: _f.start,
                onChanged: (d) {
                  if (d != null) setState(() => _f = _f.copyWith(end: d));
                },
              ),
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final preset in const [(7, 'Last 7 days'), (30, 'Last 30 days'), (90, 'Last 90 days')])
              PressScale(
                onTap: () {
                  final now = DateTime.now();
                  final end = DateTime(now.year, now.month, now.day);
                  setState(() => _f = _f.copyWith(start: end.subtract(Duration(days: preset.$1)), end: end));
                },
                child: StatusPill(preset.$2, tone: MarketTone.brand, icon: Icons.history_rounded),
              ),
          ]),
        ),
        if (widget.hasShift)
          FormLabel(
            label: 'Shift',
            child: PickerField(value: _f.shiftId, hint: 'All shifts', icon: Icons.schedule_rounded, options: _o('shifts'), onChanged: (v) => setState(() => _f = _f.copyWith(shiftId: _id(v)))),
          ),
        FormLabel(
          label: 'Department',
          child: PickerField(value: _f.departmentId, hint: 'All departments', icon: Icons.apartment_rounded, options: _o('departments'), onChanged: (v) => setState(() => _f = _f.copyWith(departmentId: _id(v)))),
        ),
        FormLabel(
          label: 'Designation',
          child: PickerField(value: _f.designationId, hint: 'All designations', icon: Icons.badge_outlined, options: _o('designations'), onChanged: (v) => setState(() => _f = _f.copyWith(designationId: _id(v)))),
        ),
        FormLabel(
          label: 'Employee type',
          child: PickerField(value: _f.employeeTypeId, hint: 'All types', icon: Icons.verified_user_outlined, options: _o('employeeTypes'), onChanged: (v) => setState(() => _f = _f.copyWith(employeeTypeId: _id(v)))),
        ),
        FormLabel(
          label: 'Section',
          child: PickerField(value: _f.employeeSectionId, hint: 'All sections', icon: Icons.layers_outlined, options: _o('sections'), onChanged: (v) => setState(() => _f = _f.copyWith(employeeSectionId: _id(v)))),
        ),
        FormLabel(
          label: 'Gender',
          child: ChipFilter<String>(
            padding: EdgeInsets.zero,
            value: _f.gender,
            onChanged: (g) => setState(() => _f = _f.copyWith(gender: g)),
            options: [(id: '', label: 'All', count: null), for (final g in _genders) (id: g, label: g, count: null)],
          ),
        ),
      ],
    );
  }
}
