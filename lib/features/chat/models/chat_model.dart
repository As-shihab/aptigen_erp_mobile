import 'dart:convert';

int toNum(dynamic value) {
  final parsed = num.tryParse(value?.toString() ?? '');
  return parsed?.toInt() ?? 0;
}

enum ChatRoomType { group, direct, channel }

enum ChatRoomVisibility { public, private }

String chatRoomTypeToValue(ChatRoomType type) {
  switch (type) {
    case ChatRoomType.direct:
      return 'single';
    case ChatRoomType.channel:
      return 'channel';
    case ChatRoomType.group:
      return 'group';
  }
}

String chatRoomVisibilityToValue(ChatRoomVisibility visibility) =>
    visibility == ChatRoomVisibility.public ? 'public' : 'private';

ChatRoomVisibility parseChatRoomVisibility(dynamic value) {
  final normalized = (value ?? '').toString().trim().toLowerCase();
  return normalized == 'public' ? ChatRoomVisibility.public : ChatRoomVisibility.private;
}

/// chat_messages has no dedicated attachment column — an attachment rides as
/// its own message row: `message` holds this JSON and `message_type` is
/// 'image'/'file' (mirrors erp/desktop's chat.data.ts convention).
class ChatAttachmentMeta {
  final String url;
  final String name;
  final String? mime;
  final int? size;
  const ChatAttachmentMeta({required this.url, required this.name, this.mime, this.size});

  Map<String, dynamic> toJson() => {'url': url, 'name': name, if (mime != null) 'mime': mime, if (size != null) 'size': size};

  static ChatAttachmentMeta? tryParse(String raw) {
    if (raw.isEmpty || !raw.startsWith('{')) return null;
    try {
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      if (parsed['url'] == null) return null;
      return ChatAttachmentMeta(
        url: parsed['url'].toString(),
        name: (parsed['name'] ?? 'Attachment').toString(),
        mime: parsed['mime']?.toString(),
        size: parsed['size'] != null ? toNum(parsed['size']) : null,
      );
    } catch (_) {
      return null;
    }
  }
}

typedef ChatMeetingMode = String; // 'video' | 'voice'
