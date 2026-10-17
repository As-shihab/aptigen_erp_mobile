import '../../../core/network/http_client.dart';
import 'simple_crud_service.dart' show withoutPharma;
import 'store_product_model.dart';

const String kProductSelect =
    'id,name,sku,barcode,short_desc,category_id,sub_category_id,uom_id,price,compare_price,cost_price,stock_qty,low_stock_at,track_stock,is_active,is_featured,thumbnail_url';

class StoreProductService {
  final ApiClient _client;
  StoreProductService(this._client);

  /// Non-pharma products unless [filter] itself filters on is_pharma (the
  /// pharma POS / inventory pass `is_pharma eq true`).
  Future<List<StoreProduct>> list({String? filter, int top = 2000}) async {
    final params = ['\$select=$kProductSelect', '\$top=$top'];
    filter = withoutPharma(filter);
    params.add('\$filter=${Uri.encodeComponent(filter!)}');
    final res = await _client.get('store_products?${params.join('&')}');
    return unwrapList(res).cast<Map<String, dynamic>>().map(StoreProduct.fromJson).toList();
  }

  /// Packagings follow their product's side — non-pharma unless [isPharma].
  Future<List<StorePackaging>> listPackagings({int top = 2000, bool isPharma = false}) async {
    final res = await _client.get('store_product_packagings?\$select=id,product_id,name,barcode,unit_qty&\$filter=is_active eq true and product/is_pharma eq $isPharma&\$top=$top');
    return unwrapList(res).cast<Map<String, dynamic>>().map(StorePackaging.fromJson).toList();
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> payload) async {
    final res = await _client.post('store_products', payload, isV8: true);
    final unwrapped = (res is Map && res['value'] is Map) ? res['value'] : res;
    return (unwrapped as Map).cast<String, dynamic>();
  }

  Future<void> update(int id, Map<String, dynamic> payload) async {
    await _client.put('store_products', id, payload);
  }

  Future<void> delete(int id) async {
    await _client.delete('store_products', id);
  }

  Future<void> adjustStockQty(int id, double newStockQty) async {
    await _client.put('store_products', id, {'stock_qty': newStockQty});
  }
}
