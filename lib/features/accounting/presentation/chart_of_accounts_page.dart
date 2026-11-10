import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/aptigen_app_bar.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../data/accounting_service.dart';
import '../models/accounting_models.dart';
import 'account_form_page.dart';

const _kTypeColors = {
  'ASSET': AppColors.brand,
  'LIABILITY': AppColors.error,
  'EQUITY': Color(0xFF8B5CF6),
  'INCOME': AppColors.success,
  'EXPENSE': AppColors.warning,
};

/// Chart of Accounts — mirrors erp/desktop's ChartOfAccounts.tsx: the ledger
/// tree plus each account's optional Bank/Cash sub-ledger row, in one list.
class ChartOfAccountsPage extends StatefulWidget {
  const ChartOfAccountsPage({super.key});

  @override
  State<ChartOfAccountsPage> createState() => _ChartOfAccountsPageState();
}

class _ChartOfAccountsPageState extends State<ChartOfAccountsPage> {
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
      setState(() => _accounts = accounts);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load accounts.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({AccountRow? editing}) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AccountFormPage(editing: editing)));
    if (saved == true) _load();
  }

  Future<void> _delete(AccountRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete account'),
        content: Text('Delete "${row.label}"? Any journal lines already posted against it will block this.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteAccount(row.id);
      _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete — it may still have journal lines posted against it.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AptigenAppBar(title: 'Chart of accounts', showBack: true),
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
          emptyMessage: 'No accounts yet — tap + to add one.',
          emptyIcon: Icons.account_balance_outlined,
          onRetry: _load,
          builder: (context) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: _accounts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _AccountTile(
              row: _accounts[index],
              onTap: () => _openForm(editing: _accounts[index]),
              onDelete: () => _delete(_accounts[index]),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final AccountRow row;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _AccountTile({required this.row, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final typeColor = _kTypeColors[row.type] ?? AppColors.slate600;
    return Dismissible(
      key: ValueKey(row.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_outline, color: AppColors.error),
      ),
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
                Container(
                  width: 6,
                  height: 36,
                  decoration: BoxDecoration(color: typeColor, borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(row.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5), overflow: TextOverflow.ellipsis),
                          ),
                          if (!row.isActive)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.slate400.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                              child: const Text('Inactive', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(row.type, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: typeColor)),
                          if (row.bankAccount != null) ...[
                            const SizedBox(width: 8),
                            Icon(row.bankAccount!.type == 'BANK' ? Icons.account_balance : Icons.payments_outlined, size: 12, color: AppColors.slate600),
                            const SizedBox(width: 3),
                            Text(row.bankAccount!.type == 'BANK' ? 'Bank' : 'Cash', style: TextStyle(fontSize: 11, color: AppColors.slate600)),
                          ],
                          if (row.parentLabel != null) ...[
                            const SizedBox(width: 8),
                            Expanded(child: Text('under ${row.parentLabel}', style: TextStyle(fontSize: 11, color: AppColors.slate400), overflow: TextOverflow.ellipsis)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (row.bankAccount != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      row.bankAccount!.currentBalance.toStringAsFixed(2),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
