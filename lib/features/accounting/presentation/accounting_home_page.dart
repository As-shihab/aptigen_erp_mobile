import 'package:flutter/material.dart';
import '../../../shared/ui/motion_kit.dart';
import 'cash_flow_page.dart';
import 'chart_of_accounts_page.dart';
import 'expenses/expenses_page.dart';
import 'journal_entries_page.dart';
import 'ledger/account_ledger_page.dart';
import 'ledger_accounts/ledger_accounts_page.dart';
import 'party_statement/party_statement_page.dart';
import 'payment_requests/payment_requests_page.dart';
import 'payment_vouchers_page.dart';
import 'reports/accounting_analytics_page.dart';
import 'reports/balance_sheet_page.dart';
import 'reports/profit_loss_page.dart';
import 'settings/accounting_settings_page.dart';

/// Accounting home — mirrors erp/desktop's accounting.nav.ts sections
/// (overview, account setup, transactions, reports) plus settings, as a hub.
class AccountingHomePage extends StatefulWidget {
  const AccountingHomePage({super.key});

  @override
  State<AccountingHomePage> createState() => _AccountingHomePageState();
}

class _AccountingHomePageState extends State<AccountingHomePage> {
  String _q = '';

  void _go(Widget page) => pushMotion(context, page);

  List<({String title, List<HubTile> tiles})> get _sections => [
        (
          title: 'Overview',
          tiles: [
            HubTile(icon: Icons.show_chart_rounded, label: 'Cash flow', caption: 'Money in and out', accent: Accent.amber, onTap: () => _go(const CashFlowPage())),
            HubTile(icon: Icons.insights_rounded, label: 'Analytics', caption: 'Daily profit and loss', accent: Accent.ocean, onTap: () => _go(const AccountingAnalyticsPage())),
            HubTile(icon: Icons.table_rows_outlined, label: 'Ledger', caption: 'Running balance per account', accent: Accent.teal, onTap: () => _go(const AccountLedgerPage())),
            HubTile(icon: Icons.menu_book_outlined, label: 'Journal entries', caption: 'Post and review entries', accent: Accent.violet, onTap: () => _go(const JournalEntriesPage())),
          ],
        ),
        (
          title: 'Account',
          tiles: [
            HubTile(icon: Icons.savings_outlined, label: 'Ledger accounts', caption: 'Bank and cash registers', accent: Accent.sky, onTap: () => _go(const LedgerAccountsPage())),
            HubTile(icon: Icons.account_tree_outlined, label: 'Chart of accounts', caption: 'General ledger accounts', accent: Accent.indigo, onTap: () => _go(const ChartOfAccountsPage())),
          ],
        ),
        (
          title: 'Transactions',
          tiles: [
            HubTile(icon: Icons.payments_outlined, label: 'Expenses', caption: 'Record spending', accent: Accent.rose, onTap: () => _go(const ExpensesPage())),
            HubTile(icon: Icons.receipt_long_outlined, label: 'Payment vouchers', caption: 'Receipts and payments', accent: Accent.emerald, onTap: () => _go(const PaymentVouchersPage())),
            HubTile(icon: Icons.inbox_outlined, label: 'Payment requests', caption: 'Approve or reject', accent: Accent.sunset, onTap: () => _go(const PaymentRequestsPage())),
          ],
        ),
        (
          title: 'Reports',
          tiles: [
            HubTile(icon: Icons.people_outline_rounded, label: 'Party statement', caption: 'Clients and suppliers', accent: Accent.teal, onTap: () => _go(const PartyStatementPage())),
            HubTile(icon: Icons.trending_up_rounded, label: 'Profit & loss', caption: 'Income minus expense', accent: Accent.emerald, onTap: () => _go(const ProfitLossPage())),
            HubTile(icon: Icons.balance_outlined, label: 'Balance sheet', caption: 'Balances and trial check', accent: Accent.indigo, onTap: () => _go(const BalanceSheetPage())),
          ],
        ),
        (
          title: 'Setup',
          tiles: [
            HubTile(icon: Icons.tune_rounded, label: 'Accounting settings', caption: 'Defaults and preferences', accent: Accent.slate, onTap: () => _go(const AccountingSettingsPage())),
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final sections = [
      for (final s in _sections) (title: s.title, tiles: q.isEmpty ? s.tiles : s.tiles.where((t) => t.label.toLowerCase().contains(q)).toList()),
    ].where((s) => s.tiles.isNotEmpty).toList();

    var index = 0;
    return MotionScaffold(
      title: 'Accounting',
      icon: Icons.account_balance_outlined,
      headerExtra: HeaderSearch(hint: 'Find an accounting area', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        for (final s in sections) sliverHubSection(title: s.title, tiles: s.tiles, startIndex: (index += s.tiles.length) - s.tiles.length),
        if (sections.isEmpty) sliverEmpty(icon: Icons.search_off_rounded, title: 'No accounting area matches "$_q"'),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
