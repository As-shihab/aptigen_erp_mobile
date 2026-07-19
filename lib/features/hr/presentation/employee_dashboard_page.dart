import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/aptigen_app_bar.dart';
import '../data/employee_dashboard_service.dart';
import 'tabs/asset_tab.dart';
import 'tabs/attendance_tab.dart';
import 'tabs/employee_request_tab.dart';
import 'tabs/my_calendar_tab.dart';
import 'tabs/my_leave_tab.dart';
import 'tabs/notice_tab.dart';
import 'tabs/payroll_tab.dart';
import 'tabs/profile_tab.dart';

/// Ported from erp/desktop's EmployeeDashboard.tsx — a "My Profile" tab
/// (inline in the desktop file, split into its own widget here) plus the
/// 7 tabs/*.tsx files.
class EmployeeDashboardPage extends StatefulWidget {
  const EmployeeDashboardPage({super.key});

  @override
  State<EmployeeDashboardPage> createState() => _EmployeeDashboardPageState();
}

class _EmployeeDashboardPageState extends State<EmployeeDashboardPage> {
  final _service = EmployeeDashboardService(ApiClient());

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _dashboard;

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
      final data = await _service.getMyDashboard();
      if (!mounted) return;
      setState(() => _dashboard = data);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load your dashboard. No employee record is linked to this account, or the request failed.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: const AptigenAppBar(title: 'Employee Dashboard', showBack: true),
        body: const Center(child: CircularProgressIndicator(color: AppColors.brand)),
      );
    }

    if (_error != null || _dashboard == null) {
      return Scaffold(
        appBar: const AptigenAppBar(title: 'Employee Dashboard', showBack: true),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 40, color: AppColors.slate400),
                const SizedBox(height: 12),
                Text(_error ?? 'Something went wrong.', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    final employee = (_dashboard!['employee'] as Map?)?.cast<String, dynamic>() ?? {};
    final kpi = (_dashboard!['kpi'] as Map?)?.cast<String, dynamic>() ?? {};
    final leaveBalances = (_dashboard!['leaveBalances'] as List?) ?? [];
    final employeeId = int.tryParse((employee['id'] ?? '').toString()) ?? 0;
    final departmentId = int.tryParse((employee['department_id'] ?? '').toString());
    final designationId = int.tryParse((employee['designation_id'] ?? '').toString());

    return DefaultTabController(
      length: 8,
      child: Scaffold(
        appBar: AptigenAppBar(
          title: 'Employee Dashboard',
          showBack: true,
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'My Profile'),
              Tab(text: 'Attendance'),
              Tab(text: 'My Leave'),
              Tab(text: 'My Calendar'),
              Tab(text: 'Payroll'),
              Tab(text: 'Notice'),
              Tab(text: 'Employee Request'),
              Tab(text: 'Asset'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ProfileTab(employee: employee, kpi: kpi, leaveBalances: leaveBalances.cast<dynamic>()),
            AttendanceTab(employeeId: employeeId),
            MyLeaveTab(employeeId: employeeId),
            MyCalendarTab(employeeId: employeeId),
            PayrollTab(employeeId: employeeId),
            NoticeTab(employeeId: employeeId, departmentId: departmentId),
            EmployeeRequestTab(employeeId: employeeId, designationId: designationId),
            AssetTab(employeeId: employeeId),
          ],
        ),
      ),
    );
  }
}
