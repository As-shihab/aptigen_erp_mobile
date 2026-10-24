import '../../../core/network/http_client.dart';
import '../../../core/storage/app_storage.dart';

// Purchase approval chains — mobile port of desktop's
// purchase/shared/poApproval.ts and store/shared/sprApproval.ts. Both chains
// share one engine: a document (PO or SPR) snapshots the approvers of an
// approve_type into its own *_approvals table at submission, then advances
// current_serial one step at a time until the last step approves (document
// APPROVED) or a required step rejects (document REJECTED). Rejecting an
// optional step only skips it.

int? approvalInt(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));
double approvalDouble(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
double? approvalDoubleOrNull(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
String? approvalStr(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Which chain a call is about.
enum ApprovalDoc {
  po('purchase_orders', 'purchase_order_approvals', 'purchase_order_id'),
  spr('store_purchase_requisitions', 'store_purchase_requisition_approvals', 'purchase_requisition_id');

  final String docEndpoint;
  final String stepsEndpoint;
  final String parentField;
  const ApprovalDoc(this.docEndpoint, this.stepsEndpoint, this.parentField);
}

class ApprovalStep {
  final int id;
  final int serial;
  final String label;
  final bool isRequired;
  final int? approverEmpId;
  final int? approverDesId;
  final int? workplaceMemberId;
  final String status; // PENDING | APPROVED | REJECTED | SKIPPED
  final int? actedBy;
  final DateTime? actedAt;
  final String? notes;
  final String? actorName;

  const ApprovalStep({
    required this.id,
    required this.serial,
    required this.label,
    required this.isRequired,
    this.approverEmpId,
    this.approverDesId,
    this.workplaceMemberId,
    required this.status,
    this.actedBy,
    this.actedAt,
    this.notes,
    this.actorName,
  });

  factory ApprovalStep.fromJson(Map json) {
    final actor = json['actor'];
    final serial = approvalInt(json['serial']) ?? 0;
    return ApprovalStep(
      id: approvalInt(json['id']) ?? 0,
      serial: serial,
      label: approvalStr(json['label']) ?? 'Step $serial',
      isRequired: json['is_required'] != false,
      approverEmpId: approvalInt(json['approver_emp_id']),
      approverDesId: approvalInt(json['approver_des_id']),
      workplaceMemberId: approvalInt(json['workplace_member_id']),
      status: (approvalStr(json['status']) ?? 'PENDING').toUpperCase(),
      actedBy: approvalInt(json['acted_by']),
      actedAt: json['acted_at'] == null ? null : DateTime.tryParse(json['acted_at'].toString()),
      notes: approvalStr(json['notes']),
      actorName: actor is Map ? (approvalStr(actor['name']) ?? approvalStr(actor['email'])) : null,
    );
  }

  bool get isDone => status == 'APPROVED' || status == 'SKIPPED';
}

/// Sorted steps from a raw `approvals` expand.
List<ApprovalStep> parseSteps(dynamic raw) {
  if (raw is! List) return const [];
  final list = raw.whereType<Map>().map(ApprovalStep.fromJson).toList()..sort((a, b) => a.serial.compareTo(b.serial));
  return list;
}

/// "2/3" — approved or skipped steps over all steps.
String approvalProgress(List<ApprovalStep> steps) {
  if (steps.isEmpty) return '';
  return '${steps.where((s) => s.isDone).length}/${steps.length}';
}

class CurrentApprover {
  final int userId;
  final int? employeeId;
  final int? designationId;
  final int? memberId;
  const CurrentApprover({required this.userId, this.employeeId, this.designationId, this.memberId});
  static const none = CurrentApprover(userId: 0);
}

ApprovalStep? currentStep(List<ApprovalStep> steps, int currentSerial) {
  for (final s in steps) {
    if (s.serial == currentSerial) return s;
  }
  return null;
}

/// A step can target an employee, a designation, or a workplace member.
bool canActOnStep(ApprovalStep? step, CurrentApprover me) {
  if (step == null || step.status != 'PENDING') return false;
  if (step.approverEmpId != null && step.approverEmpId == me.employeeId) return true;
  if (step.workplaceMemberId != null && step.workplaceMemberId == me.memberId) return true;
  if (step.approverDesId != null && me.designationId != null && step.approverDesId == me.designationId) return true;
  return false;
}

/// One decided step's outcome for the document.
enum ApprovalOutcome { approved, rejected, advanced }

class ApprovalService {
  final ApiClient client;
  ApprovalService(this.client);

  static Future<int> currentUserId() async {
    final user = await AppStorage.getUser();
    return approvalInt(user?['id']) ?? 0;
  }

  /// Batch queries that resolve the signed-in user as an approver — callers
  /// fold these into their own `$batch` so the page needs one round trip.
  static Map<String, String> meQueries(int userId) => userId <= 0
      ? const {}
      : {
          '__me_emp': 'employees?\$select=id,designation_id&\$filter=user_id eq $userId&\$top=1',
          '__me_member': 'workplace_members?\$select=id&\$filter=user_id eq $userId&\$top=1',
        };

  static CurrentApprover meFrom(int userId, Map<String, List<Map<String, dynamic>>> data) {
    if (userId <= 0) return CurrentApprover.none;
    final emp = (data['__me_emp'] ?? const []).firstOrNull;
    final member = (data['__me_member'] ?? const []).firstOrNull;
    return CurrentApprover(
      userId: userId,
      employeeId: approvalInt(emp?['id']),
      designationId: approvalInt(emp?['designation_id']),
      memberId: approvalInt(member?['id']),
    );
  }

  /// (Re)starts the chain for one document: clears old steps (a rejected
  /// document being resubmitted), snapshots the approvers renumbered 1..n
  /// and points the document at step 1. Returns the number of steps — 0
  /// means no chain / no approvers, and the document waits for a manual
  /// decision instead. Every write is sequential (each depends on the last).
  Future<int> start(ApprovalDoc doc, int docId, int? approveTypeId) async {
    final existing = unwrapList(await client.get('${doc.stepsEndpoint}?\$select=id&\$filter=${doc.parentField} eq $docId&\$top=200'));
    for (final row in existing.whereType<Map>()) {
      final id = approvalInt(row['id']);
      if (id != null) await client.delete(doc.stepsEndpoint, id);
    }
    if (approveTypeId == null) return 0;

    final approvers = unwrapList(await client.get(
      'approve_type_has_approvers?\$filter=approve_type_id eq $approveTypeId&\$orderby=serial asc&\$top=100',
    )).whereType<Map>().toList();
    if (approvers.isEmpty) return 0;

    for (var i = 0; i < approvers.length; i++) {
      final a = approvers[i];
      await client.post(
        doc.stepsEndpoint,
        {
          doc.parentField: docId,
          'serial': i + 1,
          'label': approvalStr(a['label']) ?? 'Step ${i + 1}',
          'is_required': a['is_required'] != false,
          'approver_emp_id': approvalInt(a['approver_emp_id']),
          'approver_des_id': approvalInt(a['approver_des_id']),
          'workplace_member_id': approvalInt(a['workplace_member_id']),
          'status': 'PENDING',
        },
        isV8: true,
      );
    }
    await client.put(doc.docEndpoint, docId, {'status': 'PENDING', 'approve_type_id': approveTypeId, 'current_serial': 1});
    return approvers.length;
  }

  /// Records one approver's decision and moves the document along.
  Future<ApprovalOutcome> act(
    ApprovalDoc doc, {
    required int docId,
    required int currentSerial,
    required List<ApprovalStep> steps,
    required bool approve,
    required String? notes,
    required CurrentApprover me,
  }) async {
    final step = currentStep(steps, currentSerial);
    if (step == null) throw ApiException(400, 'No pending approval step');

    final stepStatus = !approve && !step.isRequired ? 'SKIPPED' : (approve ? 'APPROVED' : 'REJECTED');
    await client.put(doc.stepsEndpoint, step.id, {
      'status': stepStatus,
      'acted_by': me.userId > 0 ? me.userId : null,
      'acted_at': DateTime.now().toUtc().toIso8601String(),
      'notes': notes,
    });

    if (stepStatus == 'REJECTED') {
      await client.put(doc.docEndpoint, docId, {'status': 'REJECTED'});
      return ApprovalOutcome.rejected;
    }
    final later = steps.where((s) => s.serial > step.serial).toList()..sort((a, b) => a.serial.compareTo(b.serial));
    if (later.isNotEmpty) {
      await client.put(doc.docEndpoint, docId, {'current_serial': later.first.serial});
      return ApprovalOutcome.advanced;
    }
    await client.put(doc.docEndpoint, docId, {'status': 'APPROVED'});
    return ApprovalOutcome.approved;
  }
}

/// One `$batch` of named OData GETs. Unlike entity_crud's batchLoad, keys in
/// [required] throw when their slot failed, so a broken main list surfaces
/// as an error (with retry) instead of an empty page.
Future<Map<String, List<Map<String, dynamic>>>> purchaseBatch(ApiClient client, Map<String, String> queries, {Set<String> required = const {}}) async {
  if (queries.isEmpty) return {};
  final keys = queries.keys.toList();
  final res = await client.batch([
    for (var i = 0; i < keys.length; i++) BatchRequest(id: '${i + 1}', method: 'GET', url: queries[keys[i]]!),
  ]);
  final responses = res is Map ? res['responses'] : null;
  final out = <String, List<Map<String, dynamic>>>{};
  for (var i = 0; i < keys.length; i++) {
    final id = '${i + 1}';
    Map? entry;
    if (responses is List) {
      for (final r in responses) {
        if (r is Map && r['id'].toString() == id) entry = r;
      }
    }
    final status = approvalInt(entry?['status']) ?? 200;
    if (required.contains(keys[i]) && (entry == null || status >= 400)) {
      final body = entry?['body'];
      final msg = body is Map ? approvalStr(body['message']) ?? approvalStr(body['error']) : null;
      throw ApiException(status, msg ?? 'Could not load');
    }
    out[keys[i]] = unwrapList(entry?['body']).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }
  return out;
}
