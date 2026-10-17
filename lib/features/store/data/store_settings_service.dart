import '../../../core/network/http_client.dart';
import 'store_util.dart';

/// Per-workplace Store feature toggles (`store_settings`). The SPR approval
/// chain fields (`has_spr_approval` + `spr_approver_type_id`) are read so the
/// SPR form can start the chain after a save (see spr_approval_service.dart);
/// `spr_approver_type_id` is only read here, never written — picking the
/// chain stays a desktop setting.
class StoreFeatureToggles {
  final int? id;
  final bool hasSprApproval;
  final bool hasSpr;
  final bool hasSr;
  final bool hasRepairMrr;
  final int? sprApproverTypeId;

  const StoreFeatureToggles({
    this.id,
    this.hasSprApproval = false,
    this.hasSpr = true,
    this.hasSr = true,
    this.hasRepairMrr = true,
    this.sprApproverTypeId,
  });

  factory StoreFeatureToggles.fromJson(Map json) => StoreFeatureToggles(
        id: toIntOrNull(json['id']),
        hasSprApproval: toBool(json['has_spr_approval']),
        hasSpr: toBool(json['has_spr'], fallback: true),
        hasSr: toBool(json['has_sr'], fallback: true),
        hasRepairMrr: toBool(json['has_repair_mrr'], fallback: true),
        sprApproverTypeId: toIntOrNull(json['spr_approver_type_id']),
      );

  StoreFeatureToggles copyWith({bool? hasSprApproval, bool? hasSpr, bool? hasSr, bool? hasRepairMrr}) => StoreFeatureToggles(
        id: id,
        hasSprApproval: hasSprApproval ?? this.hasSprApproval,
        hasSpr: hasSpr ?? this.hasSpr,
        hasSr: hasSr ?? this.hasSr,
        hasRepairMrr: hasRepairMrr ?? this.hasRepairMrr,
        sprApproverTypeId: sprApproverTypeId,
      );
}

class StoreSettingsService {
  final ApiClient _client;
  StoreSettingsService(this._client);

  Future<StoreFeatureToggles> load() async {
    final res = await _client.get(r'store_settings?$top=1');
    final rows = unwrapList(res);
    if (rows.isEmpty) return const StoreFeatureToggles();
    return StoreFeatureToggles.fromJson((rows.first as Map).cast<String, dynamic>());
  }

  Future<void> save(StoreFeatureToggles toggles, {required int moduleId}) async {
    final payload = {
      'has_spr_approval': toggles.hasSprApproval,
      'has_spr': toggles.hasSpr,
      'has_sr': toggles.hasSr,
      'has_repair_mrr': toggles.hasRepairMrr,
    };
    if (toggles.id != null) {
      await _client.put('store_settings', toggles.id!, payload);
    } else {
      await _client.post('store_settings', {...payload, 'module_id': moduleId}, isV8: true);
    }
  }
}
