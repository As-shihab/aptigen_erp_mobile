import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/async_state_view.dart';
import '../../data/employee_dashboard_service.dart';

const Map<String, Color> _leaveStatusColors = {
  'PENDING': AppColors.warning,
  'APPROVED': AppColors.success,
  'REJECTED': AppColors.error,
  'CANCELLED': AppColors.slate400,
};

class MyLeaveTab extends StatefulWidget {
  final int employeeId;
  const MyLeaveTab({super.key, required this.employeeId});

  @override
  State<MyLeaveTab> createState() => _MyLeaveTabState();
}

class _MyLeaveTabState extends State<MyLeaveTab> {
  final _service = EmployeeDashboardService(ApiClient());
  bool _loading = true;
  String? _error;
  List<dynamic> _requests = [];
  List<dynamic> _balances = [];
  List<dynamic> _leaveTypes = [];

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
      final workspace = await _service.getLeaveWorkspace(widget.employeeId);
      if (!mounted) return;
      setState(() {
        _requests = workspace['requests'] ?? [];
        _balances = workspace['balances'] ?? [];
        _leaveTypes = workspace['leaveTypes'] ?? [];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load leave.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(int id) async {
    try {
      await _service.cancelLeaveRequest(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leave request cancelled')));
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to cancel request')));
    }
  }

  Future<void> _openRequestSheet() async {
    int? leaveTypeId;
    DateTimeRange? range;
    final reasonController = TextEditingController();
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Request Leave', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: leaveTypeId,
                decoration: const InputDecoration(labelText: 'Leave Type'),
                items: _leaveTypes
                    .map((t) => (t as Map))
                    .map((t) => DropdownMenuItem<int>(
                          value: int.tryParse((t['id'] ?? '').toString()),
                          child: Text((t['name'] ?? '').toString()),
                        ))
                    .toList(),
                onChanged: (value) => setSheetState(() => leaveTypeId = value),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(
                  range == null
                      ? 'Select dates'
                      : '${DateFormat('dd MMM yyyy').format(range!.start)} → ${DateFormat('dd MMM yyyy').format(range!.end)}',
                ),
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDateRangePicker(
                    context: sheetContext,
                    firstDate: now.subtract(const Duration(days: 1)),
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (picked != null) setSheetState(() => range = picked);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Reason (optional)'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (leaveTypeId == null || range == null || saving)
                      ? null
                      : () async {
                          setSheetState(() => saving = true);
                          try {
                            final days = range!.end.difference(range!.start).inDays + 1;
                            await _service.createLeaveRequest(
                              employeeId: widget.employeeId,
                              leaveTypeId: leaveTypeId!,
                              startDate: range!.start,
                              endDate: range!.end,
                              daysCount: days,
                              reason: reasonController.text,
                            );
                            if (!sheetContext.mounted) return;
                            Navigator.of(sheetContext).pop();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leave request submitted')));
                            _load();
                          } catch (_) {
                            setSheetState(() => saving = false);
                            if (!sheetContext.mounted) return;
                            ScaffoldMessenger.of(sheetContext).showSnackBar(const SnackBar(content: Text('Failed to submit request')));
                          }
                        },
                  child: Text(saving ? 'Submitting...' : 'Submit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openRequestSheet,
        icon: const Icon(Icons.add),
        label: const Text('Request Leave'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: AsyncStateView(
          loading: _loading,
          error: _error,
          isEmpty: false,
          onRetry: _load,
          builder: (context) => ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (_balances.isNotEmpty)
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _balances.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final b = (_balances[index] as Map);
                      final leaveType = (b['leave_type'] as Map?)?['name']?.toString() ?? '—';
                      return Container(
                        width: 120,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.slate400.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(leaveType, style: TextStyle(fontSize: 9, color: AppColors.slate400), overflow: TextOverflow.ellipsis),
                            Text('${b['used']}/${b['allocated']} used', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              if (_requests.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Center(child: Text('No leave requests yet.', style: TextStyle(color: AppColors.slate600))),
                )
              else
                ..._requests.map((raw) {
                  final r = (raw as Map).cast<String, dynamic>();
                  final leaveType = (r['leave_type'] as Map?)?['name']?.toString() ?? '—';
                  final start = DateTime.tryParse((r['start_date'] ?? '').toString());
                  final end = DateTime.tryParse((r['end_date'] ?? '').toString());
                  final status = (r['status'] ?? '').toString();
                  final id = int.tryParse((r['id'] ?? '').toString()) ?? 0;
                  return Card(
                    child: ListTile(
                      title: Text(leaveType, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${start != null ? DateFormat('dd MMM yyyy').format(start) : '—'} → ${end != null ? DateFormat('dd MMM yyyy').format(end) : '—'} · ${r['days_count']} day(s)'
                        '${(r['reason'] ?? '').toString().isNotEmpty ? '\n"${r['reason']}"' : ''}',
                      ),
                      isThreeLine: (r['reason'] ?? '').toString().isNotEmpty,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          StatusChip(label: status, color: _leaveStatusColors[status] ?? AppColors.slate400),
                          if (status == 'PENDING')
                            TextButton(onPressed: () => _cancel(id), child: const Text('Cancel', style: TextStyle(fontSize: 12))),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
