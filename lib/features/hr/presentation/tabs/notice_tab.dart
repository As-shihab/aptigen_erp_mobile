import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/employee_dashboard_service.dart';
import 'dash_common.dart';

String _readKey(int employeeId, int noticeId) => 'notice_read_${employeeId}_$noticeId';

/// Ported from desktop tabs/NoticeTab.tsx — notices targeted at everyone,
/// the employee's department or the employee. Read state is per device,
/// like desktop's localStorage flag.
class NoticeTab extends DashSection {
  final int? departmentId;

  /// Called with the unread count after each load / acknowledgement.
  final ValueChanged<int>? onUnreadChanged;
  const NoticeTab({super.key, required super.employeeId, this.departmentId, super.refreshToken, this.onUnreadChanged});

  @override
  State<NoticeTab> createState() => _NoticeTabState();
}

class _NoticeTabState extends State<NoticeTab> with DashLoader<NoticeTab> {
  List<Map<String, dynamic>> _notices = [];
  Set<int> _read = {};
  String _filter = 'all';

  @override
  Future<void> fetch() async {
    final notices = await service.getNotices(employeeId: widget.employeeId, departmentId: widget.departmentId);
    final prefs = await SharedPreferences.getInstance();
    final read = <int>{
      for (final n in notices)
        if (prefs.getBool(_readKey(widget.employeeId, asInt(n['id']))) == true) asInt(n['id']),
    };
    if (!mounted) return;
    setState(() {
      _notices = notices;
      _read = read;
    });
    _report();
  }

  void _report() => widget.onUnreadChanged?.call(_notices.where((n) => !_read.contains(asInt(n['id']))).length);

  Future<void> _ack(Iterable<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    for (final id in ids) {
      await prefs.setBool(_readKey(widget.employeeId, id), true);
    }
    if (!mounted) return;
    setState(() => _read = {..._read, ...ids});
    _report();
  }

  Future<void> _open(Map<String, dynamic> n) async {
    final id = asInt(n['id']);
    final read = _read.contains(id);
    final ok = await showMotionSheet<bool>(context, (ctx) {
      final p = MarketPalette.of(ctx);
      return FormSheet(
        title: '${n['title'] ?? 'Notice'}',
        subtitle: fmtDateTime(parseDate(n['created_at'])),
        submitLabel: 'Got it',
        onSubmit: read ? null : () => Navigator.pop(ctx, true),
        children: [
          Text('${n['content'] ?? ''}', style: TextStyle(fontSize: 14, height: 1.6, color: p.text)),
          const SizedBox(height: 8),
        ],
      );
    });
    if (ok == true) _ack([id]);
  }

  @override
  Widget build(BuildContext context) {
    final state = stateSliver();
    if (state != null) return state;
    if (_notices.isEmpty) return sliverEmpty(icon: Icons.notifications_none_rounded, title: 'No notices for you right now');

    final unread = _notices.where((n) => !_read.contains(asInt(n['id']))).toList();
    final list = _filter == 'unread' ? unread : _notices;

    return SliverMainAxisGroup(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(children: [
            Expanded(
              child: ChipFilter<String>(
                value: _filter,
                onChanged: (v) => setState(() => _filter = v),
                options: [
                  (id: 'all', label: 'All', count: _notices.length),
                  (id: 'unread', label: 'Unread', count: unread.length),
                ],
              ),
            ),
            if (unread.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: () => _ack(unread.map((n) => asInt(n['id']))),
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: const Text('Mark all read'),
                ),
              ),
          ]),
        ),
      ),
      if (list.isEmpty)
        sliverEmpty(icon: Icons.mark_email_read_outlined, title: "You're all caught up")
      else
        sliverStagger(
          count: list.length,
          builder: (_, i) {
            final n = list[i];
            final isRead = _read.contains(asInt(n['id']));
            return MotionTile(
              onTap: () => _open(n),
              leading: AccentIcon(isRead ? Icons.notifications_none_rounded : Icons.notifications_active_rounded,
                  accent: isRead ? Accent.ocean : Accent.ocean, size: 42),
              title: '${n['title'] ?? ''}',
              subtitle: '${n['content'] ?? ''}',
              meta: fmtDate(parseDate(n['created_at'])),
              trailing: isRead ? null : const StatusPill('New', tone: MarketTone.brand),
            );
          },
        ),
    ]);
  }
}

/// Unread notice count for the dashboard badge (same per-device read flags).
Future<int> countUnreadNotices(EmployeeDashboardService service, {required int employeeId, int? departmentId}) async {
  final notices = await service.getNotices(employeeId: employeeId, departmentId: departmentId);
  final prefs = await SharedPreferences.getInstance();
  return notices.where((n) => prefs.getBool(_readKey(employeeId, asInt(n['id']))) != true).length;
}
