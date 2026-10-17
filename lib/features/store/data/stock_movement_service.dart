import '../../../core/network/http_client.dart';
import 'simple_crud_service.dart' show withoutPharma;
import 'stock_movement_model.dart';

class StockMovementService {
  final ApiClient _client;
  StockMovementService(this._client);

  Future<List<StockMovementRow>> list({String? filter, int top = 500}) async {
    final params = ['\$expand=product,location,batch', '\$orderby=id desc', '\$top=$top'];
    // Store ledger: movements of non-pharma products only.
    params.add('\$filter=${Uri.encodeComponent(withoutPharma(filter, field: 'product/is_pharma')!)}');
    final res = await _client.get('store_stock_movements?${params.join('&')}');
    return unwrapList(res).cast<Map<String, dynamic>>().map(StockMovementRow.fromJson).toList();
  }

  Future<List<StockMovementRow>> listAdjustments({int top = 500}) {
    return list(filter: "reference_type eq 'ADJUSTMENT'", top: top);
  }
}
