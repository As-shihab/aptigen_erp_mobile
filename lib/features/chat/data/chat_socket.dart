import 'package:flutter/foundation.dart';
import '../../../core/network/socket_client.dart';

/// Ported from erp/desktop's chat.socket.ts — reuses the single shared
/// AppSocket connection (same ChatGateway/workplace-room join already used
/// for attendance realtime), just adding chat's own room join/leave events.
void joinChatRoom(int roomId) {
  AppSocket.instance?.emit('chat:join-room', {'roomId': roomId});
}

void leaveChatRoom(int roomId) {
  AppSocket.instance?.emit('chat:leave-room', {'roomId': roomId});
}

typedef ChatEventHandler = void Function(dynamic payload);

VoidCallback subscribeChatSocket(String event, ChatEventHandler handler) {
  final socket = AppSocket.instance;
  if (socket == null) return () {};
  void listener(dynamic data) => handler(data);
  socket.on(event, listener);
  return () => socket.off(event, listener);
}
