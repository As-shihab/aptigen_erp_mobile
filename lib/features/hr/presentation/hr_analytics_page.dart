import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/hr_analytics_service.dart';

/// Ported from erp/desktop's HrmDashboard.tsx — charts stacked vertically
/// (mobile can't match the desktop's side-by-side density).
class HrAnalyticsPage extends StatefulWidget {
  const HrAnalyticsPage({super.key});

  @override
  State<HrAnalyticsPage> createState() => _HrAnalyticsPageState();
}

class _HrAnalyticsPageState extends State<HrAnalyticsPage> {
  final _service = HrAnalyticsService(ApiClient());

  DateTimeRange _range = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 30)), end: DateTime.now());
  int? _departmentId;
  int? _shiftId;
  List<dynamic> _departments = [];
  List<dynamic> _shifts = [];

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _analytics = {};

  @override
  void initState() {
    super.initState();
    _loadFilters();
    _loadAnalytics();
  }

  Future<void> _loadFilters() async {
    try {
      final options = await _service.getFilterOptions();
      if (!mounted) return;
      setState(() {
        _departments = options['departments'] ?? [];
        _shifts = options['shifts'] ?? [];
      });
    } catch (_) {
      // filters are optional — analytics still loads without them
    }
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getDashboardAnalytics(
        startDate: _range.start,
        endDate: _range.end,
        departmentId: _departmentId,
        shiftId: _shiftId,
      );
      if (!mounted) return;
      setState(() => _analytics = data);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load analytics.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _map(String key) => (_analytics[key] as Map?)?.cast<String, dynamic>() ?? {};
  List<dynamic> _list(String key) => (_analytics[key] as List?) ?? [];

  @override
  Widget build(BuildContext context) {
    final metrics = _map('metrics');
    final payroll = _map('payroll');
    final attendance = _map('attendance');
    final asset = _map('asset');
    final leave = _list('leave');
    final group = _map('group');

    return Scaffold(
      appBar: AppBar(title: const Text('HR Analytics')),
      body: RefreshIndicator(
        onRefresh: _loadAnalytics,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 64),
                    Center(child: Text(_error!)),
                    Center(child: TextButton(onPressed: _loadAnalytics, child: const Text('Retry'))),
                  ])
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildFilters(),
                      const SizedBox(height: 16),
                      _buildMetricsGrid(metrics),
                      const SizedBox(height: 20),
                      _SectionTitle(color: AppColors.warning, label: 'Employee Payroll Analysis'),
                      const SizedBox(height: 8),
                      _buildPayrollStats((payroll['stats'] as Map?)?.cast<String, dynamic>() ?? {}),
                      const SizedBox(height: 12),
                      _ChartCard(height: 220, child: _buildPayrollBar((payroll['bar'] as Map?)?.cast<String, dynamic>() ?? {})),
                      const SizedBox(height: 12),
                      _ChartCard(height: 220, child: _buildDonut((payroll['donut'] as List?) ?? [])),
                      const SizedBox(height: 20),
                      _SectionTitle(color: AppColors.success, label: 'Employee Attendance Analysis'),
                      const SizedBox(height: 8),
                      _ChartCard(height: 220, child: _buildAttendanceLine(attendance)),
                      const SizedBox(height: 20),
                      _SectionTitle(color: AppColors.warning, label: 'Employee Asset Analysis'),
                      const SizedBox(height: 8),
                      _ChartCard(height: 220, child: _buildAssetBar(asset)),
                      const SizedBox(height: 20),
                      _SectionTitle(color: AppColors.success, label: 'Employee Leave Request Analysis'),
                      const SizedBox(height: 8),
                      _ChartCard(height: 220, child: _buildDonut(leave)),
                      const SizedBox(height: 20),
                      _SectionTitle(color: AppColors.warning, label: 'Employee Group Analysis'),
                      const SizedBox(height: 8),
                      _ChartCard(height: 220, child: _buildGroupPie(group)),
                      const SizedBox(height: 24),
                    ],
                  ),
      ),
    );
  }

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range, size: 18),
          label: Text('${DateFormat('dd MMM').format(_range.start)} - ${DateFormat('dd MMM yyyy').format(_range.end)}'),
          onPressed: () async {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
              lastDate: DateTime.now(),
              initialDateRange: _range,
            );
            if (picked != null) {
              setState(() => _range = picked);
              _loadAnalytics();
            }
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                initialValue: _departmentId,
                decoration: const InputDecoration(labelText: 'Department'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('All Departments')),
                  ..._departments.map((d) => (d as Map)).map(
                        (d) => DropdownMenuItem<int?>(
                          value: int.tryParse((d['id'] ?? '').toString()),
                          child: Text((d['name'] ?? '').toString(), overflow: TextOverflow.ellipsis),
                        ),
                      ),
                ],
                onChanged: (value) {
                  setState(() => _departmentId = value);
                  _loadAnalytics();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int?>(
                initialValue: _shiftId,
                decoration: const InputDecoration(labelText: 'Shift'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('All Shifts')),
                  ..._shifts.map((s) => (s as Map)).map(
                        (s) => DropdownMenuItem<int?>(
                          value: int.tryParse((s['id'] ?? '').toString()),
                          child: Text((s['name'] ?? '').toString(), overflow: TextOverflow.ellipsis),
                        ),
                      ),
                ],
                onChanged: (value) {
                  setState(() => _shiftId = value);
                  _loadAnalytics();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricsGrid(Map<String, dynamic> metrics) {
    final items = [
      ('Shift Employees', metrics['shiftEmployees']),
      ('Total Overtime', metrics['totalOvertime']),
      ('Total In Shift', metrics['totalInShift']),
      ('Shift Presents', metrics['shiftPresents']),
      ('Shift Absents', metrics['shiftAbsents']),
      ('Total Employees', metrics['totalEmployees']),
      ('Total Presents', metrics['totalPresents']),
      ('Total Absents', metrics['totalAbsents']),
      ('Total On Leave', metrics['totalOnLeave']),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.3,
      children: items.map((item) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.slate400.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${item.$2 ?? 0}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text(item.$1, textAlign: TextAlign.center, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.slate600)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPayrollStats(Map<String, dynamic> stats) {
    final items = [
      ('Total Outstanding', stats['totalOutstanding']),
      ('Total Salary', stats['totalSalary']),
      ('Payable Days', stats['payableDays']),
      ('Total Generated', stats['totalGenerated']),
    ];
    return Row(
      children: items
          .map((item) => Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(border: Border.all(color: AppColors.slate400.withValues(alpha: 0.25)), borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.$1, style: TextStyle(fontSize: 8, color: AppColors.slate600), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('${item.$2 ?? 0}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildPayrollBar(Map<String, dynamic> bar) {
    final categories = ((bar['categories'] as List?) ?? []).cast<dynamic>();
    final series = ((bar['series'] as List?) ?? []).cast<dynamic>();
    if (categories.isEmpty || series.isEmpty) return const _EmptyChart();

    final groups = <BarChartGroupData>[];
    for (var i = 0; i < categories.length; i++) {
      final rods = <BarChartRodData>[];
      for (final s in series) {
        final map = (s as Map);
        final data = ((map['data'] as List?) ?? []);
        final value = i < data.length ? (num.tryParse((data[i] ?? 0).toString()) ?? 0).toDouble() : 0.0;
        final colorHex = (map['color'] ?? '').toString();
        rods.add(BarChartRodData(toY: value, color: _parseHexColor(colorHex, fallback: AppColors.brand), width: 12));
      }
      groups.add(BarChartGroupData(x: i, barRods: rods));
    }

    return BarChart(BarChartData(
      barGroups: groups,
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= categories.length) return const SizedBox.shrink();
              return Padding(padding: const EdgeInsets.only(top: 4), child: Text(categories[index].toString(), style: const TextStyle(fontSize: 9)));
            },
          ),
        ),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: const FlGridData(drawVerticalLine: false),
      borderData: FlBorderData(show: false),
    ));
  }

  Widget _buildAttendanceLine(Map<String, dynamic> attendance) {
    final dates = ((attendance['dates'] as List?) ?? []).cast<dynamic>();
    final data = ((attendance['data'] as List?) ?? []).cast<dynamic>();
    if (dates.isEmpty || data.isEmpty) return const _EmptyChart();

    final spots = <FlSpot>[
      for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), (num.tryParse((data[i] ?? 0).toString()) ?? 0).toDouble()),
    ];

    return LineChart(LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: AppColors.success,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: AppColors.success.withValues(alpha: 0.15)),
        ),
      ],
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: (dates.length / 4).clamp(1, dates.length).toDouble(),
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= dates.length) return const SizedBox.shrink();
              return Padding(padding: const EdgeInsets.only(top: 4), child: Text(dates[index].toString(), style: const TextStyle(fontSize: 9)));
            },
          ),
        ),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: const FlGridData(drawVerticalLine: false),
      borderData: FlBorderData(show: false),
    ));
  }

  Widget _buildAssetBar(Map<String, dynamic> asset) {
    return _buildPayrollBar(asset);
  }

  Widget _buildDonut(List<dynamic> slices) {
    if (slices.isEmpty) return const _EmptyChart();
    final sections = slices.map((raw) {
      final map = (raw as Map);
      final value = (num.tryParse((map['value'] ?? 0).toString()) ?? 0).toDouble();
      final color = _parseHexColor((map['color'] ?? '').toString(), fallback: AppColors.brand);
      return PieChartSectionData(value: value, color: color, title: (map['label'] ?? '').toString(), radius: 60, titleStyle: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700));
    }).toList();
    return PieChart(PieChartData(sections: sections, centerSpaceRadius: 36, sectionsSpace: 2));
  }

  Widget _buildGroupPie(Map<String, dynamic> group) {
    final labels = ((group['labels'] as List?) ?? []).cast<dynamic>();
    final data = ((group['data'] as List?) ?? []).cast<dynamic>();
    final colors = ((group['colors'] as List?) ?? []).cast<dynamic>();
    if (labels.isEmpty || data.isEmpty) return const _EmptyChart();

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < labels.length; i++) {
      final value = i < data.length ? (num.tryParse((data[i] ?? 0).toString()) ?? 0).toDouble() : 0.0;
      final color = i < colors.length ? _parseHexColor(colors[i].toString(), fallback: AppColors.brand) : AppColors.brand;
      sections.add(PieChartSectionData(value: value, color: color, title: labels[i].toString(), radius: 60, titleStyle: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)));
    }
    return PieChart(PieChartData(sections: sections, centerSpaceRadius: 0, sectionsSpace: 2));
  }

  Color _parseHexColor(String raw, {required Color fallback}) {
    var hex = raw.trim();
    if (!hex.startsWith('#')) return fallback;
    hex = hex.substring(1);
    final value = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    return value != null ? Color(value) : fallback;
  }
}

class _SectionTitle extends StatelessWidget {
  final Color color;
  final String label;
  const _SectionTitle({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 4, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  final double height;
  final Widget child;
  const _ChartCard({required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.slate400.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('No data for this range.', style: TextStyle(color: AppColors.slate400, fontSize: 12)));
  }
}
