import '../../../core/network/http_client.dart';

/// Ported from erp/desktop's EmployeeDashboard.tsx + tabs/*.tsx.
class EmployeeDashboardService {
  final ApiClient _client;
  EmployeeDashboardService(this._client);

  /// GET /api/hrm/my-dashboard — resolves the signed-in user's own
  /// employee record + KPIs + leave balances server-side.
  Future<Map<String, dynamic>?> getMyDashboard() async {
    final data = await _client.get('hrm/my-dashboard', isV8: false);
    return (data as Map?)?.cast<String, dynamic>();
  }

  Future<List<dynamic>> getAttendance(int employeeId) async {
    final data = await _client.get(
      'attendance_logs?\$filter=employee_id eq $employeeId&\$select=id,attendance_date,check_in_time,check_out_time,has_late,has_overtime,overtime_minutes,status&\$orderby=attendance_date desc&\$top=100',
    );
    return unwrapList(data);
  }

  Future<Map<String, List<dynamic>>> getLeaveWorkspace(int employeeId) async {
    final year = DateTime.now().year;
    final result = await _client.batch([
      BatchRequest(
        id: '1',
        method: 'GET',
        url: 'leave_requests?\$filter=employee_id eq $employeeId&\$expand=leave_type(\$select=id,name)&\$orderby=id desc&\$top=200',
      ),
      BatchRequest(
        id: '2',
        method: 'GET',
        url: 'leave_balances?\$filter=employee_id eq $employeeId and year eq $year&\$expand=leave_type(\$select=id,name)&\$top=50',
      ),
      BatchRequest(
        id: '3',
        method: 'GET',
        url: 'leave_types?\$select=id,name&\$filter=is_active eq true&\$top=200',
      ),
    ]);
    return {
      'requests': unwrapList(unwrapBatchBody(result, '1')),
      'balances': unwrapList(unwrapBatchBody(result, '2')),
      'leaveTypes': unwrapList(unwrapBatchBody(result, '3')),
    };
  }

  Future<void> createLeaveRequest({
    required int employeeId,
    required int leaveTypeId,
    required DateTime startDate,
    required DateTime endDate,
    required int daysCount,
    String? reason,
  }) async {
    await _client.post('leave_requests', {
      'employee_id': employeeId,
      'leave_type_id': leaveTypeId,
      'start_date': startDate.toUtc().toIso8601String(),
      'end_date': endDate.toUtc().toIso8601String(),
      'days_count': daysCount,
      'reason': reason?.trim().isEmpty == true ? null : reason,
      'status': 'PENDING',
      'current_serial': 1,
    });
  }

  Future<void> cancelLeaveRequest(int id) async {
    await _client.put('leave_requests', id, {'status': 'CANCELLED'});
  }

  Future<List<dynamic>> getRoster(DateTime start, DateTime end) async {
    final s = '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final e = '${end.year.toString().padLeft(4, '0')}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
    final data = await _client.get('hrm/my-roster?start_date=$s&end_date=$e', isV8: false);
    return data is List ? data : const [];
  }

  Future<List<dynamic>> getPayrolls(int employeeId) async {
    final data = await _client.get('payrolls?\$filter=employee_id eq $employeeId&\$orderby=start_date desc&\$top=100');
    return unwrapList(data);
  }

  Future<List<dynamic>> getAssets(int employeeId) async {
    final data = await _client.get(
      'employee_has_assets?\$filter=employee_id eq $employeeId&\$expand=asset(\$expand=asset_group)&\$orderby=id desc&\$top=200',
    );
    return unwrapList(data);
  }

  Future<List<dynamic>> getNotices({required int employeeId, int? departmentId}) async {
    final data = await _client.get('hr_notices?\$filter=is_active eq true&\$orderby=created_at desc&\$top=200');
    final rows = unwrapList(data);
    return rows.where((row) {
      final map = (row as Map);
      final targetType = (map['target_type'] ?? '').toString();
      if (targetType == 'ALL') return true;
      if (targetType == 'DEPARTMENTS') {
        final ids = (map['department_ids'] as List?)?.map((e) => int.tryParse(e.toString())).toList() ?? [];
        return departmentId != null && ids.contains(departmentId);
      }
      if (targetType == 'EMPLOYEES') {
        final ids = (map['employee_ids'] as List?)?.map((e) => int.tryParse(e.toString())).toList() ?? [];
        return ids.contains(employeeId);
      }
      return false;
    }).toList();
  }

  /// "Requests awaiting my approval" — mirrors EmployeeRequestTab's
  /// current-serial + approver-chain resolution.
  Future<List<dynamic>> getPendingApprovals({required int employeeId, int? designationId}) async {
    final result = await _client.batch([
      BatchRequest(
        id: '1',
        method: 'GET',
        url: "leave_requests?\$filter=status eq 'PENDING'&\$expand=employee(\$select=id,first_name,last_name,employee_no),leave_type(\$select=id,name)&\$orderby=id asc&\$top=200",
      ),
      BatchRequest(
        id: '2',
        method: 'GET',
        url: 'leave_type_has_middleman?\$select=leave_type_id,serial,approver_emp_id,approver_des_id&\$top=500',
      ),
    ]);
    final requests = unwrapList(unwrapBatchBody(result, '1'));
    final chain = unwrapList(unwrapBatchBody(result, '2')).cast<Map>();

    return requests.where((row) {
      final map = row as Map;
      final reqEmployeeId = int.tryParse((map['employee_id'] ?? '').toString());
      if (reqEmployeeId == employeeId) return false;
      final leaveTypeId = map['leave_type_id'];
      final serial = map['current_serial'];
      final step = chain.cast<Map?>().firstWhere(
            (m) => m != null && m['leave_type_id'] == leaveTypeId && m['serial'] == serial,
            orElse: () => null,
          );
      if (step == null) return false;
      final approverEmpId = int.tryParse((step['approver_emp_id'] ?? '').toString());
      final approverDesId = int.tryParse((step['approver_des_id'] ?? '').toString());
      return approverEmpId == employeeId || (designationId != null && approverDesId == designationId);
    }).toList();
  }

  Future<void> actOnLeaveRequest(int id, {required String status, String? notes}) async {
    await _client.put('leave_requests', id, {
      'status': status,
      'notes': notes?.trim().isEmpty == true ? null : notes,
    });
  }
}
