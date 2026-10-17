import '../../../core/network/http_client.dart';
import '../models/stay_model.dart';

/// Ported from erp/desktop's aptigen module (StaysList.tsx + CreateStays.tsx).
/// `stays` is a dedicated REST controller (isV8=false, `/api/stays`), scoped
/// by `workplace_id` (any member of the workplace can see/manage the shared
/// stays inventory) rather than `user_id`. `amenities`/`stay_categories` are
/// plain OData lookups (isV8=true) — unaffected by that scoping change.
class StaysService {
  final ApiClient _client;
  StaysService(this._client);

  Future<List<Stay>> loadStays() async {
    final res = await _client.get('stays', isV8: false);
    return unwrapList(res).cast<Map<String, dynamic>>().map(Stay.fromJson).toList();
  }

  Future<List<StayAmenity>> loadAmenities() async {
    final res = await _client.get(r'amenities?$top=200');
    return unwrapList(res).cast<Map<String, dynamic>>().map(StayAmenity.fromJson).toList();
  }

  Future<List<StayCategory>> loadCategories() async {
    final res = await _client.get(r'stay_categories?$filter=is_active eq true&$top=200');
    return unwrapList(res).cast<Map<String, dynamic>>().map(StayCategory.fromJson).toList();
  }

  Future<void> create(Map<String, dynamic> payload) async {
    await _client.post('stays', payload, isV8: false);
  }

  Future<void> update(int id, Map<String, dynamic> payload) async {
    await _client.put('stays', id, payload, isV8: false);
  }

  Future<void> delete(int id) async {
    await _client.delete('stays', id, isV8: false);
  }
}
