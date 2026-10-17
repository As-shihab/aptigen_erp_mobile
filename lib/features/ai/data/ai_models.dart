import '../../store/data/store_util.dart';

class AiSession {
  final int id;
  final String? title;
  final String updatedAt;
  const AiSession({required this.id, this.title, required this.updatedAt});

  factory AiSession.fromJson(Map json) => AiSession(
        id: toNum(json['id']),
        title: toStringOrNull(json['title']),
        updatedAt: (json['updated_at'] ?? '').toString(),
      );
}

/// One turn in the chat — mutable `text`/`rows` so the streaming UI can keep
/// patching the same in-place bubble as words arrive, mirroring desktop's
/// `setMessages(prev => { next[next.length-1] = {...} })` pattern.
class AiChatMessage {
  final String role; // 'user' | 'ai'
  String text;
  List<Map<String, dynamic>> rows;
  AiChatMessage({required this.role, required this.text, this.rows = const []});

  factory AiChatMessage.fromHistoryRow(Map json) => AiChatMessage(
        role: json['role'] == 'user' ? 'user' : 'ai',
        text: (json['content'] ?? '').toString(),
      );
}

class AiStreamResult {
  final int sessionId;
  final String fullText;
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> toolActions;
  const AiStreamResult({required this.sessionId, required this.fullText, this.rows = const [], this.toolActions = const []});
}
