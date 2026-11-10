import 'package:flutter/foundation.dart';
import '../../../core/network/http_client.dart';

/// Unread notification count per module id (`notifications.module_id`) for
/// the current user in the active workplace — drives the badges on the home
/// launcher tiles. Mirrors erp/desktop's useModuleUnreadCounts.ts:
///  - load: GET /api/notifications/unread-by-module → `{"3": 5, "12": 1}`
///    (zero-count modules omitted, scoped server-side)
///  - live: [onCreated] bumps the payload's module on each foreground FCM
///    push (fed from HomeShellPage's PushNotifications listener)
///  - refetch: after mark read / mark all read (NotificationsService calls
///    [refresh] on success), home pull-to-refresh, returning to Home.
class ModuleUnreadCounts {
  ModuleUnreadCounts._();

  static final ValueNotifier<Map<int, int>> counts = ValueNotifier(const {});

  static int _generation = 0;

  static Future<void> refresh() async {
    final generation = ++_generation;
    try {
      final res = await ApiClient().get('notifications/unread-by-module', isV8: false);
      if (generation != _generation) return; // a newer refresh superseded us
      final source = res is Map ? (res['value'] is Map ? res['value'] as Map : res) : const {};
      final next = <int, int>{};
      source.forEach((key, value) {
        final id = int.tryParse(key.toString()) ?? 0;
        final count = int.tryParse(value?.toString() ?? '') ?? 0;
        if (id > 0 && count > 0) next[id] = count;
      });
      counts.value = Map.unmodifiable(next);
    } catch (_) {
      // Route missing (older backend) or offline — just keep what we had
      // (empty on first load, so no badges show).
    }
  }

  /// `notification:created`-shaped payload (see PushNotifications). Buyer (public-site)
  /// notifications carry no workplace — never ERP badges.
  static void onCreated(dynamic payload) {
    if (payload is! Map) return;
    if (payload['workplace_id'] == null || payload['is_read'] == true) return;
    final moduleId = int.tryParse(payload['module_id']?.toString() ?? '') ?? 0;
    if (moduleId <= 0) return;
    final next = Map<int, int>.from(counts.value);
    next[moduleId] = (next[moduleId] ?? 0) + 1;
    counts.value = Map.unmodifiable(next);
  }

  /// Logout / workplace switch.
  static void clear() {
    _generation++;
    counts.value = const {};
  }
}

String formatBadgeCount(int count) => count > 99 ? '99+' : '$count';
