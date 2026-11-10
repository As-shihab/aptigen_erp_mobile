import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/aptigen_app_bar.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../data/accounting_service.dart';
import '../models/accounting_models.dart';
import 'widgets/search_picker.dart';

class _LineDraft {
  AccountRow? account;
  final debitCtrl = TextEditingController();
  final creditCtrl = TextEditingController();
  final remarksCtrl = TextEditingController();

  void dispose() {
    debitCtrl.dispose();
    creditCtrl.dispose();
    remarksCtrl.dispose();
  }
}

/// Journal Entries — the general ledger's source of truth. Create + delete
/// only, no edit — mirrors erp/desktop's JournalEntries.tsx: an entry posts
/// immediately (no draft/posted workflow) and moves bank/cash balances right
/// away, so a mistake is fixed by deleting (which reverses the balance
/// impact) and re-entering, not editing history.
class JournalEntriesPage extends StatefulWidget {
  const JournalEntriesPage({super.key});

  @override
  State<JournalEntriesPage> createState() => _JournalEntriesPageState();
}

class _JournalEntriesPageState extends State<JournalEntriesPage> {
  final _service = AccountingService(ApiClient());
  bool _loading = true;
  String? _error;
  List<JournalEntryRow> _rows = [];

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
      final rows = await _service.loadJournalEntries();
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load journal entries.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const _JournalEntryFormPage()));
    if (created == true) _load();
  }

  Future<void> _delete(JournalEntryRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete journal entry'),
        content: Text('Delete "${row.jeNo}"? Any bank/cash balance it moved will be reversed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final lines = await _service.loadJournalEntryLines(row.id);
      final bankAccounts = await _service.loadBankAccounts();
      for (final line in lines) {
        final bank = bankAccounts.where((b) => b.accountId == line.accountId).firstOrNull;
        if (bank != null) await _service.syncBankBalance(bank.id, -(line.debit - line.credit));
      }
    } catch (_) {
      // Non-fatal — the entry itself still gets deleted below.
    }
    try {
      await _service.deleteJournalEntry(row.id);
      _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete journal entry')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AptigenAppBar(title: 'Journal entries', showBack: true),
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
          emptyMessage: 'No journal entries yet — tap + to post one.',
          emptyIcon: Icons.menu_book_outlined,
          onRetry: _load,
          builder: (context) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: _rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = _rows[index];
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(row.jeNo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                                  child: Text(row.referenceType ?? 'Manual', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.brand)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('${row.lines.length} line${row.lines.length == 1 ? '' : 's'}${row.entryDate != null ? ' · ${row.entryDate!.split('T').first}' : ''}',
                                style: TextStyle(fontSize: 11, color: AppColors.slate600)),
                            if ((row.remarks ?? '').isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(row.remarks!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColors.slate400)),
                            ],
                          ],
                        ),
                      ),
                      Text(row.total.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
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

class _JournalEntryFormPage extends StatefulWidget {
  const _JournalEntryFormPage();

  @override
  State<_JournalEntryFormPage> createState() => _JournalEntryFormPageState();
}

class _JournalEntryFormPageState extends State<_JournalEntryFormPage> {
  final _service = AccountingService(ApiClient());
  final _jeNoCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  DateTime? _entryDate;
  bool _generatingJeNo = true;
  bool _loadingAccounts = true;
  bool _saving = false;
  List<AccountRow> _accounts = [];
  List<BankAccountInfo> _bankAccounts = [];
  final List<_LineDraft> _lines = [_LineDraft(), _LineDraft()];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
    _generateJeNo();
  }

  @override
  void dispose() {
    _jeNoCtrl.dispose();
    _remarksCtrl.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    try {
      final accounts = await _service.loadPostableAccounts();
      final bankAccounts = await _service.loadBankAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _bankAccounts = bankAccounts;
      });
    } catch (_) {
      // Empty picker — the rest of the form still works.
    } finally {
      if (mounted) setState(() => _loadingAccounts = false);
    }
  }

  Future<void> _generateJeNo() async {
    final code = await _service.generateCode(code: 'JE', table: 'journal_entries');
    if (!mounted) return;
    setState(() {
      if (code != null) _jeNoCtrl.text = code;
      _generatingJeNo = false;
    });
  }

  void _addLine() => setState(() => _lines.add(_LineDraft()));
  void _removeLine(int index) {
    if (_lines.length <= 2) return;
    setState(() {
      _lines.removeAt(index).dispose();
    });
  }

  List<_LineDraft> get _validLines =>
      _lines.where((l) => l.account != null && ((double.tryParse(l.debitCtrl.text) ?? 0) > 0 || (double.tryParse(l.creditCtrl.text) ?? 0) > 0)).toList();

  double get _totalDebit => _validLines.fold(0, (sum, l) => sum + (double.tryParse(l.debitCtrl.text) ?? 0));
  double get _totalCredit => _validLines.fold(0, (sum, l) => sum + (double.tryParse(l.creditCtrl.text) ?? 0));

  bool get _isBalanced {
    final valid = _validLines;
    if (valid.length < 2 || _totalDebit <= 0 || _totalDebit != _totalCredit) return false;
    return valid.every((l) => !((double.tryParse(l.debitCtrl.text) ?? 0) > 0 && (double.tryParse(l.creditCtrl.text) ?? 0) > 0));
  }

  bool get _canSave => _jeNoCtrl.text.trim().isNotEmpty && _isBalanced;

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    try {
      final journalEntryId = await _service.createJournalEntry(
        jeNo: _jeNoCtrl.text.trim(),
        entryDate: (_entryDate ?? DateTime.now()).toIso8601String(),
        remarks: _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
      );

      for (final line in _validLines) {
        final debit = double.tryParse(line.debitCtrl.text) ?? 0;
        final credit = double.tryParse(line.creditCtrl.text) ?? 0;
        await _service.createJournalEntryLine(
          journalEntryId: journalEntryId,
          accountId: line.account!.id,
          debit: debit,
          credit: credit,
          remarks: line.remarksCtrl.text.trim().isEmpty ? null : line.remarksCtrl.text.trim(),
        );
        final bank = _bankAccounts.where((b) => b.accountId == line.account!.id).firstOrNull;
        if (bank != null) await _service.syncBankBalance(bank.id, debit - credit);
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to post journal entry')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: _entryDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked != null) setState(() => _entryDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AptigenAppBar(title: 'New journal entry', showBack: true),
      body: _loadingAccounts
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                TextField(
                  controller: _jeNoCtrl,
                  enabled: !_generatingJeNo,
                  decoration: InputDecoration(labelText: 'JE No *', suffixIcon: _generatingJeNo ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Entry date', suffixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
                    child: Text(_entryDate == null ? 'Today' : _entryDate!.toIso8601String().split('T').first),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(controller: _remarksCtrl, decoration: const InputDecoration(labelText: 'Remarks (optional)'), maxLines: 2),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Lines (debit must equal credit)', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextButton.icon(onPressed: _addLine, icon: const Icon(Icons.add, size: 18), label: const Text('Add line')),
                  ],
                ),
                const SizedBox(height: 8),
                ...List.generate(_lines.length, (index) => _LineEditor(
                      line: _lines[index],
                      accounts: _accounts,
                      canRemove: _lines.length > 2,
                      onChanged: () => setState(() {}),
                      onRemove: () => _removeLine(index),
                    )),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Debit: ${_totalDebit.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text('Credit: ${_totalCredit.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(_isBalanced ? 'Balanced' : 'Not balanced', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _isBalanced ? AppColors.success : AppColors.error)),
                    ],
                  ),
                ),
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
              child: Text(_saving ? 'Posting…' : 'Post entry'),
            ),
          ),
        ),
      ),
    );
  }
}

class _LineEditor extends StatelessWidget {
  final _LineDraft line;
  final List<AccountRow> accounts;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  const _LineEditor({required this.line, required this.accounts, required this.canRemove, required this.onChanged, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: AppColors.slate400.withValues(alpha: 0.2)), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showSearchPicker<AccountRow>(context: context, title: 'Select account', items: accounts, labelOf: (a) => a.label);
                    if (picked != null) {
                      line.account = picked;
                      onChanged();
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Account', isDense: true),
                    child: Text(line.account?.label ?? 'Select…', overflow: TextOverflow.ellipsis, style: TextStyle(color: line.account == null ? AppColors.slate400 : null)),
                  ),
                ),
              ),
              if (canRemove) IconButton(icon: const Icon(Icons.close, size: 18, color: AppColors.error), onPressed: onRemove),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: line.debitCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Debit', isDense: true),
                  onChanged: (_) {
                    if (line.debitCtrl.text.isNotEmpty) line.creditCtrl.clear();
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: line.creditCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Credit', isDense: true),
                  onChanged: (_) {
                    if (line.creditCtrl.text.isNotEmpty) line.debitCtrl.clear();
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(controller: line.remarksCtrl, decoration: const InputDecoration(labelText: 'Remarks (optional)', isDense: true)),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
