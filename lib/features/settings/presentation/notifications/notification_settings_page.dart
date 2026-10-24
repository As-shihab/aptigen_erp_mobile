import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../../notifications/data/notifications_service.dart';
import '../../../notifications/models/notification_model.dart';
import '../../data/settings_service.dart';
import '../widgets/settings_widgets.dart';

/// Settings → Notifications. Desktop Notifications.tsx: push / email
/// preference switches (`/api/user/preference`) and the recent
/// notifications list. Adds read filters, mark read and mark all read.
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final _prefs = PreferenceService();
  final _notifs = NotificationsService(ApiClient());
  bool _push = true;
  bool _email = true;
  bool _prefsLoading = true;
  List<AppNotification> _rows = [];
  int _unread = 0;
  bool _loading = true;
  String? _error;
  String _chip = 'all';
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    final prefsF = _prefs.get().then((v) {
      if (!mounted) return;
      setState(() {
        _push = v.push;
        _email = v.email;
      });
    }).catchError((_) {}).whenComplete(() {
      if (mounted) setState(() => _prefsLoading = false);
    });
    try {
      final res = await _notifs.list(top: 100);
      if (!mounted) return;
      setState(() {
        _rows = res.rows;
        _unread = res.unreadCount;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load notifications'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await prefsF;
  }

  Future<void> _setPref(String key, bool v) async {
    final prev = key == 'push_notification' ? _push : _email;
    setState(() => key == 'push_notification' ? _push = v : _email = v);
    try {
      await _prefs.update({key: v});
    } catch (e) {
      if (!mounted) return;
      setState(() => key == 'push_notification' ? _push = prev : _email = prev);
      marketToast(context, errorMessage(e, 'Could not save preference'), error: true);
    }
  }

  Future<void> _markRead(AppNotification n) async {
    if (n.isRead) return;
    try {
      await _notifs.markRead(n.id);
      if (!mounted) return;
      _replace(n, true);
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not mark as read'), error: true);
    }
  }

  void _replace(AppNotification n, bool read) {
    setState(() {
      _rows = [
        for (final r in _rows)
          r.id == n.id
              ? AppNotification(
                  id: r.id,
                  title: r.title,
                  body: r.body,
                  link: r.link,
                  isRead: read,
                  createdAt: r.createdAt,
                  moduleName: r.moduleName,
                  actorName: r.actorName,
                  actorAvatarUrl: r.actorAvatarUrl,
                )
              : r,
      ];
      _unread = _rows.where((r) => !r.isRead).length;
    });
  }

  Future<void> _markAll() async {
    try {
      await _notifs.markAllRead();
      if (!mounted) return;
      marketToast(context, 'All notifications marked as read');
      _load();
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not mark all as read'), error: true);
    }
  }

  void _detail(AppNotification n) {
    _markRead(n);
    showMotionSheet<void>(context, (ctx) {
      final p = MarketPalette.of(ctx);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SheetGrabber(),
            Row(children: [
              InitialsAvatar(n.actorName ?? n.title, imageUrl: n.actorAvatarUrl, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
                  Text([if (n.actorName != null) n.actorName!, fmtDateTime(n.createdAt)].join(' · '), style: TextStyle(fontSize: 12, color: p.label)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            if ((n.body ?? '').isNotEmpty) Text(n.body!, style: TextStyle(fontSize: 14, height: 1.45, color: p.text)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, children: [
              StatusPill('Read', tone: MarketTone.ok),
              if (n.moduleName != null) StatusPill(humanize(n.moduleName), tone: MarketTone.brand),
            ]),
          ]),
        ),
      );
    });
  }

  List<AppNotification> get _visible {
    final q = _q.trim().toLowerCase();
    return _rows.where((n) {
      if (_chip == 'unread' && n.isRead) return false;
      if (_chip == 'read' && !n.isRead) return false;
      return q.isEmpty || '${n.title} ${n.body ?? ''} ${n.actorName ?? ''}'.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final rows = _visible;
    final unreadLocal = _rows.where((r) => !r.isRead).length;
    return MotionScaffold(
      title: 'Notifications',
      subtitle: _unread > 0 ? '$_unread unread' : 'Preferences and recent alerts',
      icon: Icons.notifications_active_outlined,
      accent: Accent.amber,
      onRefresh: _load,
      onFab: unreadLocal > 0 ? _markAll : null,
      fabLabel: 'Mark all read',
      fabIcon: Icons.done_all_rounded,
      headerExtra: HeaderSearch(hint: 'Search notifications', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        sliverBox(FadeSlideIn(
          child: SettingsSection(
            icon: Icons.tune_rounded,
            accent: Accent.amber,
            title: 'Notification preferences',
            subtitle: 'Choose how you want to be notified',
            child: _prefsLoading
                ? const Column(children: [SkeletonBox(height: 56, radius: 14), SizedBox(height: 10), SkeletonBox(height: 56, radius: 14)])
                : Column(children: [
                    SwitchField(label: 'Push notifications', sub: 'Live alerts pushed to this device', value: _push, onChanged: (v) => _setPref('push_notification', v)),
                    SwitchField(label: 'Email notifications', sub: 'Sent to your account email', value: _email, onChanged: (v) => _setPref('email_notification', v)),
                  ]),
          ),
        )),
        sliverBox(SectionHeader('Recent notifications', subtitle: '${_rows.length} latest'), padding: const EdgeInsets.fromLTRB(18, 0, 18, 0)),
        SliverToBoxAdapter(
          child: ChipFilter<String>(
            value: _chip,
            options: [
              (id: 'all', label: 'All', count: _rows.length),
              (id: 'unread', label: 'Unread', count: unreadLocal),
              (id: 'read', label: 'Read', count: _rows.length - unreadLocal),
            ],
            onChanged: (v) => setState(() => _chip = v),
          ),
        ),
        if (_loading)
          sliverSkeleton(count: 5, height: 72)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(icon: Icons.notifications_none_rounded, title: _rows.isEmpty ? 'No notifications yet' : 'Nothing here', message: _rows.isEmpty ? 'Alerts from your workplace will show up here.' : null)
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final n = rows[i];
              return MotionTile(
                key: ValueKey(n.id),
                leading: Stack(clipBehavior: Clip.none, children: [
                  InitialsAvatar(n.actorName ?? n.title, imageUrl: n.actorAvatarUrl, size: 42),
                  if (!n.isRead)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(width: 12, height: 12, decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle, border: Border.all(color: p.card, width: 2))),
                    ),
                ]),
                title: n.title,
                subtitle: n.body,
                meta: [timeAgo(n.createdAt), if (n.moduleName != null) humanize(n.moduleName)].join(' · '),
                trailing: StatusPill(n.isRead ? 'Read' : 'Unread', tone: n.isRead ? MarketTone.neutral : MarketTone.brand),
                onTap: () => _detail(n),
                onLongPress: n.isRead ? null : () => _markRead(n),
              );
            },
          ),
      ],
    );
  }
}
