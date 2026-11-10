import '../../../core/network/http_client.dart';
import '../../../core/storage/app_storage.dart';
import '../../../shared/ui/entity_crud.dart' show batchLoad;
import '../models/accounting_models.dart';
import 'accounting_service.dart';

/// Ported from erp/desktop's ledger/AccountLedger.tsx,
/// ledger-accounts/LedgerAccounts.tsx and settings/AccountSettings.tsx —
/// the calls those three pages need that AccountingService doesn't already
/// cover. Writes that AccountingService already has (accounts /
/// bank_accounts create/update/delete) go through it instead.
class AccountingLedgerService {
  final ApiClient _client;
  final AccountingService _accounting;
  AccountingLedgerService([ApiClient? client])
      : _client = client ?? ApiClient(),
        _accounting = AccountingService(client ?? ApiClient());

  // ── Ledger ───────────────────────────────────────────────────────────

  /// The custom /api/accounting/journal-entry-lines route caps every page at
  /// 500 rows (MAX_TAKE in cloud's accounting.service.ts) — desktop asks for
  /// `$top=10000` in one go and silently gets the newest 500. This pages
  /// through with `$skip` until the route's own `total` is reached instead,
  /// stopping at desktop's intended 10000-row ceiling.
  static const _pageSize = 500;
  static const lineCap = 10000;

  Future<({List<LedgerLine> lines, bool truncated})> loadLines({int? accountId}) async {
    final filter = accountId == null ? '' : '&\$filter=account_id eq $accountId';
    final lines = <LedgerLine>[];
    var total = 0;
    var skip = 0;
    do {
      final res = await _client.get(
        'accounting/journal-entry-lines?\$select=id,debit,credit,remarks,account_id'
        '&\$expand=account(\$select=id,code,name),journal_entry(\$select=je_no,entry_date,reference_type)'
        '&\$orderby=id desc&\$top=$_pageSize&\$skip=$skip$filter',
        isV8: false,
      );
      final rows = (res is Map && res['data'] is List) ? res['data'] as List : const [];
      total = res is Map ? toInt(res['total']) : rows.length;
      lines.addAll(rows.whereType<Map>().map(LedgerLine.fromJson));
      skip += _pageSize;
      if (rows.isEmpty) break;
    } while (skip < total && skip < lineCap);
    return (lines: lines, truncated: total > lines.length);
  }

  /// Postable accounts for the ledger's account filter — same query as
  /// desktop's (non-group, active, with type + opening_balance for the
  /// running balance).
  Future<List<AccountRow>> loadPostableAccounts() => _accounting.loadPostableAccounts();

  // ── Ledger accounts (bank_accounts) ──────────────────────────────────

  /// Every bank/cash register, active or not — the list itself filters by
  /// status client-side (desktop's All / Inactive / Active segment), and the
  /// next sequential ledger code needs inactive rows too: accounts.code is
  /// unique per workplace, so skipping an inactive register's code would
  /// hand the same code out twice.
  Future<List<LedgerAccount>> loadLedgerAccounts() async {
    final res = await _client.get('bank_accounts?\$expand=account,parent_bank_account&\$orderby=id asc&\$top=2000');
    return unwrapList(res).whereType<Map>().map(LedgerAccount.fromJson).toList();
  }

  /// A ledger account always needs its own chart of account entry first
  /// (bank_accounts.account_id is required + unique) — created together,
  /// sequentially, since the second write needs the first one's id.
  Future<void> createLedgerAccount({required String code, required Map<String, dynamic> bankBody, required double openingBalance}) async {
    final accountId = await _accounting.createAccount({
      'parent_id': null,
      'code': code,
      'name': bankBody['name'],
      'type': 'ASSET',
      'is_group': false,
      'opening_balance': openingBalance,
      'is_active': bankBody['is_active'],
    });
    await _accounting.createBankAccount({
      ...bankBody,
      'account_id': accountId,
      'opening_balance': openingBalance,
      'current_balance': openingBalance,
    });
  }

  /// Edit only touches the bank_accounts fields — the backing ledger
  /// account's code/type stay owned by the chart of accounts once created.
  Future<void> updateLedgerAccount(int id, Map<String, dynamic> bankBody) => _accounting.updateBankAccount(id, bankBody);

  Future<void> deleteLedgerAccount(int id) => _accounting.deleteBankAccount(id);

  /// Best-effort clean-up of the register's own backing accounts row
  /// (bank_accounts.account is onDelete: Restrict, so this never happens by
  /// DB cascade). Fails while that account still has posted journal lines,
  /// which is the point: that history stays protected.
  Future<void> deleteBackingAccount(int accountId) => _accounting.deleteAccount(accountId);

  // ── Accounting settings ──────────────────────────────────────────────

  /// Non-group, active accounts for the default-account pickers, minus the
  /// ones backing a bank/cash register (those already have their own list
  /// and would only show up here as confusing duplicates) — plus the
  /// workplace's single account_settings row, in one batch.
  Future<({List<SettingsAccountOption> accounts, Map<String, dynamic>? settings, int? workplaceId})> loadSettings() async {
    final workplaceId = await _workplaceId();
    final d = await batchLoad(_client, {
      'accounts': 'accounts?\$select=id,code,name&\$expand=bank_account(\$select=id)&\$filter=is_group eq false and is_active eq true&\$top=1000',
      if (workplaceId != null) 'settings': 'account_settings?\$filter=workplace_id eq $workplaceId',
    });
    final accounts = (d['accounts'] ?? const <Map<String, dynamic>>[])
        .where((a) => a['bank_account'] == null)
        .map((a) => SettingsAccountOption(id: toInt(a['id']), code: (a['code'] ?? '').toString(), name: (a['name'] ?? '').toString()))
        .toList();
    final rows = d['settings'] ?? const <Map<String, dynamic>>[];
    return (accounts: accounts, settings: rows.isEmpty ? null : {...rows.first}, workplaceId: workplaceId);
  }

  /// Nothing creates the account_settings row on workplace setup (unlike
  /// hr_settings), so the settings page lazily creates it on first load —
  /// same as desktop.
  Future<Map<String, dynamic>?> createSettings(int workplaceId) async {
    final res = await _client.post('account_settings', {'workplace_id': workplaceId}, isV8: true);
    final row = res is Map ? (res['value'] ?? res) : null;
    return row is Map ? row.cast<String, dynamic>() : null;
  }

  Future<void> patchSettings(Object id, Map<String, dynamic> partial) => _client.put('account_settings', id, partial);

  Future<int?> _workplaceId() async {
    final user = await AppStorage.getUser();
    final workplace = (user?['selectedWorkplace'] ?? user?['workplace']);
    final id = workplace is Map ? toInt(workplace['id']) : 0;
    return id > 0 ? id : null;
  }
}

/// One journal_entry_lines row with its header + account flattened on —
/// mirrors desktop AccountLedger.tsx's `LineRow`. `createdAt`/`createdBy`
/// come from the route's audit-log enrichment (journal_entries has no
/// created_by column), so older entries can legitimately have neither.
class LedgerLine {
  final int id;
  final int accountId;
  final double debit;
  final double credit;
  final String? remarks;
  final String? accountCode;
  final String? accountName;
  final String? jeNo;
  final String? entryDate;
  final String? referenceType;
  final String? createdAt;
  final String? createdBy;

  const LedgerLine({
    required this.id,
    required this.accountId,
    required this.debit,
    required this.credit,
    this.remarks,
    this.accountCode,
    this.accountName,
    this.jeNo,
    this.entryDate,
    this.referenceType,
    this.createdAt,
    this.createdBy,
  });

  bool get isDebit => debit > 0;
  String? get accountLabel => accountCode == null && accountName == null ? null : '${accountCode ?? ''} — ${accountName ?? ''}';

  factory LedgerLine.fromJson(Map json) {
    final account = json['account'] is Map ? json['account'] as Map : null;
    final header = json['journal_entry'] is Map ? json['journal_entry'] as Map : null;
    return LedgerLine(
      id: toInt(json['id']),
      accountId: toInt(json['account_id'] ?? account?['id']),
      debit: toDoubleValue(json['debit']),
      credit: toDoubleValue(json['credit']),
      remarks: toStringOrNull(json['remarks']),
      accountCode: toStringOrNull(account?['code']),
      accountName: toStringOrNull(account?['name']),
      jeNo: toStringOrNull(header?['je_no']),
      entryDate: toStringOrNull(header?['entry_date']),
      referenceType: toStringOrNull(header?['reference_type']),
      createdAt: toStringOrNull(header?['created_at']),
      createdBy: toStringOrNull(header?['created_by']),
    );
  }
}

/// A bank_accounts row as the ledger accounts list needs it — unlike
/// [BankAccountInfo] it carries the register's own `name`, its backing
/// ledger account and its parent register.
class LedgerAccount {
  final int id;
  final String name;
  final String type; // BANK | CASH
  final String? accountNo;
  final String? bankName;
  final bool isMain;
  final int? parentBankAccountId;
  final String? parentName;
  final double openingBalance;
  final double currentBalance;
  final bool isActive;
  final int? accountId;
  final String? accountCode;
  final String? accountName;

  const LedgerAccount({
    required this.id,
    required this.name,
    required this.type,
    this.accountNo,
    this.bankName,
    required this.isMain,
    this.parentBankAccountId,
    this.parentName,
    required this.openingBalance,
    required this.currentBalance,
    required this.isActive,
    this.accountId,
    this.accountCode,
    this.accountName,
  });

  /// `code — name` of the register, as desktop's parent picker shows it.
  String get pickLabel => '${accountCode ?? ''} — $name';

  factory LedgerAccount.fromJson(Map json) {
    final account = json['account'] is Map ? json['account'] as Map : null;
    final parent = json['parent_bank_account'] is Map ? json['parent_bank_account'] as Map : null;
    final accountId = toInt(json['account_id'] ?? account?['id']);
    return LedgerAccount(
      id: toInt(json['id']),
      name: (json['name'] ?? '').toString(),
      type: (json['type'] ?? 'BANK').toString(),
      accountNo: toStringOrNull(json['account_no']),
      bankName: toStringOrNull(json['bank_name']),
      isMain: json['is_main'] != false,
      parentBankAccountId: json['parent_bank_account_id'] == null ? null : toInt(json['parent_bank_account_id']),
      parentName: toStringOrNull(parent?['name']),
      openingBalance: toDoubleValue(json['opening_balance']),
      currentBalance: toDoubleValue(json['current_balance']),
      isActive: json['is_active'] != false,
      accountId: accountId > 0 ? accountId : null,
      accountCode: toStringOrNull(account?['code']),
      accountName: toStringOrNull(account?['name']),
    );
  }
}

class SettingsAccountOption {
  final int id;
  final String code;
  final String name;
  const SettingsAccountOption({required this.id, required this.code, required this.name});

  String get label => '$code — $name';
}
