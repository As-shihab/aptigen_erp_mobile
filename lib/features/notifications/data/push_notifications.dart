import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../../app/app.dart';
import '../../../core/device/device_identity.dart';
import '../../../core/network/http_client.dart';
import '../../sell/market/presentation/messages/chat_page.dart';
import '../../sell/market/presentation/orders_page.dart';
import '../presentation/notifications_page.dart';

/// FCM push for every notification the backend creates — cloud's
/// deliverNotifications() (src/module/notifications/push.ts) sends one push
/// per row to each device registered here via `/api/notifications/push-token`.
///
/// App in background/killed → the OS shows the push itself.
/// App in foreground → Android hands it to [FirebaseMessaging.onMessage]
/// without showing anything, so it's shown via flutter_local_notifications;
/// iOS shows it itself (setForegroundNotificationPresentationOptions).
///
/// Needs android/app/google-services.json + ios/Runner/GoogleService-Info.plist;
/// without them [init] logs once and push stays off.
class PushNotifications {
  static const _channelId = 'aptigen_notifications';
  static const _channel = AndroidNotificationChannel(
    _channelId,
    'Notifications',
    description: 'Aptigen ERP workplace notifications',
    importance: Importance.high,
  );

  static final _local = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Foreground pushes, as `notification:created`-shaped maps (title, body,
  /// workplace_id, module_id) — HomeShellPage bumps its badges from these.
  static final List<void Function(Map<String, dynamic>)> _listeners = [];
  static void addListener(void Function(Map<String, dynamic>) fn) => _listeners.add(fn);
  static void removeListener(void Function(Map<String, dynamic>) fn) => _listeners.remove(fn);

  /// Call after login (HomeShellPage) — safe to call repeatedly; re-registers
  /// the token each time so a workplace switch moves it server-side.
  static Future<void> init() async {
    try {
      if (!_ready) {
        await Firebase.initializeApp();
        await _local.initialize(
          const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false,
            ),
          ),
          onDidReceiveNotificationResponse: (r) => _openForLink(r.payload),
        );
        await _local
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(_channel);

        final messaging = FirebaseMessaging.instance;
        await messaging.requestPermission();
        await messaging.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

        FirebaseMessaging.onMessage.listen(_onForegroundMessage);
        FirebaseMessaging.onMessageOpenedApp.listen((m) => _openForLink(m.data['link']?.toString()));
        messaging.onTokenRefresh.listen(_register);

        // Cold start from a tapped push.
        final initial = await messaging.getInitialMessage();
        if (initial != null) _openForLink(initial.data['link']?.toString());
        _ready = true;
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _register(token);
    } catch (e) {
      debugPrint('[push] disabled: $e');
    }
  }

  /// Call before the session is cleared — the remove route needs the auth token.
  static Future<void> unregister() async {
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await ApiClient().post('notifications/push-token/remove', {'token': token}, timeout: const Duration(seconds: 5));
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  static Future<void> clearTray() async {
    try {
      await _local.cancelAll();
    } catch (_) {}
  }

  static Future<void> _register(String token) async {
    try {
      await ApiClient().post('notifications/push-token', {
        'token': token,
        'platform': DeviceIdentity.platform,
        'device_id': await DeviceIdentity.id(),
      });
    } catch (_) {}
  }

  static void _onForegroundMessage(RemoteMessage message) {
    final data = message.data;
    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    final payload = <String, dynamic>{
      'id': int.tryParse(data['notification_id'] ?? ''),
      'title': title,
      'body': body,
      'workplace_id': int.tryParse(data['workplace_id'] ?? ''),
      'module_id': int.tryParse(data['module_id'] ?? ''),
    };
    for (final fn in List.of(_listeners)) {
      fn(payload);
    }

    if (!Platform.isAndroid || title.isEmpty) return;
    _local.show(
      payload['id'] as int? ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: data['link']?.toString(),
    );
  }

  /// A tapped push: `market_message` pushes (link `/sell/online/messages?c=<id>`)
  /// open that buyer chat, website order pushes (link
  /// `/sell/online/market/orders?order=<id>`) open that order; everything
  /// else opens the notifications list.
  static void _openForLink(String? link) {
    final chatId = marketChatIdFromLink(link);
    final order = marketOrderFromLink(link);
    if (chatId != null) {
      openMarketChatFromAnywhere(chatId);
    } else if (order.isOrders) {
      openMarketOrdersFromAnywhere(orderId: order.orderId);
    } else {
      _openNotificationsPage();
    }
  }

  static void _openNotificationsPage() {
    navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const NotificationsPage()));
  }
}
