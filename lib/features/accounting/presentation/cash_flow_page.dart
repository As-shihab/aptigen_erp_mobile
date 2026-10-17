import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../shared/widgets/aptigen_app_bar.dart';
import '../data/accounting_service.dart';
import '../models/accounting_models.dart';

/// Cash Flow overview — a focused subset of erp/desktop's
/// AccountingCashFlow.tsx, which is a full cross-module BI dashboard (sales,
/// store MRR, purchase orders, payroll, ...). Mobile scope here is
/// deliberately just what this module itself owns — bank/cash balances and
/// Payment Voucher receipts/payments — not a port of every KPI on that page.
class CashFlowPage extends StatefulWidget {
  const CashFlowPage({super.key});

  @override
  State<CashFlowPage> createState() => _CashFlowPageState();
}

class _CashFlowPageState extends State<CashFlowPage> {
  final _service = AccountingService(ApiClient());
  bool _loading = true;
  String? _error;
  List<PaymentVoucherRow> _vouchers = [];
  List<BankAccountInfo> _bankAccounts = [];

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
      final vouchers = await _service.loadPaymentVouchers();
      final bankAccounts = await _service.loadBankAccounts();
      if (!mounted) return;
      setState(() {
        _vouchers = vouchers;
        _bankAccounts = bankAccounts;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load cash flow data.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AptigenAppBar(title: 'Cash Flow', showBack: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: AppColors.slate600)))
              : RefreshIndicator(color: AppColors.brand, onRefresh: _load, child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthVouchers = _vouchers.where((v) {
      final date = DateTime.tryParse(v.voucherDate ?? '');
      return date != null && !date.isBefore(monthStart);
    });
    final receipts = monthVouchers.where((v) => v.type == 'RECEIPT').fold<double>(0, (sum, v) => sum + v.amount);
    final payments = monthVouchers.where((v) => v.type == 'PAYMENT').fold<double>(0, (sum, v) => sum + v.amount);
    final net = receipts - payments;

    final bankBalance = _bankAccounts.where((b) => b.type == 'BANK').fold<double>(0, (sum, b) => sum + b.currentBalance);
    final cashBalance = _bankAccounts.where((b) => b.type == 'CASH').fold<double>(0, (sum, b) => sum + b.currentBalance);

    final days = List.generate(14, (i) => DateTime(now.year, now.month, now.day).subtract(Duration(days: 13 - i)));
    final dailyIn = days.map((d) => _vouchers
        .where((v) => v.type == 'RECEIPT' && _isSameDay(DateTime.tryParse(v.voucherDate ?? ''), d))
        .fold<double>(0, (sum, v) => sum + v.amount)).toList();
    final dailyOut = days.map((d) => _vouchers
        .where((v) => v.type == 'PAYMENT' && _isSameDay(DateTime.tryParse(v.voucherDate ?? ''), d))
        .fold<double>(0, (sum, v) => sum + v.amount)).toList();
    final maxY = [...dailyIn, ...dailyOut].fold<double>(0, (m, v) => v > m ? v : m);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            Expanded(child: _Kpi(label: 'Bank balance', value: bankBalance, color: AppColors.brand)),
            const SizedBox(width: 10),
            Expanded(child: _Kpi(label: 'Cash balance', value: cashBalance, color: AppColors.success)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _Kpi(label: 'Receipts (this month)', value: receipts, color: AppColors.success)),
            const SizedBox(width: 10),
            Expanded(child: _Kpi(label: 'Payments (this month)', value: payments, color: AppColors.error)),
          ],
        ),
        const SizedBox(height: 10),
        _Kpi(label: 'Net cash flow (this month)', value: net, color: net < 0 ? AppColors.error : AppColors.success, wide: true),
        const SizedBox(height: 20),
        Text('Cash in vs cash out — last 14 days', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.slate600)),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: maxY <= 0
              ? Center(child: Text('No payment vouchers in this window.', style: TextStyle(color: AppColors.slate600)))
              : BarChart(
                  BarChartData(
                    maxY: maxY * 1.15,
                    alignment: BarChartAlignment.spaceAround,
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= days.length || index % 3 != 0) return const SizedBox.shrink();
                            final d = days[index];
                            return Padding(padding: const EdgeInsets.only(top: 6), child: Text('${d.day}/${d.month}', style: const TextStyle(fontSize: 9)));
                          },
                        ),
                      ),
                    ),
                    barGroups: List.generate(days.length, (i) => BarChartGroupData(x: i, barRods: [
                          BarChartRodData(toY: dailyIn[i], color: AppColors.success, width: 5, borderRadius: BorderRadius.circular(2)),
                          BarChartRodData(toY: dailyOut[i], color: AppColors.error, width: 5, borderRadius: BorderRadius.circular(2)),
                        ])),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Legend(color: AppColors.success, label: 'Cash in'),
            const SizedBox(width: 16),
            _Legend(color: AppColors.error, label: 'Cash out'),
          ],
        ),
      ],
    );
  }

  bool _isSameDay(DateTime? a, DateTime b) => a != null && a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Kpi extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool wide;
  const _Kpi({required this.label, required this.value, required this.color, this.wide = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatMoney(value), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.slate600)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.slate600)),
      ],
    );
  }
}
