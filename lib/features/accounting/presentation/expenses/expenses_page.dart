import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/utils/currency.dart';
import '../../../../shared/ui/motion_kit.dart' hide toInt, toDouble;
import '../../data/accounting_transactions_service.dart';
import '../../models/accounting_models.dart';

/// Expenses — mobile port of desktop accounting/expenses/Expenses.tsx: a
/// focused, always-money-out entry point on top of the same payment
/// voucher / journal entry machinery (a plain PAYMENT voucher underneath).
/// Only EXPENSE accounts are offered, the paid-from bank/cash account comes
/// from that account's "Default paid from", and saving posts immediately.
/// Create + delete only — delete reverses the bank/cash balance.
class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final _service = AccountingTransactionsService(ApiClient());
  bool _loading = true;
  String? _error;
  String _query = '';
  List<PaymentVoucherRow> _rows = [];
  ExpenseLookups _lookups = ExpenseLookups.empty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    try {
      final rows = await _service.loadExpenses();
      ExpenseLookups lookups;
      try {
        lookups = await _service.loadExpenseLookups();
      } catch (_) {
        // Empty pickers — the list itself still shows.
        lookups = ExpenseLookups.empty;
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _lookups = lookups;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load expenses'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _partyName(PaymentVoucherRow r) {
    if (r.partyId == null) return r.partyType == 'OTHER' ? 'Other' : null;
    final list = r.partyType == 'CLIENT' ? _lookups.clients : r.partyType == 'SUPPLIER' ? _lookups.suppliers : const <PartyOption>[];
    return list.where((p) => p.id == r.partyId).firstOrNull?.name;
  }

  List<PaymentVoucherRow> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows
        .where((r) => [r.pvNo, r.debitAccountLabel, r.creditAccountLabel, r.remarks, _partyName(r)].any((s) => (s ?? '').toLowerCase().contains(q)))
        .toList();
  }

  Future<void> _openCreate() async {
    final created = await showMotionSheet<bool>(context, (_) => _ExpenseFormSheet(service: _service, lookups: _lookups));
    if (created == true) {
      if (mounted) marketToast(context, 'Expense posted');
      _load();
    }
  }

  Future<bool> _delete(PaymentVoucherRow row) async {
    final ok = await confirmMarket(
      context,
      title: 'Delete expense',
      message: 'Delete expense "${row.pvNo}"? Its journal entry and bank/cash balance impact will be reversed.',
    );
    if (!ok) return false;
    try {
      await _service.deletePayment(row, _lookups.banks);
      if (mounted) {
        setState(() => _rows.removeWhere((r) => r.id == row.id));
        marketToast(context, 'Expense deleted');
      }
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete expense'), error: true);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final rows = _visible;
    final now = DateTime.now();
    final total = _rows.fold<double>(0, (s, r) => s + r.amount);
    final thisMonth = _rows.where((r) {
      final d = parseDate(r.voucherDate)?.toLocal();
      return d != null && d.year == now.year && d.month == now.month;
    }).fold<double>(0, (s, r) => s + r.amount);

    return MotionScaffold(
      title: 'Expenses',
      icon: Icons.payments_outlined,
      accent: Accent.rose,
      onRefresh: _load,
      fabLabel: 'New expense',
      onFab: _openCreate,
      headerExtra: HeaderSearch(hint: 'Search expenses', onChanged: (v) => setState(() => _query = v)),
      slivers: [
        if (!_loading && _error == null && _rows.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.only(top: 14),
            sliver: SliverToBoxAdapter(
              child: KpiStrip(children: [
                GradientKpi(icon: Icons.calendar_month_outlined, label: 'This month', value: thisMonth, format: (v) => formatMoney(v, decimalDigits: 0), accent: Accent.rose),
                GradientKpi(icon: Icons.account_balance_wallet_outlined, label: 'All time', value: total, format: (v) => formatMoney(v, decimalDigits: 0), accent: Accent.sunset),
                GradientKpi(icon: Icons.receipt_long_outlined, label: 'Entries', value: _rows.length, accent: Accent.slate),
              ]),
            ),
          ),
        if (_loading)
          sliverSkeleton(count: 6)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.payments_outlined,
            title: _rows.isEmpty ? 'No expenses yet' : 'No matches',
            message: _rows.isEmpty ? 'Tap new expense to record money spent.' : 'Try a different search.',
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final party = _partyName(r);
              final date = parseDate(r.voucherDate);
              return MotionTile(
                leading: const AccentIcon(Icons.call_made_rounded, accent: Accent.rose, size: 40),
                title: r.pvNo,
                subtitle: r.debitAccountLabel ?? '—',
                meta: [
                  'From ${r.creditAccountLabel ?? '—'}',
                  if (party != null) 'To $party',
                  if (date != null) fmtDate(date),
                ].join(' · '),
                trailing: Text(formatMoney(r.amount), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.error)),
                onTap: () => _showDetail(r, party),
                onDelete: () => _delete(r),
              );
            },
          ),
      ],
    );
  }

  void _showDetail(PaymentVoucherRow r, String? party) {
    showMotionSheet<void>(context, (ctx) {
      final p = MarketPalette.of(ctx);
      final date = parseDate(r.voucherDate);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetGrabber(),
            Text(r.pvNo, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 10),
            InfoRow('Amount', formatMoney(r.amount), emphasize: true),
            InfoRow('Expense account', r.debitAccountLabel ?? '—'),
            InfoRow('Paid from', r.creditAccountLabel ?? '—'),
            if (r.partyType != null) InfoRow('Given to', party ?? humanize(r.partyType)),
            InfoRow('Date', date == null ? '—' : fmtDate(date)),
            if (r.remarks != null) InfoRow('Remarks', r.remarks!),
            const SizedBox(height: 14),
            Text('Expenses post immediately and can\'t be edited. Delete it (swipe left) and re-enter to correct a mistake.',
                style: TextStyle(fontSize: 12, color: p.label)),
          ]),
        ),
      );
    });
  }
}

class _ExpenseFormSheet extends StatefulWidget {
  final AccountingTransactionsService service;
  final ExpenseLookups lookups;
  const _ExpenseFormSheet({required this.service, required this.lookups});

  @override
  State<_ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends State<_ExpenseFormSheet> {
  final _noCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  bool _generating = true;
  bool _saving = false;
  ExpenseAccountOption? _account;
  String? _partyType;
  int? _partyId;
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    _generateNo();
  }

  @override
  void dispose() {
    _noCtrl.dispose();
    _amountCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _generateNo() async {
    final code = await widget.service.generateExpenseNo();
    if (!mounted) return;
    setState(() {
      if (code != null && _noCtrl.text.trim().isEmpty) _noCtrl.text = code;
      _generating = false;
    });
  }

  List<PartyOption> get _parties => _partyType == 'CLIENT' ? widget.lookups.clients : _partyType == 'SUPPLIER' ? widget.lookups.suppliers : const [];

  double get _amount => double.tryParse(_amountCtrl.text.trim()) ?? 0;
  bool get _canSave => _noCtrl.text.trim().isNotEmpty && _account != null && _amount > 0 && !_generating;

  /// The paid-from side is the expense account's own default — resolved
  /// against the loaded bank list so the balance sync knows which
  /// bank_accounts row to move.
  BankOption? get _paidFrom {
    final a = _account;
    if (a?.paidFromAccountId == null) return null;
    return widget.lookups.banks.where((b) => b.accountId == a!.paidFromAccountId).firstOrNull ??
        BankOption(id: a!.paidFromBankId!, accountId: a.paidFromAccountId!, name: a.paidFromName ?? '', currentBalance: 0);
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    final bank = _paidFrom;
    if (bank == null) {
      marketToast(context, '"${_account!.label}" has no default paid from set. Set one on it in chart of accounts first.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final remarks = _remarksCtrl.text.trim();
      await widget.service.postPayment(
        number: _noCtrl.text.trim(),
        date: _date,
        debitAccountId: _account!.id,
        bank: bank,
        amount: _amount,
        partyType: _partyType,
        partyId: _partyId,
        remarks: remarks.isEmpty ? null : remarks,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Failed to save expense'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final paidFrom = _paidFrom;
    return FormSheet(
      title: 'New expense',
      submitLabel: 'Post expense',
      busy: _saving,
      onSubmit: _canSave ? _save : null,
      children: [
        FormLabel(
          label: 'Expense no',
          required: true,
          child: TextField(
            controller: _noCtrl,
            enabled: !_generating,
            onChanged: (_) => setState(() {}),
            decoration: motionInput(context, hint: _generating ? 'Generating…' : 'e.g. EXP-2026-0001', icon: Icons.tag_rounded),
          ),
        ),
        FormLabel(
          label: 'Expense account',
          required: true,
          help: _account == null
              ? null
              : paidFrom != null
                  ? 'Paid from ${paidFrom.name.isEmpty ? 'its default account' : paidFrom.name}'
                  : 'No default paid from set on this account. Set one in chart of accounts before posting.',
          child: PickerField(
            value: _account?.id,
            hint: 'Select an expense account',
            icon: Icons.account_tree_outlined,
            options: [for (final a in widget.lookups.expenseAccounts) PickOption(a.id, a.label, sub: a.paidFromName == null ? null : 'Paid from ${a.paidFromName}')],
            onChanged: (v) => setState(() => _account = widget.lookups.expenseAccounts.where((a) => a.id == v).firstOrNull),
          ),
        ),
        FormLabel(
          label: 'Given to',
          child: ChipFilter<String?>(
            padding: EdgeInsets.zero,
            value: _partyType,
            options: const [
              (id: null, label: 'None', count: null),
              (id: 'CLIENT', label: 'Client', count: null),
              (id: 'SUPPLIER', label: 'Supplier', count: null),
              (id: 'OTHER', label: 'Other', count: null),
            ],
            onChanged: (v) => setState(() {
              _partyType = v;
              _partyId = null;
            }),
          ),
        ),
        if (_partyType == 'CLIENT' || _partyType == 'SUPPLIER')
          FormLabel(
            label: _partyType == 'CLIENT' ? 'Client' : 'Supplier',
            child: PickerField(
              value: _partyId,
              hint: _partyType == 'CLIENT' ? 'Select a client (optional)' : 'Select a supplier (optional)',
              icon: Icons.person_outline_rounded,
              options: [for (final party in _parties) PickOption(party.id, party.name)],
              onChanged: (v) => setState(() => _partyId = v == null ? null : toInt(v)),
            ),
          ),
        FormLabel(
          label: 'Amount',
          required: true,
          child: TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: motionInput(context, hint: '0.00', icon: Icons.payments_outlined),
          ),
        ),
        FormLabel(
          label: 'Date',
          help: _date == null ? 'Defaults to today' : null,
          child: DatePickField(value: _date, onChanged: (d) => setState(() => _date = d)),
        ),
        FormLabel(
          label: 'Remarks',
          child: TextField(
            controller: _remarksCtrl,
            maxLines: 3,
            minLines: 2,
            style: TextStyle(color: p.text),
            decoration: motionInput(context, hint: 'What was this for?'),
          ),
        ),
      ],
    );
  }
}
