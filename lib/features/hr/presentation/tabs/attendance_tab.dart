import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/async_state_view.dart';
import '../../data/employee_dashboard_service.dart';

class AttendanceTab extends StatefulWidget {
  final int employeeId;
  const AttendanceTab({super.key, required this.employeeId});

  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> {
  final _service = EmployeeDashboardService(ApiClient());
  bool _loading = true;
  String? _error;
  List<dynamic> _rows = [];

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
      final rows = await _service.getAttendance(widget.employeeId);
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load attendance.');
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
        isEmpty: _rows.isEmpty,
        emptyMessage: 'No attendance records yet.',
        emptyIcon: Icons.event_busy,
        onRetry: _load,
        builder: (context) => ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final row = (_rows[index] as Map).cast<String, dynamic>();
            final date = DateTime.tryParse((row['attendance_date'] ?? '').toString());
            final checkIn = DateTime.tryParse((row['check_in_time'] ?? '').toString());
            final checkOut = DateTime.tryParse((row['check_out_time'] ?? '').toString());
            final hasLate = row['has_late'] == true;
            final hasOvertime = row['has_overtime'] == true;
            final overtimeMinutes = num.tryParse((row['overtime_minutes'] ?? 0).toString()) ?? 0;

            return ListTile(
              leading: SizedBox(
                width: 44,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(date != null ? DateFormat('dd MMM').format(date) : '—', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    Text(date != null ? DateFormat('EEE').format(date).toUpperCase() : '', style: TextStyle(fontSize: 9, color: AppColors.slate400)),
                  ],
                ),
              ),
              title: Row(
                children: [
                  Icon(Icons.login, size: 13, color: AppColors.success),
                  const SizedBox(width: 3),
                  Text(checkIn != null ? DateFormat('hh:mm a').format(checkIn.toLocal()) : '—', style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 10),
                  Icon(Icons.logout, size: 13, color: AppColors.error),
                  const SizedBox(width: 3),
                  Text(checkOut != null ? DateFormat('hh:mm a').format(checkOut.toLocal()) : '—', style: const TextStyle(fontSize: 12)),
                ],
              ),
              subtitle: hasOvertime && overtimeMinutes > 0
                  ? Text('OT ${(overtimeMinutes / 60).toStringAsFixed(1)}h', style: TextStyle(color: AppColors.warning, fontSize: 11))
                  : null,
              trailing: StatusChip(
                label: hasLate ? 'Late' : 'Present',
                color: hasLate ? AppColors.warning : AppColors.success,
              ),
            );
          },
        ),
      ),
    );
  }
}
