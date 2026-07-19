import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
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

  static sio.Socket connect(SocketContext context) {
    final existing = _socket;
    if (existing != null && existing.connected) return existing;
    existing?.dispose();

    final socket = sio.io(
      AppConfig.apiBase,
      sio.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setAuth({'workplaceId': context.workplaceId, 'memberId': context.memberId, 'userId': context.userId})
          .enableAutoConnect()
          .build(),
    );
    socket.onConnect((_) => isConnected.value = true);
    socket.onDisconnect((_) => isConnected.value = false);
    socket.onConnectError((_) => isConnected.value = false);
    socket.onError((_) => isConnected.value = false);
    _socket = socket;
    return socket;
  }

  static sio.Socket? get instance => _socket;

  static void disconnect() {
    _socket?.dispose();
    _socket = null;
    isConnected.value = false;
  }
}
