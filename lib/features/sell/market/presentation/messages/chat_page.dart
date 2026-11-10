import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../app/app.dart';
import '../../../../../core/network/http_client.dart';
import '../../../../../core/network/socket_client.dart';
import '../../../../notifications/data/module_unread_counts.dart';
import '../../data/market_messages_service.dart';
import '../widgets/market_ui.dart';
import 'chat_attachments.dart';
import 'message_widgets.dart';

/// Which conversation's chat is on screen (if any) — the inbox uses it to
/// skip bumping that row's unread count for live buyer messages.
class ChatOpenTracker {
  ChatOpenTracker._();
  static int? openId;
}

/// Opens the seller chat for [conversationId] from anywhere (push tap,
/// notifications list) via the root navigator.
void openMarketChatFromAnywhere(int conversationId) {
  navigatorKey.currentState?.push(marketRoute(MarketChatPage(conversationId: conversationId)));
}

/// `/sell/online/messages?c=<id>` (the link on `market_message`
/// notifications) → conversation id, else null.
int? marketChatIdFromLink(String? link) {
  if (link == null || !link.contains('/sell/online/messages')) return null;
  final uri = Uri.tryParse(link);
  return int.tryParse(uri?.queryParameters['c'] ?? '');
}

/// One buyer conversation: product card, bubbles with day separators, load
/// earlier on scroll to top, live socket updates and an optimistic composer.
class MarketChatPage extends StatefulWidget {
  final int conversationId;
  final MarketConversation? initial;
  const MarketChatPage({super.key, required this.conversationId, this.initial});

  @override
  State<MarketChatPage> createState() => _MarketChatPageState();
}

class _MarketChatPageState extends State<MarketChatPage> {
  final _api = MarketMessagesService();
  final _scroll = ScrollController();
  final _draft = TextEditingController();
  final _focus = FocusNode();
  final _subs = <VoidCallback>[];

  MarketChatPerson? _buyer;
  MarketChatListing? _listing;
  // Oldest first (render reversed so the newest sits at the bottom).
  List<MarketMessage> _messages = [];
  bool _hasMore = false;
  // Buyer's last read time — our messages at or before it show "Seen".
  DateTime? _buyerReadAt;
  bool _loading = true;
  bool _loadingEarlier = false;
  String? _error;
  int? _previousOpen;

  // Picked files waiting in the composer tray, and the files behind each
  // optimistic attachment send (kept for retry).
  List<MarketOutgoingFile> _picked = [];
  String? _attachError;
  final _outbox = <String, List<MarketOutgoingFile>>{};
  final _lastProgress = <Object, double>{};

  int get _id => widget.conversationId;

  @override
  void initState() {
    super.initState();
    _buyer = widget.initial?.buyer;
    _listing = widget.initial?.listing;
    _previousOpen = ChatOpenTracker.openId;
    ChatOpenTracker.openId = _id;
    _scroll.addListener(_onScroll);
    _draft.addListener(() => setState(() {}));
    _subs
      ..add(AppSocket.subscribe('market:message', _onSocketMessage))
      ..add(AppSocket.subscribe('market:message-read', _onSocketRead))
      ..add(SellerMessagesUnread.attach());
    _load();
    _api.markNotificationsRead().then((changed) {
      if (changed) ModuleUnreadCounts.refresh();
    });
  }

  @override
  void dispose() {
    for (final off in _subs) {
      off();
    }
    if (ChatOpenTracker.openId == _id) ChatOpenTracker.openId = _previousOpen;
    _scroll.dispose();
    _draft.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await _api.thread(_id);
      if (!mounted) return;
      setState(() {
        _buyer = t.buyer;
        _listing = t.listing ?? _listing;
        _messages = _mergeKeepingLocal(t.messages);
        _hasMore = t.hasMore;
        _buyerReadAt = t.buyerReadAt ?? _buyerReadAt;
        _loading = false;
      });
      SellerMessagesUnread.refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode < 500 ? e.message : 'Could not load this conversation.';
        _loading = false;
      });
    }
  }

  /// Server page + any optimistic / failed sends still in flight.
  List<MarketMessage> _mergeKeepingLocal(List<MarketMessage> server) {
    final local = _messages.where((m) => m.isTemp).toList();
    return [...server, ...local];
  }

  void _onScroll() {
    // Reversed list: the oldest messages are at maxScrollExtent (the top).
    if (!_scroll.hasClients || !_hasMore || _loadingEarlier || _loading) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) _loadEarlier();
  }

  Future<void> _loadEarlier() async {
    final oldest = _messages.where((m) => !m.isTemp).firstOrNull;
    if (oldest == null) return;
    setState(() => _loadingEarlier = true);
    try {
      final t = await _api.thread(_id, before: oldest.id as int);
      if (!mounted) return;
      final seen = _messages.map((m) => m.id).toSet();
      setState(() {
        _messages = [...t.messages.where((m) => !seen.contains(m.id)), ..._messages];
        _hasMore = t.hasMore;
      });
    } catch (_) {
      // scrolling to the top again retries
    } finally {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  bool get _nearBottom => !_scroll.hasClients || _scroll.position.pixels < 120;

  void _scrollToNewest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  void _onSocketMessage(dynamic payload) {
    if (!mounted || payload is! Map) return;
    final convId = int.tryParse('${payload['conversation_id']}') ?? 0;
    final raw = payload['message'];
    if (convId != _id || raw is! Map) return;
    final msg = MarketMessage.fromJson(raw);
    if (_messages.any((m) => m.id == msg.id)) return;
    final stick = _nearBottom || msg.fromSeller;
    setState(() {
      // Our own optimistic send echoed back before the POST resolved.
      final tmp = msg.fromSeller ? _messages.indexWhere((m) => m.isTemp && m.pending && !m.failed && m.body == msg.body && m.attachments.length == msg.attachments.length) : -1;
      if (tmp != -1) {
        _messages = [..._messages.take(tmp), msg, ..._messages.skip(tmp + 1)];
      } else {
        _messages = [..._messages, msg];
      }
    });
    if (stick) _scrollToNewest();
    // A buyer message landed while we're looking at it — re-open to keep it read.
    if (!msg.fromSeller) {
      _api.thread(_id).then((_) => SellerMessagesUnread.refresh()).catchError((_) {});
    }
  }

  /// Buyer opened this chat — flip our sent messages to "Seen".
  void _onSocketRead(dynamic raw) {
    if (raw is! Map || toInt(raw['conversation_id']) != _id || raw['side'] != 'buyer') return;
    if (!mounted) return;
    setState(() => _buyerReadAt = parseChatTime(raw['read_at']) ?? DateTime.now());
  }

  // ── Composer ───────────────────────────────────────────────────────────

  void _send() {
    final body = _draft.text.trim();
    final files = List<MarketOutgoingFile>.of(_picked);
    if ((body.isEmpty && files.isEmpty) || body.length > kMarketMessageMaxLength) return;
    final tempId = 'tmp-${DateTime.now().microsecondsSinceEpoch}';
    if (files.isNotEmpty) _outbox[tempId] = files;
    setState(() {
      _messages = [
        ..._messages,
        MarketMessage(
          id: tempId,
          conversationId: _id,
          senderId: 0,
          fromSeller: true,
          body: body,
          createdAt: DateTime.now(),
          attachments: [for (final f in files) f.toAttachment()],
          pending: true,
        ),
      ];
      _picked = [];
      _attachError = null;
    });
    _draft.clear();
    _scrollToNewest();
    _deliver(tempId, body);
  }

  Future<void> _deliver(String tempId, String body) async {
    final files = _outbox[tempId];
    try {
      final real = files == null
          ? await _api.send(_id, body)
          : await _api.sendFiles(_id, files, body: body, onProgress: (v) => _setProgress(tempId, v));
      _outbox.remove(tempId);
      _lastProgress.remove(tempId);
      if (!mounted) return;
      setState(() {
        final without = _messages.where((m) => m.id != tempId).toList();
        _messages = real == null || without.any((m) => m.id == real.id) ? without : [...without, real];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _messages = [for (final m in _messages) m.id == tempId ? m.copyWith(pending: false, failed: true) : m]);
    }
  }

  /// Upload progress for an optimistic attachment bubble (throttled to ~2% steps).
  void _setProgress(String tempId, double v) {
    final last = _lastProgress[tempId] ?? 0;
    if (!mounted || (v < 1 && v - last < 0.02)) return;
    _lastProgress[tempId] = v;
    setState(() => _messages = [for (final m in _messages) m.id == tempId ? m.copyWith(progress: v) : m]);
  }

  void _retry(MarketMessage m) {
    _lastProgress.remove(m.id);
    setState(() => _messages = [for (final x in _messages) x.id == m.id ? x.copyWith(pending: true, failed: false, progress: 0) : x]);
    _deliver(m.id as String, m.body);
  }

  void _discard(MarketMessage m) {
    _outbox.remove(m.id);
    _lastProgress.remove(m.id);
    setState(() => _messages = _messages.where((x) => x.id != m.id).toList());
  }

  // ── Attachments ────────────────────────────────────────────────────────

  Future<void> _openAttachSheet() async {
    final remaining = kMarketAttachmentMax - _picked.length;
    if (remaining <= 0) {
      setState(() => _attachError = 'You can attach up to $kMarketAttachmentMax files per message');
      return;
    }
    final p = MarketPalette.of(context);
    Widget option(BuildContext ctx, IconData icon, int accent, String title, String subtitle, String value) => ListTile(
          leading: AccentListIcon(icon, index: accent),
          title: Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.text)),
          subtitle: Text(subtitle, style: TextStyle(fontSize: 12.5, color: p.label)),
          onTap: () => Navigator.pop(ctx, value),
        );
    final choice = await showMarketSheet<String>(
      context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text('Attach', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
            ),
            option(ctx, Icons.photo_library_outlined, 0, 'Photo or video', 'Choose from your gallery', 'media'),
            option(ctx, Icons.photo_camera_outlined, 3, 'Take a photo', 'Use the camera', 'camera'),
            option(ctx, Icons.attach_file, 4, 'File', 'PDF, Word, Excel, PowerPoint, text, CSV, zip or rar', 'file'),
          ]),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    try {
      switch (choice) {
        case 'media':
          final picker = ImagePicker();
          final List<XFile> picked;
          if (remaining >= 2) {
            picked = await picker.pickMultipleMedia(limit: remaining);
          } else {
            final one = await picker.pickMedia();
            picked = one == null ? const [] : [one];
          }
          await _addXFiles(picked);
        case 'camera':
          final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
          if (shot != null) await _addXFiles([shot]);
        case 'file':
          final res = await FilePicker.pickFiles(
            allowMultiple: true,
            type: FileType.custom,
            allowedExtensions: kMarketAttachmentDocMime.keys.toList(),
          );
          if (res == null) return;
          _addPicked([
            for (final f in res.files)
              if (f.path != null) (path: f.path!, name: f.name, size: f.size, hint: null),
          ]);
      }
    } catch (_) {
      if (mounted) setState(() => _attachError = "Could not open the picker. Check the app's permissions.");
    }
  }

  Future<void> _addXFiles(List<XFile> files) async {
    final items = <({String path, String name, int size, String? hint})>[];
    for (final x in files) {
      items.add((path: x.path, name: x.name, size: await x.length(), hint: x.mimeType));
    }
    if (mounted) _addPicked(items);
  }

  /// Client-side checks matching the server: at most 6 files, 25 MB each,
  /// images / videos / allowed documents only.
  void _addPicked(List<({String path, String name, int size, String? hint})> items) {
    if (items.isEmpty) return;
    final next = List<MarketOutgoingFile>.of(_picked);
    var tooBig = 0, badType = 0, overLimit = 0;
    for (final it in items) {
      final mime = attachmentMime(it.name, it.hint);
      if (!isAllowedAttachment(it.name, mime)) {
        badType++;
      } else if (it.size > kMarketAttachmentMaxBytes) {
        tooBig++;
      } else if (next.length >= kMarketAttachmentMax) {
        overLimit++;
      } else if (!next.any((f) => f.path == it.path)) {
        next.add(MarketOutgoingFile(path: it.path, name: it.name, size: it.size, mime: mime));
      }
    }
    final problems = [
      if (tooBig > 0) '$tooBig over 25 MB',
      if (badType > 0) '$badType not a supported type',
      if (overLimit > 0) '$overLimit over the $kMarketAttachmentMax file limit',
    ];
    setState(() {
      _picked = next;
      _attachError = problems.isEmpty ? null : 'Skipped ${problems.join(', ')}';
    });
  }

  void _removePicked(int i) => setState(() {
        _picked = [..._picked]..removeAt(i);
        _attachError = null;
      });

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final buyer = _buyer;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: p.line)),
        titleSpacing: 0,
        title: Row(children: [
          if (buyer != null) ...[BuyerAvatar(buyer, size: 34), const SizedBox(width: 10)],
          Expanded(
            child: Text(buyer?.displayName ?? (_loading ? 'Loading…' : 'Conversation'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
          ),
        ]),
      ),
      body: Column(children: [
        if (_listing != null)
          _ProductCard(listing: _listing!)
        else if (_loading && _messages.isEmpty)
          const _ProductCardSkeleton(),
        Expanded(child: _thread(p)),
        if (_error == null || _messages.isNotEmpty) _composer(p),
      ]),
    );
  }

  Widget _thread(MarketPalette p) {
    if (_loading && _messages.isEmpty) {
      return ListView(
        reverse: true,
        padding: const EdgeInsets.all(16),
        children: [
          for (final (i, (w, h)) in const [(170.0, 38.0), (230.0, 56.0), (120.0, 38.0), (250.0, 38.0), (200.0, 74.0), (150.0, 38.0), (210.0, 56.0)].indexed)
            Align(
              alignment: i.isEven ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SkeletonBox(width: w, height: h, radius: 16),
              ),
            ),
        ],
      );
    }
    if (_error != null && _messages.isEmpty) {
      return ListView(children: [
        MarketEmpty(icon: Icons.cloud_off_outlined, title: 'Conversation unavailable', message: _error, actionLabel: 'Try again', onAction: _load),
      ]);
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('No messages in this conversation yet', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: p.label)),
        ),
      );
    }
    final n = _messages.length;
    final extra = (_hasMore || _loadingEarlier) ? 1 : 0;
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: n + extra,
      itemBuilder: (_, i) {
        if (i == n) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _loadingEarlier
                  ? const _EarlierSkeleton()
                  : TextButton(onPressed: _loadEarlier, child: const Text('Load earlier messages')),
            ),
          );
        }
        // Reversed: i = 0 is the newest; idx indexes the oldest-first list.
        final idx = n - 1 - i;
        final m = _messages[idx];
        final prev = idx > 0 ? _messages[idx - 1] : null;
        final next = idx < n - 1 ? _messages[idx + 1] : null;
        final newDay = prev == null || !isSameChatDay(prev.createdAt, m.createdAt);
        final grouped = !newDay && prev.fromSeller == m.fromSeller && m.createdAt.difference(prev.createdAt).inMinutes < 5;
        final lastOfGroup = next == null ||
            next.fromSeller != m.fromSeller ||
            !isSameChatDay(next.createdAt, m.createdAt) ||
            next.createdAt.difference(m.createdAt).inMinutes >= 5;
        return Column(key: ValueKey(m.id), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (newDay) _DaySeparator(chatDayLabel(m.createdAt)),
          _Bubble(
            message: m,
            grouped: grouped,
            showTime: lastOfGroup,
            seen: m.fromSeller && !m.isTemp && _buyerReadAt != null && !m.createdAt.isAfter(_buyerReadAt!),
            onRetry: () => _retry(m),
            onDiscard: () => _discard(m),
          ),
        ]);
      },
    );
  }

  Widget _composer(MarketPalette p) {
    final text = _draft.text.trim();
    final tooLong = text.length > kMarketMessageMaxLength;
    final canSend = (text.isNotEmpty || _picked.isNotEmpty) && !tooLong && !_loading;
    return Container(
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_picked.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChatAttachmentTray(files: _picked, onRemove: _removePicked),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 0, 6),
                child: Row(children: [
                  Icon(Icons.photo_library_outlined, size: 13, color: p.label),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('Files are also saved to your media library under B2B',
                        style: TextStyle(fontSize: 11.5, color: p.label)),
                  ),
                ]),
              ),
            ],
            if (_attachError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 0, 6),
                child: Row(children: [
                  Icon(Icons.error_outline, size: 14, color: p.error),
                  const SizedBox(width: 4),
                  Expanded(child: Text(_attachError!, style: TextStyle(fontSize: 12, color: p.error, fontWeight: FontWeight.w600))),
                  InkWell(
                    onTap: () => setState(() => _attachError = null),
                    child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.close, size: 14, color: p.label)),
                  ),
                ]),
              ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(
                tooltip: 'Attach',
                onPressed: _loading ? null : _openAttachSheet,
                color: p.label,
                icon: const Icon(Icons.add_circle_outline, size: 24),
              ),
              Expanded(
                child: TextField(
                  controller: _draft,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(fontSize: 14.5, color: p.text),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Write a reply',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    filled: true,
                    fillColor: p.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: p.line)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: p.line)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: p.brand)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: canSend ? _send : null,
                style: IconButton.styleFrom(backgroundColor: p.brand, foregroundColor: Colors.white, disabledBackgroundColor: p.surface),
                icon: const Icon(Icons.send_rounded, size: 20),
              ),
            ]),
            if (text.length > kMarketMessageMaxLength - 200)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 52),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('${text.length}/$kMarketMessageMaxLength',
                      style: TextStyle(fontSize: 11, color: tooLong ? p.error : p.label, fontWeight: tooLong ? FontWeight.w700 : FontWeight.w400)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final MarketChatListing listing;
  const _ProductCard({required this.listing});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final price = chatListingPrice(listing);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(color: p.card, border: Border(bottom: BorderSide(color: p.line))),
      child: Row(children: [
        ListingThumb(listing, size: 40),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(listing.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
            if (price.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(price, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.brand)),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _ProductCardSkeleton extends StatelessWidget {
  const _ProductCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(color: p.card, border: Border(bottom: BorderSide(color: p.line))),
      child: const Row(children: [
        SkeletonBox(width: 40, height: 40, radius: 8),
        SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SkeletonBox(width: 170, height: 12),
            SizedBox(height: 6),
            SkeletonBox(width: 70, height: 11),
          ]),
        ),
      ]),
    );
  }
}

/// Small placeholder bubbles at the top while older messages load.
class _EarlierSkeleton extends StatelessWidget {
  const _EarlierSkeleton();

  @override
  Widget build(BuildContext context) => const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(alignment: Alignment.centerLeft, child: SkeletonBox(width: 150, height: 30, radius: 14)),
        SizedBox(height: 6),
        Align(alignment: Alignment.centerRight, child: SkeletonBox(width: 110, height: 30, radius: 14)),
        SizedBox(height: 6),
        Align(alignment: Alignment.centerLeft, child: SkeletonBox(width: 190, height: 30, radius: 14)),
      ]);
}

class _DaySeparator extends StatelessWidget {
  final String label;
  const _DaySeparator(this.label);

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Expanded(child: Divider(color: p.line, height: 1)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(label, style: TextStyle(fontSize: 11.5, color: p.label))),
        Expanded(child: Divider(color: p.line, height: 1)),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final MarketMessage message;
  final bool grouped;
  final bool showTime;
  /// Our message and the buyer has opened the chat since it was sent.
  final bool seen;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;
  const _Bubble({required this.message, required this.grouped, required this.showTime, this.seen = false, required this.onRetry, required this.onDiscard});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final m = message;
    final mine = m.fromSeller;
    const r = Radius.circular(18);
    const tail = Radius.circular(6);
    final fg = mine ? Colors.white : p.text;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.78;
    final hasText = m.body.isNotEmpty || m.listing != null;
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: mine ? p.brand : p.card,
        border: mine ? null : Border.all(color: p.line),
        borderRadius: BorderRadius.only(
          topLeft: r,
          topRight: r,
          bottomLeft: !mine && !grouped ? tail : r,
          bottomRight: mine && !grouped ? tail : r,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (m.listing != null)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: mine ? Colors.black.withValues(alpha: 0.12) : p.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ListingThumb(m.listing!, size: 34),
              const SizedBox(width: 8),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(m.listing!.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
                  if (chatListingPrice(m.listing!).isNotEmpty)
                    Text(chatListingPrice(m.listing!), style: TextStyle(fontSize: 11.5, color: fg.withValues(alpha: 0.8))),
                ]),
              ),
            ]),
          ),
        if (m.body.isNotEmpty) Text(m.body, style: TextStyle(fontSize: 14.5, height: 1.35, color: fg)),
      ]),
    );

    Widget meta;
    if (m.failed) {
      meta = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 13, color: p.error),
        const SizedBox(width: 4),
        Text('Not sent', style: TextStyle(fontSize: 11.5, color: p.error, fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        _MetaAction(label: 'Retry', color: p.brand, onTap: onRetry),
        const SizedBox(width: 10),
        _MetaAction(label: 'Discard', color: p.label, onTap: onDiscard),
      ]);
    } else if (m.pending) {
      final pct = m.attachments.isNotEmpty && m.progress > 0 ? ' ${(m.progress * 100).round()}%' : '';
      meta = Text('Sending…$pct', style: TextStyle(fontSize: 11, color: p.label));
    } else if (showTime && mine) {
      // Read status on our own messages: one tick sent, blue double tick seen.
      meta = Row(mainAxisSize: MainAxisSize.min, children: [
        Text(chatClock(m.createdAt), style: TextStyle(fontSize: 11, color: p.label)),
        const SizedBox(width: 4),
        Icon(seen ? Icons.done_all : Icons.done, size: 14, color: seen ? p.info : p.label),
        const SizedBox(width: 2),
        Text(seen ? 'Seen' : 'Sent', style: TextStyle(fontSize: 11, color: seen ? p.info : p.label)),
      ]);
    } else if (showTime) {
      meta = Text(chatClock(m.createdAt), style: TextStyle(fontSize: 11, color: p.label));
    } else {
      meta = const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(top: grouped ? 2 : 10),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            if (m.attachments.isNotEmpty)
              Opacity(
                opacity: m.failed ? 0.6 : 1,
                child: ChatMessageAttachments(attachments: m.attachments, maxWidth: maxWidth, pending: m.pending, progress: m.progress),
              ),
            if (m.attachments.isNotEmpty && hasText) const SizedBox(height: 4),
            if (hasText || m.attachments.isEmpty) Opacity(opacity: m.pending ? 0.7 : (m.failed ? 0.6 : 1), child: bubble),
            if (m.failed || m.pending || showTime) Padding(padding: const EdgeInsets.fromLTRB(4, 3, 4, 0), child: meta),
          ]),
        ),
      ),
    );
  }
}

class _MetaAction extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MetaAction({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ),
      );
}
