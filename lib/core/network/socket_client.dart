import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import '../billing/paywall_state.dart';
import '../config/app_config.dart';
import '../storage/app_storage.dart';
import 'http_client.dart';

class SocketContext {
  final int workplaceId;
  final int memberId;
  final int userId;
  const SocketContext({required this.workplaceId, required this.memberId, required this.userId});
}

/// Resolves the {workplaceId, memberId, userId} triple the backend's
/// ChatGateway expects in the socket handshake `auth` payload to auto-join
/// the `workplace:{id}` room (see chat.gateway.ts's bindPresence) — mirrors
/// erp/desktop's resolveChatContext.
Future<SocketContext?> resolveSocketContext(ApiClient client) async {
  final storedUser = await AppStorage.getUser();
  if (storedUser == null) return null;

  final userId = int.tryParse((storedUser['id'] ?? '').toString()) ?? 0;
  final workplaceMap = (storedUser['selectedWorkplace'] ?? storedUser['workplace']) as Map?;
  final workplaceId = int.tryParse((workplaceMap?['id'] ?? '').toString()) ?? 0;
  if (userId == 0 || workplaceId == 0) return null;

  final data = await client.get('workplace_members?\$filter=workplace_id eq $workplaceId and user_id eq $userId&\$top=1');
  final rows = unwrapList(data);
  if (rows.isEmpty) return null;
  final memberId = int.tryParse(((rows.first as Map)['id'] ?? '').toString()) ?? 0;
  if (memberId == 0) return null;

  return SocketContext(workplaceId: workplaceId, memberId: memberId, userId: userId);
}

/// Thin wrapper over socket_io_client — same bare-origin / default-namespace
/// / handshake-auth convention as erp/desktop's socket/client.ts + chat.socket.ts.
/// One shared connection for the whole app (attendance today, more events later).
class AppSocket {
  static sio.Socket? _socket;

  /// Reflects live connect/disconnect state — the app header's Wi-Fi
  /// indicator listens to this (matches desktop AppHeaderBar.tsx's
  /// `isSocketConnected`-driven Wifi icon color).
  static final ValueNotifier<bool> isConnected = ValueNotifier(false);

  static SocketContext? _context;

  static sio.Socket connect(SocketContext context) {
    final existing = _socket;
    final sameScope = _context?.workplaceId == context.workplaceId && _context?.userId == context.userId;
    // Reuse only for the same user + workplace — after logout and signing
    // into another workplace the old socket would otherwise keep receiving
    // the previous workplace's room events (e.g. billing:invoice-updated).
    if (existing != null && existing.connected && sameScope) return existing;
    existing?.dispose();
    _context = context;

    final socket = sio.io(
      AppConfig.apiBase,
      sio.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setAuth({'workplaceId': context.workplaceId, 'memberId': context.memberId, 'userId': context.userId})
          .enableAutoConnect()
          .build(),
    );
    // The default namespace carries no handshake auth for this join (unlike
    // ChatGateway's workplaceId/memberId, which IS in the handshake above and
    // auto-joins the workplace room) — the notification bell's `user:{id}`
    // room needs this explicit join every time the socket (re)connects, same
    // as erp/desktop's AppBootstrapContext.tsx. See socket.gateway.ts's
    // `notifications:join` handler.
    // Admin approved/rejected one of this workplace's module invoices —
    // reload the paywall snapshot, then ack so the backend marks it synced
    // (unacked pushes are re-sent on the next `workplace:join`). Same as
    // erp/desktop's AppBootstrapContext handleBillingInvoiceUpdated. Attached
    // before the join below so a backlog flush on join isn't missed.
    socket.on('billing:invoice-updated', (data) async {
      // With an ack requested, socket_io_client hands over [payload, ack].
      final ack = data is List && data.isNotEmpty && data.last is Function ? data.last as Function : null;
      try {
        await PaywallState.load();
        ack?.call({'ok': true});
      } catch (_) {
        ack?.call({'ok': false});
      }
    });
    socket.onConnect((_) {
      isConnected.value = true;
      socket.emit('notifications:join', {'userId': context.userId});
      // Explicit room join (desktop does the same) — this is what triggers
      // the backend's flushPendingBillingSync for missed invoice updates.
      socket.emit('workplace:join', {'workplaceId': context.workplaceId});
    });
    socket.onDisconnect((_) => isConnected.value = false);
    socket.onConnectError((_) => isConnected.value = false);
    socket.onError((_) => isConnected.value = false);
    _socket = socket;
    // Re-attach every [subscribe]d event to the new connection.
    for (final event in _subscribers.keys) {
      socket.on(event, _dispatcherFor(event));
    }
    return socket;
  }

  static sio.Socket? get instance => _socket;

  // ── Event subscriptions that survive reconnects / socket swaps ──────────
  // `instance?.on(...)` only binds to the socket alive right now; screens
  // that outlive a socket swap (market chat, unread badges) subscribe here
  // instead and get re-bound whenever [connect] builds a new socket.
  static final Map<String, Set<void Function(dynamic)>> _subscribers = {};
  static final Map<String, void Function(dynamic)> _dispatchers = {};

  static void Function(dynamic) _dispatcherFor(String event) => _dispatchers.putIfAbsent(
        event,
        () => (dynamic data) {
          // Payloads that carry an ack arrive as [payload, ack].
          final payload = data is List && data.isNotEmpty && data.last is Function ? data.first : data;
          for (final fn in List.of(_subscribers[event] ?? const <void Function(dynamic)>{})) {
            try {
              fn(payload);
            } catch (e) {
              debugPrint('[socket] $event listener failed: $e');
            }
          }
        },
      );

  /// Listens for [event] on the shared socket (now and after any reconnect).
  /// Returns a function that removes the listener.
  static VoidCallback subscribe(String event, void Function(dynamic payload) listener) {
    final set = _subscribers.putIfAbsent(event, () => <void Function(dynamic)>{});
    if (set.isEmpty) _socket?.on(event, _dispatcherFor(event));
    set.add(listener);
    return () {
      final current = _subscribers[event];
      if (current == null) return;
      current.remove(listener);
      if (current.isEmpty) {
        _subscribers.remove(event);
        final dispatcher = _dispatchers.remove(event);
        if (dispatcher != null) _socket?.off(event, dispatcher);
      }
    };
  }

  static void disconnect() {
    _socket?.off('billing:invoice-updated');
    _socket?.dispose();
    _socket = null;
    _context = null;
    isConnected.value = false;
  }
}
