import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';

class ProfileTab extends StatelessWidget {
  final Map<String, dynamic> employee;
  final Map<String, dynamic> kpi;
  final List<dynamic> leaveBalances;

  const ProfileTab({super.key, required this.employee, required this.kpi, required this.leaveBalances});

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
    final salary = num.tryParse((kpi['salary'] ?? 0).toString()) ?? 0;
    final presentDays = kpi['presentDaysThisMonth'] ?? 0;

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
            _KpiCard(label: 'Check-In', value: _fmtTime(kpi['checkIn']), color: AppColors.success),
            _KpiCard(label: 'Check-Out', value: _fmtTime(kpi['checkOut']), color: AppColors.brand),
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
        if (leaveBalances.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Leave Balances',
            children: leaveBalances.map((raw) {
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
