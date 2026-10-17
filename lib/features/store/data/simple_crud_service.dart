import '../../../core/network/http_client.dart';

/// One generic CRUD service reused by every flat Store lookup entity
/// (categories, sub-categories, UOMs, packagings, batches, warehouses,
/// corridors, racks, bins) instead of ~9 near-identical service files — all
/// of them are plain OData entities (isV8=true) with no bespoke backend
/// logic, so raw `Map<String,dynamic>` rows are enough; there's no need for
/// a typed model per entity the way the richer document/product features
/// need one.
/// Store entities that carry `is_pharma` — the Store module only shows the
/// non-pharma rows; pharma ones belong to the Pharma module.
const kPharmaFlaggedEntities = {
  'store_product_categories',
  'store_product_sub_categories',
  'store_product_batches',
  'store_warehouses',
  'store_warehouse_corridors',
  'store_warehouse_racks',
  'store_warehouse_bins',
};

/// Adds `is_pharma eq false` to [filter] unless the caller already filters
/// on is_pharma (e.g. a pharma screen asking for `is_pharma eq true`).
String? withoutPharma(String? filter, {String field = 'is_pharma'}) {
  if (filter != null && filter.contains('is_pharma')) return filter;
  final clause = '$field eq false';
  return filter == null || filter.trim().isEmpty ? clause : '($filter) and $clause';
}

class SimpleCrudService {
  final ApiClient _client;
  final String endpoint;
  SimpleCrudService(this._client, this.endpoint);

  Future<List<Map<String, dynamic>>> list({String? filter, String? select, String? expand, String orderBy = 'id desc', int top = 500}) async {
    if (kPharmaFlaggedEntities.contains(endpoint)) filter = withoutPharma(filter);
    final params = <String>[];
    if (select != null) params.add('\$select=$select');
    if (expand != null) params.add('\$expand=$expand');
    if (filter != null) params.add('\$filter=${Uri.encodeComponent(filter)}');
    params.add('\$orderby=${Uri.encodeComponent(orderBy)}');
    params.add('\$top=$top');
    final res = await _client.get('$endpoint?${params.join('&')}');
    return unwrapList(res).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> payload) async {
    final res = await _client.post(endpoint, payload, isV8: true);
    final unwrapped = (res is Map && res['value'] is Map) ? res['value'] : res;
    return (unwrapped as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> update(int id, Map<String, dynamic> payload) async {
    final res = await _client.put(endpoint, id, payload);
    final unwrapped = (res is Map && res['value'] is Map) ? res['value'] : res;
    return (unwrapped as Map).cast<String, dynamic>();
  }

  Future<void> delete(int id) async {
    await _client.delete(endpoint, id);
  }
}
