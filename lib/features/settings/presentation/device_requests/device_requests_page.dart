import 'package:flutter/material.dart';
import '../../../../core/network/socket_client.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/settings_service.dart';
import '../widgets/settings_widgets.dart';

/// Settings → Device request. A first mobile sign-in from a new device
/// creates a PENDING `device_requests` row (see AuthService on the backend);
/// admins approve or reject it here. Live-refreshes on the
/// `device_request:created` socket event, same as desktop DeviceRequest.tsx.
class DeviceRequestsPage extends StatefulWidget {
  const DeviceRequestsPage({super.key});

  @override
  State<DeviceRequestsPage> createState() => _DeviceRequestsPageState();
}

class _DeviceRequestsPageState extends State<DeviceRequestsPage> {
  final _svc = DeviceRequestsService();
  List<JsonRow> _rows = [];
  bool _loading = true;
  String? _error;
  String _chip = 'PENDING';
  String _q = '';
  int? _memberId;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
    _svc.myMemberId().then((id) => _memberId = id);
    AppSocket.instance?.on('device_request:created', _onCreated);
  }

  @override
  void dispose() {
    AppSocket.instance?.off('device_request:created', _onCreated);
    super.dispose();
  }

  void _onCreated(dynamic _) {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    try {
      final rows = await _svc.list();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load device requests'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(JsonRow r, String status) async {
    final id = positiveInt(r['id']);
    if (id == null) return;
    if (status == 'REJECTED') {
      final ok = await confirmMarket(context, title: 'Reject this device?', message: '${_user(r)} will not be able to sign in from "${_device(r)}".', confirm: 'Reject');
      if (!ok) return;
    }
    setState(() => _busy.add(id));
    try {
      await _svc.decide(id, status, _memberId);
      if (!mounted) return;
      setState(() {
        r['status'] = status;
        r['approved_at'] = DateTime.now().toUtc().toIso8601String();
      });
      marketToast(context, status == 'APPROVED' ? 'Device approved' : 'Device rejected');
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Action failed'), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  String _user(JsonRow r) {
    final u = r['user'];
    if (u is Map) {
      for (final k in ['name', 'email', 'phone']) {
        if (str(u[k]).isNotEmpty) return str(u[k]);
      }
    }
    return 'User #${str(r['user_id'])}';
  }

  String _device(JsonRow r) => str(r['device_name']).isEmpty ? 'Unknown device' : str(r['device_name']);

  IconData _platformIcon(String p) => switch (p.toLowerCase()) {
        'ios' => Icons.phone_iphone_rounded,
        'android' => Icons.phone_android_rounded,
        _ => Icons.devices_other_rounded,
      };

  int _count(String s) => s == 'ALL' ? _rows.length : _rows.where((r) => str(r['status']).toUpperCase() == s).length;

  void _detail(JsonRow r) {
    showMotionSheet<void>(context, (ctx) {
      final p = MarketPalette.of(ctx);
      final status = str(r['status']).toUpperCase();
      final lat = r['latitude'];
      final lng = r['longitude'];
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SheetGrabber(),
            AccentIcon(_platformIcon(str(r['platform'])), accent: Accent.sky, size: 60),
            const SizedBox(height: 10),
            Text(_device(r), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
            Text(_user(r), style: TextStyle(fontSize: 13, color: p.label)),
            const SizedBox(height: 8),
            StatusPill(humanize(status), tone: toneForStatus(status)),
            const SizedBox(height: 14),
            GlowCard(
              child: Column(children: [
                InfoRow('Platform', str(r['platform']).isEmpty ? '-' : humanize(str(r['platform']))),
                InfoRow('Device id', str(r['device_id'])),
                InfoRow('Location', lat is num && lng is num ? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}' : '-'),
                InfoRow('Requested', fmtDateTime(parseDate(r['created_at']))),
                InfoRow('Last seen', parseDate(r['last_seen_at']) == null ? '-' : fmtDateTime(parseDate(r['last_seen_at']))),
                if (status != 'PENDING') InfoRow('Decided', parseDate(r['approved_at']) == null ? '-' : fmtDateTime(parseDate(r['approved_at']))),
              ]),
            ),
            if (status == 'PENDING') ...[
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: p.error, minimumSize: const Size.fromHeight(50)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _decide(r, 'REJECTED');
                    },
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GradientButton(
                    label: 'Approve',
                    icon: Icons.check_rounded,
                    accent: Accent.emerald,
                    onTap: () {
                      Navigator.pop(ctx);
                      _decide(r, 'APPROVED');
                    },
                  ),
                ),
              ]),
            ],
          ]),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final q = _q.trim().toLowerCase();
    final rows = _rows.where((r) {
      if (_chip != 'ALL' && str(r['status']).toUpperCase() != _chip) return false;
      return q.isEmpty || '${_user(r)} ${_device(r)} ${str(r['platform'])}'.toLowerCase().contains(q);
    }).toList();
    final pending = _count('PENDING');
    return MotionScaffold(
      title: 'Device request',
      subtitle: pending > 0 ? '$pending waiting for approval' : 'Approve phones that sign in',
      icon: Icons.phonelink_lock_outlined,
      accent: Accent.sky,
      onRefresh: _load,
      headerExtra: HeaderSearch(hint: 'Search user or device', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _chip,
              options: [
                (id: 'PENDING', label: 'Pending', count: pending),
                (id: 'APPROVED', label: 'Approved', count: _count('APPROVED')),
                (id: 'REJECTED', label: 'Rejected', count: _count('REJECTED')),
                (id: 'ALL', label: 'All', count: _rows.length),
              ],
              onChanged: (v) => setState(() => _chip = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton(height: 120)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.verified_user_outlined,
            title: _chip == 'PENDING' ? 'All caught up' : 'Nothing here',
            message: _chip == 'PENDING' ? 'New sign-in requests from phones appear here instantly.' : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final id = positiveInt(r['id']) ?? 0;
              final status = str(r['status']).toUpperCase();
              final busy = _busy.contains(id);
              return GlowCard(
                key: ValueKey(id),
                onTap: () => _detail(r),
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    AccentIcon(_platformIcon(str(r['platform'])), accent: status == 'PENDING' ? Accent.amber : (status == 'APPROVED' ? Accent.emerald : Accent.rose), size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_device(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text)),
                        Text(_user(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.label)),
                        Text('Requested ${timeAgo(parseDate(r['created_at']))}', style: TextStyle(fontSize: 11.5, color: p.label.withValues(alpha: 0.85))),
                      ]),
                    ),
                    StatusPill(humanize(status), tone: toneForStatus(status)),
                  ]),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: status != 'PENDING'
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: busy
                                ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4)))
                                : Row(children: [
                                    Expanded(child: _ActionPill(label: 'Reject', icon: Icons.close_rounded, tone: MarketTone.error, onTap: () => _decide(r, 'REJECTED'))),
                                    const SizedBox(width: 10),
                                    Expanded(child: _ActionPill(label: 'Approve', icon: Icons.check_rounded, tone: MarketTone.ok, onTap: () => _decide(r, 'APPROVED'))),
                                  ]),
                          ),
                  ),
                ]),
              );
            },
          ),
      ],
    );
  }
}

class _ActionPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final MarketTone tone;
  final VoidCallback onTap;
  const _ActionPill({required this.label, required this.icon, required this.tone, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = MarketPalette.of(context).tone(tone);
    return PressScale(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.fg.withValues(alpha: 0.3))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: c.fg),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.fg)),
        ]),
      ),
    );
  }
}
