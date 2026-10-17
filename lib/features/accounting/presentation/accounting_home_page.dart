import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/aptigen_app_bar.dart';
import 'bank_cash_accounts_page.dart';
import 'cash_flow_page.dart';
import 'chart_of_accounts_page.dart';
import 'journal_entries_page.dart';
import 'payment_vouchers_page.dart';

class _AccountingTile {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final WidgetBuilder builder;
  const _AccountingTile({required this.icon, required this.label, required this.description, required this.color, required this.builder});
}

/// Landing page for the Accounting module — mirrors erp/desktop's
/// accounting.nav.ts grouping (Chart of Accounts, Journal Entries + Ledger,
/// Payment Vouchers, Bank/Cash Accounts, Cash Flow), as a mobile launcher
/// grid instead of a sidebar.
class AccountingHomePage extends StatelessWidget {
  const AccountingHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _AccountingTile(
        icon: Icons.account_balance_outlined,
        label: 'Chart of Accounts',
        description: 'Ledger accounts, bank & cash sub-ledgers',
        color: AppColors.brand,
        builder: (_) => const ChartOfAccountsPage(),
      ),
      _AccountingTile(
        icon: Icons.menu_book_outlined,
        label: 'Journal Entries',
        description: 'Post and review general ledger entries',
        color: const Color(0xFF8B5CF6),
        builder: (_) => const JournalEntriesPage(),
      ),
      _AccountingTile(
        icon: Icons.receipt_long_outlined,
        label: 'Payment Vouchers',
        description: 'Record receipts and payments',
        color: AppColors.success,
        builder: (_) => const PaymentVouchersPage(),
      ),
      _AccountingTile(
        icon: Icons.savings_outlined,
        label: 'Bank / Cash Accounts',
        description: 'Balances across every bank & cash account',
        color: AppColors.info,
        builder: (_) => const BankCashAccountsPage(),
      ),
      _AccountingTile(
        icon: Icons.show_chart,
        label: 'Cash Flow',
        description: 'Receipts, payments, and balances at a glance',
        color: AppColors.warning,
        builder: (_) => const CashFlowPage(),
      ),
    ];

    return Scaffold(
      appBar: AptigenAppBar(title: 'Accounting', showBack: true),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final tile = tiles[index];
          return Material(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: tile.builder)),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.slate400.withValues(alpha: 0.2))),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: tile.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                      child: Icon(tile.icon, color: tile.color),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tile.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(tile.description, style: TextStyle(fontSize: 11.5, color: AppColors.slate600)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.slate400),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
