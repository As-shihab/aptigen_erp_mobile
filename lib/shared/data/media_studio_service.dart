import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/network/http_client.dart';
import '../models/media_edit_ops.dart';
import '../models/media_library_item.dart';

// Image studio data layer — port of erp/desktop's image-studio/api.ts and
// templates.ts. Edit preview / save / compress are custom `/api/media/...`
// routes (isV8 = false); templates are the generic OData entity
// `media_edit_templates` (isV8 = true).

/// Same timeouts as desktop's image-studio/constants.ts.
const studioPreviewDebounce = Duration(milliseconds: 450);
const studioPreviewTimeout = Duration(seconds: 60);
const studioSaveTimeout = Duration(seconds: 180);
const studioHistoryLimit = 50;

class StudioPreview {
  final Uint8List bytes;
  final int width;
  final int height;
  final bool hasAlpha;
  const StudioPreview({required this.bytes, required this.width, required this.height, required this.hasAlpha});
}

class CompressResult {
  final MediaLibraryItem? item;
  final int before;
  final int after;
  final bool compressed;
  const CompressResult({required this.item, required this.before, required this.after, required this.compressed});
}

class MediaEditTemplate {
  final int id;
  final String name;
  final String? description;
  final EditOps ops;
  final String? previewUrl;
  final int? createdBy;
  final String? createdAt;
  final String? updatedAt;

  const MediaEditTemplate({
    required this.id,
    required this.name,
    this.description,
    required this.ops,
    this.previewUrl,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory MediaEditTemplate.fromJson(Map<String, dynamic> row) {
    final name = (row['name'] ?? '').toString().trim();
    final description = row['description']?.toString();
    return MediaEditTemplate(
      id: int.tryParse('${row['id']}') ?? -1,
      name: name.isEmpty ? 'Untitled template' : name,
      description: description == null || description.isEmpty ? null : description,
      ops: stripCrop(EditOps.fromJson(row['ops'])),
      previewUrl: row['preview_url']?.toString(),
      createdBy: int.tryParse('${row['created_by']}'),
      createdAt: row['created_at']?.toString(),
      updatedAt: row['updated_at']?.toString(),
    );
  }

  MediaEditTemplate copyWith({String? name, Object? description = const Object(), EditOps? ops, String? updatedAt}) => MediaEditTemplate(
        id: id,
        name: name ?? this.name,
        description: description is String? ? description : this.description,
        ops: ops ?? this.ops,
        previewUrl: previewUrl,
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// Turns ApiClient errors into a short, readable message (desktop's describeStudioError).
String describeStudioError(Object? error, String fallback) {
  if (error is TimeoutException) return 'The image service took too long to respond';
  if (error is http.ClientException) return 'You are offline — connect to the internet and try again';
  if (error is ApiException) {
    if (error.statusCode == 503) return 'Image service unavailable';
    final raw = error.message;
    if (!raw.startsWith('Request failed')) return raw;
    // Body wasn't a plain `message` string — class-validator arrays etc.
    final idx = raw.indexOf(': ');
    if (idx > 0) {
      try {
        final parsed = jsonDecode(raw.substring(idx + 2));
        if (parsed is Map) {
          final msg = parsed['message'];
          if (msg is List && msg.isNotEmpty) return msg.join(', ');
          if (parsed['error'] is String) return parsed['error'] as String;
        }
      } catch (_) {/* not json */}
    }
    return '$fallback (${error.statusCode})';
  }
  final text = '$error';
  if (text.contains('SocketException') || text.contains('Failed host lookup')) {
    return 'You are offline — connect to the internet and try again';
  }
  return fallback;
}

/// Session-only cache busting for images whose file was overwritten in place
/// ("Replace original", compress, Lab replace). The URL stays the same, so
/// the image cache would keep showing the old pixels — desktop's
/// markMediaItemReplaced / withCacheBust. Applied at display time only.
class MediaCacheBust {
  static final Map<int, int> _replacedAt = {};
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static void markReplaced(int id) {
    _replacedAt[id] = DateTime.now().millisecondsSinceEpoch;
    changes.value++;
  }

  static String apply(int id, String url) {
    final v = _replacedAt[id];
    if (v == null || url.isEmpty || url.startsWith('data:')) return url;
    return '$url${url.contains('?') ? '&' : '?'}v=$v';
  }
}

/// `fileUrl?view=tiny|small|large` (desktop's withView), cache-busted.
String mediaView(MediaLibraryItem item, String view) {
  final base = item.isImage && item.fileUrl.isNotEmpty
      ? '${item.fileUrl}${item.fileUrl.contains('?') ? '&' : '?'}view=$view'
      : item.previewUrl;
  return MediaCacheBust.apply(item.id, base);
}

Uint8List _decodeDataUrl(String image) {
  final comma = image.indexOf(',');
  final payload = image.startsWith('data:') && comma > 0 ? image.substring(comma + 1) : image;
  return base64Decode(payload);
}

dynamic _unwrapValue(dynamic res) => res is Map && res['value'] != null ? res['value'] : res;

class MediaStudioService {
  static const _templates = 'media_edit_templates';
  final ApiClient _client;
  MediaStudioService([ApiClient? client]) : _client = client ?? ApiClient();

  Future<StudioPreview> preview(int id, EditOps ops) async {
    final res = await _client.post('media/items/$id/edit/preview', {'ops': ops.toJson()}, timeout: studioPreviewTimeout);
    final body = _unwrapValue(res);
    final image = body is Map ? body['image'] : null;
    if (image is! String || image.isEmpty) throw Exception('Preview response had no image');
    return StudioPreview(
      bytes: _decodeDataUrl(image),
      width: int.tryParse('${body['width']}') ?? 0,
      height: int.tryParse('${body['height']}') ?? 0,
      hasAlpha: body['has_alpha'] == true,
    );
  }

  /// mode: 'copy' | 'replace'. Returns the saved item (the new copy, or the replaced original).
  Future<MediaLibraryItem?> save(int id, EditOps ops, String mode, {String? name}) async {
    final res = await _client.post(
      'media/items/$id/edit/save',
      {'ops': ops.toJson(), 'mode': mode, if (name != null && name.isNotEmpty) 'name': name},
      timeout: studioSaveTimeout,
    );
    dynamic row = res is Map ? (res['item'] ?? (res['value'] is Map ? (res['value']['item'] ?? res['value']) : null) ?? res) : null;
    if (row is! Map) return null;
    final item = MediaLibraryItem.fromJson(row.cast<String, dynamic>());
    if (mode == 'replace') MediaCacheBust.markReplaced(item.id == 0 ? id : item.id);
    return item;
  }

  /// Server-side sharp compression written over the original file (same
  /// format, so the URL never changes). Works on the saved image, not on
  /// unsaved studio edits.
  Future<CompressResult> compress(int id, int targetKb) async {
    final res = await _client.post('media/items/$id/compress', {'target_kb': targetKb}, timeout: studioSaveTimeout);
    final body = _unwrapValue(res);
    final map = body is Map ? body : const {};
    final rawItem = map['item'];
    final item = rawItem is Map ? MediaLibraryItem.fromJson(rawItem.cast<String, dynamic>()) : null;
    final compressed = map['compressed'] == true;
    if (compressed) MediaCacheBust.markReplaced(item?.id ?? id);
    return CompressResult(
      item: item,
      before: int.tryParse('${map['before_bytes']}') ?? 0,
      after: int.tryParse('${map['after_bytes']}') ?? 0,
      compressed: compressed,
    );
  }

  // ── Templates (OData `media_edit_templates`) ──

  Future<List<MediaEditTemplate>> loadTemplates() async {
    final res = await _client.get('$_templates?\$orderby=updated_at desc&\$top=200');
    return unwrapList(res)
        .whereType<Map>()
        .map((r) => MediaEditTemplate.fromJson(r.cast<String, dynamic>()))
        .where((t) => t.id >= 0)
        .toList();
  }

  Future<MediaEditTemplate> createTemplate({required String name, String? description, required EditOps ops}) async {
    final res = await _client.post(
      _templates,
      {
        'name': name.trim(),
        'description': (description ?? '').trim().isEmpty ? null : description!.trim(),
        'ops': templateOps(ops).toJson(),
        'preview_url': null,
      },
      isV8: true,
    );
    final row = _unwrapValue(res);
    return MediaEditTemplate.fromJson(row is Map ? row.cast<String, dynamic>() : {'name': name});
  }

  /// Returns the updated row, or null when the server didn't echo one back.
  Future<MediaEditTemplate?> updateTemplate(int id, {String? name, Object? description = const Object(), EditOps? ops}) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (description is String?) 'description': (description ?? '').trim().isEmpty ? null : description!.trim(),
      if (ops != null) 'ops': templateOps(ops).toJson(),
    };
    final res = await _client.put(_templates, id, body);
    final row = _unwrapValue(res);
    return row is Map && row['id'] != null ? MediaEditTemplate.fromJson(row.cast<String, dynamic>()) : null;
  }

  Future<void> deleteTemplate(int id) => _client.delete(_templates, id);
}

/// Workplace edit templates with load / rename / delete helpers (useTemplates.ts).
class TemplatesStore extends ChangeNotifier {
  final MediaStudioService _service;
  TemplatesStore([MediaStudioService? service]) : _service = service ?? MediaStudioService();

  List<MediaEditTemplate> templates = [];
  bool loading = false;
  bool loaded = false;
  String? error;
  int _seq = 0;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> ensureLoaded() async {
    if (!loaded && !loading) await reload();
  }

  Future<void> reload() async {
    final s = ++_seq;
    loading = true;
    error = null;
    _notify();
    try {
      final list = await _service.loadTemplates();
      if (s == _seq) templates = list;
    } catch (e) {
      if (s == _seq) error = describeStudioError(e, 'Could not load templates');
    } finally {
      if (s == _seq) {
        loading = false;
        loaded = true;
        _notify();
      }
    }
  }

  /// Inserts or replaces a template locally (newest first).
  void upsert(MediaEditTemplate t) {
    templates = [t, ...templates.where((x) => x.id != t.id)];
    _notify();
  }

  Future<void> rename(MediaEditTemplate t, String name, String description) async {
    final saved = await _service.updateTemplate(t.id, name: name, description: description);
    upsert(saved ??
        t.copyWith(name: name, description: description.isEmpty ? null : description, updatedAt: DateTime.now().toIso8601String()));
  }

  Future<void> remove(MediaEditTemplate t) async {
    await _service.deleteTemplate(t.id);
    templates = templates.where((x) => x.id != t.id).toList();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
