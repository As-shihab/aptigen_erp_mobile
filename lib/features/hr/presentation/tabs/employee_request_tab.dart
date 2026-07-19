import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/async_state_view.dart';
import '../../data/employee_dashboard_service.dart';

class EmployeeRequestTab extends StatefulWidget {
  final int employeeId;
  final int? designationId;
  const EmployeeRequestTab({super.key, required this.employeeId, this.designationId});

  @override
  State<EmployeeRequestTab> createState() => _EmployeeRequestTabState();
}

class _EmployeeRequestTabState extends State<EmployeeRequestTab> {
  final _service = EmployeeDashboardService(ApiClient());
  bool _loading = true;
  String? _error;
  List<dynamic> _pending = [];
  final Map<int, TextEditingController> _notes = {};
  int? _acting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _notes.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.getPendingApprovals(employeeId: widget.employeeId, designationId: widget.designationId);
      if (!mounted) return;
      setState(() => _pending = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load requests.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(int id, String status) async {
    setState(() => _acting = id);
    try {
      await _service.actOnLeaveRequest(id, status: status, notes: _notes[id]?.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status == 'APPROVED' ? 'Leave approved' : 'Leave rejected')));
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action failed')));
    } finally {
      if (mounted) setState(() => _acting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: AsyncStateView(
        loading: _loading,
        error: _error,
        isEmpty: _pending.isEmpty,
        emptyMessage: 'Nothing needs your approval right now.',
        emptyIcon: Icons.fact_check_outlined,
        onRetry: _load,
        builder: (context) => ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _pending.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final r = (_pending[index] as Map).cast<String, dynamic>();
            final id = int.tryParse((r['id'] ?? '').toString()) ?? 0;
            final employee = (r['employee'] as Map?)?.cast<String, dynamic>() ?? {};
            final name = [employee['first_name'], employee['last_name']].where((s) => s != null && s.toString().trim().isNotEmpty).join(' ');
            final leaveType = (r['leave_type'] as Map?)?['name']?.toString() ?? '—';
            final start = DateTime.tryParse((r['start_date'] ?? '').toString());
            final end = DateTime.tryParse((r['end_date'] ?? '').toString());
            final controller = _notes.putIfAbsent(id, () => TextEditingController());
            final acting = _acting == id;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$name · $leaveType', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      '${start != null ? DateFormat('dd MMM yyyy').format(start) : '—'} → ${end != null ? DateFormat('dd MMM yyyy').format(end) : '—'} · ${r['days_count']} day(s)',
                      style: TextStyle(color: AppColors.slate600, fontSize: 11),
                    ),
                    if ((r['reason'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('"${r['reason']}"', style: TextStyle(color: AppColors.slate600, fontSize: 11, fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: controller,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Note (optional)'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                            onPressed: acting ? null : () => _act(id, 'APPROVED'),
                            child: Text(acting ? 'Saving...' : 'Approve'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                            onPressed: acting ? null : () => _act(id, 'REJECTED'),
                            child: Text(acting ? 'Saving...' : 'Reject'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
