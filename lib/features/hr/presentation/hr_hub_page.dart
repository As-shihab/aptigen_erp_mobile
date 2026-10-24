import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../shared/ui/entity_crud.dart';
import '../../../shared/ui/motion_kit.dart';
import 'assets/asset_groups_page.dart';
import 'assets/asset_list_page.dart';
import 'attendance/attendance_board_page.dart';
import 'attendance/attendance_list_page.dart';
import 'biometrics/face_recognition_page.dart';
import 'biometrics/fingerprint_page.dart';
import 'blacklist/blacklist_page.dart';
import 'bonus/bonus_list_page.dart';
import 'bonus/bonus_types_page.dart';
import 'employee_dashboard_page.dart';
import 'employees/employee_groups_page.dart';
import 'employees/employee_list_page.dart';
import 'hr_analytics_page.dart';
import 'kpi/kpi_list_page.dart';
import 'kpi/promotion_history_page.dart';
import 'kpi/promotion_page.dart';
import 'leave/event_types_page.dart';
import 'leave/hr_calendar_page.dart';
import 'leave/leave_requests_page.dart';
import 'leave/leave_types_page.dart';
import 'locations/locations_page.dart';
import 'notify/notices_page.dart';
import 'notify/policies_page.dart';
import 'org/org_pages.dart';
import 'payroll/payroll_months_page.dart';
import 'payroll/payroll_page.dart';
import 'payroll/payroll_process_page.dart';
import 'payroll/salary_structure_page.dart';
import 'recruitment/hiring_page.dart';
import 'recruitment/resumes_page.dart';
import 'settings/hr_settings_page.dart';
import 'shift/roster_page.dart';
import 'shift/shift_overrides_page.dart';
import 'shift/shifts_page.dart';

typedef _Area = (IconData icon, String title, String? subtitle, VoidCallback onTap);

/// HR home — same SAP Horizon layout as the Store home (store_home_page.dart):
/// a brand headcount card, alert KPIs, quick actions, then every HR area
/// grouped like desktop's hr.nav.ts as plain list rows.
class HrHubPage extends StatefulWidget {
  const HrHubPage({super.key});

  @override
  State<HrHubPage> createState() => _HrHubPageState();
}

class _HrHubPageState extends State<HrHubPage> {
  final _client = ApiClient();
  bool _loading = true;
  int _employees = 0;
  int _present = 0;
  int _pendingLeave = 0;
  int _departments = 0;
  int _openHiring = 0;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day).toIso8601String();
    try {
      final data = await batchLoad(_client, {
        'employees': 'employees?\$select=id&\$filter=is_active eq true&\$top=5000',
        'present': 'attendance_logs?\$select=id&\$filter=attendance_date eq $today&\$top=5000',
        'leave': "leave_requests?\$select=id&\$filter=status eq 'PENDING'&\$top=5000",
        'departments': 'departments?\$select=id&\$top=1000',
        'hiring': "hiring?\$select=id&\$filter=status eq 'open'&\$top=1000",
      });
      if (!mounted) return;
      setState(() {
        _employees = data['employees']?.length ?? 0;
        _present = data['present']?.length ?? 0;
        _pendingLeave = data['leave']?.length ?? 0;
        _departments = data['departments']?.length ?? 0;
        _openHiring = data['hiring']?.length ?? 0;
      });
    } catch (_) {
      // Headline numbers are a nicety — the home still works without them.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _go(Widget page) => pushMotion(context, page).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final q = _q.trim().toLowerCase();
    final sections = [
      for (final (title, areas) in _sections())
        (title, q.isEmpty ? areas : areas.where((a) => a.$2.toLowerCase().contains(q) || (a.$3 ?? '').toLowerCase().contains(q)).toList()),
    ].where((s) => s.$2.isNotEmpty).toList();

    return MarketScaffold(
      title: 'Human resources',
      actions: [
        IconButton(tooltip: 'HR settings', icon: const Icon(Icons.settings_outlined), onPressed: () => _go(const HrSettingsPage())),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            HeaderSearch(hint: 'Find an HR area', onChanged: (v) => setState(() => _q = v)),
            if (q.isEmpty) ...[
              const SizedBox(height: 12),
              _headcountCard(),
              const SizedBox(height: 12),
              _kpis(),
              _quickActions(p),
            ],
            for (final (s, (title, areas)) in sections.indexed) ...[
              SectionHeader(title),
              MarketCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (var i = 0; i < areas.length; i++) ...[
                    if (i > 0) Divider(height: 1, indent: 62, color: p.line),
                    _areaRow(p, areas[i], sections.take(s).fold<int>(0, (n, e) => n + e.$2.length) + i),
                  ],
                ]),
              ),
            ],
            if (sections.isEmpty) MarketEmpty(icon: Icons.search_off_rounded, title: 'No HR area matches "$_q"'),
          ],
        ),
      ),
    );
  }

  Widget _headcountCard() {
    final p = MarketPalette.of(context);
    final rate = _employees == 0 ? 0 : (_present / _employees * 100).round();
    return FadeSlideIn(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Active employees', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
          const SizedBox(height: 6),
          _loading && _employees == 0
              ? const SizedBox(
                  height: 30,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(width: 120, child: LinearProgressIndicator(color: Colors.white, backgroundColor: Colors.white24)),
                  ),
                )
              : CountUp(
                  value: _employees,
                  format: (v) => '${v.round()}',
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.1),
                ),
          const SizedBox(height: 12),
          Row(children: [
            _headStat('Checked in', '$_present'),
            _headStat('Attendance', '$rate%'),
            _headStat('Departments', '$_departments'),
          ]),
          const SizedBox(height: 2),
          const Text('Today', style: TextStyle(color: Colors.white60, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _headStat(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
        ]),
      );

  Widget _kpis() {
    final notIn = (_employees - _present).clamp(0, _employees);
    final tiles = [
      KpiTile(icon: Icons.how_to_reg_outlined, label: 'Checked in', value: _present, tone: MarketTone.ok, onTap: () => _go(const AttendanceBoardPage())),
      KpiTile(
        icon: Icons.person_off_outlined,
        label: 'Not checked in',
        value: notIn,
        tone: notIn > 0 ? MarketTone.warn : MarketTone.ok,
        onTap: () => _go(const AttendanceBoardPage()),
      ),
      KpiTile(
        icon: Icons.pending_actions_outlined,
        label: 'Leave pending',
        value: _pendingLeave,
        tone: _pendingLeave > 0 ? MarketTone.warn : MarketTone.ok,
        onTap: () => _go(const LeaveRequestsPage()),
      ),
      KpiTile(icon: Icons.person_add_alt_outlined, label: 'Open positions', value: _openHiring, tone: MarketTone.info, onTap: () => _go(const HiringPage())),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.35,
      children: [for (var i = 0; i < tiles.length; i++) FadeSlideIn(index: i + 1, child: tiles[i])],
    );
  }

  Widget _quickActions(MarketPalette p) {
    final actions = <(IconData, String, VoidCallback)>[
      (Icons.fingerprint, 'Punch', () => _go(const EmployeeDashboardPage())),
      (Icons.dashboard_customize_outlined, 'Today', () => _go(const AttendanceBoardPage())),
      (Icons.event_available_outlined, 'Leave', () => _go(const LeaveRequestsPage())),
      (Icons.payments_outlined, 'Payroll', () => _go(const PayrollProcessPage())),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(children: [
        for (final a in actions)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: a.$3,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: p.card, shape: BoxShape.circle, border: Border.all(color: p.line)),
                    child: Icon(a.$1, color: p.brand, size: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(a.$2, style: TextStyle(fontSize: 12, color: p.text, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _areaRow(MarketPalette p, _Area a, int index) {
    final pending = a.$2 == 'Leave requests' ? _pendingLeave : 0;
    return ListTile(
      onTap: a.$4,
      leading: AccentListIcon(a.$1, index: index),
      title: Text(a.$2, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
      subtitle: a.$3 == null ? null : Text(a.$3!, style: TextStyle(fontSize: 12, color: p.label)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (pending > 0) StatusPill('$pending pending', tone: MarketTone.warn),
        Icon(Icons.chevron_right, color: p.label),
      ]),
    );
  }

  List<(String, List<_Area>)> _sections() => [
        ('Me', [
          (Icons.badge_outlined, 'Employee dashboard', 'Punch in, leave and payslips', () => _go(const EmployeeDashboardPage())),
          (Icons.insights_outlined, 'HR analytics', 'Headcount, attendance and payroll trends', () => _go(const HrAnalyticsPage())),
        ]),
        ('People', [
          (Icons.people_alt_outlined, 'Employees', 'Directory and profiles', () => _go(const EmployeeListPage())),
          (Icons.groups_2_outlined, 'Employee groups', 'Teams and assignments', () => _go(const EmployeeGroupsPage())),
          (Icons.account_tree_outlined, 'Departments', null, () => _go(const DepartmentsPage())),
          (Icons.workspace_premium_outlined, 'Designations', null, () => _go(const DesignationsPage())),
          (Icons.category_outlined, 'Employee types', null, () => _go(const EmployeeTypesPage())),
          (Icons.view_module_outlined, 'Employee sections', null, () => _go(const EmployeeSectionsPage())),
          (Icons.place_outlined, 'Locations', 'Work sites and geofences', () => _go(const LocationsPage())),
          (Icons.block_outlined, 'Black list', null, () => _go(const BlacklistPage())),
        ]),
        ('Attendance and shifts', [
          (Icons.fact_check_outlined, 'Attendance list', 'Daily records and corrections', () => _go(const AttendanceListPage())),
          (Icons.dashboard_customize_outlined, 'Attendance board', 'Who is in today', () => _go(const AttendanceBoardPage())),
          (Icons.schedule_outlined, 'Shifts', null, () => _go(const ShiftsPage())),
          (Icons.calendar_view_week_outlined, 'Roster', 'Weekly shift plan', () => _go(const RosterPage())),
          (Icons.swap_horiz, 'Shift overrides', 'Swaps and replacements', () => _go(const ShiftOverridesPage())),
        ]),
        ('Payroll', [
          (Icons.payments_outlined, 'Generate payroll', 'Run a month for selected employees', () => _go(const PayrollProcessPage())),
          (Icons.account_balance_wallet_outlined, 'Payroll', 'Payslips and payment status', () => _go(const PayrollPage())),
          (Icons.history, 'Payroll months', null, () => _go(const PayrollMonthsPage())),
          (Icons.tune, 'Salary structure', null, () => _go(const SalaryStructurePage())),
          (Icons.card_giftcard_outlined, 'Bonus types', null, () => _go(const BonusTypesPage())),
          (Icons.redeem_outlined, 'Bonus list', null, () => _go(const BonusListPage())),
        ]),
        ('Leave and calendar', [
          (Icons.event_available_outlined, 'Leave requests', 'Approve or reject', () => _go(const LeaveRequestsPage())),
          (Icons.beach_access_outlined, 'Leave types', null, () => _go(const LeaveTypesPage())),
          (Icons.calendar_month_outlined, 'Calendar', 'Holidays, events and leave', () => _go(const HrCalendarPage())),
          (Icons.event_note_outlined, 'Event types', null, () => _go(const EventTypesPage())),
        ]),
        ('Growth and hiring', [
          (Icons.trending_up, 'Promotion', 'Eligible employees', () => _go(const PromotionPage())),
          (Icons.manage_history_outlined, 'Promotion history', null, () => _go(const PromotionHistoryPage())),
          (Icons.speed_outlined, 'KPI list', null, () => _go(const KpiListPage())),
          (Icons.person_add_alt_outlined, 'Hiring', 'Open positions', () => _go(const HiringPage())),
          (Icons.description_outlined, 'Resumes', 'Applicants and stages', () => _go(const ResumesPage())),
        ]),
        ('Assets', [
          (Icons.devices_other_outlined, 'Asset list', null, () => _go(const AssetListPage())),
          (Icons.inventory_2_outlined, 'Asset groups', null, () => _go(const AssetGroupsPage())),
        ]),
        ('Notify', [
          (Icons.policy_outlined, 'Policies', null, () => _go(const PoliciesPage())),
          (Icons.campaign_outlined, 'Notices', null, () => _go(const NoticesPage())),
        ]),
        ('Setup', [
          (Icons.face_outlined, 'Face recognition', 'Enrol faces for punch in', () => _go(const FaceRecognitionPage())),
          (Icons.fingerprint, 'Fingerprint', 'Devices and enrolment', () => _go(const FingerprintPage())),
          (Icons.settings_outlined, 'HR settings', 'Rules and defaults', () => _go(const HrSettingsPage())),
        ]),
      ];
}
