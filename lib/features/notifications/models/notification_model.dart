import '../../../core/config/app_config.dart';

// The API returns media as relative paths (e.g. `/public/uploads/x.jpg`),
// not absolute URLs — same per-file convention as stay_model.dart's
// `_resolveMediaUrl` / media_library_item.dart's `_toAbsUrl` (mirrors
// erp/desktop's LazyImage.tsx `resolveMediaUrl`).
String? _resolveMediaUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http') || url.startsWith('data:')) return url;
  return '${AppConfig.apiBase}${url.startsWith('/') ? '' : '/'}$url';
}

int _toInt(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;

/// Mirrors cloud/src/module/notifications' response shape — one row per
/// recipient, already permission-filtered server-side (notifyWorkplace()),
/// so nothing here needs its own visibility check. Same fields
/// erp/desktop's AppHeaderBar.tsx maps (mapNotificationRow), including the
/// `actor` (whoever triggered the notification, not the viewer) added
/// alongside the actor-avatar feature there.
class AppNotification {
  final int id;
  final String title;
  final String? body;
  final String? link;
  final bool isRead;
  final DateTime createdAt;
  final String? moduleName;
  final String? actorName;
  final String? actorAvatarUrl;

  const AppNotification({
    required this.id,
    required this.title,
    this.body,
    this.link,
    required this.isRead,
    required this.createdAt,
    this.moduleName,
    this.actorName,
    this.actorAvatarUrl,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final module = json['module'] as Map?;
    final actor = json['actor'] as Map?;
    return AppNotification(
      id: _toInt(json['id']),
      title: (json['title'] ?? '').toString(),
      body: json['body']?.toString(),
      link: json['link']?.toString(),
      isRead: json['is_read'] == true,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString())?.toLocal() ?? DateTime.now(),
      moduleName: module?['name']?.toString(),
      actorName: actor?['name']?.toString(),
      actorAvatarUrl: _resolveMediaUrl(actor?['image_url']?.toString()),
    );
  }

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        title: title,
        body: body,
        link: link,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
        moduleName: moduleName,
        actorName: actorName,
        actorAvatarUrl: actorAvatarUrl,
      );
}
