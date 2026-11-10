import '../../../core/network/http_client.dart';
import '../models/accounting_models.dart';

/// One journal_entry_lines row as the reports need it — the line's amounts
/// plus its account's type and its header's entry date, so Profit & loss,
/// Balance sheet and Analytics can all group/filter client-side the way
/// erp/desktop's ProfitLoss.tsx / BalanceSheet.tsx / AccountingAnalytics.tsx
/// do (there's no backend aggregation endpoint for any of them).
class ReportLine {
  final int accountId;
  final double debit;
  final double credit;
  final String? accountCode;
  final String? accountName;
  final String? accountType;
  final DateTime? entryDate;

  const ReportLine({
    required this.accountId,
    required this.debit,
    required this.credit,
    this.accountCode,
    this.accountName,
    this.accountType,
    this.entryDate,
  });

  factory ReportLine.fromJson(Map json) {
    final account = json['account'] is Map ? json['account'] as Map : null;
    final entry = json['journal_entry'] is Map ? json['journal_entry'] as Map : null;
    return ReportLine(
      accountId: toInt(json['account_id']),
      debit: toDoubleValue(json['debit']),
      credit: toDoubleValue(json['credit']),
      accountCode: toStringOrNull(account?['code']),
      accountName: toStringOrNull(account?['name']),
      accountType: toStringOrNull(account?['type']),
      // Local calendar day, same as desktop's moment(entry_date).
      entryDate: DateTime.tryParse(entry?['entry_date']?.toString() ?? '')?.toLocal(),
    );
  }
}

class AccountingReportsService {
  final ApiClient _client;
  AccountingReportsService(this._client);

  // The custom /api/accounting/journal-entry-lines route clamps `$top` to 500
  // (cloud/src/module/accounting/accounting.service.ts MAX_TAKE), so desktop's
  // single `$top=10000`/`$top=20000` fetch silently gets only the newest 500
  // lines. Mobile pages through with `$skip` instead, using the route's own
  // `total`, up to the same 20000-row ceiling desktop's Balance sheet uses.
  static const _pageSize = 500;
  static const _maxRows = 20000;

  /// Every journal_entry_lines row of the workplace (no date filter — the
  /// pages filter by entry date client-side, same as desktop). [withDetails]
  /// adds the account's code/name/type and the header's entry_date; the
  /// Balance sheet only needs account_id/debit/credit.
  Future<List<ReportLine>> loadAllLines({bool withDetails = true}) async {
    final expand = withDetails ? '&\$expand=account(\$select=code,name,type),journal_entry(\$select=entry_date)' : '';
    String page(int skip) =>
        'accounting/journal-entry-lines?\$select=account_id,debit,credit$expand&\$orderby=id asc&\$top=$_pageSize&\$skip=$skip';

    List<Map> rowsOf(dynamic res) => (res is Map && res['data'] is List) ? (res['data'] as List).cast<Map>() : const [];

    final first = await _client.get(page(0), isV8: false);
    final rows = [...rowsOf(first)];
    final total = first is Map ? toInt(first['total']) : rows.length;
    final target = total > _maxRows ? _maxRows : total;

    // Remaining pages are independent — fetched a few at a time in parallel.
    // This is a custom /api route, so it can't ride a /v1/$batch call.
    final skips = [for (var s = _pageSize; s < target; s += _pageSize) s];
    for (var i = 0; i < skips.length; i += 4) {
      final chunk = skips.skip(i).take(4);
      final pages = await Future.wait(chunk.map((s) => _client.get(page(s), isV8: false)));
      for (final res in pages) {
        rows.addAll(rowsOf(res));
      }
    }
    return rows.map(ReportLine.fromJson).toList();
  }
}
