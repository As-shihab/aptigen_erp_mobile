import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/async_state_view.dart';
import '../../data/employee_dashboard_service.dart';

const Map<String, Color> _payrollStatusColors = {
  'PENDING': AppColors.warning,
  'PAID': AppColors.success,
  'CANCELLED': AppColors.error,
};

class PayrollTab extends StatefulWidget {
  final int employeeId;
  const PayrollTab({super.key, required this.employeeId});

  @override
  State<PayrollTab> createState() => _PayrollTabState();
}

class _PayrollTabState extends State<PayrollTab> {
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
      final rows = await _service.getPayrolls(widget.employeeId);
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load payroll.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  num _n(Map row, String key) => num.tryParse((row[key] ?? 0).toString()) ?? 0;

  void _openDetail(Map<String, dynamic> row) {
    final start = DateTime.tryParse((row['start_date'] ?? '').toString());
    final end = DateTime.tryParse((row['end_date'] ?? '').toString());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Payslip Detail', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              '${start != null ? DateFormat('dd MMM yyyy').format(start) : '—'} → ${end != null ? DateFormat('dd MMM yyyy').format(end) : '—'}',
              style: TextStyle(color: AppColors.slate600, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _row('Basic Salary', _n(row, 'basic')),
            _row('House Rent', _n(row, 'house_rent')),
            _row('Medical Allowance', _n(row, 'medical_allowance')),
            _row('Transport Allowance', _n(row, 'transport_allowance')),
            _row('Other Allowance', _n(row, 'other_allowance')),
            _row('Bonuses', _n(row, 'bonuses'), color: AppColors.success),
            const Divider(height: 24),
            _row('Gross Salary', _n(row, 'gross_salary'), bold: true, color: AppColors.success),
            const SizedBox(height: 12),
            _row('Tax', _n(row, 'tax'), color: AppColors.error),
            _row('Social Security', _n(row, 'social_security'), color: AppColors.error),
            _row('Other Deductions', _n(row, 'other_deductions'), color: AppColors.error),
            _row('Penalties', _n(row, 'penalties'), color: AppColors.error),
            _row('Total Deductions', _n(row, 'total_deductions'), bold: true, color: AppColors.error),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Net Pay', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text(_n(row, 'net_salary').toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.success)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, num value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: 12)),
          Text(value.toStringAsFixed(0), style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w700, fontSize: 13, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: AsyncStateView(
        loading: _loading,
        error: _error,
        isEmpty: _rows.isEmpty,
        emptyMessage: 'No payroll records yet.',
        emptyIcon: Icons.account_balance_wallet_outlined,
        onRetry: _load,
        builder: (context) => ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final row = (_rows[index] as Map).cast<String, dynamic>();
            final start = DateTime.tryParse((row['start_date'] ?? '').toString());
            final end = DateTime.tryParse((row['end_date'] ?? '').toString());
            final status = (row['status'] ?? '').toString();
            return ListTile(
              onTap: () => _openDetail(row),
              title: Text(
                '${start != null ? DateFormat('dd MMM yyyy').format(start) : '—'} → ${end != null ? DateFormat('dd MMM yyyy').format(end) : '—'}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              subtitle: Text('Gross ${_n(row, 'gross_salary').toStringAsFixed(0)} · Deductions ${_n(row, 'total_deductions').toStringAsFixed(0)}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_n(row, 'net_salary').toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.success)),
                  const SizedBox(height: 4),
                  StatusChip(label: status, color: _payrollStatusColors[status] ?? AppColors.slate400),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
