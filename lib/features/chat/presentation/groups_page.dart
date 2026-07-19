import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/network/socket_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chat_service.dart';
import '../models/chat_model.dart';
import 'group_detail_page.dart';

class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  final _service = ChatService(ApiClient());
  SocketContext? _context;
  List<Map<String, dynamic>> _groups = [];
  Map<int, int> _counts = {};
  bool _loading = true;

  static const _palette = [Color(0xFF0EA5E9), Color(0xFFF97316), Color(0xFF8B5CF6), Color(0xFF22C55E), Color(0xFFE11D48), Color(0xFF14B8A6)];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final context = await _service.resolveContext();
      if (context == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final result = await _service.loadGroupsForMember(context.memberId);
      if (!mounted) return;
      setState(() {
        _context = context;
        _groups = result.rooms;
        _counts = result.counts;
      });
    } catch (_) {
      // leave list empty on failure
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createGroup() async {
    final context = _context;
    if (context == null) return;
    final controller = TextEditingController();
    var visibility = ChatRoomVisibility.private;

    final name = await showDialog<String>(
      context: this.context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Create Group'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Group name')),
              const SizedBox(height: 12),
              SegmentedButton<ChatRoomVisibility>(
                segments: const [
                  ButtonSegment(value: ChatRoomVisibility.private, label: Text('Private')),
                  ButtonSegment(value: ChatRoomVisibility.public, label: Text('Public')),
                ],
                selected: {visibility},
                onSelectionChanged: (selection) => setDialogState(() => visibility = selection.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (name == null || name.isEmpty) return;

    try {
      final created = await ApiClient().post('chat_rooms', {
        'name': name,
        'room_type': chatRoomTypeToValue(ChatRoomType.group),
        'visibility': chatRoomVisibilityToValue(visibility),
        'created_by_member_id': context.memberId,
        'is_active': true,
      }, isV8: true);
      final row = (created is Map ? created['value'] ?? created : created) as Map?;
      final roomId = toNum(row?['id']);
      if (roomId == 0) return;
      await _service.ensureGroupMembership(roomId: roomId, memberId: context.memberId, joinedBy: context.memberId);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('Could not create group.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _createGroup, icon: const Icon(Icons.add), label: const Text('Group')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : _groups.isEmpty
              ? Center(child: Text('No groups yet — tap + to create one.', style: TextStyle(color: AppColors.slate600)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _groups.length,
                    itemBuilder: (context, index) {
                      final room = _groups[index];
                      final roomId = toNum(room['id']);
                      final name = (room['name'] ?? 'Group').toString();
                      final memberCount = _counts[roomId] ?? 0;
                      final visibility = parseChatRoomVisibility(room['visibility']);
                      final accent = _palette[index % _palette.length];

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: CircleAvatar(radius: 26, backgroundColor: accent, child: const Icon(Icons.group, color: Colors.white)),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('$memberCount members · ${visibility == ChatRoomVisibility.public ? 'Public' : 'Private'}'),
                        onTap: () {
                          final chatContext = _context;
                          if (chatContext == null) return;
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => GroupDetailPage(
                              roomId: roomId,
                              roomName: name,
                              workplaceId: chatContext.workplaceId,
                              memberId: chatContext.memberId,
                            ),
                          ));
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
