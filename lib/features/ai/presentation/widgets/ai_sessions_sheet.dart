import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/ai_models.dart';
import '../../data/ai_service.dart';

/// A session with `id == 0` is the sentinel for "start a new chat" — real
/// session ids from `ai_sessions` are always positive, so this is an
/// unambiguous way to distinguish "start new" from "user dismissed the
/// sheet" (which just pops with null) without a separate result type.
const _newChatSentinel = AiSession(id: 0, title: null, updatedAt: '');

/// Past chat sessions — tap to resume one, or "New chat" to start fresh.
/// Mirrors desktop's sessions rail/slide-down panel (HeaderAiPopover.tsx).
Future<AiSession?> showAiSessionsSheet(BuildContext context, {required int userId, required int? currentSessionId}) {
  return showModalBottomSheet<AiSession>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AiSessionsSheet(userId: userId, currentSessionId: currentSessionId),
  );
}

class _AiSessionsSheet extends StatefulWidget {
  final int userId;
  final int? currentSessionId;
  const _AiSessionsSheet({required this.userId, required this.currentSessionId});

  @override
  State<_AiSessionsSheet> createState() => _AiSessionsSheetState();
}

class _AiSessionsSheetState extends State<_AiSessionsSheet> {
  late final _service = AiService(ApiClient());
  bool _loading = true;
  List<AiSession> _sessions = [];
  final Set<int> _deletingIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sessions = await _service.loadSessions(widget.userId);
      if (!mounted) return;
      setState(() => _sessions = sessions);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(AiSession session) async {
    setState(() => _deletingIds.add(session.id));
    try {
      await _service.deleteSession(session.id);
      if (!mounted) return;
      setState(() => _sessions.removeWhere((s) => s.id == session.id));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete this chat.')));
    } finally {
      if (mounted) setState(() => _deletingIds.remove(session.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.slate400.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  const Expanded(child: Text('Chats', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(_newChatSentinel),
                    icon: const Icon(Icons.add_comment_outlined, size: 16),
                    label: const Text('New chat'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                  : _sessions.isEmpty
                      ? Center(child: Text('No previous chats yet.', style: TextStyle(color: AppColors.slate600)))
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _sessions.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final session = _sessions[index];
                            final isActive = session.id == widget.currentSessionId;
                            final deleting = _deletingIds.contains(session.id);
                            return Opacity(
                              opacity: deleting ? 0.5 : 1,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: deleting ? null : () => Navigator.of(context).pop(session),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isActive ? AppColors.brand.withValues(alpha: 0.1) : Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(child: Text(session.title ?? 'Untitled chat', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                      if (deleting)
                                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      else
                                        IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error), onPressed: () => _delete(session)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}
