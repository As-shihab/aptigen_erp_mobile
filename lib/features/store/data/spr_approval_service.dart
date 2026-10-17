import '../../../core/network/http_client.dart';
import 'store_util.dart';

/// SPR approval chain — mobile port of desktop's
/// `erp/desktop/src/module/store/shared/sprApproval.ts`.
///
/// `store_settings.has_spr_approval` turns the chain on and
/// `spr_approver_type_id` picks it. The store sends an SPR (PENDING); each
/// step in `store_purchase_requisition_approvals` approves in turn (approving
/// happens on desktop). Mobile only (re)starts the chain after a save.
class SprApprovalService {
  final ApiClient _client;
  SprApprovalService(this._client);

  /// (Re)starts the chain for one SPR: drops its existing approval rows,
  /// snapshots the approvers of [approveTypeId] (renumbered 1..n so
  /// `current_serial + 1` always lands on the next step), then points the
  /// SPR at step 1. Returns the number of steps created — 0 means no chain /
  /// no approvers configured, and the SPR waits for purchasing to approve it.
  ///
  /// Every call is sequential (each depends on the previous one) and any
  /// failure is thrown — callers treat a failure as "no chain".
  Future<int> start(int sprId, int? approveTypeId) async {
    final existing = unwrapList(await _client.get(
      'store_purchase_requisition_approvals?\$select=id&\$filter=purchase_requisition_id eq $sprId&\$top=200',
    ));
    for (final row in existing.whereType<Map>()) {
      await _client.delete('store_purchase_requisition_approvals', toNum(row['id']));
    }
    if (approveTypeId == null) return 0;

    final approvers = unwrapList(await _client.get(
      'approve_type_has_approvers?\$filter=approve_type_id eq $approveTypeId&\$orderby=serial asc&\$top=100',
    )).whereType<Map>().toList();
    if (approvers.isEmpty) return 0;

    for (var i = 0; i < approvers.length; i++) {
      final a = approvers[i];
      final label = toStringOrNull(a['label']);
      await _client.post(
        'store_purchase_requisition_approvals',
        {
          'purchase_requisition_id': sprId,
          'serial': i + 1,
          'label': label ?? 'Step ${i + 1}',
          'is_required': a['is_required'] != false,
          'approver_emp_id': toIntOrNull(a['approver_emp_id']),
          'approver_des_id': toIntOrNull(a['approver_des_id']),
          'workplace_member_id': toIntOrNull(a['workplace_member_id']),
          'status': 'PENDING',
        },
        isV8: true,
      );
    }

    await _client.put('store_purchase_requisitions', sprId, {
      'status': 'PENDING',
      'approve_type_id': approveTypeId,
      'current_serial': 1,
    });
    return approvers.length;
  }
}
