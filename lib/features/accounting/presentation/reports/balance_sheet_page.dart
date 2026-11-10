import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/accounting_reports_service.dart';
import '../../data/accounting_service.dart';
import '../../models/accounting_models.dart' show AccountRow, kAccountTypes;
import 'report_widgets.dart';

typedef _AccountBalance = ({String code, String name, double amount});

const _typeTitles = {
  'ASSET': 'Assets',
  'LIABILITY': 'Liabilities',
  'EQUITY': 'Equity',
  'INCOME': 'Income',
  'EXPENSE': 'Expenses',
};
// Same hues as desktop's TYPE_COLORS (blue / red / violet / green / amber).
const _typeAccents = {
  'ASSET': Accent.ocean,
  'LIABILITY': Accent.rose,
  'EQUITY': Accent.violet,
  'INCOME': Accent.emerald,
  'EXPENSE': Accent.amber,
};
const _typeIcons = {
  'ASSET': Icons.account_balance_wallet_outlined,
  'LIABILITY': Icons.credit_card_rounded,
  'EQUITY': Icons.pie_chart_outline_rounded,
  'INCOME': Icons.south_west_rounded,
  'EXPENSE': Icons.north_east_rounded,
};

// Debit-normal types show +(debit − credit); credit-normal types flip the
// sign so a growing credit balance reads as a growing positive number —
// same convention as desktop's creditNormal() / the Journal Entries ledger.
bool _creditNormal(String type) => type == 'LIABILITY' || type == 'EQUITY' || type == 'INCOME';

// Balance sheet / trial balance — port of desktop balance-sheet/
// BalanceSheet.tsx. Every non-group account's live balance (opening_balance
// + all-time debit/credit, no date filter — "as of now"), grouped by type.
//
// The check is a real trial-balance identity, not an assumed one: every
// journal entry is balanced before it's saved (desktop and mobile both
// refuse an entry whose debits ≠ credits), so Asset + Expense balances must
// equal Liability + Equity + Income balances — a mismatch means something
// wrote lines straight to the API. It is deliberately NOT framed as
// "Assets = Liabilities + Equity": Income/Expense are never closed to
// Equity (no period-end closing flow exists), so that identity doesn't hold
// here on purpose. See desktop's accounting context.md.
class BalanceSheetPage extends StatefulWidget {
  const BalanceSheetPage({super.key});

  @override
  State<BalanceSheetPage> createState() => _BalanceSheetPageState();
}

class _BalanceSheetPageState extends State<BalanceSheetPage> {
  final _client = ApiClient();
  late final _accountingService = AccountingService(_client);
  late final _reportsService = AccountingReportsService(_client);

  Map<String, List<_AccountBalance>> _byType = {};
  bool _loaded = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = !_loaded;
      _error = null;
    });
    try {
      // accounts is /v1 OData, lines are the custom /api route — the two
      // can't share a $batch, so they're just fetched in parallel.
      final results = await Future.wait([
        _accountingService.loadAccounts(activeOnly: true),
        _reportsService.loadAllLines(withDetails: false),
      ]);
      final accounts = results[0] as List<AccountRow>;
      final lines = results[1] as List<ReportLine>;
      if (!mounted) return;
      setState(() {
        _byType = _balances(accounts, lines);
        _loaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load the balance sheet'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, List<_AccountBalance>> _balances(List<AccountRow> accounts, List<ReportLine> lines) {
    final movement = <int, double>{};
    for (final l in lines) {
      movement[l.accountId] = (movement[l.accountId] ?? 0) + (l.debit - l.credit);
    }
    return {
      for (final type in kAccountTypes)
        type: [
          for (final a in accounts.where((a) => a.type == type && !a.isGroup))
            if (_signed(type, a.openingBalance + (movement[a.id] ?? 0)) case final amount when (amount * 100).round() != 0)
              (code: a.code, name: a.name, amount: amount),
        ],
    };
  }

  double _signed(String type, double raw) => _creditNormal(type) ? -raw : raw;

  double _typeTotal(String type) => (_byType[type] ?? const []).fold<double>(0, (s, a) => s + a.amount);

  @override
  Widget build(BuildContext context) {
    return MotionScaffold(
      title: 'Balance sheet',
      icon: Icons.account_balance_rounded,
      onRefresh: _load,
      slivers: [
        if (_loading)
          sliverSkeleton(count: 4, height: 160)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else ...[
          sliverBox(_TrialBalanceCheck(
            debitNormal: _typeTotal('ASSET') + _typeTotal('EXPENSE'),
            creditNormal: _typeTotal('LIABILITY') + _typeTotal('EQUITY') + _typeTotal('INCOME'),
          )),
          sliverStagger(
            count: kAccountTypes.length,
            gap: 12,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            builder: (_, i) {
              final type = kAccountTypes[i];
              final rows = _byType[type] ?? const [];
              return _TypePanel(type: type, rows: rows, total: _typeTotal(type));
            },
          ),
        ],
      ],
    );
  }
}

class _TrialBalanceCheck extends StatelessWidget {
  final double debitNormal;
  final double creditNormal;
  const _TrialBalanceCheck({required this.debitNormal, required this.creditNormal});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final balanced = ((debitNormal - creditNormal) * 100).round() == 0;
    Widget side(String label, double value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: p.label)),
          const SizedBox(height: 2),
          CountUp(value: value, format: reportMoney, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
        ]);
    return ReportPanel(
      icon: balanced ? Icons.verified_outlined : Icons.error_outline_rounded,
      accent: balanced ? Accent.emerald : Accent.rose,
      title: 'Trial balance',
      sub: 'Live balance as of now (opening balance + all-time postings), grouped by account type',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: side('Asset + expense', debitNormal)),
          const SizedBox(width: 12),
          Expanded(child: side('Liability + equity + income', creditNormal)),
        ]),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: StatusPill(
            balanced ? 'Trial balance OK' : 'Out of balance — check for direct API writes',
            tone: balanced ? MarketTone.ok : MarketTone.error,
            icon: balanced ? Icons.check_rounded : Icons.warning_amber_rounded,
          ),
        ),
      ]),
    );
  }
}

class _TypePanel extends StatelessWidget {
  final String type;
  final List<_AccountBalance> rows;
  final double total;
  const _TypePanel({required this.type, required this.rows, required this.total});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final accent = _typeAccents[type] ?? Accent.slate;
    final icon = _typeIcons[type] ?? Icons.folder_outlined;
    return ReportPanel(
      icon: icon,
      accent: accent,
      title: _typeTitles[type] ?? humanize(type),
      sub: '${rows.length} ${rows.length == 1 ? 'account' : 'accounts'}',
      trailing: Text(reportMoney(total), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
      child: rows.isEmpty ? ReportEmpty(icon: icon, text: 'No balance yet.') : AccountAmountList(rows: rows),
    );
  }
}
