import 'dart:convert';
import '../../../core/network/http_client.dart';
import '../../../core/network/socket_client.dart';
import '../models/chat_model.dart';

/// Ported from erp/desktop's chat.data.ts.
class ChatService {
  final ApiClient _client;
  ChatService(this._client);

  String _escapeOData(String value) => value.replaceAll("'", "''");

  Future<SocketContext?> resolveContext() => resolveSocketContext(_client);

  Future<List<Map<String, dynamic>>> loadWorkplaceMembers(int workplaceId, {String search = ''}) async {
    const pageSize = 500;
    var skip = 0;
    final all = <Map<String, dynamic>>[];
    final searchFilter = search.trim().isEmpty
        ? ''
        : " and (contains(tolower(user/name), '${_escapeOData(search.trim().toLowerCase())}') or contains(tolower(user/email), '${_escapeOData(search.trim().toLowerCase())}'))";

    while (true) {
      final res = await _client.get(
        'workplace_members?\$filter=workplace_id eq $workplaceId$searchFilter&\$expand=user&\$top=$pageSize&\$skip=$skip',
      );
      final rows = unwrapList(res).cast<Map<String, dynamic>>();
      if (rows.isEmpty) break;
      all.addAll(rows);
      if (rows.length < pageSize) break;
      skip += rows.length;
    }
    return all;
  }

  Future<List<Map<String, dynamic>>> loadRoomMessages(int roomId, {int top = 100, int skip = 0}) async {
    final res = await _client.get(
      'chat_messages?\$filter=room_id eq $roomId and is_deleted eq false&\$orderby=created_at desc&\$top=$top&\$skip=$skip&\$expand=sender(\$expand=user)',
    );
    return unwrapList(res).cast<Map<String, dynamic>>().reversed.toList();
  }

  Future<void> sendRoomMessage({
    required int roomId,
    required int workplaceId,
    required int senderMemberId,
    required String message,
    String messageType = 'text',
  }) async {
    await _client.post('chat_messages', {
      'room_id': roomId,
      'workplace_id': workplaceId,
      'sender_member_id': senderMemberId,
      'message': message,
      'message_type': messageType,
    }, isV8: true);
  }

  Future<void> sendAttachmentMessage({
    required int roomId,
    required int workplaceId,
    required int senderMemberId,
    required ChatAttachmentMeta attachment,
    required String kind, // 'image' | 'file'
  }) async {
    await sendRoomMessage(
      roomId: roomId,
      workplaceId: workplaceId,
      senderMemberId: senderMemberId,
      message: jsonEncode(attachment.toJson()),
      messageType: kind,
    );
  }

  Future<int> ensureSingleRoom({required int selfMemberId, required int otherMemberId}) async {
    final first = selfMemberId < otherMemberId ? selfMemberId : otherMemberId;
    final second = selfMemberId < otherMemberId ? otherMemberId : selfMemberId;
    final pairKey = '${first}_$second';

    final roomRes = await _client.get(
      "chat_rooms?\$filter=room_type eq 'single' and direct_pair_key eq '${_escapeOData(pairKey)}' and is_active eq true&\$top=1",
    );
    final existing = unwrapList(roomRes).cast<Map>().firstOrNull;
    final existingId = toNum(existing?['id']);
    if (existingId > 0) return existingId;

    final created = await _client.post('chat_rooms', {
      'name': 'Direct Chat',
      'room_type': 'single',
      'visibility': 'private',
      'direct_pair_key': pairKey,
      'created_by_member_id': selfMemberId,
      'is_active': true,
    }, isV8: true);
    final createdRoom = (created is Map ? created['value'] ?? created : created) as Map?;
    final roomId = toNum(createdRoom?['id']);
    if (roomId == 0) return 0;

    await ensureGroupMembership(roomId: roomId, memberId: selfMemberId, joinedBy: selfMemberId);
    await ensureGroupMembership(roomId: roomId, memberId: otherMemberId, joinedBy: selfMemberId);
    return roomId;
  }

  Future<({List<Map<String, dynamic>> rooms, Map<int, int> counts, Set<int> joinedRoomIds})> loadGroupsForMember(int memberId) async {
    final roomsRes = await _client.get("chat_rooms?\$filter=room_type eq 'group' and is_active eq true&\$orderby=updated_at desc&\$top=200");
    final groupRooms = unwrapList(roomsRes).cast<Map<String, dynamic>>();

    final membershipRes = await _client.get('chat_room_members?\$filter=member_id eq $memberId&\$top=500');
    final memberships = unwrapList(membershipRes);
    final joinedRoomIds = memberships.map((row) => toNum((row as Map)['room_id'])).where((id) => id > 0).toSet();

    final accessible = groupRooms.where((room) {
      final visibility = parseChatRoomVisibility(room['visibility']);
      final createdBy = toNum(room['created_by_member_id']);
      if (visibility == ChatRoomVisibility.public) return true;
      if (createdBy == memberId) return true;
      return joinedRoomIds.contains(toNum(room['id']));
    }).toList();

    final counts = <int, int>{};
    await Future.wait(accessible.map((room) async {
      final roomId = toNum(room['id']);
      if (roomId == 0) return;
      try {
        final membersRes = await _client.get('chat_room_members?\$filter=room_id eq $roomId and is_active eq true&\$top=500');
        counts[roomId] = unwrapList(membersRes).length;
      } catch (_) {
        counts[roomId] = 0;
      }
    }));

    return (rooms: accessible, counts: counts, joinedRoomIds: joinedRoomIds);
  }

  Future<void> ensureGroupMembership({required int roomId, required int memberId, required int joinedBy}) async {
    try {
      await _client.post('chat_room_members', {
        'room_id': roomId,
        'member_id': memberId,
        'role': 'member',
        'joined_by': joinedBy,
        'is_active': true,
      }, isV8: true);
    } catch (_) {
      // ignore duplicate membership errors
    }
  }

  Future<List<Map<String, dynamic>>> loadChannelsForRoom(int parentRoomId) async {
    final res = await _client.get('chat_rooms?\$filter=parent_room_id eq $parentRoomId and is_active eq true&\$orderby=name asc&\$top=200');
    return unwrapList(res).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createChannel({required int parentRoomId, required String name, required int createdByMemberId}) async {
    final created = await _client.post('chat_rooms', {
      'name': name,
      'room_type': 'channel',
      'visibility': 'private',
      'parent_room_id': parentRoomId,
      'created_by_member_id': createdByMemberId,
      'is_active': true,
    }, isV8: true);
    final row = (created is Map ? created['value'] ?? created : created) as Map?;
    return row?.cast<String, dynamic>() ?? {};
  }

  Future<void> updateMemberRole({required int membershipId, required String role}) async {
    await _client.put('chat_room_members', membershipId, {'role': role});
  }

  Future<List<Map<String, dynamic>>> loadMeetingsForRange({required int workplaceId, required DateTime from, required DateTime to}) async {
    final res = await _client.get(
      'chat_meetings?\$filter=workplace_id eq $workplaceId and is_active eq true and scheduled_at ge ${from.toIso8601String()} and scheduled_at le ${to.toIso8601String()}&\$orderby=scheduled_at asc&\$top=500&\$expand=created_by(\$expand=user),room',
    );
    return unwrapList(res).cast<Map<String, dynamic>>();
  }

  Future<void> createMeeting({
    required int workplaceId,
    required String title,
    String? description,
    required String scheduledAtIso,
    required int durationMinutes,
    required ChatMeetingMode mode,
    String? location,
    int? roomId,
    required int createdByMemberId,
  }) async {
    await _client.post('chat_meetings', {
      'workplace_id': workplaceId,
      'room_id': roomId,
      'title': title,
      'description': description,
      'scheduled_at': scheduledAtIso,
      'duration_minutes': durationMinutes,
      'mode': mode,
      'location': location,
      'created_by_member_id': createdByMemberId,
      'is_active': true,
    }, isV8: true);
  }
}

extension FirstOrNullMap<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
