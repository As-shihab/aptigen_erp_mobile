import '../../core/network/http_client.dart';
import '../models/media_library_item.dart';

const int mediaPageSize = 24;

/// Data layer for the reusable [MediaLibraryDialog] — ported from
/// erp/desktop's media-library.store.ts (`media_categories`/`media_items`
/// OData reads, `POST /api/media/upload` for new files, `DELETE
/// /api/media/items/:id`).
class MediaLibraryService {
  final ApiClient _client;
  MediaLibraryService(this._client);

  String _escapeOData(String value) => value.replaceAll("'", "''");

  /// Matches desktop's `refreshMediaCategories` — plain unfiltered fetch,
  /// no `$filter`/`$orderby`/`$top` (the categories list is small).
  Future<List<MediaCategory>> loadCategories() async {
    final res = await _client.get('media_categories');
    return unwrapList(res).cast<Map<String, dynamic>>().map(MediaCategory.fromJson).toList();
  }

  /// Matches desktop's `addMediaCategory` — body is just `{ name }`.
  Future<MediaCategory> createCategory(String name) async {
    final created = await _client.post('media_categories', {'name': name}, isV8: true);
    final row = (created is Map ? created['value'] ?? created : created) as Map?;
    return MediaCategory.fromJson(row?.cast<String, dynamic>() ?? {'name': name});
  }

  Future<MediaCategory> ensureCategoryByName(String name) async {
    final categories = await loadCategories();
    for (final category in categories) {
      if (category.name.toLowerCase() == name.toLowerCase()) return category;
    }
    return createCategory(name);
  }

  /// Matches desktop's `fetchMediaPage` filter shape exactly (no `is_active`
  /// filter, no `$orderby` — desktop's dialog doesn't apply either). `$count`
  /// is only requested on the first page, mirroring `withCount: reset`.
  Future<({List<MediaLibraryItem> items, int total})> loadItems({
    String search = '',
    int? categoryId,
    String visibility = 'all', // 'all' | 'public' | 'private'
    int top = mediaPageSize,
    int skip = 0,
    bool withCount = true,
  }) async {
    final filters = <String>[];
    if (categoryId != null) filters.add('category_id eq $categoryId');
    if (visibility != 'all') filters.add("visibility eq '$visibility'");
    if (search.trim().isNotEmpty) {
      filters.add("contains(tolower(original_name),'${_escapeOData(search.trim().toLowerCase())}')");
    }
    final query = StringBuffer('media_items?\$top=$top&\$skip=$skip');
    if (withCount) query.write('&\$count=true');
    if (filters.isNotEmpty) query.write('&\$filter=${filters.join(' and ')}');
    final res = await _client.get(query.toString());
    final items = unwrapList(res).cast<Map<String, dynamic>>().map(MediaLibraryItem.fromJson).toList();
    // Backend's OData layer returns the page total as `@count`, not the
    // `@odata.count` key used elsewhere in this app's docs. Only present
    // when `withCount` was requested — callers should keep their previous
    // total on non-counted pages rather than treat a null as zero.
    final total = withCount && res is Map ? int.tryParse((res['@count'] ?? '').toString()) : null;
    return (items: items, total: total ?? items.length);
  }

  Future<MediaLibraryItem?> uploadFile({
    required List<int> bytes,
    required String filename,
    required int categoryId,
    String visibility = 'private',
    bool useSharp = true,
  }) async {
    final response = await _client.uploadFile(
      'media/upload',
      bytes: bytes,
      filename: filename,
      fields: {'category_id': categoryId.toString(), 'visibility': visibility},
      useSharp: useSharp,
    );
    final saved = (response is Map ? response['savedMedia'] : null) as List?;
    final item = saved?.isNotEmpty == true ? saved!.first as Map : null;
    if (item == null) return null;
    return MediaLibraryItem.fromJson(item.cast<String, dynamic>());
  }

  Future<void> deleteItem(int id) async {
    await _client.delete('media/items', id, isV8: false);
  }
}
