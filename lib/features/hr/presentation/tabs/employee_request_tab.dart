import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/employee_dashboard_service.dart';
import 'dash_common.dart';

/// Ported from desktop tabs/EmployeeRequestTab.tsx — leave requests whose
/// current approval step belongs to this employee (by person or by
/// designation). Approve / reject logs to leave_request_approvals, then
/// advances the chain or finalises the request.
class EmployeeRequestTab extends DashSection {
  final int? designationId;
  final ValueChanged<int>? onCountChanged;
  const EmployeeRequestTab({super.key, required super.employeeId, this.designationId, super.refreshToken, this.onCountChanged});

  @override
  State<EmployeeRequestTab> createState() => _EmployeeRequestTabState();
}

class _EmployeeRequestTabState extends State<EmployeeRequestTab> with DashLoader<EmployeeRequestTab> {
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _chain = [];
  final Map<int, TextEditingController> _notes = {};
  int? _acting;

  @override
  Future<void> fetch() async {
    final res = await service.getPendingApprovals(employeeId: widget.employeeId, designationId: widget.designationId);
    if (!mounted) return;
    setState(() {
      _pending = res.pending;
      _chain = res.chain;
    });
    widget.onCountChanged?.call(res.pending.length);
  }

  @override
  void dispose() {
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _act(Map<String, dynamic> row, String status) async {
    final id = asInt(row['id']);
    final approve = status == 'APPROVED';
    final ok = await confirmMarket(
      context,
      title: approve ? 'Approve this leave?' : 'Reject this leave?',
      message: approve ? 'It moves to the next approver, or is approved if this is the last step.' : 'The request will be closed as rejected.',
      confirm: approve ? 'Approve' : 'Reject',
      destructive: !approve,
    );
    if (!ok) return;
    setState(() => _acting = id);
    try {
      await service.actOnLeaveRequest(row: row, chain: _chain, approverId: widget.employeeId, status: status, notes: _notes[id]?.text);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      marketToast(context, approve ? 'Leave approved' : 'Leave rejected');
      await reload();
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Action failed'), error: true);
    } finally {
      if (mounted) setState(() => _acting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = stateSliver(skeletons: 3, height: 180);
    if (state != null) return state;
    if (_pending.isEmpty) {
      return sliverEmpty(icon: Icons.fact_check_outlined, title: 'Nothing needs your approval', message: 'Leave requests routed to you will appear here.');
    }
    return sliverStagger(
      count: _pending.length,
      builder: (context, i) {
        final p = MarketPalette.of(context);
        final r = _pending[i];
        final id = asInt(r['id']);
        final name = fullName(r['employee'] as Map?);
        final type = (r['leave_type'] as Map?)?['name'] ?? '-';
        final days = asInt(r['days_count']);
        final step = EmployeeDashboardService.stepFor(_chain, r['leave_type_id'], r['current_serial']);
        final reason = stripHtml('${r['reason'] ?? ''}');
        final ctrl = _notes.putIfAbsent(id, TextEditingController.new);
        final acting = _acting == id;
        return GlowCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              InitialsAvatar(name.isEmpty ? '?' : name, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name.isEmpty ? '-' : name, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text)),
                  Text('$type · $days day${days == 1 ? '' : 's'}', style: TextStyle(fontSize: 12.5, color: p.label)),
                ]),
              ),
              StatusPill(step?['label']?.toString() ?? 'Step ${r['current_serial']}', tone: MarketTone.warn),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.date_range_rounded, size: 16, color: p.brand),
              const SizedBox(width: 6),
              Text('${fmtDate(parseDate(r['start_date']))} to ${fmtDate(parseDate(r['end_date']))}', style: TextStyle(fontSize: 12.5, color: p.text)),
            ]),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
                child: Text(reason, style: TextStyle(fontSize: 12.5, color: p.label, fontStyle: FontStyle.italic, height: 1.4)),
              ),
            ],
            const SizedBox(height: 10),
            TextField(controller: ctrl, maxLines: 2, minLines: 1, decoration: motionInput(context, hint: 'Note (optional)', icon: Icons.sticky_note_2_outlined)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: GradientButton(label: 'Approve', icon: Icons.check_rounded, accent: Accent.emerald, busy: acting, onTap: acting ? null : () => _act(r, 'APPROVED'))),
              const SizedBox(width: 10),
              Expanded(child: GradientButton(label: 'Reject', icon: Icons.close_rounded, accent: Accent.rose, busy: acting, onTap: acting ? null : () => _act(r, 'REJECTED'))),
            ]),
          ]),
        );
      },
    );
  }
}
