import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/aptigen_app_bar.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../data/accounting_service.dart';
import '../models/accounting_models.dart';
import 'account_form_page.dart';

/// Bank/Cash accounts — a read-focused view over the same rows
/// ChartOfAccountsPage manages (bank_accounts is a sub-ledger of accounts,
/// not a separate table with its own CRUD screen — see account.prisma).
/// Tapping a row opens the same account form used there, so editing stays
/// in exactly one place.
class BankCashAccountsPage extends StatefulWidget {
  const BankCashAccountsPage({super.key});

  @override
  State<BankCashAccountsPage> createState() => _BankCashAccountsPageState();
}

class _BankCashAccountsPageState extends State<BankCashAccountsPage> {
  final _service = AccountingService(ApiClient());
  bool _loading = true;
  String? _error;
  List<AccountRow> _accounts = [];

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
      final accounts = await _service.loadAccounts();
      if (!mounted) return;
      setState(() => _accounts = accounts.where((a) => a.bankAccount != null).toList());
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load bank/cash accounts.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({AccountRow? editing}) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AccountFormPage(editing: editing)));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final bankAccounts = _accounts.where((a) => a.bankAccount!.type == 'BANK').toList();
    final cashAccounts = _accounts.where((a) => a.bankAccount!.type == 'CASH').toList();
    final bankTotal = bankAccounts.fold<double>(0, (sum, a) => sum + a.bankAccount!.currentBalance);
    final cashTotal = cashAccounts.fold<double>(0, (sum, a) => sum + a.bankAccount!.currentBalance);

    return Scaffold(
      appBar: AptigenAppBar(title: 'Bank / Cash Accounts', showBack: true),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.brand,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: _load,
        child: AsyncStateView(
          loading: _loading,
          error: _error,
          isEmpty: _accounts.isEmpty,
          emptyMessage: 'No bank or cash accounts yet — tap + to add one.',
          emptyIcon: Icons.account_balance_outlined,
          onRetry: _load,
          builder: (context) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            children: [
              Row(
                children: [
                  Expanded(child: _TotalTile(icon: Icons.account_balance, label: 'Bank balance', value: bankTotal, color: AppColors.brand)),
                  const SizedBox(width: 10),
                  Expanded(child: _TotalTile(icon: Icons.payments_outlined, label: 'Cash balance', value: cashTotal, color: AppColors.success)),
                ],
              ),
              const SizedBox(height: 16),
              if (bankAccounts.isNotEmpty) ...[
                _SectionHeader(label: 'Bank'),
                ...bankAccounts.map((a) => _BankTile(row: a, onTap: () => _openForm(editing: a))),
                const SizedBox(height: 12),
              ],
              if (cashAccounts.isNotEmpty) ...[
                _SectionHeader(label: 'Cash'),
                ...cashAccounts.map((a) => _BankTile(row: a, onTap: () => _openForm(editing: a))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final Color color;
  const _TotalTile({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value.toStringAsFixed(2), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.slate600)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.slate600, letterSpacing: 0.4)),
    );
  }
}

class _BankTile extends StatelessWidget {
  final AccountRow row;
  final VoidCallback onTap;
  const _BankTile({required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bank = row.bankAccount!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.slate400.withValues(alpha: 0.2))),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5), overflow: TextOverflow.ellipsis)),
                          if (!bank.isMain)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                              child: const Text('Sub-account', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.warning)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [if (bank.bankName != null) bank.bankName!, if (bank.accountNo != null) bank.accountNo!].join(' · '),
                        style: TextStyle(fontSize: 11, color: AppColors.slate600),
                      ),
                    ],
                  ),
                ),
                Text(bank.currentBalance.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
