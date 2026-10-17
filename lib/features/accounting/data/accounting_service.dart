import '../../../core/network/http_client.dart';
import '../models/accounting_models.dart';

/// Ported from erp/desktop's accounting module (ChartOfAccounts.tsx,
/// JournalEntries.tsx, PaymentVouchers.tsx) — same endpoints, same
/// client-driven "post a journal entry + sync the bank/cash balance"
/// sequence (there's no server-side transaction for this, matching desktop).
class AccountingService {
  final ApiClient _client;
  AccountingService(this._client);

  // ── Chart of Accounts ────────────────────────────────────────────────
  Future<List<AccountRow>> loadAccounts({bool activeOnly = false}) async {
    final filter = activeOnly ? '&\$filter=is_active eq true' : '';
    final res = await _client.get('accounts?\$expand=parent,bank_account&\$orderby=code asc&\$top=2000$filter');
    return unwrapList(res).cast<Map>().map(AccountRow.fromJson).toList();
  }

  /// Postable (non-group, active) accounts — for line/party pickers.
  Future<List<AccountRow>> loadPostableAccounts() async {
    final res = await _client.get(
      "accounts?\$select=id,code,name,type,opening_balance&\$filter=is_group eq false and is_active eq true&\$top=1000",
    );
    return unwrapList(res).cast<Map>().map(AccountRow.fromJson).toList();
  }

  Future<int> createAccount(Map<String, dynamic> body) async {
    final res = await _client.post('accounts', body, isV8: true);
    return toInt((res is Map ? (res['value'] ?? res) : res)?['id']);
  }

  Future<void> updateAccount(int id, Map<String, dynamic> body) => _client.put('accounts', id, body);

  Future<void> deleteAccount(int id) => _client.delete('accounts', id);

  Future<void> setAccountIsGroup(int id, bool isGroup) => _client.put('accounts', id, {'is_group': isGroup});

  // ── Bank / Cash sub-ledger ───────────────────────────────────────────
  /// All active bank/cash accounts — not just "main" ones, since computing
  /// the next sequential bank code (see AccountFormPage's `_nextBankCode`)
  /// needs the full set, same as erp/desktop's ChartOfAccounts.tsx. Callers
  /// that only want the "pick a parent" list filter client-side to
  /// `isMain == true`, matching desktop's own `mainBankAccountOptions`.
  Future<List<BankAccountInfo>> loadBankAccounts({String? type}) async {
    final res = await _client.get(
      "bank_accounts?\$select=id,account_id,name,type,is_main,account_no,bank_name,current_balance&\$expand=account(\$select=id,code)&\$filter=is_active eq true${type != null ? " and type eq '$type'" : ''}&\$top=2000",
    );
    return unwrapList(res).cast<Map>().map(BankAccountInfo.fromJson).toList();
  }

  Future<void> createBankAccount(Map<String, dynamic> body) => _client.post('bank_accounts', body, isV8: true);

  Future<void> updateBankAccount(int id, Map<String, dynamic> body) => _client.put('bank_accounts', id, body);

  Future<void> deleteBankAccount(int id) => _client.delete('bank_accounts', id);

  /// Re-reads the account's own current_balance right before adjusting it
  /// (not the possibly-stale value cached in a list screen) then writes
  /// `current + delta` — same read-then-write sequence as desktop's
  /// syncBankBalance in JournalEntries.tsx/PaymentVouchers.tsx (this app has
  /// no server-side ledger-posting transaction either).
  Future<void> syncBankBalance(int bankAccountId, double delta) async {
    final res = await _client.get('bank_accounts?\$select=id,current_balance&\$filter=id eq $bankAccountId&\$top=1');
    final rows = unwrapList(res);
    final current = rows.isNotEmpty ? toDoubleValue((rows.first as Map)['current_balance']) : 0.0;
    await _client.put('bank_accounts', bankAccountId, {'current_balance': current + delta});
  }

  // ── Journal Entries ──────────────────────────────────────────────────
  Future<List<JournalEntryRow>> loadJournalEntries() async {
    final res = await _client.get('journal_entries?\$expand=lines&\$orderby=id desc&\$top=500');
    return unwrapList(res).cast<Map>().map(JournalEntryRow.fromJson).toList();
  }

  Future<int> createJournalEntry({
    required String jeNo,
    String? entryDate,
    String? referenceType,
    int? referenceId,
    String? remarks,
  }) async {
    final res = await _client.post('journal_entries', {
      'je_no': jeNo,
      'entry_date': entryDate,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'remarks': remarks,
    }, isV8: true);
    return toInt((res is Map ? (res['value'] ?? res) : res)?['id']);
  }

  Future<void> setJournalEntryReferenceId(int journalEntryId, int referenceId) =>
      _client.put('journal_entries', journalEntryId, {'reference_id': referenceId});

  Future<void> deleteJournalEntry(int id) => _client.delete('journal_entries', id);

  /// journal_entry_lines has no workplace_id column of its own — the
  /// generic /v1/ OData layer would crash trying to inject one, so lines go
  /// through this custom /api/accounting route instead (mirrors
  /// cloud/src/module/accounting's own comment on why it exists).
  Future<List<JournalEntryLineRow>> loadJournalEntryLines(int journalEntryId) async {
    final res = await _client.get(
      'accounting/journal-entry-lines?\$filter=journal_entry_id eq $journalEntryId&\$expand=account(\$select=id,code,name)',
      isV8: false,
    );
    final rows = (res is Map && res['data'] is List) ? (res['data'] as List) : const [];
    return rows.cast<Map>().map(JournalEntryLineRow.fromJson).toList();
  }

  Future<void> createJournalEntryLine({
    required int journalEntryId,
    required int accountId,
    double debit = 0,
    double credit = 0,
    String? remarks,
  }) =>
      _client.post('accounting/journal-entry-lines', {
        'journal_entry_id': journalEntryId,
        'account_id': accountId,
        'debit': debit,
        'credit': credit,
        'remarks': remarks,
      }, isV8: false);

  /// Best-effort — a failure here just leaves the field blank for manual
  /// entry, same as desktop's generateJeNo()/PV equivalent.
  Future<String?> generateCode({required String code, required String table}) async {
    try {
      final res = await _client.post('generate-code', {'code': code, 'table': table}, isV8: false);
      return (res is Map) ? res['code']?.toString() : null;
    } catch (_) {
      return null;
    }
  }

  // ── Payment Vouchers ─────────────────────────────────────────────────
  Future<List<PaymentVoucherRow>> loadPaymentVouchers() async {
    final res = await _client.get('payment_vouchers?\$expand=debit_account,credit_account&\$orderby=id desc&\$top=500');
    return unwrapList(res).cast<Map>().map(PaymentVoucherRow.fromJson).toList();
  }

  Future<int> createPaymentVoucher(Map<String, dynamic> body) async {
    final res = await _client.post('payment_vouchers', body, isV8: true);
    return toInt((res is Map ? (res['value'] ?? res) : res)?['id']);
  }

  Future<void> deletePaymentVoucher(int id) => _client.delete('payment_vouchers', id);

  // ── Parties (for a Payment Voucher's optional party picker) ─────────
  Future<List<PartyOption>> loadClients() async {
    final res = await _client.get("clients?\$select=id,name&\$filter=is_active eq true&\$top=1000");
    return unwrapList(res).cast<Map>().map((row) => PartyOption(id: toInt(row['id']), name: (row['name'] ?? '').toString())).toList();
  }

  Future<List<PartyOption>> loadSuppliers() async {
    final res = await _client.get('suppliers?\$select=id,supplier_name&\$top=1000');
    return unwrapList(res)
        .cast<Map>()
        .map((row) => PartyOption(id: toInt(row['id']), name: (row['supplier_name'] ?? '').toString()))
        .toList();
  }
}
