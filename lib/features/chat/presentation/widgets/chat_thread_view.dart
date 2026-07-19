import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/media_library_dialog.dart';
import '../../data/chat_service.dart';
import '../../data/chat_socket.dart';
import '../../models/chat_model.dart';

class _PendingAttachment {
  final ChatAttachmentMeta meta;
  const _PendingAttachment(this.meta);
}

/// Shared 1:1/group/channel message thread — reused by DM, Group, and
/// Channel screens. Styled like a real messenger app: rounded bubbles,
/// grouped consecutive messages with a trailing avatar, pill-shaped
/// composer (mirrors erp/desktop's Chat.tsx + Groups.tsx message shape,
/// restyled for mobile).
class ChatThreadView extends StatefulWidget {
  final int roomId;
  final int workplaceId;
  final int memberId;
  final String placeholderName;
  final bool isGroup;

  const ChatThreadView({
    super.key,
    required this.roomId,
    required this.workplaceId,
    required this.memberId,
    required this.placeholderName,
    this.isGroup = false,
  });

  @override
  State<ChatThreadView> createState() => ChatThreadViewState();
}

class ChatThreadViewState extends State<ChatThreadView> {
  final _service = ChatService(ApiClient());
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  final List<_PendingAttachment> _pendingAttachments = [];
  bool _loading = true;
  bool _sending = false;
  VoidCallback? _unsubscribe;

  @override
  void initState() {
    super.initState();
    _load();
    joinChatRoom(widget.roomId);
    _unsubscribe = subscribeChatSocket('chat:message-created', _onIncomingMessage);
  }

  @override
  void didUpdateWidget(covariant ChatThreadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      leaveChatRoom(oldWidget.roomId);
      joinChatRoom(widget.roomId);
      _load();
    }
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    leaveChatRoom(widget.roomId);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onIncomingMessage(dynamic payload) {
    if (payload is! Map) return;
    final roomId = toNum(payload['room_id']);
    if (roomId != widget.roomId) return;
    final type = (payload['message_type'] ?? 'text').toString().toLowerCase();
    if (type == 'webrtc_signal' || type == 'call_log') return;
    final id = toNum(payload['id']);
    if (_messages.any((m) => toNum(m['id']) == id && id > 0)) return;
    if (!mounted) return;
    setState(() => _messages = [..._messages, payload.cast<String, dynamic>()]);
    _scrollToBottom();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _messages = [];
    });
    try {
      final rows = await _service.loadRoomMessages(widget.roomId, top: 100);
      if (!mounted) return;
      setState(() => _messages = rows.where((row) => (row['message_type'] ?? 'text').toString().toLowerCase() != 'webrtc_signal').toList());
      _scrollToBottom();
    } catch (_) {
      // leave the thread empty on failure — the send box still works
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  Future<void> _openAttachmentPicker() async {
    final items = await showMediaLibraryDialog(context, title: 'Attach Media', multiSelect: true, defaultCategoryName: 'Chat');
    if (items == null || items.isEmpty || !mounted) return;
    setState(() {
      _pendingAttachments.addAll(items.map((item) => _PendingAttachment(ChatAttachmentMeta(
            url: item.fileUrl,
            name: item.name,
            mime: item.mime,
            size: item.size,
          ))));
    });
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _pendingAttachments.isEmpty) return;
    setState(() => _sending = true);
    try {
      for (final attachment in _pendingAttachments) {
        await _service.sendAttachmentMessage(
          roomId: widget.roomId,
          workplaceId: widget.workplaceId,
          senderMemberId: widget.memberId,
          attachment: attachment.meta,
          kind: attachment.meta.mime?.startsWith('image/') == true ? 'image' : 'file',
        );
      }
      if (text.isNotEmpty) {
        await _service.sendRoomMessage(roomId: widget.roomId, workplaceId: widget.workplaceId, senderMemberId: widget.memberId, message: text);
      }
      _messageController.clear();
      setState(() => _pendingAttachments.clear());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not send message.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? AppColors.slate900 : AppColors.slate50,
      child: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                : _messages.isEmpty
                    ? Center(child: Text('No messages yet. Start the conversation.', style: TextStyle(color: AppColors.slate600)))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) => _buildMessageRow(index),
                      ),
          ),
          if (_pendingAttachments.isNotEmpty)
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: _pendingAttachments
                    .map((attachment) => Padding(
                          padding: const EdgeInsets.all(4),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(attachment.meta.url, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.insert_drive_file_outlined)),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: GestureDetector(
                                  onTap: () => setState(() => _pendingAttachments.remove(attachment)),
                                  child: const CircleAvatar(radius: 9, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 12, color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(icon: const Icon(Icons.add_photo_alternate_outlined), color: AppColors.brand, onPressed: _openAttachmentPicker),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 42, maxHeight: 120),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.slate400.withValues(alpha: 0.25)),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Message ${widget.placeholderName}',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        minLines: 1,
                        maxLines: 4,
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _sending ? null : _send,
                    child: CircleAvatar(
                      radius: 21,
                      backgroundColor: AppColors.brand,
                      child: _sending
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send, size: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageRow(int index) {
    final message = _messages[index];
    final senderId = toNum(message['sender_member_id']);
    final isMe = senderId == widget.memberId;
    final nextMessage = index + 1 < _messages.length ? _messages[index + 1] : null;
    final isLastInGroup = nextMessage == null || toNum(nextMessage['sender_member_id']) != senderId;
    final senderName = ((message['sender'] as Map?)?['user'] as Map?)?['name']?.toString() ?? (isMe ? 'You' : 'Member');

    final bubble = _buildBubble(message, isMe);

    if (isMe) {
      return Padding(padding: const EdgeInsets.only(bottom: 2), child: Align(alignment: Alignment.centerRight, child: bubble));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 28,
            child: isLastInGroup
                ? CircleAvatar(
                    radius: 13,
                    backgroundColor: AppColors.brand.withValues(alpha: 0.15),
                    child: Text(senderName.isNotEmpty ? senderName[0].toUpperCase() : '?', style: const TextStyle(fontSize: 11, color: AppColors.brand, fontWeight: FontWeight.w700)),
                  )
                : null,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.isGroup) Padding(padding: const EdgeInsets.only(left: 4, bottom: 2), child: Text(senderName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brand))),
                bubble,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(Map<String, dynamic> message, bool isMe) {
    final type = (message['message_type'] ?? 'text').toString().toLowerCase();
    final attachment = (type == 'image' || type == 'file') ? ChatAttachmentMeta.tryParse((message['message'] ?? '').toString()) : null;
    final text = attachment != null ? '' : (message['message'] ?? '').toString();
    final createdAt = DateTime.tryParse((message['created_at'] ?? '').toString());
    final time = createdAt != null ? TimeOfDay.fromDateTime(createdAt.toLocal()).format(context) : '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: attachment != null ? const EdgeInsets.all(4) : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      decoration: BoxDecoration(
        color: isMe ? AppColors.brand : (isDark ? const Color(0xFF1E293B) : Colors.white),
        borderRadius: BorderRadius.circular(20),
        border: isMe ? null : Border.all(color: AppColors.slate400.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attachment != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(attachment.url, height: 160, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image)),
            ),
          if (text.isNotEmpty) Padding(padding: EdgeInsets.only(top: attachment != null ? 6 : 0), child: Text(text, style: TextStyle(color: isMe ? Colors.white : null))),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(time, style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : AppColors.slate400)),
          ),
        ],
      ),
    );
  }
}
