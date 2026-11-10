import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../../core/network/http_client.dart';
import '../../../../../core/network/socket_client.dart';
import '../../../../notifications/data/module_unread_counts.dart';
import '../../data/market_messages_service.dart';
import '../widgets/market_ui.dart';
import 'chat_page.dart';
import 'message_widgets.dart';

/// Sell → Online market → Messages: the seller's inbox of buyer
/// conversations (erp/desktop MarketMessages.tsx). Live over the workplace
/// socket room (`market:message`, `market:message-read`).
class MarketMessagesPage extends StatefulWidget {
  const MarketMessagesPage({super.key});

  @override
  State<MarketMessagesPage> createState() => _MarketMessagesPageState();
}

class _MarketMessagesPageState extends State<MarketMessagesPage> {
  final _api = MarketMessagesService();
  final _search = TextEditingController();
  final _subs = <VoidCallback>[];

  List<MarketConversation> _rows = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  Timer? _reloadTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _subs
      ..add(AppSocket.subscribe('market:message', _onMessage))
      ..add(AppSocket.subscribe('market:message-read', _onRead))
      ..add(SellerMessagesUnread.attach());
    // The bell's "new message" notifications point here — clear them.
    _api.markNotificationsRead().then((changed) {
      if (changed) ModuleUnreadCounts.refresh();
    });
  }

  @override
  void dispose() {
    for (final off in _subs) {
      off();
    }
    _reloadTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _api.conversations();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent) return;
      setState(() {
        _error = e is ApiException && e.statusCode != 500 ? e.message : 'Could not load conversations. Check your connection and try again.';
        _loading = false;
      });
    }
  }

  void _onMessage(dynamic payload) {
    if (!mounted || payload is! Map) return;
    final convId = int.tryParse('${payload['conversation_id']}') ?? 0;
    final msg = payload['message'];
    if (convId == 0 || msg is! Map) return;
    final m = MarketMessage.fromJson(msg);
    final idx = _rows.indexWhere((c) => c.id == convId);
    if (idx == -1) {
      // A brand-new conversation — pull the list for buyer / listing details.
      _reloadTimer?.cancel();
      _reloadTimer = Timer(const Duration(milliseconds: 300), () => _load(silent: true));
      return;
    }
    final current = _rows[idx];
    final body = m.previewText.length > 200 ? m.previewText.substring(0, 200) : m.previewText;
    final updated = current.copyWith(
      lastMessage: body,
      lastMessageAt: m.createdAt,
      unread: m.fromSeller || ChatOpenTracker.openId == convId ? current.unread : current.unread + 1,
    );
    setState(() => _rows = [updated, ..._rows.take(idx), ..._rows.skip(idx + 1)]);
  }

  void _onRead(dynamic payload) {
    if (!mounted || payload is! Map || payload['side'] != 'seller') return;
    final convId = int.tryParse('${payload['conversation_id']}') ?? 0;
    setState(() => _rows = [for (final c in _rows) c.id == convId ? c.copyWith(unread: 0) : c]);
  }

  Future<void> _open(MarketConversation c) async {
    setState(() => _rows = [for (final r in _rows) r.id == c.id ? r.copyWith(unread: 0) : r]);
    await Navigator.of(context).push(marketRoute(MarketChatPage(conversationId: c.id, initial: c)));
    if (mounted) _load(silent: true);
  }

  List<MarketConversation> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows
        .where((c) => (c.buyer.name ?? '').toLowerCase().contains(q) || (c.listing?.title ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketScaffold(
      title: 'Messages',
      actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh))],
      body: Column(children: [
        Container(
          color: p.card,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            style: TextStyle(fontSize: 14, color: p.text),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search by buyer or product',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
              filled: true,
              fillColor: p.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
            ),
          ),
        ),
        Divider(height: 1, color: p.line),
        Expanded(child: RefreshIndicator(onRefresh: () => _load(silent: _rows.isNotEmpty), child: _body(p))),
      ]),
    );
  }

  Widget _body(MarketPalette p) {
    if (_loading && _rows.isEmpty) return const _InboxSkeleton();
    if (_error != null && _rows.isEmpty) {
      return ListView(children: [
        MarketEmpty(icon: Icons.cloud_off_outlined, title: 'Messages unavailable', message: _error, actionLabel: 'Try again', onAction: _load),
      ]);
    }
    if (_rows.isEmpty) {
      return ListView(children: const [
        MarketEmpty(
          icon: Icons.mark_chat_unread_outlined,
          title: 'No conversations yet',
          message: 'When a buyer messages your store from the market, the chat shows up here.',
        ),
      ]);
    }
    final rows = _filtered;
    if (rows.isEmpty) {
      return ListView(children: [
        MarketEmpty(icon: Icons.search_off, title: 'No matches', message: 'No buyers or products match "${_query.trim()}".'),
      ]);
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: rows.length,
      separatorBuilder: (_, _) => Divider(height: 1, indent: 72, color: p.line),
      itemBuilder: (_, i) => FadeSlideIn(index: i, child: _ConversationTile(conversation: rows[i], onTap: () => _open(rows[i]))),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final MarketConversation conversation;
  final VoidCallback onTap;
  const _ConversationTile({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final c = conversation;
    final unread = c.unread > 0;
    return Material(
      color: p.card,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            BuyerAvatar(c.buyer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(c.buyer.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14.5, fontWeight: unread ? FontWeight.w800 : FontWeight.w600, color: p.text)),
                  ),
                  const SizedBox(width: 8),
                  Text(chatListTime(c.lastMessageAt),
                      style: TextStyle(fontSize: 11.5, fontWeight: unread ? FontWeight.w700 : FontWeight.w400, color: unread ? p.brand : p.label)),
                ]),
                if (c.listing != null) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.inventory_2_outlined, size: 12, color: p.label),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(c.listing!.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
                    ),
                  ]),
                ],
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(
                    child: Text(
                      (c.lastMessage ?? '').trim().isEmpty ? 'No messages yet' : c.lastMessage!.replaceAll('\n', ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: unread ? FontWeight.w600 : FontWeight.w400, color: unread ? p.text : p.label),
                    ),
                  ),
                  if (unread) ...[const SizedBox(width: 8), UnreadBadge(c.unread)],
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _InboxSkeleton extends StatelessWidget {
  const _InboxSkeleton();

  @override
  Widget build(BuildContext context) => ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: 7,
        itemBuilder: (_, _) => const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            SkeletonBox(width: 44, height: 44, radius: 22),
            SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SkeletonBox(width: 140, height: 13),
                SizedBox(height: 8),
                SkeletonBox(height: 11),
              ]),
            ),
          ]),
        ),
      );
}
