import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/motion_kit.dart';

// KPI list — port of desktop KpiList.tsx: auto-computed per-employee stats
// for a month from /api/hrm/kpi-report (attended days, late days, best
// attendance). kpi_config in HR settings decides which criteria show.

class KpiListPage extends StatefulWidget {
  const KpiListPage({super.key});

  @override
  State<KpiListPage> createState() => _KpiListPageState();
}

class _KpiListPageState extends State<KpiListPage> {
  final _client = ApiClient();
  final _now = DateTime.now();
  late int _month = _now.month;
  late int _year = _now.year;
  bool _loading = true;
  String? _error;
  bool _hasKpi = true;
  bool _late = true;
  bool _best = true;
  List<Map<String, dynamic>> _rows = [];
  String _q = '';
  String _filter = 'all';
  String _sort = 'name';
  final _monthScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_monthScroll.hasClients) _monthScroll.jumpTo(((_month - 1) * 92.0 - 80).clamp(0, _monthScroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _monthScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _client.get('hrm/kpi-report?month=$_month&year=$_year', isV8: false);
      if (!mounted) return;
      final cfg = res is Map && res['kpi_config'] is Map ? res['kpi_config'] as Map : const {};
      setState(() {
        _hasKpi = res is Map ? asBool(res['has_kpi'], fallback: true) : true;
        _late = asBool(cfg['late'], fallback: true);
        _best = asBool(cfg['best_attendance'], fallback: true);
        _rows = res is Map && res['rows'] is List ? (res['rows'] as List).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList() : [];
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load the KPI report'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pick(int month, int year) {
    if (month == _month && year == _year) return;
    setState(() {
      _month = month;
      _year = year;
    });
    _load();
  }

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    final list = _rows.where((r) {
      if (_filter == 'best' && !asBool(r['best_attendance'])) return false;
      if (_filter == 'late' && toInt(r['late_days']) == 0) return false;
      if (q.isEmpty) return true;
      return '${r['employee_name'] ?? ''} ${r['employee_no'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
    switch (_sort) {
      case 'attended':
        list.sort((a, b) => toInt(b['attended_days']).compareTo(toInt(a['attended_days'])));
      case 'late':
        list.sort((a, b) => toInt(b['late_days']).compareTo(toInt(a['late_days'])));
      default:
        list.sort((a, b) => str(a['employee_name']).toLowerCase().compareTo(str(b['employee_name']).toLowerCase()));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final rows = _visible;
    final maxAttended = _rows.fold<int>(0, (a, r) => toInt(r['attended_days']) > a ? toInt(r['attended_days']) : a);
    final totalLate = _rows.fold<int>(0, (a, r) => a + toInt(r['late_days']));
    final bestCount = _rows.where((r) => asBool(r['best_attendance'])).length;
    return MotionScaffold(
      title: 'KPI list',
      subtitle: '${DateFormat('MMMM yyyy').format(DateTime(_year, _month))} · auto-computed from attendance',
      icon: Icons.insights_rounded,
      accent: Accent.sunset,
      onRefresh: _load,
      headerExtra: HeaderSearch(hint: 'Search employee', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Text('Year', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.label)),
                  const SizedBox(width: 10),
                  MarketSegmented<int>(
                    value: _year,
                    options: [for (final y in [_now.year, _now.year - 1, _now.year - 2]) (id: y, label: '$y', count: null)],
                    onChanged: (y) => _pick(_month, y),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  controller: _monthScroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  physics: const BouncingScrollPhysics(),
                  itemCount: 12,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final m = i + 1;
                    final sel = m == _month;
                    final future = _year == _now.year && m > _now.month;
                    return PressScale(
                      onTap: () => _pick(m, _year),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 84,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: sel ? Accent.ocean.gradient : null,
                          color: sel ? null : p.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: sel ? Colors.transparent : p.line),
                        ),
                        child: Text(
                          DateFormat('MMMM').format(DateTime(2000, m)),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : (future ? p.label.withValues(alpha: 0.6) : p.text),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
        if (_loading)
          sliverSkeleton()
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (!_hasKpi)
          sliverEmpty(icon: Icons.toggle_off_outlined, title: 'KPI is turned off', message: 'Enable KPI in HR settings to see this report.')
        else ...[
          SliverPadding(
            padding: const EdgeInsets.only(top: 16),
            sliver: SliverToBoxAdapter(
              child: KpiGrid(children: [
                KpiTile(icon: Icons.groups_rounded, label: 'Employees', value: _rows.length, tone: MarketTone.brand),
                if (_best) KpiTile(icon: Icons.emoji_events_rounded, label: 'Best attendance', value: bestCount, tone: MarketTone.ok, onTap: () => setState(() => _filter = 'best')),
                if (_late) KpiTile(icon: Icons.timer_off_rounded, label: 'Late days', value: totalLate, tone: MarketTone.error, onTap: () => setState(() => _filter = 'late')),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(top: 14),
            sliver: SliverToBoxAdapter(
              child: ChipFilter<String>(
                value: _filter,
                options: [
                  (id: 'all', label: 'All', count: _rows.length),
                  if (_best) (id: 'best', label: 'Best attendance', count: bestCount),
                  if (_late) (id: 'late', label: 'Has late days', count: _rows.where((r) => toInt(r['late_days']) > 0).length),
                ],
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
          ),
          sliverBox(
            Row(children: [
              Text('Sort by', style: TextStyle(fontSize: 12.5, color: p.label)),
              const SizedBox(width: 10),
              Expanded(
                child: MarketSegmented<String>(
                  value: _sort,
                  options: [
                    (id: 'name', label: 'Name', count: null),
                    (id: 'attended', label: 'Attended', count: null),
                    if (_late) (id: 'late', label: 'Late', count: null),
                  ],
                  onChanged: (v) => setState(() => _sort = v),
                ),
              ),
            ]),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          ),
          if (rows.isEmpty)
            sliverEmpty(icon: Icons.insights_outlined, title: _rows.isEmpty ? 'No attendance this month' : 'No matches')
          else
            KeyedSubtree(
              key: ValueKey('$_year-$_month-$_filter-$_sort'),
              child: sliverStagger(
                count: rows.length,
                builder: (_, i) {
                  final r = rows[i];
                  final name = str(r['employee_name']);
                  final attended = toInt(r['attended_days']);
                  final late = toInt(r['late_days']);
                  final best = asBool(r['best_attendance']);
                  return GlowCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      ProgressRing(
                        value: maxAttended == 0 ? 0 : attended / maxAttended,
                        size: 52,
                        stroke: 5,
                        color: best ? p.ok : p.brand,
                        center: Text('$attended', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.text)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name.isEmpty ? 'Employee' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.text)),
                          if (str(r['employee_no']).isNotEmpty) Text(str(r['employee_no']), style: TextStyle(fontSize: 12, color: p.label)),
                          const SizedBox(height: 4),
                          Text('$attended attended ${attended == 1 ? 'day' : 'days'}', style: TextStyle(fontSize: 12, color: p.label)),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        if (_late) StatusPill(late == 0 ? 'No late days' : '$late late', tone: late > 0 ? MarketTone.error : MarketTone.neutral),
                        if (_best && best) ...[
                          const SizedBox(height: 6),
                          const StatusPill('Best attendance', tone: MarketTone.ok, icon: Icons.emoji_events_rounded),
                        ],
                      ]),
                    ]),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }
}
