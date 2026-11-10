import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/network/socket_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/aptigen_app_bar.dart';
import '../../sell/market/presentation/messages/chat_page.dart';
import '../../sell/market/presentation/orders_page.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../data/notifications_service.dart';
import '../models/notification_model.dart';

String _relativeTime(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Real notification center — replaces the old "No notifications yet." stub
/// bottom sheet in home_shell_page.dart with an actual list backed by
/// cloud/src/module/notifications, mirroring erp/desktop's AppHeaderBar.tsx
/// notification popover: actor avatar per row (falls back to a bell tile for
/// system-generated rows with no actor), module badge, unread dot, mark one
/// / mark all read, pull to refresh, and live updates over the socket the
/// app already keeps connected (see socket_client.dart's `notifications:join`).
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _service = NotificationsService(ApiClient());
  List<AppNotification> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    AppSocket.instance?.on('notification:created', _onCreated);
  }

  @override
  void dispose() {
    AppSocket.instance?.off('notification:created', _onCreated);
    super.dispose();
  }

  void _onCreated(dynamic payload) {
    if (!mounted || payload is! Map) return;
    final row = AppNotification.fromJson(payload.cast<String, dynamic>());
    setState(() => _items = [row, ..._items]);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.list(top: 50);
      if (!mounted) return;
      setState(() {
        _items = result.rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load notifications.';
        _loading = false;
      });
    }
  }

  Future<void> _markRead(AppNotification item) async {
    if (item.isRead) return;
    setState(() {
      _items = _items.map((row) => row.id == item.id ? row.copyWith(isRead: true) : row).toList();
    });
    try {
      await _service.markRead(item.id);
    } catch (_) {
      // Local state already flipped — a failed sync just means it'll show
      // as read again next full reload; not worth surfacing an error for.
    }
  }

  /// Marks read, then follows links we can open in-app (market chat,
  /// website orders).
  void _onTap(AppNotification item) {
    _markRead(item);
    final chatId = marketChatIdFromLink(item.link);
    final order = marketOrderFromLink(item.link);
    if (chatId != null) {
      openMarketChatFromAnywhere(chatId);
    } else if (order.isOrders) {
      openMarketOrdersFromAnywhere(orderId: order.orderId);
    }
  }

  Future<void> _markAllRead() async {
    if (!_items.any((row) => !row.isRead)) return;
    setState(() {
      _items = _items.map((row) => row.copyWith(isRead: true)).toList();
    });
    try {
      await _service.markAllRead();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _items.where((row) => !row.isRead).length;
    return Scaffold(
      appBar: AptigenAppBar(
        title: 'Notifications',
        showBack: true,
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: _load,
        child: AsyncStateView(
          loading: _loading,
          error: _error,
          isEmpty: _items.isEmpty,
          emptyIcon: Icons.notifications_none,
          emptyMessage: "You'll see updates here as they happen.",
          onRetry: _load,
          builder: (context) => ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _NotificationTile(
              item: _items[index],
              onTap: () => _onTap(_items[index]),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification item;
  final VoidCallback onTap;
  const _NotificationTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: item.isRead
          ? (isDark ? const Color(0xFF1E293B) : Colors.white)
          : AppColors.brand.withValues(alpha: isDark ? 0.14 : 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.slate400.withValues(alpha: 0.15)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(item: item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (item.moduleName != null) ...[
                          StatusChip(label: item.moduleName!, color: AppColors.slate600),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: item.isRead ? FontWeight.w600 : FontWeight.w800,
                              color: isDark ? Colors.white : AppColors.slate900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if ((item.body ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.body!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: AppColors.slate600),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(_relativeTime(item.createdAt), style: TextStyle(fontSize: 11, color: AppColors.slate400)),
                  ],
                ),
              ),
              if (!item.isRead)
                Container(
                  margin: const EdgeInsets.only(left: 6, top: 4),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final AppNotification item;
  const _Avatar({required this.item});

  @override
  Widget build(BuildContext context) {
    final avatarUrl = item.actorAvatarUrl;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: item.isRead ? AppColors.slate100 : AppColors.brand,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl != null
          ? Image.network(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(Icons.notifications, size: 18, color: item.isRead ? AppColors.slate400 : Colors.white),
            )
          : Icon(Icons.notifications, size: 18, color: item.isRead ? AppColors.slate400 : Colors.white),
    );
  }
}
