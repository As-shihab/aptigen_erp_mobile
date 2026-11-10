import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../core/utils/currency.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/accounting_ledger_service.dart';
import '../../models/accounting_models.dart' show AccountRow;

// Ledger — port of desktop ledger/AccountLedger.tsx. Every
// journal_entry_lines row ever posted (manual journal entries, payment
// vouchers, POS sales), flat across all accounts by default. Picking an
// account narrows to that account's own running balance. Direction chips
// show the literal posted side (credit / debit), not an "in / out" reading,
// which would read backwards for debit-normal accounts.

enum _Direction { all, credit, debit }

// Credit-normal account types show a growing credit balance as a growing
// positive ledger number — same convention as desktop's creditNormal().
bool _creditNormal(String type) => type == 'LIABILITY' || type == 'EQUITY' || type == 'INCOME';

String _source(LedgerLine l) => l.referenceType == null ? 'Manual' : humanize(l.referenceType);

/// A line plus its running balance (only set when one account is picked).
class _Row {
  final LedgerLine line;
  final double? balance;
  const _Row(this.line, this.balance);
}

class AccountLedgerPage extends StatefulWidget {
  const AccountLedgerPage({super.key});

  @override
  State<AccountLedgerPage> createState() => _AccountLedgerPageState();
}

class _AccountLedgerPageState extends State<AccountLedgerPage> {
  final _service = AccountingLedgerService();
  bool _loading = true;
  String? _error;
  bool _truncated = false;
  List<LedgerLine> _lines = [];
  List<AccountRow> _accounts = [];
  int? _accountId;
  _Direction _direction = _Direction.all;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Lines come from the custom /api route (journal_entry_lines has no
  // workplace_id, so it can't go through /v1/ or a $batch) — fetched in
  // parallel with the account list instead. With an account picked the
  // filter runs server-side, so its running balance covers every line it
  // has, not just whatever fits under the row cap.
  Future<void> _load() async {
    setState(() {
      _loading = _lines.isEmpty;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.loadLines(accountId: _accountId),
        if (_accounts.isEmpty) _service.loadPostableAccounts(),
      ]);
      if (!mounted) return;
      final lines = results[0] as ({List<LedgerLine> lines, bool truncated});
      setState(() {
        _lines = lines.lines;
        _truncated = lines.truncated;
        if (results.length > 1) _accounts = results[1] as List<AccountRow>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load the ledger'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pickAccount(Object? id) {
    final next = id == null ? null : int.tryParse(id.toString());
    if (next == _accountId) return;
    setState(() {
      _accountId = next;
      _lines = [];
    });
    _load();
  }

  void _reset() {
    setState(() {
      _direction = _Direction.all;
      _q = '';
    });
    _pickAccount(null);
  }

  AccountRow? get _account => _accounts.where((a) => a.id == _accountId).firstOrNull;

  bool _matchesDirection(LedgerLine l, _Direction d) => switch (d) {
        _Direction.all => true,
        _Direction.credit => l.credit > 0,
        _Direction.debit => l.debit > 0,
      };

  /// Newest first. With one account picked, walks oldest-first from its
  /// opening balance accumulating debit − credit (sign flipped for
  /// credit-normal types). The balance runs over every line of the account
  /// before the direction filter is applied, so a filtered view still shows
  /// each line's real balance.
  List<_Row> get _rows {
    final account = _account;
    List<_Row> all;
    if (_accountId == null) {
      all = [for (final l in _lines) _Row(l, null)];
    } else {
      final sign = account != null && _creditNormal(account.type) ? -1 : 1;
      var running = account?.openingBalance ?? 0.0;
      final ordered = _lines.where((l) => l.accountId == _accountId).toList()..sort((a, b) => a.id.compareTo(b.id));
      final ascending = <_Row>[];
      for (final l in ordered) {
        running += sign * (l.debit - l.credit);
        ascending.add(_Row(l, (running * 100).roundToDouble() / 100));
      }
      all = ascending.reversed.toList();
    }
    final q = _q.trim().toLowerCase();
    return all.where((r) {
      if (!_matchesDirection(r.line, _direction)) return false;
      if (q.isEmpty) return true;
      final l = r.line;
      final hay = [l.jeNo, l.remarks, l.accountLabel, _source(l), l.createdBy].whereType<String>().join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  int _count(_Direction d) => _lines.where((l) => (_accountId == null || l.accountId == _accountId) && _matchesDirection(l, d)).length;

  Future<void> _openPrint(List<_Row> rows) async {
    await showMotionSheet<void>(context, (_) => _PrintRangeSheet(rows: rows, account: _account));
  }

  void _openDetail(_Row r) {
    final l = r.line;
    showMotionSheet<void>(
      context,
      (ctx) => FormSheet(
        title: l.jeNo ?? 'Journal line',
        children: [
          GlowCard(
            child: Column(children: [
              InfoRow('Date', fmtDate(parseDate(l.entryDate)).isEmpty ? '—' : fmtDate(parseDate(l.entryDate))),
              InfoRow('Source', _source(l)),
              InfoRow('Account', l.accountLabel ?? '—'),
              InfoRow('Side', l.isDebit ? 'Debit' : 'Credit'),
              InfoRow('Debit', formatMoney(l.debit)),
              InfoRow('Credit', formatMoney(l.credit)),
              if (r.balance != null) InfoRow('Balance', formatMoney(r.balance!), emphasize: true),
              InfoRow('Remarks', l.remarks ?? '—'),
              InfoRow('Created', fmtDateTime(parseDate(l.createdAt)).isEmpty ? '—' : fmtDateTime(parseDate(l.createdAt))),
              InfoRow('Created by', l.createdBy ?? '—'),
            ]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final rows = _rows;
    final debit = rows.fold<double>(0, (s, r) => s + r.line.debit);
    final credit = rows.fold<double>(0, (s, r) => s + r.line.credit);
    final net = credit - debit;
    // rows.first is the latest line, so its balance is the account's current one.
    final currentBalance = _accountId != null && rows.isNotEmpty ? rows.first.balance : null;
    final filtered = _accountId != null || _direction != _Direction.all || _q.isNotEmpty;

    return MotionScaffold(
      title: 'Ledger',
      icon: Icons.menu_book_outlined,
      onRefresh: _load,
      actions: [
        IconButton(tooltip: 'Print', onPressed: rows.isEmpty ? null : () => _openPrint(rows), icon: const Icon(Icons.print_outlined)),
        if (filtered) IconButton(tooltip: 'Reset', onPressed: _reset, icon: const Icon(Icons.filter_alt_off_outlined)),
      ],
      headerExtra: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PickerField(
          value: _accountId,
          hint: 'All accounts',
          icon: Icons.account_tree_outlined,
          options: [for (final a in _accounts) PickOption(a.id, a.label, sub: humanize(a.type))],
          onChanged: _pickAccount,
        ),
        const SizedBox(height: 10),
        HeaderSearch(hint: 'Search JE no, remarks, account', onChanged: (v) => setState(() => _q = v)),
      ]),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<_Direction>(
              value: _direction,
              options: [
                (id: _Direction.all, label: 'All', count: _count(_Direction.all)),
                (id: _Direction.credit, label: 'Credit', count: _count(_Direction.credit)),
                (id: _Direction.debit, label: 'Debit', count: _count(_Direction.debit)),
              ],
              onChanged: (v) => setState(() => _direction = v),
            ),
          ),
        ),
        if (!_loading && _error == null)
          SliverPadding(
            padding: const EdgeInsets.only(top: 14),
            sliver: SliverToBoxAdapter(
              child: KpiStrip(children: [
                GradientKpi(icon: Icons.receipt_long_outlined, label: 'Entries', value: rows.length, accent: Accent.slate),
                GradientKpi(icon: Icons.north_east_rounded, label: 'Total debit', value: debit, format: (v) => formatMoney(v), accent: Accent.rose),
                GradientKpi(icon: Icons.south_west_rounded, label: 'Total credit', value: credit, format: (v) => formatMoney(v), accent: Accent.emerald),
                GradientKpi(
                  icon: Icons.swap_vert_rounded,
                  label: 'Net movement',
                  value: net,
                  format: (v) => formatMoney(v),
                  accent: net >= 0 ? Accent.emerald : Accent.rose,
                ),
                if (currentBalance != null)
                  GradientKpi(icon: Icons.account_balance_wallet_outlined, label: 'Current balance', value: currentBalance, format: (v) => formatMoney(v), accent: Accent.ocean),
              ]),
            ),
          ),
        if (_truncated && !_loading)
          sliverBox(
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: p.warnBg, borderRadius: BorderRadius.circular(8)),
              child: Text(
                'Showing the latest ${NumberFormat.decimalPattern().format(AccountingLedgerService.lineCap)} lines only. Pick an account to see its full history.',
                style: TextStyle(fontSize: 12, color: p.warn),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          ),
        if (_loading)
          sliverSkeleton(height: 72)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.menu_book_outlined,
            title: _lines.isEmpty ? 'No ledger lines yet' : 'No matches',
            message: _lines.isEmpty ? 'Journal entries, payment vouchers and POS sales post here.' : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) => _LineTile(row: rows[i], showAccount: _accountId == null, onTap: () => _openDetail(rows[i])),
          ),
      ],
    );
  }
}

class _LineTile extends StatelessWidget {
  final _Row row;
  final bool showAccount;
  final VoidCallback onTap;
  const _LineTile({required this.row, required this.showAccount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final l = row.line;
    final date = fmtDate(parseDate(l.entryDate));
    final amount = l.isDebit ? l.debit : l.credit;
    final color = l.isDebit ? p.error : p.ok;
    return MotionTile(
      leading: AccentIcon(l.isDebit ? Icons.north_east_rounded : Icons.south_west_rounded, accent: l.isDebit ? Accent.rose : Accent.emerald, size: 40),
      title: [l.jeNo ?? '—', _source(l)].join(' · '),
      subtitle: showAccount ? l.accountLabel : l.remarks,
      meta: [
        if (date.isNotEmpty) date,
        if (showAccount && l.remarks != null) l.remarks!,
        if (l.createdBy != null) l.createdBy!,
      ].join(' · '),
      onTap: onTap,
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Text(formatMoney(amount), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(l.isDebit ? 'Debit' : 'Credit', style: TextStyle(fontSize: 11, color: color)),
        if (row.balance != null) ...[
          const SizedBox(height: 2),
          Text('Bal. ${formatMoney(row.balance!)}', style: TextStyle(fontSize: 11, color: p.label)),
        ],
      ]),
    );
  }
}

// ── Print range ─────────────────────────────────────────────────────────

/// Desktop's print / export range dialog: leave a date blank to include
/// everything up to that end, then print the rows currently on screen.
class _PrintRangeSheet extends StatefulWidget {
  final List<_Row> rows;
  final AccountRow? account;
  const _PrintRangeSheet({required this.rows, this.account});

  @override
  State<_PrintRangeSheet> createState() => _PrintRangeSheetState();
}

class _PrintRangeSheetState extends State<_PrintRangeSheet> {
  DateTime? _from;
  DateTime? _to;
  bool _busy = false;

  String _day(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  bool _inRange(String? entryDate) {
    final day = (entryDate ?? '').length >= 10 ? entryDate!.substring(0, 10) : '';
    if (day.isEmpty) return true;
    if (_from != null && day.compareTo(_day(_from!)) < 0) return false;
    if (_to != null && day.compareTo(_day(_to!)) > 0) return false;
    return true;
  }

  Future<void> _print() async {
    setState(() => _busy = true);
    try {
      final rows = widget.rows.where((r) => _inRange(r.line.entryDate)).toList();
      final single = widget.account != null;
      final headers = ['Date', 'JE no', 'Source', if (!single) 'Account', 'Side', 'Remarks', 'Debit', 'Credit', if (single) 'Balance', 'Created by'];
      final data = [
        for (final r in rows)
          [
            fmtDate(parseDate(r.line.entryDate)),
            r.line.jeNo ?? '',
            _source(r.line),
            if (!single) r.line.accountLabel ?? '',
            r.line.isDebit ? 'Debit' : 'Credit',
            r.line.remarks ?? '',
            formatMoneyAscii(r.line.debit),
            formatMoneyAscii(r.line.credit),
            if (single) formatMoneyAscii(r.balance ?? 0),
            r.line.createdBy ?? '',
          ],
      ];
      final range = '${_from == null ? 'Start' : fmtDate(_from)} - ${_to == null ? 'Now' : fmtDate(_to)}';
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => [
          pw.Text(single ? 'Ledger · ${widget.account!.label}' : 'Ledger', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(range, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: data,
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          ),
        ],
      ));
      await Printing.layoutPdf(onLayout: (_) => doc.save(), name: 'ledger-${_from == null ? 'start' : _day(_from!)}-to-${_to == null ? 'now' : _day(_to!)}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not print the ledger'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return FormSheet(
      title: 'Print range',
      submitLabel: 'Print',
      busy: _busy,
      onSubmit: _print,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text('Leave a date blank to include everything up to that end.', style: TextStyle(fontSize: 12.5, color: p.label)),
        ),
        FormLabel(label: 'From', child: DatePickField(value: _from, onChanged: (d) => setState(() => _from = d))),
        FormLabel(label: 'To', child: DatePickField(value: _to, onChanged: (d) => setState(() => _to = d))),
      ],
    );
  }
}
