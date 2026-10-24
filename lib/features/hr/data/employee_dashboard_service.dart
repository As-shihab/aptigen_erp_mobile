import '../../../core/network/http_client.dart';
import '../../../core/storage/app_storage.dart';

/// Ported from erp/desktop's EmployeeDashboard.tsx + tabs/*.tsx.
/// Endpoints are Prisma model names; the backend scopes workplace_id itself.
class EmployeeDashboardService {
  final ApiClient _client;
  EmployeeDashboardService(this._client);

  static List<Map<String, dynamic>> _rows(dynamic body) =>
      unwrapList(body).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// GET /api/hrm/my-dashboard — resolves the signed-in user's own
  /// employee record + KPIs + leave balances server-side.
  Future<Map<String, dynamic>?> getMyDashboard() async {
    final data = await _client.get('hrm/my-dashboard', isV8: false);
    return (data as Map?)?.cast<String, dynamic>();
  }

  /// POST /api/hrm/punch — single toggle endpoint, mirrors the fingerprint
  /// device's one-row-per-day open/close semantics: no open row today ->
  /// check-in (creates), open row -> check-out (closes it).
  /// Returns {action: 'check-in'|'check-out', checkInTime, checkOutTime}.
  Future<Map<String, dynamic>> punchAttendance() async {
    final data = await _client.post('hrm/punch', {}, isV8: false);
    return (data as Map?)?.cast<String, dynamic>() ?? {};
  }

  // ── Overview widgets (desktop profile tab, row 2) ──────────────────────

  /// One batch for the overview cards: late vs on-time logs, last 6
  /// payrolls, currently assigned devices and mobile login requests.
  Future<Map<String, List<Map<String, dynamic>>>> getOverview(int employeeId) async {
    final user = await AppStorage.getUser();
    final userId = int.tryParse('${user?['id'] ?? ''}');
    final res = await _client.batch([
      BatchRequest(id: '1', method: 'GET', url: 'attendance_logs?\$filter=employee_id eq $employeeId&\$select=id,has_late&\$top=200'),
      BatchRequest(
        id: '2',
        method: 'GET',
        url: 'payrolls?\$filter=employee_id eq $employeeId&\$select=id,start_date,net_salary,status&\$orderby=start_date desc&\$top=6',
      ),
      BatchRequest(
        id: '3',
        method: 'GET',
        url: 'employee_has_assets?\$filter=employee_id eq $employeeId and return_date eq null&\$expand=asset(\$expand=asset_group)&\$orderby=id desc&\$top=3',
      ),
      if (userId != null && userId > 0)
        BatchRequest(id: '4', method: 'GET', url: 'device_requests?\$filter=user_id eq $userId&\$orderby=id desc&\$top=3'),
    ]);
    return {
      'logs': _rows(unwrapBatchBody(res, '1')),
      'payrolls': _rows(unwrapBatchBody(res, '2')),
      'devices': _rows(unwrapBatchBody(res, '3')),
      'deviceRequests': _rows(unwrapBatchBody(res, '4')),
    };
  }

  // ── Attendance ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAttendance(int employeeId) async {
    final data = await _client.get(
      'attendance_logs?\$filter=employee_id eq $employeeId&\$select=id,attendance_date,check_in_time,check_out_time,has_late,has_overtime,overtime_minutes,status&\$orderby=attendance_date desc&\$top=100',
    );
    return _rows(data);
  }

  // ── Leave ──────────────────────────────────────────────────────────────

  Future<Map<String, List<Map<String, dynamic>>>> getLeaveWorkspace(int employeeId) async {
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
        url: 'leave_types?\$select=id,name,requires_document,max_days_per_year&\$filter=is_active eq true&\$top=200',
      ),
    ]);
    return {
      'requests': _rows(unwrapBatchBody(result, '1')),
      'balances': _rows(unwrapBatchBody(result, '2')),
      'leaveTypes': _rows(unwrapBatchBody(result, '3')),
    };
  }

  /// Approver chain for a leave type, in serial order.
  Future<List<Map<String, dynamic>>> getApproverChain(int leaveTypeId) async {
    final data = await _client.get(
      'leave_type_has_middleman?\$filter=leave_type_id eq $leaveTypeId&\$orderby=serial asc&\$select=id,serial,label,is_required&\$expand=approver_emp(\$select=id,first_name,last_name),approver_des(\$select=id,name)',
    );
    return _rows(data);
  }

  /// Uploads one supporting document to the media library (private,
  /// "Leave Documents" category) and returns {url, name}.
  Future<Map<String, String>> uploadLeaveDocument(List<int> bytes, String filename) async {
    final res = await _client.uploadFile(
      'media/upload',
      bytes: bytes,
      filename: filename,
      fields: {'category': 'Leave Documents', 'visibility': 'private'},
      useSharp: false,
    );
    final saved = res is Map && res['savedMedia'] is List && (res['savedMedia'] as List).isNotEmpty ? (res['savedMedia'] as List).first as Map : const {};
    final url = '${saved['fileUrl'] ?? saved['file_url'] ?? ''}';
    if (url.isEmpty) throw ApiException(500, 'Upload failed');
    return {'url': url, 'name': filename};
  }

  /// Creates (or, with [editingId], updates) a leave request. Mirrors
  /// desktop's save(): start/end from the picked dates, days = picked count,
  /// and a snapshot of the approver chain as `steps`.
  Future<void> saveLeaveRequest({
    int? editingId,
    required int employeeId,
    required int leaveTypeId,
    required List<DateTime> dates,
    String? reason,
    List<Map<String, String>> documents = const [],
    List<Map<String, dynamic>> approvers = const [],
  }) async {
    final sorted = [...dates]..sort();
    final body = <String, dynamic>{
      'leave_type_id': leaveTypeId,
      'start_date': DateTime.utc(sorted.first.year, sorted.first.month, sorted.first.day).toIso8601String(),
      'end_date': DateTime.utc(sorted.last.year, sorted.last.month, sorted.last.day).toIso8601String(),
      'days_count': sorted.length,
      'reason': (reason ?? '').trim().isEmpty ? null : reason!.trim(),
      'document_url': documents.isEmpty ? null : documents.first['url'],
      'document_urls': documents,
      'steps': [
        for (final a in approvers)
          {
            'serial': a['serial'],
            'label': a['label'],
            'is_required': a['is_required'] ?? true,
            'approver_emp_id': (a['approver_emp'] as Map?)?['id'],
            'approver_des_id': (a['approver_des'] as Map?)?['id'],
            'status': 'PENDING',
          },
      ],
    };
    if (editingId != null) {
      await _client.put('leave_requests', editingId, body);
    } else {
      await _client.post('leave_requests', {...body, 'employee_id': employeeId, 'status': 'PENDING', 'current_serial': 1}, isV8: true);
    }
  }

  Future<void> cancelLeaveRequest(int id) async {
    await _client.put('leave_requests', id, {'status': 'CANCELLED'});
  }

  Future<void> deleteLeaveRequest(int id) async {
    await _client.delete('leave_requests', id);
  }

  // ── Calendar ───────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getRoster(DateTime start, DateTime end) async {
    final data = await _client.get('hrm/my-roster?start_date=${_ymd(start)}&end_date=${_ymd(end)}', isV8: false);
    return data is List ? data.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList() : const [];
  }

  /// Workplace calendar events, event types and HR settings in one batch.
  Future<Map<String, List<Map<String, dynamic>>>> getCalendarRefs() async {
    final res = await _client.batch([
      BatchRequest(id: '1', method: 'GET', url: 'calendar_events?\$select=id,title,date,end_date,type,description,event_type_id&\$top=2000'),
      BatchRequest(id: '2', method: 'GET', url: 'event_types?\$select=id,name,is_off&\$filter=is_active eq true&\$top=200'),
      BatchRequest(id: '3', method: 'GET', url: 'hr_settings?\$top=1'),
    ]);
    return {
      'events': _rows(unwrapBatchBody(res, '1')),
      'eventTypes': _rows(unwrapBatchBody(res, '2')),
      'settings': _rows(unwrapBatchBody(res, '3')),
    };
  }

  // ── Payroll / assets / notices ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPayrolls(int employeeId) async {
    final data = await _client.get('payrolls?\$filter=employee_id eq $employeeId&\$orderby=start_date desc&\$top=100');
    return _rows(data);
  }

  Future<List<Map<String, dynamic>>> getAssets(int employeeId) async {
    final data = await _client.get(
      'employee_has_assets?\$filter=employee_id eq $employeeId&\$expand=asset(\$expand=asset_group)&\$orderby=id desc&\$top=200',
    );
    return _rows(data);
  }

  Future<List<Map<String, dynamic>>> getNotices({required int employeeId, int? departmentId}) async {
    final data = await _client.get('hr_notices?\$filter=is_active eq true&\$orderby=created_at desc&\$top=200');
    List<int> ids(dynamic v) => (v as List?)?.map((e) => int.tryParse('$e')).whereType<int>().toList() ?? const [];
    return _rows(data).where((n) {
      final target = '${n['target_type'] ?? ''}';
      if (target == 'ALL') return true;
      if (target == 'DEPARTMENTS') return departmentId != null && ids(n['department_ids']).contains(departmentId);
      if (target == 'EMPLOYEES') return ids(n['employee_ids']).contains(employeeId);
      return false;
    }).toList();
  }

  // ── Approvals (employee request tab) ───────────────────────────────────

  /// "Requests awaiting my approval" — mirrors EmployeeRequestTab's
  /// current-serial + approver-chain resolution. Returns the matching
  /// requests and the full chain (needed when acting).
  Future<({List<Map<String, dynamic>> pending, List<Map<String, dynamic>> chain})> getPendingApprovals({
    required int employeeId,
    int? designationId,
  }) async {
    final result = await _client.batch([
      BatchRequest(
        id: '1',
        method: 'GET',
        url: "leave_requests?\$filter=status eq 'PENDING'&\$expand=employee(\$select=id,first_name,last_name,employee_no),leave_type(\$select=id,name)&\$orderby=id asc&\$top=200",
      ),
      BatchRequest(
        id: '2',
        method: 'GET',
        url: 'leave_type_has_middleman?\$select=leave_type_id,serial,label,approver_emp_id,approver_des_id&\$top=500',
      ),
    ]);
    final requests = _rows(unwrapBatchBody(result, '1'));
    final chain = _rows(unwrapBatchBody(result, '2'));
    final pending = requests.where((r) {
      if (int.tryParse('${r['employee_id']}') == employeeId) return false;
      final step = stepFor(chain, r['leave_type_id'], r['current_serial']);
      if (step == null) return false;
      final empId = int.tryParse('${step['approver_emp_id'] ?? ''}');
      final desId = int.tryParse('${step['approver_des_id'] ?? ''}');
      return empId == employeeId || (designationId != null && desId == designationId);
    }).toList();
    return (pending: pending, chain: chain);
  }

  static Map<String, dynamic>? stepFor(List<Map<String, dynamic>> chain, dynamic leaveTypeId, dynamic serial) {
    for (final m in chain) {
      if ('${m['leave_type_id']}' == '$leaveTypeId' && '${m['serial']}' == '$serial') return m;
    }
    return null;
  }

  /// Logs the decision against the approver's step, then rejects, advances
  /// to the next step, or finally approves — same as desktop's act().
  Future<void> actOnLeaveRequest({
    required Map<String, dynamic> row,
    required List<Map<String, dynamic>> chain,
    required int approverId,
    required String status,
    String? notes,
  }) async {
    final id = int.parse('${row['id']}');
    final serial = int.tryParse('${row['current_serial']}') ?? 1;
    final noteText = (notes ?? '').trim().isEmpty ? null : notes!.trim();
    final step = stepFor(chain, row['leave_type_id'], serial);

    await _client.post('leave_request_approvals', {
      'leave_request_id': id,
      'serial': serial,
      'label': step?['label'] ?? 'Step $serial',
      'approver_id': approverId,
      'status': status,
      'notes': noteText,
      'acted_at': DateTime.now().toUtc().toIso8601String(),
    }, isV8: true);

    if (status == 'REJECTED') {
      await _client.put('leave_requests', id, {'status': 'REJECTED', 'rejection_reason': noteText});
    } else if (stepFor(chain, row['leave_type_id'], serial + 1) != null) {
      await _client.put('leave_requests', id, {'current_serial': serial + 1});
    } else {
      await _client.put('leave_requests', id, {'status': 'APPROVED'});
    }
  }
}
