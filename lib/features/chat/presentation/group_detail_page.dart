import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chat_service.dart';
import '../models/chat_model.dart';
import 'widgets/chat_thread_view.dart';

class GroupDetailPage extends StatefulWidget {
  final int roomId;
  final String roomName;
  final int workplaceId;
  final int memberId;

  const GroupDetailPage({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.workplaceId,
    required this.memberId,
  });

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

const _roomRoles = ['member', 'admin'];

class _GroupDetailPageState extends State<GroupDetailPage> {
  final _service = ChatService(ApiClient());
  List<Map<String, dynamic>> _channels = [];
  List<Map<String, dynamic>> _roster = [];
  int _activeChannelId = 0; // 0 = General (the group's own room)
  bool _loadingMeta = true;

  int get _activeRoomId => _activeChannelId != 0 ? _activeChannelId : widget.roomId;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    setState(() => _loadingMeta = true);
    try {
      final channels = await _service.loadChannelsForRoom(widget.roomId);
      final rosterRes = await ApiClient().get(
        'chat_room_members?\$filter=room_id eq ${widget.roomId} and is_active eq true&\$expand=member(\$expand=user)&\$top=500',
      );
      final roster = unwrapList(rosterRes).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _channels = channels;
        _roster = roster;
      });
    } catch (_) {
      // leave meta empty on failure — the thread itself still works
    } finally {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  Future<void> _createChannel() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create Channel'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. announcements')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final created = await _service.createChannel(parentRoomId: widget.roomId, name: name, createdByMemberId: widget.memberId);
      await _loadMeta();
      final channelId = toNum(created['id']);
      if (channelId > 0) setState(() => _activeChannelId = channelId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create channel.')));
    }
  }

  Future<void> _changeRole(Map<String, dynamic> row, String role) async {
    final membershipId = toNum(row['id']);
    if (membershipId == 0) return;
    try {
      await _service.updateMemberRole(membershipId: membershipId, role: role);
      await _loadMeta();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update role.')));
    }
  }

  void _showRoles() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Group Roles', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (_roster.isEmpty) Text('No members loaded.', style: TextStyle(color: AppColors.slate600)),
            ..._roster.map((row) {
              final user = (row['member'] as Map?)?['user'] as Map?;
              final name = (user?['name'] ?? 'Member').toString();
              final role = (row['role'] ?? 'member').toString().toLowerCase();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(name)),
                    DropdownButton<String>(
                      value: _roomRoles.contains(role) ? role : 'member',
                      items: _roomRoles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                      onChanged: (value) {
                        if (value != null) _changeRole(row, value);
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeChannelName = _activeChannelId == 0
        ? null
        : (_channels.firstWhere((c) => toNum(c['id']) == _activeChannelId, orElse: () => {})['name']?.toString());

    return Scaffold(
        appBar: AppBar(
          title: Text(activeChannelName != null ? '${widget.roomName} · #$activeChannelName' : widget.roomName),
          actions: [
            IconButton(icon: const Icon(Icons.shield_outlined), tooltip: 'Group Roles', onPressed: _showRoles),
          ],
        ),
        body: Column(
          children: [
            SizedBox(
              height: 44,
              child: _loadingMeta
                  ? const SizedBox.shrink()
                  : ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      children: [
                        ChoiceChip(
                          label: const Text('#general'),
                          selected: _activeChannelId == 0,
                          onSelected: (_) => setState(() => _activeChannelId = 0),
                        ),
                        const SizedBox(width: 8),
                        ..._channels.expand((channel) {
                          final id = toNum(channel['id']);
                          return [
                            ChoiceChip(
                              label: Text('#${channel['name']}'),
                              selected: _activeChannelId == id,
                              onSelected: (_) => setState(() => _activeChannelId = id),
                            ),
                            const SizedBox(width: 8),
                          ];
                        }),
                        ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text('Channel'), onPressed: _createChannel),
                      ],
                    ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ChatThreadView(
                key: ValueKey(_activeRoomId),
                roomId: _activeRoomId,
                workplaceId: widget.workplaceId,
                memberId: widget.memberId,
                placeholderName: activeChannelName != null ? '#$activeChannelName' : widget.roomName,
                isGroup: true,
              ),
            ),
          ],
        ),
      );
  }
}
