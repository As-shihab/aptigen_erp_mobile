import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/aptigen_app_bar.dart';
import '../data/accounting_service.dart';
import '../models/accounting_models.dart';
import 'widgets/search_picker.dart';

const _kSubTypes = ['NONE', 'BANK', 'CASH'];
const _kSubTypeLabels = {'NONE': 'None', 'BANK': 'Bank', 'CASH': 'Cash'};

/// Next sequential bank/cash code (00001, 00002, ...) — same client-derived
/// numbering as erp/desktop's ChartOfAccounts.tsx `nextBankCode`.
String _nextBankCode(List<BankAccountInfo> allBankAccounts) {
  var max = 0;
  for (final b in allBankAccounts) {
    final parsed = int.tryParse(b.accountCode ?? '');
    if (parsed != null) max = parsed > max ? parsed : max;
  }
  return (max + 1).toString().padLeft(5, '0');
}

/// Create/edit form for one Chart of Accounts row — merges the ledger
/// account and its optional Bank/Cash sub-ledger into one form, exactly
/// like erp/desktop's ChartOfAccounts.tsx (there's no separate Bank/Cash
/// create screen; picking Bank/Cash here just reveals the extra fields).
class AccountFormPage extends StatefulWidget {
  final AccountRow? editing;
  const AccountFormPage({super.key, this.editing});

  @override
  State<AccountFormPage> createState() => _AccountFormPageState();
}

class _AccountFormPageState extends State<AccountFormPage> {
  final _service = AccountingService(ApiClient());
  bool _loadingLookups = true;
  bool _saving = false;

  List<AccountRow> _accounts = [];
  List<BankAccountInfo> _bankAccounts = [];

  late bool _isActive;
  late TextEditingController _codeCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _openingBalanceCtrl;
  late String _type;
  AccountRow? _parent;
  late String _subType;
  late TextEditingController _accountNoCtrl;
  late TextEditingController _bankNameCtrl;
  late bool _isMain;
  BankAccountInfo? _parentBankAccount;

  bool get _isEditMode => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _isActive = editing?.isActive ?? true;
    _codeCtrl = TextEditingController(text: editing?.code ?? '');
    _nameCtrl = TextEditingController(text: editing?.name ?? '');
    _openingBalanceCtrl = TextEditingController(text: (editing?.openingBalance ?? 0).toString());
    _type = editing?.type ?? kAccountTypes.first;
    _subType = editing?.bankAccount?.type ?? 'NONE';
    _accountNoCtrl = TextEditingController(text: editing?.bankAccount?.accountNo ?? '');
    _bankNameCtrl = TextEditingController(text: editing?.bankAccount?.bankName ?? '');
    _isMain = editing?.bankAccount?.isMain ?? true;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadingLookups = true);
    try {
      final accounts = await _service.loadAccounts(activeOnly: true);
      final bankAccounts = await _service.loadBankAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = accounts.where((a) => a.id != widget.editing?.id).toList();
        _bankAccounts = bankAccounts.where((b) => b.id != widget.editing?.bankAccount?.id).toList();
        final editing = widget.editing;
        if (editing?.parentId != null) {
          _parent = _accounts.where((a) => a.id == editing!.parentId).firstOrNull;
        }
        final parentBankId = editing?.bankAccount?.parentBankAccountId;
        if (parentBankId != null) {
          _parentBankAccount = _bankAccounts.where((b) => b.id == parentBankId).firstOrNull;
        }
      });
    } catch (_) {
      // Lookups failing just means empty pickers — the form itself still works.
    } finally {
      if (mounted) setState(() => _loadingLookups = false);
    }
  }

  List<BankAccountInfo> get _mainBankAccountOptions => _bankAccounts.where((b) => b.isMain && b.type == _subType).toList();

  void _selectSubType(String subType) {
    setState(() {
      _subType = subType;
      if (subType == 'NONE') {
        _accountNoCtrl.clear();
        _bankNameCtrl.clear();
        _isMain = true;
        _parentBankAccount = null;
        return;
      }
      _parent = null;
      if (!_isEditMode) {
        _codeCtrl.text = _nextBankCode(_bankAccounts);
      }
    });
  }

  bool get _canSave {
    if (_codeCtrl.text.trim().isEmpty || _nameCtrl.text.trim().isEmpty) return false;
    if (_subType == 'BANK' && (_accountNoCtrl.text.trim().isEmpty || _bankNameCtrl.text.trim().isEmpty)) return false;
    if (_subType != 'NONE' && !_isMain && _parentBankAccount == null) return false;
    return true;
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    try {
      final accountBody = {
        'parent_id': _subType == 'NONE' ? _parent?.id : null,
        'code': _codeCtrl.text.trim(),
        'name': _nameCtrl.text.trim(),
        'type': _type,
        'is_group': false,
        'opening_balance': double.tryParse(_openingBalanceCtrl.text) ?? 0,
        'is_active': _isActive,
      };

      int accountId;
      if (_isEditMode) {
        accountId = widget.editing!.id;
        await _service.updateAccount(accountId, accountBody);
      } else {
        accountId = await _service.createAccount(accountBody);
      }

      if (_subType == 'NONE') {
        final linkedBankId = widget.editing?.bankAccount?.id;
        if (linkedBankId != null) await _service.deleteBankAccount(linkedBankId);
        if (_parent != null) await _service.setAccountIsGroup(_parent!.id, true);
      } else {
        final bankBody = {
          'account_id': accountId,
          'name': _nameCtrl.text.trim(),
          'type': _subType,
          'account_no': _accountNoCtrl.text.trim().isEmpty ? null : _accountNoCtrl.text.trim(),
          'bank_name': _bankNameCtrl.text.trim().isEmpty ? null : _bankNameCtrl.text.trim(),
          'is_main': _isMain,
          'parent_bank_account_id': _isMain ? null : _parentBankAccount?.id,
        };
        final linkedBankId = widget.editing?.bankAccount?.id;
        if (linkedBankId != null) {
          await _service.updateBankAccount(linkedBankId, bankBody);
        } else {
          final opening = double.tryParse(_openingBalanceCtrl.text) ?? 0;
          await _service.createBankAccount({...bankBody, 'opening_balance': opening, 'current_balance': opening});
        }
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save account')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _openingBalanceCtrl.dispose();
    _accountNoCtrl.dispose();
    _bankNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AptigenAppBar(title: _isEditMode ? 'Edit account' : 'New account', showBack: true),
      body: _loadingLookups
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _codeCtrl,
                  enabled: _subType == 'NONE',
                  decoration: InputDecoration(labelText: _subType == 'NONE' ? 'Code *' : 'Bank code (auto)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type *'),
                  items: kAccountTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (value) => setState(() => _type = value ?? _type),
                ),
                const SizedBox(height: 12),
                TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name *')),
                const SizedBox(height: 12),
                if (_subType == 'NONE')
                  _PickerField(
                    label: 'Parent account (optional)',
                    value: _parent?.label,
                    onTap: () async {
                      final picked = await showSearchPicker<AccountRow>(
                        context: context,
                        title: 'Select parent account',
                        items: _accounts,
                        labelOf: (a) => a.label,
                      );
                      if (picked != null) setState(() => _parent = picked);
                    },
                    onClear: _parent == null ? null : () => setState(() => _parent = null),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _openingBalanceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Opening balance'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _subType,
                  decoration: const InputDecoration(labelText: 'Bank or cash account'),
                  items: _kSubTypes.map((t) => DropdownMenuItem(value: t, child: Text(_kSubTypeLabels[t]!))).toList(),
                  onChanged: (value) => _selectSubType(value ?? 'NONE'),
                ),
                if (_subType != 'NONE') ...[
                  const SizedBox(height: 16),
                  if (_subType == 'BANK') ...[
                    TextField(controller: _bankNameCtrl, decoration: const InputDecoration(labelText: 'Bank name *')),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _accountNoCtrl,
                    decoration: InputDecoration(labelText: _subType == 'BANK' ? 'Account no *' : 'Account no (optional)'),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Main account'),
                    value: _isMain,
                    onChanged: (value) => setState(() {
                      _isMain = value;
                      _parentBankAccount = null;
                    }),
                  ),
                  if (!_isMain)
                    _PickerField(
                      label: 'Parent bank/cash account *',
                      value: _parentBankAccount == null ? null : (_parentBankAccount!.bankName ?? _parentBankAccount!.accountNo ?? 'Account ${_parentBankAccount!.id}'),
                      onTap: () async {
                        final picked = await showSearchPicker<BankAccountInfo>(
                          context: context,
                          title: 'Select main account',
                          items: _mainBankAccountOptions,
                          labelOf: (b) => b.bankName ?? b.accountNo ?? 'Account ${b.id}',
                        );
                        if (picked != null) setState(() => _parentBankAccount = picked);
                      },
                      onClear: null,
                    ),
                  if (_isEditMode && widget.editing?.bankAccount != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        "Current balance only moves via posted Journal Entries/Payment Vouchers, not this form.",
                        style: TextStyle(fontSize: 12, color: AppColors.slate600),
                      ),
                    ),
                ],
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
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  const _PickerField({required this.label, required this.value, required this.onTap, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: onClear != null
                ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: onClear)
                : const Icon(Icons.arrow_drop_down),
          ),
          child: Text(value ?? 'Select…', style: TextStyle(color: value == null ? AppColors.slate400 : null)),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
