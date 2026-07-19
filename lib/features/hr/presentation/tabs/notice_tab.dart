import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/async_state_view.dart';
import '../../data/employee_dashboard_service.dart';

String _readKey(int employeeId, int noticeId) => 'notice_read_${employeeId}_$noticeId';

class NoticeTab extends StatefulWidget {
  final int employeeId;
  final int? departmentId;
  const NoticeTab({super.key, required this.employeeId, this.departmentId});

  @override
  State<NoticeTab> createState() => _NoticeTabState();
}

class _NoticeTabState extends State<NoticeTab> {
  final _service = EmployeeDashboardService(ApiClient());
  bool _loading = true;
  String? _error;
  List<dynamic> _notices = [];
  Set<int> _readIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notices = await _service.getNotices(employeeId: widget.employeeId, departmentId: widget.departmentId);
      final prefs = await SharedPreferences.getInstance();
      final readIds = <int>{};
      for (final raw in notices) {
        final id = int.tryParse(((raw as Map)['id'] ?? '').toString()) ?? 0;
        if (id != 0 && prefs.getBool(_readKey(widget.employeeId, id)) == true) readIds.add(id);
      }
      if (!mounted) return;
      setState(() {
        _notices = notices;
        _readIds = readIds;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load notices.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _acknowledge(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_readKey(widget.employeeId, id), true);
    if (!mounted) return;
    setState(() => _readIds = {..._readIds, id});
  }

  void _openDetail(Map<String, dynamic> notice, int id) {
    final createdAt = DateTime.tryParse((notice['created_at'] ?? '').toString());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((notice['title'] ?? '').toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            if (createdAt != null)
              Text(DateFormat('dd MMM yyyy, HH:mm').format(createdAt), style: TextStyle(color: AppColors.slate400, fontSize: 11)),
            const SizedBox(height: 12),
            Text((notice['content'] ?? '').toString(), style: const TextStyle(height: 1.5)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.of(sheetContext).pop(), child: const Text('Close')),
                if (!_readIds.contains(id))
                  FilledButton(
                    onPressed: () {
                      _acknowledge(id);
                      Navigator.of(sheetContext).pop();
                    },
                    child: const Text('Got it'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: AsyncStateView(
        loading: _loading,
        error: _error,
        isEmpty: _notices.isEmpty,
        emptyMessage: 'No notices for you right now.',
        emptyIcon: Icons.notifications_none,
        onRetry: _load,
        builder: (context) => ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _notices.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final n = (_notices[index] as Map).cast<String, dynamic>();
            final id = int.tryParse((n['id'] ?? '').toString()) ?? 0;
            final read = _readIds.contains(id);
            final createdAt = DateTime.tryParse((n['created_at'] ?? '').toString());
            return ListTile(
              onTap: () => _openDetail(n, id),
              leading: Icon(read ? Icons.notifications_none : Icons.notifications_active, color: read ? AppColors.slate400 : AppColors.brand),
              title: Row(
                children: [
                  Flexible(child: Text((n['title'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                  if (!read) ...[
                    const SizedBox(width: 6),
                    const StatusChip(label: 'NEW', color: AppColors.brand),
                  ],
                ],
              ),
              subtitle: Text(
                '${(n['content'] ?? '').toString()}\n${createdAt != null ? DateFormat('dd MMM yyyy').format(createdAt) : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: true,
            );
          },
        ),
      ),
    );
  }
}
