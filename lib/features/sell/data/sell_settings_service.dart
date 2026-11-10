import '../../../core/network/http_client.dart';
import '../../store/data/store_util.dart';

/// Per-workplace Sell module feature toggles — same shape/purpose as
/// `store_settings`. `has_sale_approval`'s approver-type chain is out of
/// scope here (separate approvals system), same simplification Store made
/// for `has_spr_approval`. Desktop itself never actually enforces
/// `has_discounts` in PosTerminal.tsx (a known desktop gap) — mirrored as a
/// stored-but-unenforced toggle here too, not silently "fixed" into a
/// behavior desktop doesn't have.
class SellFeatureToggles {
  final int? id;
  final bool hasPos;
  final bool hasReturns;
  final bool hasQuotation;
  final bool hasDiscounts;
  final bool hasSaleApproval;

  /// Staff may create store products from Sales (hub "Product" shortcut).
  final bool hasProductCreate;

  const SellFeatureToggles({
    this.id,
    this.hasPos = true,
    this.hasReturns = true,
    this.hasQuotation = true,
    this.hasDiscounts = true,
    this.hasSaleApproval = false,
    this.hasProductCreate = true,
  });

  factory SellFeatureToggles.fromJson(Map json) => SellFeatureToggles(
        id: toIntOrNull(json['id']),
        hasPos: toBool(json['has_pos'], fallback: true),
        hasReturns: toBool(json['has_returns'], fallback: true),
        hasQuotation: toBool(json['has_quotation'], fallback: true),
        hasDiscounts: toBool(json['has_discounts'], fallback: true),
        hasSaleApproval: toBool(json['has_sale_approval']),
        hasProductCreate: toBool(json['has_product_create'], fallback: true),
      );

  SellFeatureToggles copyWith({bool? hasPos, bool? hasReturns, bool? hasQuotation, bool? hasDiscounts, bool? hasSaleApproval, bool? hasProductCreate}) => SellFeatureToggles(
        id: id,
        hasPos: hasPos ?? this.hasPos,
        hasReturns: hasReturns ?? this.hasReturns,
        hasQuotation: hasQuotation ?? this.hasQuotation,
        hasDiscounts: hasDiscounts ?? this.hasDiscounts,
        hasSaleApproval: hasSaleApproval ?? this.hasSaleApproval,
        hasProductCreate: hasProductCreate ?? this.hasProductCreate,
      );
}

class SellSettingsService {
  final ApiClient _client;
  SellSettingsService(this._client);

  Future<SellFeatureToggles> load() async {
    final res = await _client.get(r'sell_settings?$top=1');
    final rows = unwrapList(res);
    if (rows.isEmpty) return const SellFeatureToggles();
    return SellFeatureToggles.fromJson((rows.first as Map).cast<String, dynamic>());
  }

  Future<void> save(SellFeatureToggles toggles, {required int moduleId}) async {
    final payload = {
      'has_pos': toggles.hasPos,
      'has_returns': toggles.hasReturns,
      'has_quotation': toggles.hasQuotation,
      'has_discounts': toggles.hasDiscounts,
      'has_sale_approval': toggles.hasSaleApproval,
      'has_product_create': toggles.hasProductCreate,
    };
    if (toggles.id != null) {
      await _client.put('sell_settings', toggles.id!, payload);
    } else {
      await _client.post('sell_settings', {...payload, 'module_id': moduleId}, isV8: true);
    }
  }
}
