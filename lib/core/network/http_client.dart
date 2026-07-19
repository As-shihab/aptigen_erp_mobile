import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../storage/app_storage.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class BatchRequest {
  final String id;
  final String method;
  final String url;
  final Map<String, dynamic>? body;
  BatchRequest({required this.id, required this.method, required this.url, this.body});

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'url': url,
        if (body != null) 'body': body,
      };
}

/// Centralized HTTP client — mirrors erp/desktop's HttpClient:
/// `/aptigen/` (OData, isV8=true) vs `/api/` (isV8=false), same header/token
/// convention, and the same `{value: [...], "@count": N}` response shape
/// (the backend's odata.service.ts returns `@count`, not `@odata.count`
/// despite that being the more common OData convention name).
class ApiClient {
  static const Duration _timeout = Duration(seconds: 15);

  /// Optional hook wired up once at app start so any 401 can force a
  /// session clear + redirect to the welcome screen, matching desktop's
  /// centralized handleUnauthorized().
  static Future<void> Function()? onUnauthorized;

  Uri _uri(String endpoint, bool isV8) {
    final base = isV8 ? AppConfig.v8Base : AppConfig.apiPrefix;
    final normalizedEndpoint = endpoint.replaceFirst(RegExp(r'^/+'), '');
    return Uri.parse('$base$normalizedEndpoint');
  }

  Future<Map<String, String>> _headers() async {
    final token = await AppStorage.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'authorization': token,
    };
  }

  Future<dynamic> _parse(http.Response res, {String? endpoint}) async {
    if (res.statusCode == 401) {
      if (endpoint != 'auth/login' && onUnauthorized != null) {
        await onUnauthorized!();
      }
      throw ApiException(401, 'Unauthorized');
    }
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, 'Request failed (${res.statusCode}): ${res.body}');
    }
    if (res.body.isEmpty) return null;
    try {
      return jsonDecode(res.body);
    } catch (_) {
      return res.body;
    }
  }

  Future<dynamic> get(String endpoint, {bool isV8 = true}) async {
    final res = await http
        .get(_uri(endpoint, isV8), headers: await _headers())
        .timeout(_timeout);
    return _parse(res, endpoint: endpoint);
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> body, {bool isV8 = false}) async {
    final res = await http
        .post(_uri(endpoint, isV8), headers: await _headers(), body: jsonEncode(body))
        .timeout(_timeout);
    return _parse(res, endpoint: endpoint);
  }

  Future<dynamic> put(String endpoint, Object id, Map<String, dynamic> body, {bool isV8 = true}) async {
    final fullEndpoint = isV8 ? '$endpoint($id)' : '$endpoint/$id';
    final res = await http
        .put(_uri(fullEndpoint, isV8), headers: await _headers(), body: jsonEncode(body))
        .timeout(_timeout);
    return _parse(res, endpoint: fullEndpoint);
  }

  Future<dynamic> delete(String endpoint, Object id, {bool isV8 = true}) async {
    final fullEndpoint = isV8 ? '$endpoint($id)' : '$endpoint/$id';
    final res = await http
        .delete(_uri(fullEndpoint, isV8), headers: await _headers())
        .timeout(_timeout);
    return _parse(res, endpoint: fullEndpoint);
  }

  /// Multipart upload — mirrors erp/desktop's media-library.store.ts
  /// `addMediaFiles` (POST /api/media/upload, field name `media`).
  /// `useSharp` mirrors desktop's `{ useSharp: true }` upload option —
  /// sent as the `x-media-use-sharp` header the backend's media service reads.
  Future<dynamic> uploadFile(
    String endpoint, {
    required List<int> bytes,
    required String filename,
    Map<String, String> fields = const {},
    String fileFieldName = 'media',
    bool isV8 = false,
    bool useSharp = true,
  }) async {
    final uri = _uri(endpoint, isV8);
    final token = await AppStorage.getToken();
    final request = http.MultipartRequest('POST', uri)
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes(fileFieldName, bytes, filename: filename));
    if (token != null && token.isNotEmpty) request.headers['authorization'] = token;
    request.headers['x-media-use-sharp'] = useSharp.toString();

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final res = await http.Response.fromStream(streamed);
    return _parse(res, endpoint: endpoint);
  }

  /// One round-trip for multiple independent OData GETs — mirrors the
  /// desktop app's `http.batch()` convention (POST /aptigen/$batch).
  Future<dynamic> batch(List<BatchRequest> requests, {bool isV8 = true}) async {
    final res = await http
        .post(
          _uri(r'$batch', isV8),
          headers: await _headers(),
          body: jsonEncode({'requests': requests.map((r) => r.toJson()).toList()}),
        )
        .timeout(_timeout);
    return _parse(res);
  }
}

/// `{value: [...]}` / bare-array unwrap, matching desktop's parseRows().
List<dynamic> unwrapList(dynamic body) {
  if (body is List) return body;
  if (body is Map<String, dynamic>) {
    final value = body['value'];
    if (value is List) return value;
  }
  return const [];
}

/// Pulls a single response's body out of a `$batch` result by request id.
Map<String, dynamic>? unwrapBatchBody(dynamic batchResult, String requestId) {
  if (batchResult is! Map<String, dynamic>) return null;
  final responses = batchResult['responses'];
  if (responses is! List) return null;
  for (final entry in responses) {
    if (entry is Map<String, dynamic> && entry['id'].toString() == requestId) {
      final body = entry['body'];
      return body is Map<String, dynamic> ? body : null;
    }
  }
  return null;
}
