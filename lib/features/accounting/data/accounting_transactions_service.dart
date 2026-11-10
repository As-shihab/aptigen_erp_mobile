import '../../../core/network/http_client.dart';
import '../models/accounting_models.dart';
import 'accounting_service.dart';

/// Ported from erp/desktop's accounting Expenses.tsx, PaymentRequests.tsx
/// and PartyStatement.tsx. Lookups load in one `$batch` each (same calls as
/// desktop); the actual ledger posting reuses [AccountingService]'s journal
/// entry / line / bank balance / voucher calls so expenses, approved
/// requests and manual vouchers all post the exact same way.
class AccountingTransactionsService {
  final ApiClient _client;
  final AccountingService _accounting;
  AccountingTransactionsService(this._client) : _accounting = AccountingService(_client);

  AccountingService get accounting => _accounting;

  Future<List<List<dynamic>>> _batch(List<String> urls) async {
    final res = await _client.batch([
      for (var i = 0; i < urls.length; i++) BatchRequest(id: '${i + 1}', method: 'GET', url: urls[i]),
    ]);
    return [for (var i = 0; i < urls.length; i++) unwrapList(unwrapBatchBody(res, '${i + 1}'))];
  }

  static List<BankOption> _banks(List<dynamic> rows) => rows.cast<Map>().map(BankOption.fromJson).toList();

  static List<PartyOption> _parties(List<dynamic> rows, String nameKey) =>
      rows.cast<Map>().map((r) => PartyOption(id: toInt(r['id']), name: (r[nameKey] ?? '').toString())).toList();

  static Map<int, String> _employeeNames(List<dynamic> rows) => {
        for (final e in rows.cast<Map>())
          toInt(e['id']): [e['first_name'], e['last_name']].where((s) => s != null && s.toString().trim().isNotEmpty).join(' '),
      };

  // ── Shared posting sequence ──────────────────────────────────────────
  /// Same five sequential steps as desktop's PaymentVouchers.tsx save()
  /// (each needs the previous result, so no batch): journal entry header →
  /// debit + credit lines → bank/cash balance sync → voucher row → backfill
  /// the journal entry's reference_id. Always money out here (expense or an
  /// approved request), so the bank/cash account is the credit side.
  /// Returns the new voucher id (0 when the backend didn't return one).
  Future<int> postPayment({
    required String number,
    required DateTime? date,
    required int debitAccountId,
    required BankOption bank,
    required double amount,
    String? partyType,
    int? partyId,
    String? remarks,
  }) async {
    // entry_date / voucher_date are non-nullable DateTime columns — null
    // fails the create and a bare yyyy-mm-dd is rejected, so always send a
    // full ISO datetime, falling back to now.
    final when = (date ?? DateTime.now()).toUtc().toIso8601String();
    final journalEntryId = await _accounting.createJournalEntry(
      jeNo: number,
      entryDate: when,
      referenceType: 'PAYMENT_VOUCHER',
      remarks: remarks,
    );
    if (journalEntryId <= 0) throw Exception('Journal entry did not return an id');

    await _accounting.createJournalEntryLine(journalEntryId: journalEntryId, accountId: debitAccountId, debit: amount);
    await _accounting.createJournalEntryLine(journalEntryId: journalEntryId, accountId: bank.accountId, credit: amount);
    await _accounting.syncBankBalance(bank.id, -amount);

    final voucherId = await _accounting.createPaymentVoucher({
      'journal_entry_id': journalEntryId,
      'debit_account_id': debitAccountId,
      'credit_account_id': bank.accountId,
      'pv_no': number,
      'type': 'PAYMENT',
      'party_type': partyType,
      'party_id': partyId,
      'amount': amount,
      'voucher_date': when,
      'remarks': remarks,
    });
    if (voucherId > 0) await _accounting.setJournalEntryReferenceId(journalEntryId, voucherId);
    return voucherId;
  }

  /// Reverses a PAYMENT voucher's bank/cash impact (its credit side), then
  /// deletes the linked journal entry — payment_vouchers.journal_entry_id
  /// cascades, so lines and the voucher row go with it. The balance
  /// reversal is best-effort, same as desktop.
  Future<void> deletePayment(PaymentVoucherRow row, List<BankOption> banks) async {
    final bank = banks.where((b) => b.accountId == row.creditAccountId).firstOrNull;
    if (bank != null) {
      try {
        await _accounting.syncBankBalance(bank.id, row.amount);
      } catch (_) {
        // Non-fatal — the journal entry still gets deleted below.
      }
    }
    await _accounting.deleteJournalEntry(row.journalEntryId);
  }

  // ── Expenses ─────────────────────────────────────────────────────────
  /// Every PAYMENT voucher — an expense is a plain PAYMENT voucher
  /// underneath, same list desktop's Expenses grid reads.
  Future<List<PaymentVoucherRow>> loadExpenses() async {
    final res = await _client.get("payment_vouchers?\$expand=debit_account,credit_account&\$filter=type eq 'PAYMENT'&\$orderby=id desc&\$top=500");
    return unwrapList(res).cast<Map>().map(PaymentVoucherRow.fromJson).toList();
  }

  Future<ExpenseLookups> loadExpenseLookups() async {
    final r = await _batch([
      "accounts?\$select=id,code,name,type&\$expand=linked_bank_account(\$select=id,account_id,name)&\$filter=is_group eq false and is_active eq true and type eq 'EXPENSE'&\$top=500",
      'bank_accounts?\$select=id,account_id,name,current_balance&\$filter=is_active eq true&\$top=500',
      'clients?\$select=id,name&\$filter=is_active eq true&\$top=1000',
      'suppliers?\$select=id,supplier_name&\$top=1000',
    ]);
    return ExpenseLookups(
      expenseAccounts: r[0].cast<Map>().map(ExpenseAccountOption.fromJson).toList(),
      banks: _banks(r[1]),
      clients: _parties(r[2], 'name'),
      suppliers: _parties(r[3], 'supplier_name'),
    );
  }

  /// payment_vouchers' running-number column is pv_no, not the exp_no the
  /// EXP code would default to, so `column` is passed explicitly (desktop
  /// does the same). Best-effort — null leaves the field for manual entry.
  Future<String?> generateExpenseNo() async {
    try {
      final res = await _client.post('generate-code', {'code': 'EXP', 'table': 'payment_vouchers', 'column': 'pv_no'}, isV8: false);
      return (res is Map) ? res['code']?.toString() : null;
    } catch (_) {
      return null;
    }
  }

  // ── Payment requests ─────────────────────────────────────────────────
  Future<List<PaymentRequestRow>> loadPaymentRequests() async {
    final res = await _client.get('payment_requests?\$orderby=id desc&\$top=500');
    return unwrapList(res).cast<Map>().map(PaymentRequestRow.fromJson).toList();
  }

  Future<RequestLookups> loadRequestLookups() async {
    final r = await _batch([
      // $expand=bank_account so bank/cash-backed ledger accounts can be
      // dropped from the contra picker — those have their own picker.
      'accounts?\$select=id,code,name&\$expand=bank_account(\$select=id)&\$filter=is_group eq false and is_active eq true&\$top=1000',
      'bank_accounts?\$select=id,account_id,name,current_balance&\$filter=is_active eq true&\$top=500',
      'employees?\$select=id,first_name,last_name&\$top=2000',
      'clients?\$select=id,name&\$top=2000',
      'suppliers?\$select=id,supplier_name&\$top=2000',
    ]);
    return RequestLookups(
      accounts: r[0].cast<Map>().where((a) => a['bank_account'] == null).map(AccountRow.fromJson).toList(),
      banks: _banks(r[1]),
      employees: _employeeNames(r[2]),
      clients: {for (final p in _parties(r[3], 'name')) p.id: p.name},
      suppliers: {for (final p in _parties(r[4], 'supplier_name')) p.id: p.name},
    );
  }

  Future<void> updatePaymentRequest(int id, Map<String, dynamic> body) => _client.put('payment_requests', id, body);

  // ── Party statement ──────────────────────────────────────────────────
  Future<({List<PartyOption> clients, List<PartyOption> suppliers})> loadStatementParties() async {
    final r = await _batch([
      'clients?\$select=id,name&\$filter=is_active eq true&\$top=2000',
      'suppliers?\$select=id,supplier_name&\$top=2000',
    ]);
    return (clients: _parties(r[0], 'name'), suppliers: _parties(r[1], 'supplier_name'));
  }

  /// A client's statement = their sales orders + vouchers tagged to them; a
  /// supplier's is vouchers only (purchase orders / MRRs carry a free-text
  /// supplier_name, no supplier_id FK to walk). Sorted by date with a
  /// running Σdebit − Σcredit, same as desktop.
  Future<List<StatementLine>> loadPartyStatement(String partyType, int partyId) async {
    final isClient = partyType == 'CLIENT';
    final r = await _batch([
      "payment_vouchers?\$select=id,pv_no,type,amount,voucher_date&\$filter=party_type eq '$partyType' and party_id eq $partyId&\$top=2000",
      if (isClient) 'sales_orders?\$select=id,total,status,completed_at,created_at&\$filter=client_id eq $partyId&\$top=2000',
    ]);

    final entries = <({DateTime? date, String description, double debit, double credit})>[];
    if (isClient) {
      for (final s in r[1].cast<Map>()) {
        entries.add((
          date: DateTime.tryParse((s['completed_at'] ?? s['created_at'] ?? '').toString()),
          description: 'Sale #${s['id']} (${(s['status'] ?? '').toString().toLowerCase()})',
          debit: toDoubleValue(s['total']),
          credit: 0,
        ));
      }
    }
    for (final v in r[0].cast<Map>()) {
      // CLIENT: a receipt reduces what they owe us (credit), a payment to
      // them (refund) increases it. SUPPLIER: a payment reduces what we owe
      // them (credit), a receipt from them reduces our cost (debit).
      final isReceipt = v['type'] == 'RECEIPT';
      final reducesBalance = isClient ? isReceipt : !isReceipt;
      final amount = toDoubleValue(v['amount']);
      entries.add((
        date: DateTime.tryParse((v['voucher_date'] ?? '').toString()),
        description: '${isReceipt ? 'Receipt' : 'Payment'} ${v['pv_no'] ?? ''}',
        debit: reducesBalance ? 0 : amount,
        credit: reducesBalance ? amount : 0,
      ));
    }

    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    entries.sort((a, b) => (a.date ?? epoch).compareTo(b.date ?? epoch));
    var running = 0.0;
    return [
      for (final e in entries)
        StatementLine(
          date: e.date,
          description: e.description,
          debit: e.debit,
          credit: e.credit,
          balance: ((running += e.debit - e.credit) * 100).roundToDouble() / 100,
        ),
    ];
  }
}

// ── Models ─────────────────────────────────────────────────────────────

/// Active bank/cash account as the transaction pickers need it — desktop's
/// `BankAccountOption` (with its display `name`, which [BankAccountInfo]
/// doesn't carry).
class BankOption {
  final int id;
  final int accountId;
  final String name;
  final double currentBalance;
  const BankOption({required this.id, required this.accountId, required this.name, required this.currentBalance});

  factory BankOption.fromJson(Map json) => BankOption(
        id: toInt(json['id']),
        accountId: toInt(json['account_id']),
        name: (json['name'] ?? '').toString(),
        currentBalance: toDoubleValue(json['current_balance']),
      );
}

/// EXPENSE-type account plus its "Default paid from" bank/cash account
/// (accounts.linked_bank_account) — an expense's paid-from side is derived
/// from this rather than picked separately, same as desktop.
class ExpenseAccountOption {
  final int id;
  final String code;
  final String name;
  final int? paidFromBankId;
  final int? paidFromAccountId;
  final String? paidFromName;

  const ExpenseAccountOption({
    required this.id,
    required this.code,
    required this.name,
    this.paidFromBankId,
    this.paidFromAccountId,
    this.paidFromName,
  });

  String get label => '$code — $name';

  factory ExpenseAccountOption.fromJson(Map json) {
    final linked = json['linked_bank_account'] is Map ? json['linked_bank_account'] as Map : null;
    return ExpenseAccountOption(
      id: toInt(json['id']),
      code: (json['code'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      paidFromBankId: linked == null ? null : toInt(linked['id']),
      paidFromAccountId: linked == null ? null : toInt(linked['account_id']),
      paidFromName: linked == null ? null : toStringOrNull(linked['name']),
    );
  }
}

class ExpenseLookups {
  final List<ExpenseAccountOption> expenseAccounts;
  final List<BankOption> banks;
  final List<PartyOption> clients;
  final List<PartyOption> suppliers;
  const ExpenseLookups({required this.expenseAccounts, required this.banks, required this.clients, required this.suppliers});

  static const empty = ExpenseLookups(expenseAccounts: [], banks: [], clients: [], suppliers: []);
}

/// Mirrors erp/desktop's PaymentRequests.tsx `RequestRow`.
class PaymentRequestRow {
  final int id;
  final int? paymentVoucherId;
  final String sourceModule;
  final String referenceType;
  final int referenceId;
  final String? partyType;
  final int? partyId;
  final String requestNo;
  final double amount;
  final String status; // PENDING | APPROVED | REJECTED
  final DateTime? requestDate;
  final String? remarks;
  final String? decisionRemarks;

  const PaymentRequestRow({
    required this.id,
    this.paymentVoucherId,
    required this.sourceModule,
    required this.referenceType,
    required this.referenceId,
    this.partyType,
    this.partyId,
    required this.requestNo,
    required this.amount,
    required this.status,
    this.requestDate,
    this.remarks,
    this.decisionRemarks,
  });

  bool get isPending => status == 'PENDING';

  factory PaymentRequestRow.fromJson(Map json) => PaymentRequestRow(
        id: toInt(json['id']),
        paymentVoucherId: json['payment_voucher_id'] == null ? null : toInt(json['payment_voucher_id']),
        sourceModule: (json['source_module'] ?? '').toString(),
        referenceType: (json['reference_type'] ?? '').toString(),
        referenceId: toInt(json['reference_id']),
        partyType: toStringOrNull(json['party_type']),
        partyId: json['party_id'] == null ? null : toInt(json['party_id']),
        requestNo: (json['request_no'] ?? '').toString(),
        amount: toDoubleValue(json['amount']),
        status: (json['status'] ?? 'PENDING').toString(),
        requestDate: DateTime.tryParse((json['request_date'] ?? '').toString()),
        remarks: toStringOrNull(json['remarks']),
        decisionRemarks: toStringOrNull(json['decision_remarks']),
      );
}

class RequestLookups {
  /// Postable non-bank accounts — the contra (expense / payable) side.
  final List<AccountRow> accounts;
  final List<BankOption> banks;
  final Map<int, String> employees;
  final Map<int, String> clients;
  final Map<int, String> suppliers;
  const RequestLookups({required this.accounts, required this.banks, required this.employees, required this.clients, required this.suppliers});

  static const empty = RequestLookups(accounts: [], banks: [], employees: {}, clients: {}, suppliers: {});

  /// Party is polymorphic (plain party_type / party_id, no relation), so
  /// names come from the lookup maps.
  String? partyName(String? type, int? id) {
    if (id == null) return null;
    return switch (type) {
      'EMPLOYEE' => employees[id],
      'CLIENT' => clients[id],
      'SUPPLIER' => suppliers[id],
      _ => null,
    };
  }
}

class StatementLine {
  final DateTime? date;
  final String description;
  final double debit;
  final double credit;
  final double balance;
  const StatementLine({this.date, required this.description, required this.debit, required this.credit, required this.balance});
}
