import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/network/socket_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/employee_dashboard_service.dart';

class ProfileTab extends StatefulWidget {
  final Map<String, dynamic> employee;
  final Map<String, dynamic> kpi;
  final List<dynamic> leaveBalances;

  const ProfileTab({super.key, required this.employee, required this.kpi, required this.leaveBalances});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _service = EmployeeDashboardService(ApiClient());
  late Map<String, dynamic> _kpi;
  bool _punching = false;
  void Function(dynamic)? _attendanceListener;

  int get _employeeId => int.tryParse((widget.employee['id'] ?? '').toString()) ?? 0;

  @override
  void initState() {
    super.initState();
    _kpi = Map<String, dynamic>.from(widget.kpi);
    _connectRealtime();
  }

  Future<void> _connectRealtime() async {
    final context = await resolveSocketContext(ApiClient());
    if (context == null || !mounted) return;
    final socket = AppSocket.connect(context);

    void listener(dynamic payload) {
      if (payload is! Map) return;
      final eventEmployeeId = int.tryParse((payload['employee_id'] ?? '').toString());
      if (eventEmployeeId != _employeeId) return;
      if (!mounted) return;
      setState(() {
        _kpi['checkIn'] = payload['check_in_time'];
        _kpi['checkOut'] = payload['check_out_time'];
      });
    }

    _attendanceListener = listener;
    socket.on('attendance:recorded', listener);
  }

  @override
  void dispose() {
    final listener = _attendanceListener;
    if (listener != null) {
      AppSocket.instance?.off('attendance:recorded', listener);
    }
    super.dispose();
  }

  Future<void> _punch() async {
    setState(() => _punching = true);
    try {
      final result = await _service.punchAttendance();
      if (!mounted) return;
      setState(() {
        _kpi['checkIn'] = result['checkInTime'];
        _kpi['checkOut'] = result['checkOutTime'];
      });
      final action = (result['action'] ?? '').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(action == 'check-in' ? 'Checked in' : 'Checked out')),
      );
    } catch (error) {
      if (!mounted) return;
      debugPrint('punchAttendance failed: $error');
      final message = error is ApiException
          ? 'Could not record attendance (${error.statusCode}): ${error.message}'
          : 'Could not record attendance: $error';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _punching = false);
    }
  }

  String _fmtTime(dynamic value) {
    if (value == null) return '—';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return '—';
    return DateFormat('hh:mm a').format(parsed.toLocal());
  }

  String _fmtDate(dynamic value) {
    if (value == null) return '—';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return '—';
    return DateFormat('dd MMM yyyy').format(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final employee = widget.employee;
    final firstName = (employee['first_name'] ?? '').toString();
    final lastName = (employee['last_name'] ?? '').toString();
    final name = [firstName, lastName].where((s) => s.trim().isNotEmpty).join(' ');
    final initials = [firstName, lastName]
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase())
        .join();
    final isActive = employee['is_active'] == true;
    final department = (employee['department'] as Map?)?['name']?.toString();
    final designation = (employee['designation'] as Map?)?['name']?.toString();
    final shift = (employee['shift'] as Map?)?['name']?.toString();
    final salary = num.tryParse((_kpi['salary'] ?? 0).toString()) ?? 0;
    final presentDays = _kpi['presentDaysThisMonth'] ?? 0;

    final hasCheckedIn = _kpi['checkIn'] != null;
    final hasCheckedOut = _kpi['checkOut'] != null;
    final canCheckIn = !hasCheckedIn;
    final canCheckOut = hasCheckedIn && !hasCheckedOut;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.slate400.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.brand.withValues(alpha: 0.15),
                child: Text(initials, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.brand)),
              ),
              const SizedBox(height: 12),
              Text(name.isEmpty ? '—' : name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              if (designation != null) Text(designation, style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  if ((employee['employee_no'] ?? '').toString().isNotEmpty)
                    _Chip(text: employee['employee_no'].toString(), color: AppColors.brand),
                  _Chip(text: isActive ? '● Active' : '● Inactive', color: isActive ? AppColors.success : AppColors.slate400),
                  if (department != null) _Chip(text: department, color: AppColors.slate600),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                      onPressed: (canCheckIn && !_punching) ? _punch : null,
                      icon: const Icon(Icons.login, size: 18),
                      label: Text(_punching && canCheckIn ? 'Checking in...' : 'Check In'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                      onPressed: (canCheckOut && !_punching) ? _punch : null,
                      icon: const Icon(Icons.logout, size: 18),
                      label: Text(_punching && canCheckOut ? 'Checking out...' : 'Check Out'),
                    ),
                  ),
                ],
              ),
              if (hasCheckedIn && hasCheckedOut) ...[
                const SizedBox(height: 8),
                Text('Attendance completed for today.', style: TextStyle(fontSize: 11, color: AppColors.slate600)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: [
            _KpiCard(label: 'Check-In', value: _fmtTime(_kpi['checkIn']), color: AppColors.success),
            _KpiCard(label: 'Check-Out', value: _fmtTime(_kpi['checkOut']), color: AppColors.brand),
            _KpiCard(label: 'Salary', value: salary.toStringAsFixed(0), color: AppColors.warning),
            _KpiCard(label: 'Present', value: '$presentDays days', color: AppColors.info),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Details',
          children: [
            _DetailRow(label: 'Email', value: (employee['email'] ?? '—').toString()),
            _DetailRow(label: 'Phone', value: (employee['contact_number'] ?? '—').toString()),
            _DetailRow(label: 'Shift', value: shift ?? '—'),
            _DetailRow(label: 'Joining Date', value: _fmtDate(employee['joining_date'])),
            _DetailRow(label: 'Blood Group', value: (employee['blood_group'] ?? '—').toString()),
            _DetailRow(label: 'Emergency Contact', value: (employee['emergency_contact_name'] ?? '—').toString()),
          ],
        ),
        if (widget.leaveBalances.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Leave Balances',
            children: widget.leaveBalances.map((raw) {
              final b = (raw as Map);
              return _DetailRow(label: (b['name'] ?? '—').toString(), value: '${b['used']}/${b['total']}');
            }).toList(),
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _KpiCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate400.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppColors.slate600, fontSize: 12)),
          Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
        ],
      ),
    );
  }
}
