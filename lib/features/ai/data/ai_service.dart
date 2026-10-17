import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../../../core/network/http_client.dart';
import '../../../core/storage/app_storage.dart';
import 'ai_models.dart';

/// Mirrors erp/desktop's HeaderAiPopover.tsx — same backend (`cloud/src/
/// module/ai`), same streamed word-by-word answer + trailing JSON
/// (`rows`/`toolActions`) after a sentinel marker. Voice input/output and
/// the admin-only "Train the AI" flow are out of scope on mobile (a
/// deliberate simplification — chat is the core value; voice would need two
/// more native plugins, and training is a dev/admin tool gated behind a
/// backend env flag most workplaces don't have on anyway).
class AiService {
  // Must match STREAM_DATA_SENTINEL in cloud/src/module/ai/ai.controller.ts
  // and erp/desktop's HeaderAiPopover.tsx exactly.
  static const _sentinel = '\n␞AI_DATA␞\n';

  final ApiClient _client;
  AiService(this._client);

  /// Streams the assistant's reply, calling [onTextUpdate] with the
  /// cumulative text after every chunk (same "replace the last bubble"
  /// approach as desktop, not an append-only diff). Resolves once the
  /// stream ends, with the final text plus any structured `rows`/
  /// `toolActions` trailer.
  Future<AiStreamResult> askStream({
    required String question,
    int? sessionId,
    required void Function(String text) onTextUpdate,
  }) async {
    final token = await AppStorage.getToken();
    final request = http.Request('POST', Uri.parse('${AppConfig.apiPrefix}ai/ask/stream'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'question': question, if (sessionId != null) 'session_id': sessionId});
    if (token != null && token.isNotEmpty) request.headers['authorization'] = token;

    final streamed = await http.Client().send(request).timeout(const Duration(seconds: 90));
    if (streamed.statusCode >= 400) {
      final body = await streamed.stream.bytesToString();
      var message = 'AI request failed.';
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['error'] is String) message = decoded['error'] as String;
      } catch (_) {
        // non-JSON error body — keep the generic fallback
      }
      throw ApiException(streamed.statusCode, message);
    }

    final newSessionId = int.tryParse(streamed.headers['x-ai-session-id'] ?? '') ?? sessionId ?? 0;

    var buffer = '';
    var full = '';
    var dataText = '';
    var sentinelHit = false;
    await for (final chunk in streamed.stream.transform(utf8.decoder)) {
      if (!sentinelHit) {
        buffer += chunk;
        final idx = buffer.indexOf(_sentinel);
        if (idx == -1) {
          full = buffer;
        } else {
          full = buffer.substring(0, idx);
          dataText = buffer.substring(idx + _sentinel.length);
          sentinelHit = true;
        }
        onTextUpdate(full);
      } else {
        dataText += chunk;
      }
    }

    var rows = <Map<String, dynamic>>[];
    var toolActions = <Map<String, dynamic>>[];
    if (dataText.isNotEmpty) {
      try {
        final decoded = jsonDecode(dataText);
        if (decoded is Map) {
          rows = ((decoded['rows'] as List?) ?? const []).cast<Map<String, dynamic>>();
          toolActions = ((decoded['toolActions'] as List?) ?? const []).cast<Map<String, dynamic>>();
        }
      } catch (_) {
        // malformed trailer — surface the text-only answer
      }
    }

    return AiStreamResult(sessionId: newSessionId, fullText: full, rows: rows, toolActions: toolActions);
  }

  Future<List<AiSession>> loadSessions(int userId) async {
    final res = await _client.get('ai_sessions?\$select=id,title,created_at,updated_at&\$filter=user_id eq $userId&\$orderby=updated_at desc');
    return unwrapList(res).cast<Map<String, dynamic>>().map(AiSession.fromJson).toList();
  }

  Future<List<AiChatMessage>> loadSessionHistory(int sessionId) async {
    final res = await _client.get('ai_chat_histories?\$select=role,content&\$filter=session_id eq $sessionId&\$orderby=created_at asc');
    return unwrapList(res).cast<Map<String, dynamic>>().map(AiChatMessage.fromHistoryRow).toList();
  }

  Future<void> deleteSession(int id) async {
    await _client.delete('ai/sessions', id, isV8: false);
  }
}
