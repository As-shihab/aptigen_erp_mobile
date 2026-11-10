import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/network/socket_client.dart';

// Seller inbox for buyer ↔ seller market chat — same custom /api routes as
// erp/desktop's Sell → Online → Market → Messages (cloud
// market-messages.service.ts). Responses are plain JSON, not OData-wrapped.

int _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _toDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

const kMarketMessageMaxLength = 2000;
const kMarketMessageNotificationType = 'market_message';

class MarketChatPerson {
  final int id;
  final String? name;
  final String? avatarUrl;
  const MarketChatPerson({required this.id, this.name, this.avatarUrl});

  String get displayName => (name ?? '').trim().isEmpty ? 'Buyer' : name!.trim();

  factory MarketChatPerson.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    return MarketChatPerson(id: _toInt(m['id']), name: m['name']?.toString(), avatarUrl: m['avatar_url']?.toString());
  }
}

class MarketChatListing {
  final int id;
  final String title;
  final String? thumbnailUrl;
  final double? price;
  final String? currency;
  const MarketChatListing({required this.id, required this.title, this.thumbnailUrl, this.price, this.currency});

  static MarketChatListing? fromJson(dynamic json) {
    if (json is! Map) return null;
    return MarketChatListing(
      id: _toInt(json['id']),
      title: (json['title'] ?? '').toString(),
      thumbnailUrl: json['thumbnail_url']?.toString(),
      price: json['price'] == null ? null : _toDouble(json['price']),
      currency: json['currency']?.toString(),
    );
  }
}

class MarketConversation {
  final int id;
  final MarketChatPerson buyer;
  final MarketChatListing? listing;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unread;
  const MarketConversation({required this.id, required this.buyer, this.listing, this.lastMessage, this.lastMessageAt, this.unread = 0});

  factory MarketConversation.fromJson(Map json) => MarketConversation(
        id: _toInt(json['id']),
        buyer: MarketChatPerson.fromJson(json['buyer']),
        listing: MarketChatListing.fromJson(json['listing']),
        lastMessage: json['last_message']?.toString(),
        lastMessageAt: parseChatTime(json['last_message_at']),
        unread: _toInt(json['unread']),
      );

  MarketConversation copyWith({String? lastMessage, DateTime? lastMessageAt, int? unread}) => MarketConversation(
        id: id,
        buyer: buyer,
        listing: listing,
        lastMessage: lastMessage ?? this.lastMessage,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        unread: unread ?? this.unread,
      );
}

// ── Attachments ──────────────────────────────────────────────────────────
// Same limits as cloud market-messages.controller.ts (POST :id/files).

const kMarketAttachmentMax = 6;
const kMarketAttachmentMaxBytes = 25 * 1024 * 1024;

/// Extension → content type for chat uploads. Images and videos are always
/// allowed; anything else must be one of the document types the server takes.
const kMarketAttachmentDocMime = <String, String>{
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'zip': 'application/zip',
  'rar': 'application/vnd.rar',
};

const _mediaMime = <String, String>{
  'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp',
  'heic': 'image/heic', 'heif': 'image/heif', 'bmp': 'image/bmp', 'avif': 'image/avif',
  'mp4': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm', 'm4v': 'video/x-m4v', '3gp': 'video/3gpp',
  'mkv': 'video/x-matroska', 'avi': 'video/x-msvideo',
};

String fileExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// Best-effort content type from [name], falling back to a concrete [hint]
/// (e.g. XFile.mimeType) when the extension is unknown.
String attachmentMime(String name, [String? hint]) {
  final ext = fileExtension(name);
  final fallback = hint != null && hint.contains('/') ? hint : 'application/octet-stream';
  return _mediaMime[ext] ?? kMarketAttachmentDocMime[ext] ?? fallback;
}

String attachmentKind(String mime) {
  if (mime.startsWith('image/')) return 'image';
  if (mime.startsWith('video/')) return 'video';
  if (mime == 'application/octet-stream') return 'other';
  return 'document';
}

/// Whether the server will accept a file with this name / content type.
bool isAllowedAttachment(String name, String mime) =>
    mime.startsWith('image/') || mime.startsWith('video/') || kMarketAttachmentDocMime.containsKey(fileExtension(name));

class MarketAttachment {
  final int? mediaId;
  final String? url;
  final String? previewUrl;
  final String name;
  final String mime;
  final String kind; // image | video | document | other
  final int size;

  /// Device path for optimistic (not yet uploaded) attachments.
  final String? localPath;
  const MarketAttachment({this.mediaId, this.url, this.previewUrl, required this.name, required this.mime, required this.kind, this.size = 0, this.localPath});

  bool get isImage => kind == 'image';
  bool get isVideo => kind == 'video';

  static MarketAttachment? fromJson(dynamic json) {
    if (json is! Map) return null;
    final name = (json['name'] ?? '').toString();
    final mime = (json['mime'] ?? '').toString();
    final kind = (json['kind'] ?? '').toString();
    return MarketAttachment(
      mediaId: json['media_id'] == null ? null : _toInt(json['media_id']),
      url: json['url']?.toString(),
      previewUrl: json['preview_url']?.toString(),
      name: name.isEmpty ? 'File' : name,
      mime: mime,
      kind: kind.isEmpty ? attachmentKind(mime) : kind,
      size: _toInt(json['size']),
    );
  }

  static List<MarketAttachment> listFrom(dynamic json) =>
      json is List ? json.map(MarketAttachment.fromJson).whereType<MarketAttachment>().toList() : const [];
}

/// A picked file waiting to be sent (kept for retries).
class MarketOutgoingFile {
  final String path;
  final String name;
  final int size;
  final String mime;
  const MarketOutgoingFile({required this.path, required this.name, required this.size, required this.mime});

  String get kind => attachmentKind(mime);

  MarketAttachment toAttachment() => MarketAttachment(name: name, mime: mime, kind: kind, size: size, localPath: path);
}

class MarketMessage {
  /// Server id (int) or a client-only temp id (`tmp-…`) for optimistic sends.
  final Object id;
  final int conversationId;
  final int senderId;
  final bool fromSeller;
  final String body;
  final MarketChatListing? listing;
  final DateTime createdAt;
  final List<MarketAttachment> attachments;
  final bool pending;
  final bool failed;

  /// Upload progress 0–1 for optimistic attachment sends.
  final double progress;
  const MarketMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.fromSeller,
    required this.body,
    this.listing,
    required this.createdAt,
    this.attachments = const [],
    this.pending = false,
    this.failed = false,
    this.progress = 0,
  });

  bool get isTemp => id is String;

  /// Inbox row text — the body, else "Sent a photo" etc. (server's preview()).
  String get previewText {
    if (body.isNotEmpty || attachments.isEmpty) return body;
    if (attachments.length > 1) return 'Sent ${attachments.length} files';
    final kind = attachments.first.kind;
    return kind == 'image' ? 'Sent a photo' : (kind == 'video' ? 'Sent a video' : 'Sent a file');
  }

  factory MarketMessage.fromJson(Map json) => MarketMessage(
        id: _toInt(json['id']),
        conversationId: _toInt(json['conversation_id']),
        senderId: _toInt(json['sender_id']),
        fromSeller: json['side'] == 'seller',
        body: (json['body'] ?? '').toString(),
        listing: MarketChatListing.fromJson(json['listing']),
        createdAt: parseChatTime(json['created_at']) ?? DateTime.now(),
        attachments: MarketAttachment.listFrom(json['attachments']),
      );

  MarketMessage copyWith({bool? pending, bool? failed, double? progress}) => MarketMessage(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        fromSeller: fromSeller,
        body: body,
        listing: listing,
        createdAt: createdAt,
        attachments: attachments,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
        progress: progress ?? this.progress,
      );
}

DateTime? parseChatTime(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

class MarketThread {
  final int id;
  final MarketChatPerson buyer;
  final MarketChatListing? listing;
  final List<MarketMessage> messages;
  final bool hasMore;

  /// When the buyer last opened the chat — seller messages up to here are "Seen".
  final DateTime? buyerReadAt;
  const MarketThread({required this.id, required this.buyer, this.listing, required this.messages, required this.hasMore, this.buyerReadAt});
}

class MarketMessagesService {
  MarketMessagesService([ApiClient? client]) : _http = client ?? ApiClient();
  final ApiClient _http;

  static List<Map> _list(dynamic res) {
    final list = res is List ? res : (res is Map ? (res['value'] ?? res['data'] ?? const []) : const []);
    return list is List ? list.whereType<Map>().toList() : const [];
  }

  /// Newest first, for the caller's active workplace.
  Future<List<MarketConversation>> conversations() async =>
      _list(await _http.get('market/seller-messages', isV8: false)).map(MarketConversation.fromJson).toList();

  Future<int> unreadCount() async {
    final res = await _http.get('market/seller-messages/unread', isV8: false);
    if (res is! Map) return 0;
    final v = res['count'] ?? (res['value'] is Map ? res['value']['count'] : null);
    return _toInt(v).clamp(0, 1 << 30);
  }

  /// Oldest first, 40 per page. Opening marks the seller side read.
  Future<MarketThread> thread(int id, {int? before}) async {
    final res = await _http.get('market/seller-messages/$id${before != null ? '?before=$before' : ''}', isV8: false);
    final m = res is Map ? res : const {};
    final conv = m['conversation'] is Map ? m['conversation'] as Map : const {};
    return MarketThread(
      id: _toInt(conv['id'] ?? id),
      buyer: MarketChatPerson.fromJson(conv['buyer']),
      listing: MarketChatListing.fromJson(conv['listing']),
      messages: _list(m['messages']).map(MarketMessage.fromJson).toList(),
      hasMore: m['has_more'] == true,
      buyerReadAt: parseChatTime(conv['buyer_read_at']),
    );
  }

  Future<MarketMessage?> send(int id, String body) async {
    final res = await _http.post('market/seller-messages/$id', {'body': body}, isV8: false);
    final row = res is Map && res['value'] is Map ? res['value'] as Map : res;
    return row is Map && row['id'] != null ? MarketMessage.fromJson(row) : null;
  }

  /// Multipart send of up to [kMarketAttachmentMax] files plus optional text.
  /// The server also files them into the store's media library (category
  /// "B2B"). [onProgress] reports 0–1 of the request body sent.
  Future<MarketMessage?> sendFiles(int id, List<MarketOutgoingFile> files, {String body = '', void Function(double)? onProgress}) async {
    final parts = <http.MultipartFile>[
      for (final f in files) await http.MultipartFile.fromPath('files', f.path, filename: f.name, contentType: MediaType.parse(f.mime)),
    ];
    final res = await _http.uploadMultipart(
      'market/seller-messages/$id/files',
      files: parts,
      fields: {if (body.isNotEmpty) 'body': body},
      timeout: const Duration(minutes: 10),
      onProgress: onProgress == null ? null : (sent, total) => onProgress(total <= 0 ? 0 : (sent / total).clamp(0, 1).toDouble()),
    );
    final row = res is Map && res['value'] is Map ? res['value'] as Map : res;
    return row is Map && row['id'] != null ? MarketMessage.fromJson(row) : null;
  }

  /// Clears the bell's "new message" notifications (same as desktop's
  /// markNotificationTypesRead) — best effort.
  Future<bool> markNotificationsRead() async {
    try {
      final res = await _http.post('notifications/read-by-type', {
        'types': [kMarketMessageNotificationType],
      }, isV8: false);
      return res is Map && _toInt(res['count']) > 0;
    } catch (_) {
      return false;
    }
  }
}

/// Total unread buyer messages across the workplace's market conversations —
/// drives the badge on the market hub's Messages tile (desktop's
/// useSellerMessagesUnread). [attach] while a screen shows the badge: it
/// refetches now, on app resume and (debounced) on any `market:message` /
/// `market:message-read` socket event.
class SellerMessagesUnread {
  SellerMessagesUnread._();

  static final ValueNotifier<int> count = ValueNotifier(0);
  static final _service = MarketMessagesService();
  static int _attached = 0;
  static Timer? _debounce;
  static VoidCallback? _offMessage;
  static VoidCallback? _offRead;
  static AppLifecycleListener? _lifecycle;

  static Future<void> refresh() async {
    try {
      count.value = await _service.unreadCount();
    } catch (_) {
      // keep the last count — a failed refresh shouldn't hide the badge
    }
  }

  static void _schedule([dynamic _]) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), refresh);
  }

  static VoidCallback attach() {
    _attached++;
    if (_attached == 1) {
      _offMessage = AppSocket.subscribe('market:message', _schedule);
      _offRead = AppSocket.subscribe('market:message-read', _schedule);
      _lifecycle = AppLifecycleListener(onResume: refresh);
    }
    refresh();
    var detached = false;
    return () {
      if (detached) return;
      detached = true;
      _attached--;
      if (_attached == 0) {
        _offMessage?.call();
        _offRead?.call();
        _lifecycle?.dispose();
        _debounce?.cancel();
        _offMessage = _offRead = null;
        _lifecycle = null;
      }
    };
  }
}
