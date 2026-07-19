import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/network/socket_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chat_service.dart';
import 'dm_thread_page.dart';

class DirectMessagesPage extends StatefulWidget {
  const DirectMessagesPage({super.key});

  @override
  State<DirectMessagesPage> createState() => _DirectMessagesPageState();
}

class _DirectMessagesPageState extends State<DirectMessagesPage> {
  final _service = ChatService(ApiClient());
  SocketContext? _context;
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  String _search = '';

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
      final members = await _service.loadWorkplaceMembers(context.workplaceId);
      if (!mounted) return;
      setState(() {
        _context = context;
        _members = members.where((m) => (m['id'] as num?)?.toInt() != context.memberId).toList();
      });
    } catch (_) {
      // leave list empty on failure
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openThread(Map<String, dynamic> member) async {
    final chatContext = _context;
    if (chatContext == null) return;
    final otherMemberId = (member['id'] as num).toInt();
    final name = ((member['user'] as Map?)?['name'] ?? 'Member').toString();
    final roomId = await _service.ensureSingleRoom(selfMemberId: chatContext.memberId, otherMemberId: otherMemberId);
    if (roomId == 0 || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DmThreadPage(roomId: roomId, workplaceId: chatContext.workplaceId, memberId: chatContext.memberId, peerName: name, peerMemberId: otherMemberId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _members.where((m) {
      if (_search.isEmpty) return true;
      final name = ((m['user'] as Map?)?['name'] ?? '').toString().toLowerCase();
      return name.contains(_search.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            decoration: BoxDecoration(color: AppColors.slate400.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(24)),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search people', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 10)),
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
              : filtered.isEmpty
                  ? Center(child: Text('No workplace members found.', style: TextStyle(color: AppColors.slate600)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final member = filtered[index];
                          final user = member['user'] as Map?;
                          final name = (user?['name'] ?? 'Member').toString();
                          final email = (user?['email'] ?? '').toString();
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: CircleAvatar(
                              radius: 26,
                              backgroundColor: AppColors.brand.withValues(alpha: 0.15),
                              child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700, fontSize: 18)),
                            ),
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: email.isNotEmpty ? Text(email) : null,
                            onTap: () => _openThread(member),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
