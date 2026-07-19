import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/async_state_view.dart';
import '../../data/employee_dashboard_service.dart';

const Map<String, Color> _rosterStatusColors = {
  'present': AppColors.success,
  'absent': Color(0xFFDC2626),
  'leave': AppColors.warning,
  'off': AppColors.slate400,
  'upcoming': AppColors.brand,
};
const Map<String, String> _rosterStatusLabels = {
  'present': 'Present',
  'absent': 'Absent',
  'leave': 'On Leave',
  'off': 'Day Off',
  'upcoming': 'Upcoming',
};

/// Simplified to a dated list (rather than porting a full custom calendar
/// grid widget) — a month either side of today, matching desktop's window.
class MyCalendarTab extends StatefulWidget {
  final int employeeId;
  const MyCalendarTab({super.key, required this.employeeId});

  @override
  State<MyCalendarTab> createState() => _MyCalendarTabState();
}

class _MyCalendarTabState extends State<MyCalendarTab> {
  final _service = EmployeeDashboardService(ApiClient());
  bool _loading = true;
  String? _error;
  List<dynamic> _roster = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month - 1, 1);
      final end = DateTime(now.year, now.month + 2, 0);
      final rows = await _service.getRoster(start, end);
      if (!mounted) return;
      setState(() => _roster = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load calendar.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: AsyncStateView(
        loading: _loading,
        error: _error,
        isEmpty: _roster.isEmpty,
        emptyMessage: 'No roster data available.',
        emptyIcon: Icons.calendar_month,
        onRetry: _load,
        builder: (context) => ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _roster.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final r = (_roster[index] as Map).cast<String, dynamic>();
            final date = DateTime.tryParse((r['date'] ?? '').toString());
            final status = (r['status'] ?? '').toString();
            final isDayOff = status == 'off' || status == 'leave';
            final label = _rosterStatusLabels[status] ?? status;
            final color = _rosterStatusColors[status] ?? AppColors.slate400;
            final isToday = date != null && DateUtils.isSameDay(date, DateTime.now());

            return ListTile(
              tileColor: isToday ? AppColors.brand.withValues(alpha: 0.06) : null,
              leading: SizedBox(
                width: 44,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(date != null ? DateFormat('dd').format(date) : '—', style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(date != null ? DateFormat('MMM').format(date).toUpperCase() : '', style: TextStyle(fontSize: 9, color: AppColors.slate400)),
                  ],
                ),
              ),
              title: Text(isDayOff ? label : (r['shift'] ?? '—').toString(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              subtitle: isDayOff ? null : Text((r['time'] ?? '').toString(), style: const TextStyle(fontSize: 11)),
              trailing: StatusChip(label: label, color: color),
            );
          },
        ),
      ),
    );
  }
}
