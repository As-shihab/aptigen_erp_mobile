import '../../../core/network/http_client.dart';
import '../models/notification_model.dart';

class NotificationsResult {
  final List<AppNotification> rows;
  final int unreadCount;
  const NotificationsResult({required this.rows, required this.unreadCount});
}

/// Mirrors erp/desktop's AppHeaderBar.tsx notification calls — same
/// `/api/notifications` custom (non-OData) routes, own-user/own-workplace
/// scoped server-side (notifications.controller.ts derives both from the
/// auth token, never from a query param), so nothing extra to pass here.
class NotificationsService {
  final ApiClient _client;
  NotificationsService(this._client);

  Future<NotificationsResult> list({bool unreadOnly = false, int top = 30, int skip = 0}) async {
    final query = {
      if (unreadOnly) 'unread': 'true',
      'top': '$top',
      'skip': '$skip',
    };
    final qs = query.entries.map((e) => '${e.key}=${e.value}').join('&');
    final res = await _client.get('notifications?$qs', isV8: false);
    final rows = (res is Map<String, dynamic> && res['rows'] is List)
        ? (res['rows'] as List).cast<Map<String, dynamic>>().map(AppNotification.fromJson).toList()
        : <AppNotification>[];
    final unreadCount = _toInt(res is Map<String, dynamic> ? res['unreadCount'] : null);
    return NotificationsResult(rows: rows, unreadCount: unreadCount);
  }

  Future<void> markRead(int id) => _client.post('notifications/$id/read', {}, isV8: false);

  Future<void> markAllRead() => _client.post('notifications/read-all', {}, isV8: false);
}

int _toInt(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;
