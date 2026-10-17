import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/aptigen_app_bar.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../data/accounting_service.dart';
import '../models/accounting_models.dart';
import 'widgets/search_picker.dart';

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Payment Vouchers — an everyday data-entry screen on top of the ledger:
/// pick a bank/cash account + a contra account, RECEIPT/PAYMENT decides
/// which side is debit vs credit. Mirrors erp/desktop's PaymentVouchers.tsx,
/// including "saving one posts its own journal entry underneath" and
/// create+delete-only (same append-only reasoning as Journal Entries).
class PaymentVouchersPage extends StatefulWidget {
  const PaymentVouchersPage({super.key});

  @override
  State<PaymentVouchersPage> createState() => _PaymentVouchersPageState();
}

class _PaymentVouchersPageState extends State<PaymentVouchersPage> {
  final _service = AccountingService(ApiClient());
  bool _loading = true;
  String? _error;
  List<PaymentVoucherRow> _rows = [];
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
      final rows = await _service.loadPaymentVouchers();
      final bankAccounts = await _service.loadBankAccounts();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _bankAccounts = bankAccounts;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load payment vouchers.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const _PaymentVoucherFormPage()));
    if (created == true) _load();
  }

  Future<void> _delete(PaymentVoucherRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete payment voucher'),
        content: Text('Delete "${row.pvNo}"? Its journal entry and bank/cash balance impact will be reversed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final bankSide = _bankAccounts.where((b) => b.accountId == row.debitAccountId || b.accountId == row.creditAccountId).firstOrNull;
      if (bankSide != null) {
        final delta = bankSide.accountId == row.debitAccountId ? -row.amount : row.amount;
        await _service.syncBankBalance(bankSide.id, delta);
      }
    } catch (_) {
      // Non-fatal — the voucher/journal entry still get deleted below.
    }
    try {
      // Deleting the linked journal_entries row cascades to both
      // journal_entry_lines and this payment_vouchers row.
      await _service.deleteJournalEntry(row.journalEntryId);
      _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete payment voucher')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AptigenAppBar(title: 'Payment Vouchers', showBack: true),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        backgroundColor: AppColors.brand,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: _load,
        child: AsyncStateView(
          loading: _loading,
          error: _error,
          isEmpty: _rows.isEmpty,
          emptyMessage: 'No payment vouchers yet — tap + to record one.',
          emptyIcon: Icons.receipt_long_outlined,
          onRetry: _load,
          builder: (context) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: _rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = _rows[index];
              final isReceipt = row.type == 'RECEIPT';
              return Dismissible(
                key: ValueKey(row.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) async {
                  _delete(row);
                  return false;
                },
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.delete_outline, color: AppColors.error),
                ),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.slate400.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(color: (isReceipt ? AppColors.success : AppColors.error).withValues(alpha: 0.12), shape: BoxShape.circle),
                        child: Icon(isReceipt ? Icons.call_received : Icons.call_made, size: 16, color: isReceipt ? AppColors.success : AppColors.error),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(row.pvNo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                            const SizedBox(height: 3),
                            Text(
                              '${row.debitAccountLabel ?? '—'} → ${row.creditAccountLabel ?? '—'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: AppColors.slate600),
                            ),
                            if (row.voucherDate != null) Text(row.voucherDate!.split('T').first, style: TextStyle(fontSize: 11, color: AppColors.slate400)),
                          ],
                        ),
                      ),
                      Text(
                        row.amount.toStringAsFixed(2),
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: isReceipt ? AppColors.success : AppColors.error),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PaymentVoucherFormPage extends StatefulWidget {
  const _PaymentVoucherFormPage();

  @override
  State<_PaymentVoucherFormPage> createState() => _PaymentVoucherFormPageState();
}

class _PaymentVoucherFormPageState extends State<_PaymentVoucherFormPage> {
  final _service = AccountingService(ApiClient());
  final _pvNoCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _generatingPvNo = true;
  String _type = 'RECEIPT';
  DateTime? _voucherDate;
  String? _partyType;
  PartyOption? _party;

  List<AccountRow> _accounts = [];
  List<BankAccountInfo> _bankAccounts = [];
  List<PartyOption> _clients = [];
  List<PartyOption> _suppliers = [];
  BankAccountInfo? _bankAccount;
  AccountRow? _otherAccount;

  List<PartyOption> get _parties => _partyType == 'CLIENT' ? _clients : _partyType == 'SUPPLIER' ? _suppliers : const [];

  @override
  void initState() {
    super.initState();
    _load();
    _generatePvNo();
  }

  @override
  void dispose() {
    _pvNoCtrl.dispose();
    _amountCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final accounts = await _service.loadPostableAccounts();
      final bankAccounts = await _service.loadBankAccounts();
      final clients = await _service.loadClients();
      final suppliers = await _service.loadSuppliers();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _bankAccounts = bankAccounts.where((b) => b.isActive).toList();
        _clients = clients;
        _suppliers = suppliers;
      });
    } catch (_) {
      // Empty pickers — the rest of the form still works.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generatePvNo() async {
    final code = await _service.generateCode(code: 'PV', table: 'payment_vouchers');
    if (!mounted) return;
    setState(() {
      if (code != null) _pvNoCtrl.text = code;
      _generatingPvNo = false;
    });
  }

  double get _amount => double.tryParse(_amountCtrl.text) ?? 0;
  bool get _canSave => _pvNoCtrl.text.trim().isNotEmpty && _bankAccount != null && _otherAccount != null && _amount > 0;

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    try {
      final debitAccountId = _type == 'RECEIPT' ? _bankAccount!.accountId : _otherAccount!.id;
      final creditAccountId = _type == 'RECEIPT' ? _otherAccount!.id : _bankAccount!.accountId;

      final journalEntryId = await _service.createJournalEntry(
        jeNo: _pvNoCtrl.text.trim(),
        entryDate: _voucherDate?.toIso8601String(),
        referenceType: 'PAYMENT_VOUCHER',
        remarks: _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
      );

      await _service.createJournalEntryLine(journalEntryId: journalEntryId, accountId: debitAccountId, debit: _amount);
      await _service.createJournalEntryLine(journalEntryId: journalEntryId, accountId: creditAccountId, credit: _amount);
      await _service.syncBankBalance(_bankAccount!.id, _type == 'RECEIPT' ? _amount : -_amount);

      final voucherId = await _service.createPaymentVoucher({
        'journal_entry_id': journalEntryId,
        'debit_account_id': debitAccountId,
        'credit_account_id': creditAccountId,
        'pv_no': _pvNoCtrl.text.trim(),
        'type': _type,
        'party_type': _partyType,
        'party_id': _party?.id,
        'amount': _amount,
        'voucher_date': _voucherDate?.toIso8601String(),
        'remarks': _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
      });
      if (voucherId > 0) await _service.setJournalEntryReferenceId(journalEntryId, voucherId);

      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save payment voucher')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: _voucherDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked != null) setState(() => _voucherDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AptigenAppBar(title: 'New Payment Voucher', showBack: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                TextField(
                  controller: _pvNoCtrl,
                  enabled: !_generatingPvNo,
                  decoration: const InputDecoration(labelText: 'PV No *'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type *'),
                  items: const [
                    DropdownMenuItem(value: 'RECEIPT', child: Text('RECEIPT (money in)')),
                    DropdownMenuItem(value: 'PAYMENT', child: Text('PAYMENT (money out)')),
                  ],
                  onChanged: (value) => setState(() => _type = value ?? 'RECEIPT'),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showSearchPicker<BankAccountInfo>(
                      context: context,
                      title: 'Select bank / cash account',
                      items: _bankAccounts,
                      labelOf: (b) => b.bankName ?? b.accountNo ?? 'Account ${b.id}',
                    );
                    if (picked != null) setState(() => _bankAccount = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Bank / Cash account *', suffixIcon: Icon(Icons.arrow_drop_down)),
                    child: Text(
                      _bankAccount == null ? 'Select…' : (_bankAccount!.bankName ?? _bankAccount!.accountNo ?? 'Account ${_bankAccount!.id}'),
                      style: TextStyle(color: _bankAccount == null ? AppColors.slate400 : null),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showSearchPicker<AccountRow>(
                      context: context,
                      title: 'Select the other side of the entry',
                      items: _accounts,
                      labelOf: (a) => a.label,
                    );
                    if (picked != null) setState(() => _otherAccount = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(labelText: _type == 'RECEIPT' ? 'Income / Receivable account *' : 'Expense / Payable account *', suffixIcon: const Icon(Icons.arrow_drop_down)),
                    child: Text(_otherAccount?.label ?? 'Select…', overflow: TextOverflow.ellipsis, style: TextStyle(color: _otherAccount == null ? AppColors.slate400 : null)),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _partyType,
                  decoration: const InputDecoration(labelText: 'Party type (optional)'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('None')),
                    DropdownMenuItem(value: 'CLIENT', child: Text('Client')),
                    DropdownMenuItem(value: 'SUPPLIER', child: Text('Supplier')),
                    DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                  ],
                  onChanged: (value) => setState(() {
                    _partyType = value;
                    _party = null;
                  }),
                ),
                if (_partyType != null && _partyType != 'OTHER') ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showSearchPicker<PartyOption>(context: context, title: 'Select party', items: _parties, labelOf: (p) => p.name);
                      if (picked != null) setState(() => _party = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Party (optional)', suffixIcon: Icon(Icons.arrow_drop_down)),
                      child: Text(_party?.name ?? 'Select…', style: TextStyle(color: _party == null ? AppColors.slate400 : null)),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount *'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Voucher date', suffixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
                    child: Text(_voucherDate == null ? 'Today' : _voucherDate!.toIso8601String().split('T').first),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(controller: _remarksCtrl, decoration: const InputDecoration(labelText: 'Remarks (optional)'), maxLines: 2),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _canSave && !_saving ? _save : null,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: Colors.white),
              child: Text(_saving ? 'Saving…' : 'Submit'),
            ),
          ),
        ),
      ),
    );
  }
}
