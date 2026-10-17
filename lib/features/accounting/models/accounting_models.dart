int toInt(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;
double toDoubleValue(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0;
String? toStringOrNull(dynamic value) {
  final s = value?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

const kAccountTypes = ['ASSET', 'LIABILITY', 'EQUITY', 'INCOME', 'EXPENSE'];

class BankAccountInfo {
  final int id;
  final int accountId;
  final String type; // BANK | CASH
  final String? accountNo;
  final String? bankName;
  final bool isMain;
  final int? parentBankAccountId;
  final double currentBalance;
  final double openingBalance;
  final bool isActive;
  // Only populated when the query expands `account($select=id,code)` (see
  // AccountingService.loadMainBankAccounts) — the ledger account's own
  // `code`, needed for ChartOfAccounts' sequential bank-code numbering
  // (mirrors erp/desktop's `MainBankAccountOption.account.code`).
  final String? accountCode;

  const BankAccountInfo({
    required this.id,
    required this.accountId,
    required this.type,
    this.accountNo,
    this.bankName,
    required this.isMain,
    this.parentBankAccountId,
    required this.currentBalance,
    required this.openingBalance,
    required this.isActive,
    this.accountCode,
  });

  factory BankAccountInfo.fromJson(Map json) {
    final account = json['account'] is Map ? json['account'] as Map : null;
    return BankAccountInfo(
      id: toInt(json['id']),
      accountId: toInt(json['account_id'] ?? account?['id']),
      type: (json['type'] ?? 'BANK').toString(),
      accountNo: toStringOrNull(json['account_no']),
      bankName: toStringOrNull(json['bank_name']),
      isMain: json['is_main'] != false,
      parentBankAccountId: json['parent_bank_account_id'] == null ? null : toInt(json['parent_bank_account_id']),
      currentBalance: toDoubleValue(json['current_balance']),
      openingBalance: toDoubleValue(json['opening_balance']),
      isActive: json['is_active'] != false,
      accountCode: account == null ? null : toStringOrNull(account['code']),
    );
  }
}

/// Mirrors erp/desktop's ChartOfAccounts.tsx `AccountRow` — the ledger
/// account plus its optional bank/cash sub-ledger row (`bank_account`),
/// merged into one form there and kept that way here.
class AccountRow {
  final int id;
  final int? parentId;
  final String code;
  final String name;
  final String type;
  final bool isGroup;
  final double openingBalance;
  final bool isActive;
  final String? parentLabel;
  final BankAccountInfo? bankAccount;

  const AccountRow({
    required this.id,
    this.parentId,
    required this.code,
    required this.name,
    required this.type,
    required this.isGroup,
    required this.openingBalance,
    required this.isActive,
    this.parentLabel,
    this.bankAccount,
  });

  String get label => '$code — $name';

  factory AccountRow.fromJson(Map json) {
    final parent = json['parent'] is Map ? json['parent'] as Map : null;
    final bankAccount = json['bank_account'] is Map ? json['bank_account'] as Map : null;
    return AccountRow(
      id: toInt(json['id']),
      parentId: json['parent_id'] == null ? null : toInt(json['parent_id']),
      code: (json['code'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      type: (json['type'] ?? 'ASSET').toString(),
      isGroup: json['is_group'] == true,
      openingBalance: toDoubleValue(json['opening_balance']),
      isActive: json['is_active'] != false,
      parentLabel: parent == null ? null : '${parent['code']} — ${parent['name']}',
      bankAccount: bankAccount == null ? null : BankAccountInfo.fromJson(bankAccount),
    );
  }
}

class JournalEntryLineRow {
  final int id;
  final int accountId;
  final double debit;
  final double credit;
  final String? remarks;
  final String? accountLabel;

  const JournalEntryLineRow({
    required this.id,
    required this.accountId,
    required this.debit,
    required this.credit,
    this.remarks,
    this.accountLabel,
  });

  factory JournalEntryLineRow.fromJson(Map json) {
    final account = json['account'] is Map ? json['account'] as Map : null;
    return JournalEntryLineRow(
      id: toInt(json['id']),
      accountId: toInt(json['account_id']),
      debit: toDoubleValue(json['debit']),
      credit: toDoubleValue(json['credit']),
      remarks: toStringOrNull(json['remarks']),
      accountLabel: account == null ? null : '${account['code']} — ${account['name']}',
    );
  }
}

/// Mirrors erp/desktop's JournalEntries.tsx `JournalEntryRow`.
class JournalEntryRow {
  final int id;
  final String jeNo;
  final String? entryDate;
  final String? referenceType;
  final String? remarks;
  final List<JournalEntryLineRow> lines;

  const JournalEntryRow({
    required this.id,
    required this.jeNo,
    this.entryDate,
    this.referenceType,
    this.remarks,
    required this.lines,
  });

  double get total => lines.fold<double>(0, (sum, l) => sum + l.debit);

  factory JournalEntryRow.fromJson(Map json) {
    final linesRaw = json['lines'] is List ? json['lines'] as List : const [];
    return JournalEntryRow(
      id: toInt(json['id']),
      jeNo: (json['je_no'] ?? '').toString(),
      entryDate: toStringOrNull(json['entry_date']),
      referenceType: toStringOrNull(json['reference_type']),
      remarks: toStringOrNull(json['remarks']),
      lines: linesRaw.cast<Map>().map(JournalEntryLineRow.fromJson).toList(),
    );
  }
}

const kPartyTypes = ['CLIENT', 'SUPPLIER', 'OTHER'];

/// Mirrors erp/desktop's PaymentVouchers.tsx `VoucherRow`.
class PaymentVoucherRow {
  final int id;
  final int journalEntryId;
  final String pvNo;
  final String type; // RECEIPT | PAYMENT
  final String? partyType;
  final int? partyId;
  final double amount;
  final String? voucherDate;
  final String? remarks;
  final int debitAccountId;
  final int creditAccountId;
  final String? debitAccountLabel;
  final String? creditAccountLabel;

  const PaymentVoucherRow({
    required this.id,
    required this.journalEntryId,
    required this.pvNo,
    required this.type,
    this.partyType,
    this.partyId,
    required this.amount,
    this.voucherDate,
    this.remarks,
    required this.debitAccountId,
    required this.creditAccountId,
    this.debitAccountLabel,
    this.creditAccountLabel,
  });

  factory PaymentVoucherRow.fromJson(Map json) {
    final debitAccount = json['debit_account'] is Map ? json['debit_account'] as Map : null;
    final creditAccount = json['credit_account'] is Map ? json['credit_account'] as Map : null;
    return PaymentVoucherRow(
      id: toInt(json['id']),
      journalEntryId: toInt(json['journal_entry_id']),
      pvNo: (json['pv_no'] ?? '').toString(),
      type: (json['type'] ?? 'RECEIPT').toString(),
      partyType: toStringOrNull(json['party_type']),
      partyId: json['party_id'] == null ? null : toInt(json['party_id']),
      amount: toDoubleValue(json['amount']),
      voucherDate: toStringOrNull(json['voucher_date']),
      remarks: toStringOrNull(json['remarks']),
      debitAccountId: toInt(json['debit_account_id']),
      creditAccountId: toInt(json['credit_account_id']),
      debitAccountLabel: debitAccount == null ? null : '${debitAccount['code']} — ${debitAccount['name']}',
      creditAccountLabel: creditAccount == null ? null : '${creditAccount['code']} — ${creditAccount['name']}',
    );
  }
}

class PartyOption {
  final int id;
  final String name;
  const PartyOption({required this.id, required this.name});
}
