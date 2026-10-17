import '../../../core/network/http_client.dart';
import 'store_util.dart';

/// A generic `{id, label}` option for a dropdown/`ComboBox`-equivalent field
/// — optionally carrying a `parentId` so cascading FK pickers (warehouse ->
/// corridor -> rack -> bin, category -> sub-category) can filter their
/// options by whichever parent value is currently selected, same idea as
/// desktop's `visibleCorridors`/`visibleRacks`/`visibleBins` filters.
class LookupOption {
  final int id;
  final String label;
  final int? parentId;
  const LookupOption({required this.id, required this.label, this.parentId});
}

/// One place to load every independent Store lookup list mobile pages need —
/// batches them in a single round trip per CLAUDE.md's batch-loading rule
/// (mirrored here even though this is Flutter, not the desktop app, since
/// `ApiClient.batch` was built to mirror that exact convention).
class StoreLookupService {
  final ApiClient _client;
  StoreLookupService(this._client);

  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async {
    // Store lookups are the non-pharma side only (is_pharma rows belong to Pharma).
    const q = '\$select=id,name&\$filter=is_active eq true and is_pharma eq false&\$top=500';
    final result = await _client.batch([
      BatchRequest(id: 'categories', method: 'GET', url: 'store_product_categories?$q'),
      BatchRequest(id: 'subCategories', method: 'GET', url: 'store_product_sub_categories?$q&\$select=id,name,category_id'),
      BatchRequest(id: 'uoms', method: 'GET', url: 'store_uoms?\$select=id,name,code,symbol&\$filter=is_active eq true&\$top=500'),
      BatchRequest(id: 'warehouses', method: 'GET', url: 'store_warehouses?\$select=id,code,name,type&\$filter=is_active eq true and is_pharma eq false&\$top=500'),
      BatchRequest(id: 'corridors', method: 'GET', url: 'store_warehouse_corridors?\$select=id,code,name,warehouse_id&\$filter=is_active eq true and is_pharma eq false&\$top=500'),
      BatchRequest(id: 'racks', method: 'GET', url: 'store_warehouse_racks?\$select=id,code,name,corridor_id&\$filter=is_active eq true and is_pharma eq false&\$top=500'),
      BatchRequest(id: 'bins', method: 'GET', url: 'store_warehouse_bins?\$select=id,code,name,rack_id&\$filter=is_active eq true and is_pharma eq false&\$top=500'),
      BatchRequest(id: 'batches', method: 'GET', url: 'store_product_batches?\$select=id,batch_no,product_id,status&\$filter=is_pharma eq false&\$top=1000'),
      BatchRequest(id: 'departments', method: 'GET', url: 'departments?\$select=id,name&\$top=500'),
      BatchRequest(id: 'products', method: 'GET', url: 'store_products?\$select=id,name&\$filter=is_active eq true and is_pharma eq false&\$top=2000'),
    ]);

    Map<String, dynamic>? body(String id) => unwrapBatchBody(result, id);
    List<Map<String, dynamic>> rows(String id) => unwrapList(body(id)).cast<Map<String, dynamic>>();

    return {
      'categories': rows('categories'),
      'subCategories': rows('subCategories'),
      'uoms': rows('uoms'),
      'warehouses': rows('warehouses'),
      'corridors': rows('corridors'),
      'racks': rows('racks'),
      'bins': rows('bins'),
      'batches': rows('batches'),
      'departments': rows('departments'),
      'products': rows('products'),
    };
  }
}

String codeLabel(Map row) {
  final code = (row['code'] ?? '').toString();
  final name = toStringOrNull(row['name']);
  return name != null ? '$code — $name' : code;
}

List<LookupOption> toOptions(List<Map<String, dynamic>> rows, {String labelField = 'name', String? parentField}) {
  return rows
      .map((r) => LookupOption(
            id: toNum(r['id']),
            label: (r[labelField] ?? '').toString(),
            parentId: parentField != null ? toIntOrNull(r[parentField]) : null,
          ))
      .toList();
}

List<LookupOption> toCodeOptions(List<Map<String, dynamic>> rows, {String? parentField}) {
  return rows
      .map((r) => LookupOption(
            id: toNum(r['id']),
            label: codeLabel(r),
            parentId: parentField != null ? toIntOrNull(r[parentField]) : null,
          ))
      .toList();
}
