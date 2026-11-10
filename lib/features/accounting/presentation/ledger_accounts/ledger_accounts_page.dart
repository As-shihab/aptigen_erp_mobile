import 'package:flutter/material.dart';
import '../../../../core/utils/currency.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/accounting_ledger_service.dart';

// Ledger accounts — port of desktop ledger-accounts/LedgerAccounts.tsx: the
// bank / cash registers (bank_accounts). Every register is backed by its own
// chart of account entry (ASSET, bank_accounts.account_id is required +
// unique), so creating one creates both rows; editing only touches the
// bank_accounts fields; deleting removes the register and then, best-effort,
// its backing account. current_balance is never edited here — only posted
// journal entries / payment vouchers move it.

const _types = [('BANK', 'Bank'), ('CASH', 'Cash')];

String _typeLabel(String t) => t == 'CASH' ? 'Cash' : 'Bank';

/// Next sequential ledger code (00001, 00002, ...) for a new register's
/// backing account — shared numbering across bank and cash, derived from
/// the codes already handed out (no backend endpoint for it).
String _nextBankCode(List<LedgerAccount> all) {
  var max = 0;
  for (final b in all) {
    final code = b.accountCode ?? '';
    if (RegExp(r'^\d+$').hasMatch(code)) {
      final n = int.parse(code);
      if (n > max) max = n;
    }
  }
  return (max + 1).toString().padLeft(5, '0');
}

class LedgerAccountsPage extends StatefulWidget {
  const LedgerAccountsPage({super.key});

  @override
  State<LedgerAccountsPage> createState() => _LedgerAccountsPageState();
}

class _LedgerAccountsPageState extends State<LedgerAccountsPage> {
  final _service = AccountingLedgerService();
  bool _loading = true;
  String? _error;
  List<LedgerAccount> _rows = [];
  String _q = '';
  String _chip = 'All';

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
      final rows = await _service.loadLedgerAccounts();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load ledger accounts'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, bool Function(LedgerAccount)> get _chips => {
        'All': (_) => true,
        'Active': (r) => r.isActive,
        'Inactive': (r) => !r.isActive,
      };

  List<LedgerAccount> get _visible {
    final q = _q.trim().toLowerCase();
    final pred = _chips[_chip]!;
    return _rows.where((r) {
      if (!pred(r)) return false;
      if (q.isEmpty) return true;
      final hay = [r.name, r.accountNo, r.bankName, r.accountCode, r.accountName, r.parentName, _typeLabel(r.type)]
          .whereType<String>()
          .join(' ')
          .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _openForm([LedgerAccount? row]) async {
    final saved = await showMotionSheet<bool>(context, (_) => _LedgerAccountForm(service: _service, all: _rows, existing: row));
    if (saved == true) {
      if (mounted) marketToast(context, row == null ? 'Ledger account created' : 'Ledger account updated');
      _load();
    }
  }

  Future<bool> _delete(LedgerAccount row) async {
    final ok = await confirmMarket(
      context,
      title: 'Delete ledger account?',
      message: 'Delete ledger account "${row.name}"? Its backing chart of account entry is deleted with it. '
          'If journal lines are already posted against it, that entry is kept and has to be cleaned up first.',
    );
    if (!ok) return false;
    try {
      await _service.deleteLedgerAccount(row.id);
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete ledger account'), error: true);
      return false;
    }
    // The register is gone — now its own backing account. Fails while that
    // account still has posted lines, which keeps that history protected.
    var backingKept = false;
    if (row.accountId != null) {
      try {
        await _service.deleteBackingAccount(row.accountId!);
      } catch (_) {
        backingKept = true;
      }
    }
    if (mounted) {
      setState(() => _rows.removeWhere((r) => r.id == row.id));
      marketToast(
        context,
        backingKept ? 'Ledger account deleted. Its chart of account entry was kept because it has posted lines.' : 'Ledger account deleted',
      );
    }
    return true;
  }

  Future<void> _more(LedgerAccount row) async {
    final key = await showActionSheet(context, title: row.name, actions: [
      (key: 'edit', label: 'Edit', icon: Icons.edit_outlined, destructive: false),
      (key: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted || key == null) return;
    if (key == 'edit') _openForm(row);
    if (key == 'delete') _delete(row);
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final rows = _visible;
    final chips = _chips;
    final active = _rows.where((r) => r.isActive);
    final bankTotal = active.where((r) => r.type == 'BANK').fold<double>(0, (s, r) => s + r.currentBalance);
    final cashTotal = active.where((r) => r.type == 'CASH').fold<double>(0, (s, r) => s + r.currentBalance);

    return MotionScaffold(
      title: 'Ledger accounts',
      icon: Icons.account_balance_outlined,
      onRefresh: _load,
      onFab: () => _openForm(),
      fabLabel: 'New',
      headerExtra: HeaderSearch(hint: 'Search name, bank, account no', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        if (!_loading && _error == null && _rows.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.only(top: 14),
            sliver: SliverToBoxAdapter(
              child: KpiStrip(children: [
                GradientKpi(icon: Icons.account_balance_outlined, label: 'Bank balance', value: bankTotal, format: (v) => formatMoney(v), accent: Accent.ocean),
                GradientKpi(icon: Icons.payments_outlined, label: 'Cash balance', value: cashTotal, format: (v) => formatMoney(v), accent: Accent.emerald),
                GradientKpi(icon: Icons.list_alt_rounded, label: 'Active accounts', value: active.length, accent: Accent.slate),
              ]),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _chip,
              options: [for (final k in chips.keys) (id: k, label: k, count: _rows.where(chips[k]!).length)],
              onChanged: (v) => setState(() => _chip = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton()
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.account_balance_outlined,
            title: _rows.isEmpty ? 'No ledger accounts yet' : 'No matches',
            message: _rows.isEmpty ? 'Add the bank accounts and cash boxes money moves through.' : null,
            actionLabel: _rows.isEmpty ? 'New ledger account' : null,
            onAction: _rows.isEmpty ? () => _openForm() : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final details = [r.bankName, r.accountNo].whereType<String>().join(' · ');
              final meta = [
                if (r.accountCode != null) 'Ledger ${r.accountCode}',
                if (!r.isMain && r.parentName != null) 'Under ${r.parentName}',
              ].join(' · ');
              return MotionTile(
                key: ValueKey(r.id),
                leading: AccentIcon(
                  r.type == 'CASH' ? Icons.payments_outlined : Icons.account_balance_outlined,
                  accent: r.type == 'CASH' ? Accent.emerald : Accent.ocean,
                  size: 42,
                ),
                title: r.name,
                subtitle: details.isEmpty ? _typeLabel(r.type) : '${_typeLabel(r.type)} · $details',
                meta: meta,
                trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  Text(formatMoney(r.currentBalance), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
                  if (!r.isActive || !r.isMain) ...[
                    const SizedBox(height: 4),
                    !r.isActive ? const StatusPill('Inactive', tone: MarketTone.error) : const StatusPill('Sub-account', tone: MarketTone.warn),
                  ],
                ]),
                onTap: () => _openForm(r),
                onLongPress: () => _more(r),
                onDelete: () => _delete(r),
              );
            },
          ),
      ],
    );
  }
}

// ── Create / edit ───────────────────────────────────────────────────────

class _LedgerAccountForm extends StatefulWidget {
  final AccountingLedgerService service;
  final List<LedgerAccount> all;
  final LedgerAccount? existing;
  const _LedgerAccountForm({required this.service, required this.all, this.existing});

  @override
  State<_LedgerAccountForm> createState() => _LedgerAccountFormState();
}

class _LedgerAccountFormState extends State<_LedgerAccountForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _accountNo = TextEditingController(text: widget.existing?.accountNo ?? '');
  late final _bankName = TextEditingController(text: widget.existing?.bankName ?? '');
  final _opening = TextEditingController(text: '0');
  late String _type = widget.existing?.type ?? 'BANK';
  late bool _isMain = widget.existing?.isMain ?? true;
  late int? _parentId = widget.existing?.parentBankAccountId;
  late bool _isActive = widget.existing?.isActive ?? true;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _accountNo, _bankName]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _accountNo, _bankName, _opening]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Active main registers of the same type, never the one being edited.
  List<PickOption> get _parentOptions => [
        for (final b in widget.all)
          if (b.isActive && b.isMain && b.type == _type && b.id != widget.existing?.id) PickOption(b.id, b.pickLabel),
      ];

  bool get _valid {
    if (_name.text.trim().isEmpty) return false;
    if (_type == 'BANK' && (_accountNo.text.trim().isEmpty || _bankName.text.trim().isEmpty)) return false;
    if (!_isMain && _parentId == null) return false;
    return true;
  }

  void _selectType(String type) {
    setState(() {
      _type = type;
      _isMain = true;
      _parentId = null;
    });
  }

  Future<void> _save() async {
    if (!_valid) return;
    setState(() => _saving = true);
    final bankBody = <String, dynamic>{
      'name': _name.text.trim(),
      'type': _type,
      'account_no': _accountNo.text.trim().isEmpty ? null : _accountNo.text.trim(),
      'bank_name': _bankName.text.trim().isEmpty ? null : _bankName.text.trim(),
      'is_main': _isMain,
      'parent_bank_account_id': _isMain ? null : _parentId,
      'is_active': _isActive,
    };
    try {
      if (_isEdit) {
        await widget.service.updateLedgerAccount(widget.existing!.id, bankBody);
      } else {
        await widget.service.createLedgerAccount(
          code: _nextBankCode(widget.all),
          bankBody: bankBody,
          openingBalance: double.tryParse(_opening.text.trim()) ?? 0,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Failed to save ledger account'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return FormSheet(
      title: _isEdit ? 'Edit ledger account' : 'New ledger account',
      submitLabel: _isEdit ? 'Save changes' : 'Create',
      busy: _saving,
      onSubmit: _valid ? _save : null,
      children: [
        SwitchField(label: 'Active', value: _isActive, onChanged: (v) => setState(() => _isActive = v)),
        FormLabel(
          label: 'Name',
          required: true,
          child: TextField(controller: _name, textCapitalization: TextCapitalization.sentences, decoration: motionInput(context, hint: 'e.g. Main current account', icon: Icons.badge_outlined)),
        ),
        FormLabel(
          label: 'Type',
          required: true,
          help: _isEdit ? 'The type can\'t change once the account exists.' : null,
          child: Wrap(spacing: 8, children: [
            for (final t in _types)
              ChoiceChip(label: Text(t.$2), selected: _type == t.$1, onSelected: _isEdit ? null : (_) => _selectType(t.$1)),
          ]),
        ),
        if (_type == 'BANK')
          FormLabel(
            label: 'Bank name',
            required: true,
            child: TextField(controller: _bankName, textCapitalization: TextCapitalization.words, decoration: motionInput(context, hint: 'Enter bank name', icon: Icons.account_balance_outlined)),
          ),
        FormLabel(
          label: 'Account no',
          required: _type == 'BANK',
          child: TextField(controller: _accountNo, decoration: motionInput(context, hint: _type == 'CASH' ? 'Optional' : 'Enter account number', icon: Icons.numbers_rounded)),
        ),
        SwitchField(
          label: 'Main account',
          sub: _isMain ? null : 'Nests under another main ${_typeLabel(_type).toLowerCase()} account',
          value: _isMain,
          onChanged: (v) => setState(() {
            _isMain = v;
            _parentId = null;
          }),
        ),
        if (!_isMain)
          FormLabel(
            label: 'Parent account',
            required: true,
            child: PickerField(
              value: _parentId,
              hint: 'Pick the main account this nests under',
              icon: Icons.account_tree_outlined,
              options: _parentOptions,
              onChanged: (v) => setState(() => _parentId = v == null ? null : int.tryParse(v.toString())),
            ),
          ),
        if (!_isEdit)
          FormLabel(
            label: 'Opening balance',
            child: TextField(
              controller: _opening,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: motionInput(context, icon: Icons.account_balance_wallet_outlined),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Current balance only moves via posted journal entries and payment vouchers, not this form.',
              style: TextStyle(fontSize: 12, color: p.label),
            ),
          ),
      ],
    );
  }
}
