import '../../../core/network/http_client.dart';

/// Ported from erp/desktop's HrmDashboard.tsx.
class HrAnalyticsService {
  final ApiClient _client;
  HrAnalyticsService(this._client);

  Future<Map<String, dynamic>> getDashboardAnalytics({
    required DateTime startDate,
    required DateTime endDate,
    int? departmentId,
    int? shiftId,
  }) async {
    String fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final params = {
      'start_date': fmt(startDate),
      'end_date': fmt(endDate),
      if (departmentId != null) 'department_id': departmentId.toString(),
      if (shiftId != null) 'shift_id': shiftId.toString(),
    };
    final query = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    final data = await _client.get('hrm/dashboard-analytics?$query', isV8: false);
    return (data as Map?)?.cast<String, dynamic>() ?? {};
  }

  Future<Map<String, List<dynamic>>> getFilterOptions() async {
    final result = await _client.batch([
      BatchRequest(id: '1', method: 'GET', url: 'departments'),
      BatchRequest(id: '2', method: 'GET', url: 'employee_shifts?\$select=id,name&\$filter=is_active eq true&\$top=200'),
    ]);
    return {
      'departments': unwrapList(unwrapBatchBody(result, '1')),
      'shifts': unwrapList(unwrapBatchBody(result, '2')),
    };
  }
}
