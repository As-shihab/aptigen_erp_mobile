import '../../core/config/app_config.dart';

int _toNum(dynamic value) {
  final parsed = num.tryParse(value?.toString() ?? '');
  return parsed?.toInt() ?? 0;
}

String _toAbsUrl(String url) {
  if (url.isEmpty) return url;
  if (url.startsWith('http') || url.startsWith('data:')) return url;
  return '${AppConfig.apiBase}${url.startsWith('/') ? '' : '/'}$url';
}

/// Mirrors erp/desktop's media-library.store.ts `mapItem` shape — one row
/// from `media_items` (browsed) or one entry of `POST /api/media/upload`'s
/// `savedMedia` response (just-uploaded).
class MediaLibraryItem {
  final int id;
  final String name;
  final String fileUrl;
  final String previewUrl;
  final String? mime;
  final String? extension;
  final String kind; // 'image' | 'document' | 'other'
  final String visibility; // 'public' | 'private'
  final int size;
  final int? categoryId;
  final String? categoryName;

  const MediaLibraryItem({
    required this.id,
    required this.name,
    required this.fileUrl,
    required this.previewUrl,
    this.mime,
    this.extension,
    required this.kind,
    required this.visibility,
    required this.size,
    this.categoryId,
    this.categoryName,
  });

  bool get isImage => kind == 'image';

  factory MediaLibraryItem.fromJson(Map<String, dynamic> json) {
    final fileUrl = (json['fileUrl'] ?? json['file_url'] ?? '').toString();
    final previewUrl = (json['previewUrl'] ?? json['preview_url'] ?? fileUrl).toString();
    final category = json['category'];
    return MediaLibraryItem(
      id: _toNum(json['id']),
      name: (json['name'] ?? json['originalName'] ?? json['original_name'] ?? 'Untitled').toString(),
      fileUrl: _toAbsUrl(fileUrl),
      previewUrl: _toAbsUrl(previewUrl),
      mime: (json['mime'] ?? json['mimeType'] ?? json['mime_type'])?.toString(),
      extension: json['extension']?.toString(),
      kind: (json['kind'] ?? 'other').toString(),
      visibility: (json['visibility'] ?? 'private').toString(),
      size: _toNum(json['size'] ?? json['sizeBytes'] ?? json['size_bytes']),
      categoryId: json['category_id'] != null
          ? _toNum(json['category_id'])
          : (category is Map ? _toNum(category['id']) : null),
      categoryName: category is Map ? category['name']?.toString() : null,
    );
  }
}

class MediaCategory {
  final int id;
  final String name;
  const MediaCategory({required this.id, required this.name});

  factory MediaCategory.fromJson(Map<String, dynamic> json) =>
      MediaCategory(id: _toNum(json['id']), name: (json['name'] ?? '').toString());
}
