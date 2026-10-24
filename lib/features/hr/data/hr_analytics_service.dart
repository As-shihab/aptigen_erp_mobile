import '../../../core/network/http_client.dart';

/// Filters for GET /api/hrm/dashboard-analytics — mirrors desktop
/// HrmAnalytics.tsx's filter drawer.
class HrAnalyticsFilters {
  final DateTime start;
  final DateTime end;
  final int? shiftId;
  final int? departmentId;
  final int? designationId;
  final int? employeeTypeId;
  final int? employeeSectionId;
  final String gender;

  const HrAnalyticsFilters({
    required this.start,
    required this.end,
    this.shiftId,
    this.departmentId,
    this.designationId,
    this.employeeTypeId,
    this.employeeSectionId,
    this.gender = '',
  });

  factory HrAnalyticsFilters.defaults({int? shiftId}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return HrAnalyticsFilters(start: today.subtract(const Duration(days: 30)), end: today, shiftId: shiftId);
  }

  static const _keep = Object();

  HrAnalyticsFilters copyWith({
    DateTime? start,
    DateTime? end,
    Object? shiftId = _keep,
    Object? departmentId = _keep,
    Object? designationId = _keep,
    Object? employeeTypeId = _keep,
    Object? employeeSectionId = _keep,
    String? gender,
  }) =>
      HrAnalyticsFilters(
        start: start ?? this.start,
        end: end ?? this.end,
        shiftId: identical(shiftId, _keep) ? this.shiftId : shiftId as int?,
        departmentId: identical(departmentId, _keep) ? this.departmentId : departmentId as int?,
        designationId: identical(designationId, _keep) ? this.designationId : designationId as int?,
        employeeTypeId: identical(employeeTypeId, _keep) ? this.employeeTypeId : employeeTypeId as int?,
        employeeSectionId: identical(employeeSectionId, _keep) ? this.employeeSectionId : employeeSectionId as int?,
        gender: gender ?? this.gender,
      );
}

class HrAnalyticsService {
  final ApiClient _client;
  HrAnalyticsService(this._client);

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<Map<String, dynamic>> getDashboardAnalytics(HrAnalyticsFilters f, {bool hasShift = true}) async {
    final params = <String, String>{
      'start_date': _ymd(f.start),
      'end_date': _ymd(f.end),
      if (f.departmentId != null) 'department_id': '${f.departmentId}',
      if (hasShift && f.shiftId != null) 'shift_id': '${f.shiftId}',
      if (f.designationId != null) 'designation_id': '${f.designationId}',
      if (f.employeeTypeId != null) 'employee_type_id': '${f.employeeTypeId}',
      if (f.employeeSectionId != null) 'employee_section_id': '${f.employeeSectionId}',
      if (f.gender.isNotEmpty) 'gender': f.gender,
    };
    final query = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    final data = await _client.get('hrm/dashboard-analytics?$query', isV8: false);
    return (data as Map?)?.cast<String, dynamic>() ?? {};
  }

  /// Reference lists + HR settings in one batch round-trip.
  Future<Map<String, List<Map<String, dynamic>>>> getFilterOptions() async {
    const q = '\$select=id,name&\$filter=is_active eq true&\$top=200';
    final result = await _client.batch([
      BatchRequest(id: '1', method: 'GET', url: 'departments?\$select=id,name&\$top=500'),
      BatchRequest(id: '2', method: 'GET', url: 'employee_shifts?$q'),
      BatchRequest(id: '3', method: 'GET', url: 'designations?$q'),
      BatchRequest(id: '4', method: 'GET', url: 'employee_types?$q'),
      BatchRequest(id: '5', method: 'GET', url: 'employee_sections?$q'),
      BatchRequest(id: '6', method: 'GET', url: 'hr_settings?\$top=1'),
    ]);
    List<Map<String, dynamic>> rows(String id) =>
        unwrapList(unwrapBatchBody(result, id)).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    return {
      'departments': rows('1'),
      'shifts': rows('2'),
      'designations': rows('3'),
      'employeeTypes': rows('4'),
      'sections': rows('5'),
      'settings': rows('6'),
    };
  }
}
