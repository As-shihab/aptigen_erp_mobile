import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/employee_dashboard_service.dart';
import 'dash_common.dart';
import 'hr_charts.dart';

DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

/// An approver has already acted once any step snapshot left PENDING — the
/// employee can no longer edit, cancel or delete (desktop rule).
bool _hasApprovalActivity(Map<String, dynamic> r) => r['steps'] is List && (r['steps'] as List).whereType<Map>().any((s) => '${s['status']}' != 'PENDING');

bool _editable(Map<String, dynamic> r) => '${r['status']}' == 'PENDING' && !_hasApprovalActivity(r);

List<Map<String, String>> _docsOf(Map<String, dynamic> r) {
  final list = r['document_urls'];
  if (list is List && list.isNotEmpty) {
    return list.whereType<Map>().map((m) => {'url': '${m['url'] ?? ''}', 'name': '${m['name'] ?? 'Document'}'}).where((m) => m['url']!.isNotEmpty).toList();
  }
  final single = '${r['document_url'] ?? ''}';
  return single.isEmpty ? [] : [{'url': single, 'name': single.split('/').last}];
}

String _approverName(Map<String, dynamic> step) {
  final emp = step['approver_emp'] as Map?;
  if (emp != null) return fullName(emp);
  final des = step['approver_des'] as Map?;
  if (des != null) return 'Any ${des['name']}';
  return 'Unassigned';
}

/// Ported from desktop tabs/MyLeaveTab.tsx — balance rings, request history
/// with edit / cancel / delete while untouched, and the step-by-step apply
/// wizard (type → dates → reason → documents when required → approvers →
/// status).
class MyLeaveTab extends DashSection {
  const MyLeaveTab({super.key, required super.employeeId, super.refreshToken});

  @override
  State<MyLeaveTab> createState() => MyLeaveTabState();
}

class MyLeaveTabState extends State<MyLeaveTab> with DashLoader<MyLeaveTab> {
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _balances = [];
  List<Map<String, dynamic>> _types = [];
  String _filter = 'ALL';

  @override
  Future<void> fetch() async {
    final w = await service.getLeaveWorkspace(widget.employeeId);
    if (!mounted) return;
    setState(() {
      _requests = w['requests']!;
      _balances = w['balances']!;
      _types = w['leaveTypes']!;
    });
  }

  List<({DateTime start, DateTime end, bool approved})> _taken(int? excludeId) => [
        for (final r in _requests)
          if (asInt(r['id']) != excludeId && ('${r['status']}' == 'PENDING' || '${r['status']}' == 'APPROVED'))
            if (parseDate(r['start_date']) != null && parseDate(r['end_date']) != null)
              (start: _d(parseDate(r['start_date'])!.toLocal()), end: _d(parseDate(r['end_date'])!.toLocal()), approved: '${r['status']}' == 'APPROVED'),
      ];

  /// Opens the apply wizard (also used by the dashboard FAB).
  Future<void> openApply([Map<String, dynamic>? editing]) async {
    if (loading) return;
    final saved = await showMotionSheet<bool>(
      context,
      (_) => _LeaveWizard(
        service: service,
        employeeId: widget.employeeId,
        types: _types,
        balances: _balances,
        taken: _taken(editing == null ? null : asInt(editing['id'])),
        editing: editing,
      ),
    );
    if (saved == true) reload();
  }

  Future<void> _cancel(Map<String, dynamic> r) async {
    final ok = await confirmMarket(context, title: 'Cancel this request?', message: 'Your approvers will no longer see it.', confirm: 'Cancel request');
    if (!ok) return;
    try {
      await service.cancelLeaveRequest(asInt(r['id']));
      if (mounted) marketToast(context, 'Leave request cancelled');
      reload();
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Failed to cancel request'), error: true);
    }
  }

  Future<bool> _delete(Map<String, dynamic> r) async {
    final ok = await confirmMarket(context, title: 'Delete this request?', message: 'Delete this ${(r['leave_type'] as Map?)?['name'] ?? 'leave'} request? This cannot be undone.');
    if (!ok) return false;
    try {
      await service.deleteLeaveRequest(asInt(r['id']));
      if (mounted) marketToast(context, 'Leave request deleted');
      reload();
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Failed to delete request'), error: true);
      return false;
    }
  }

  Future<void> _actions(Map<String, dynamic> r) async {
    final key = await showActionSheet(context, title: (r['leave_type'] as Map?)?['name']?.toString() ?? 'Leave request', actions: [
      (key: 'view', label: 'View details', icon: Icons.visibility_outlined, destructive: false),
      if (_editable(r)) ...[
        (key: 'edit', label: 'Edit request', icon: Icons.edit_outlined, destructive: false),
        (key: 'cancel', label: 'Cancel request', icon: Icons.block_rounded, destructive: true),
        (key: 'delete', label: 'Delete request', icon: Icons.delete_outline_rounded, destructive: true),
      ],
    ]);
    if (!mounted) return;
    switch (key) {
      case 'view':
        _details(r);
      case 'edit':
        openApply(r);
      case 'cancel':
        _cancel(r);
      case 'delete':
        _delete(r);
    }
  }

  void _details(Map<String, dynamic> r) {
    final docs = _docsOf(r);
    final steps = (r['steps'] as List?)?.whereType<Map>().toList() ?? const [];
    showMotionSheet<void>(context, (ctx) {
      final p = MarketPalette.of(ctx);
      final reason = stripHtml('${r['reason'] ?? ''}');
      return FormSheet(
        title: '${(r['leave_type'] as Map?)?['name'] ?? 'Leave request'}',
        subtitle: '${fmtDate(parseDate(r['start_date']))} to ${fmtDate(parseDate(r['end_date']))} · ${r['days_count']} day(s)',
        children: [
          Row(children: [StatusPill(humanize('${r['status']}'), tone: toneForStatus('${r['status']}'))]),
          const SizedBox(height: 12),
          if (reason.isNotEmpty) ...[
            const SectionHeader('Reason'),
            Text(reason, style: TextStyle(fontSize: 13.5, color: p.text, height: 1.5)),
            const SizedBox(height: 12),
          ],
          if (steps.isNotEmpty) ...[
            const SectionHeader('Approval chain'),
            for (var i = 0; i < steps.length; i++) _StepRow(step: steps[i].cast<String, dynamic>(), last: i == steps.length - 1, current: asInt(r['current_serial']) == asInt(steps[i]['serial'])),
            const SizedBox(height: 8),
          ],
          if (docs.isNotEmpty) ...[
            const SectionHeader('Documents'),
            _DocStrip(docs: docs),
            const SizedBox(height: 8),
          ],
          if (_editable(r))
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    openApply(r);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: p.error),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _cancel(r);
                  },
                  icon: const Icon(Icons.block_rounded, size: 18),
                  label: const Text('Cancel'),
                ),
              ),
            ]),
          const SizedBox(height: 12),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = stateSliver();
    if (state != null) return state;

    int count(String s) => _requests.where((r) => '${r['status']}' == s).length;
    final list = _filter == 'ALL' ? _requests : _requests.where((r) => '${r['status']}' == _filter).toList();

    return SliverMainAxisGroup(slivers: [
      if (_balances.isNotEmpty) ...[
        sliverBox(const SectionHeader('Balances', subtitle: 'This year')),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.9),
            itemCount: _balances.length,
            itemBuilder: (_, i) => FadeSlideIn(index: i, child: _BalanceCard(row: _balances[i], color: chartColorAt(i))),
          ),
        ),
      ],
      sliverBox(SectionHeader('My requests', subtitle: '${_requests.length} in total',
          trailing: TextButton.icon(onPressed: openApply, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Apply')))),
      SliverToBoxAdapter(
        child: ChipFilter<String>(
          value: _filter,
          onChanged: (v) => setState(() => _filter = v),
          options: [
            (id: 'ALL', label: 'All', count: _requests.length),
            (id: 'PENDING', label: 'Pending', count: count('PENDING')),
            (id: 'APPROVED', label: 'Approved', count: count('APPROVED')),
            (id: 'REJECTED', label: 'Rejected', count: count('REJECTED')),
            (id: 'CANCELLED', label: 'Cancelled', count: count('CANCELLED')),
          ],
        ),
      ),
      if (list.isEmpty)
        sliverEmpty(
          icon: Icons.flight_takeoff_rounded,
          title: _requests.isEmpty ? 'No leave requests yet' : 'Nothing matches this filter',
          actionLabel: _requests.isEmpty ? 'Apply for leave' : null,
          onAction: _requests.isEmpty ? openApply : null,
        )
      else
        sliverStagger(
          count: list.length,
          builder: (_, i) => _RequestCard(
            row: list[i],
            onTap: () => _details(list[i]),
            onLongPress: () => _actions(list[i]),
            onDelete: _editable(list[i]) ? () => _delete(list[i]) : null,
          ),
        ),
    ]);
  }
}

class _BalanceCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final Color color;
  const _BalanceCard({required this.row, required this.color});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final used = toDouble(row['used']);
    final total = toDouble(row['allocated'] ?? row['total']);
    final left = (total - used).clamp(0, double.infinity);
    return GlowCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        ProgressRing(
          value: total > 0 ? used / total : 0,
          size: 52,
          stroke: 6,
          color: color,
          center: CountUp(value: left, format: (v) => '${v.round()}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.text)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${(row['leave_type'] as Map?)?['name'] ?? row['name'] ?? '-'}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 2),
            Text('${used.round()} used · ${left.round()} left', style: TextStyle(fontSize: 11, color: p.label)),
          ]),
        ),
      ]),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Future<bool> Function()? onDelete;
  const _RequestCard({required this.row, required this.onTap, required this.onLongPress, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final status = '${row['status']}';
    final steps = (row['steps'] as List?)?.whereType<Map>().toList() ?? const [];
    final docs = _docsOf(row);
    final reason = stripHtml('${row['reason'] ?? ''}');
    final days = asInt(row['days_count']);
    final card = GlowCard(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AccentIcon(Icons.flight_takeoff_rounded, accent: switch (status) { 'APPROVED' => Accent.emerald, 'REJECTED' => Accent.rose, 'CANCELLED' => Accent.ocean, _ => Accent.amber }, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${(row['leave_type'] as Map?)?['name'] ?? '-'}', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text)),
              Text('${fmtDate(parseDate(row['start_date']))} to ${fmtDate(parseDate(row['end_date']))}', style: TextStyle(fontSize: 12, color: p.label)),
            ]),
          ),
          StatusPill(humanize(status), tone: toneForStatus(status)),
        ]),
        if (reason.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.label, height: 1.35)),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.today_rounded, size: 15, color: p.brand),
          const SizedBox(width: 4),
          Text('$days day${days == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: p.text, fontWeight: FontWeight.w600)),
          if (docs.isNotEmpty) ...[
            const SizedBox(width: 12),
            Icon(Icons.attach_file_rounded, size: 15, color: p.brand),
            Text('${docs.length}', style: TextStyle(fontSize: 12, color: p.text, fontWeight: FontWeight.w600)),
          ],
          const Spacer(),
          for (final s in steps)
            Container(
              width: 18,
              height: 6,
              margin: const EdgeInsets.only(left: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: switch ('${s['status']}') { 'APPROVED' => p.ok, 'REJECTED' => p.error, 'SKIPPED' => p.neutral, _ => p.line },
              ),
            ),
        ]),
      ]),
    );
    if (onDelete == null) return card;
    return Dismissible(
      key: ValueKey('leave_${row['id']}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onDelete!(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(color: p.errorBg, borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.delete_outline_rounded, color: p.error),
      ),
      child: card,
    );
  }
}

class _StepRow extends StatelessWidget {
  final Map<String, dynamic> step;
  final bool last;
  final bool current;
  const _StepRow({required this.step, required this.last, required this.current});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final status = '${step['status'] ?? 'PENDING'}';
    final color = switch (status) { 'APPROVED' => p.ok, 'REJECTED' => p.error, 'SKIPPED' => p.neutral, _ => current ? p.warn : p.line };
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: status == 'APPROVED'
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 15)
                : status == 'REJECTED'
                    ? const Icon(Icons.close_rounded, color: Colors.white, size: 15)
                    : Text('${step['serial']}', style: TextStyle(color: current ? Colors.white : p.label, fontSize: 11.5, fontWeight: FontWeight.w800)),
          ),
          if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: p.line)),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 3),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${step['label'] ?? 'Step ${step['serial']}'}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
                  if (step['is_required'] == false) Text('Optional', style: TextStyle(fontSize: 11, color: p.label)),
                ]),
              ),
              StatusPill(humanize(status), tone: toneForStatus(status)),
            ]),
          ),
        ),
      ]),
    );
  }
}

bool _isImage(String url) => RegExp(r'\.(png|jpe?g|gif|webp|heic|bmp)(\?|$)', caseSensitive: false).hasMatch(url);

class _DocStrip extends StatelessWidget {
  final List<Map<String, String>> docs;
  final void Function(String url)? onRemove;
  const _DocStrip({required this.docs, this.onRemove});

  void _open(BuildContext context, Map<String, String> doc) {
    final url = doc['url']!;
    if (!_isImage(url)) {
      Clipboard.setData(ClipboardData(text: url));
      marketToast(context, 'Link copied');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Padding(padding: EdgeInsets.all(40), child: Text('Could not load file')))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(children: [
      for (var i = 0; i < docs.length; i++)
        FadeSlideIn(
          index: i,
          offsetY: 6,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PressScale(
              onTap: () => _open(context, docs[i]),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: _isImage(docs[i]['url']!)
                          ? Image.network(docs[i]['url']!, fit: BoxFit.cover, errorBuilder: (_, _, _) => Icon(Icons.description_outlined, color: p.label))
                          : Container(color: p.card, child: Icon(Icons.description_outlined, color: p.brand)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(docs[i]['name']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.text, fontWeight: FontWeight.w600))),
                  if (onRemove != null)
                    IconButton(onPressed: () => onRemove!(docs[i]['url']!), icon: Icon(Icons.close_rounded, color: p.error, size: 19))
                  else
                    Icon(Icons.open_in_full_rounded, color: p.label, size: 18),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

// ── Apply / edit wizard ─────────────────────────────────────────────────

enum _Step { type, dates, reason, documents, approvers, status }

extension on _Step {
  String get label => switch (this) {
        _Step.type => 'Type',
        _Step.dates => 'Dates',
        _Step.reason => 'Reason',
        _Step.documents => 'Documents',
        _Step.approvers => 'Approvers',
        _Step.status => 'Status',
      };
}

class _LeaveWizard extends StatefulWidget {
  final EmployeeDashboardService service;
  final int employeeId;
  final List<Map<String, dynamic>> types;
  final List<Map<String, dynamic>> balances;
  final List<({DateTime start, DateTime end, bool approved})> taken;
  final Map<String, dynamic>? editing;
  const _LeaveWizard({required this.service, required this.employeeId, required this.types, required this.balances, required this.taken, this.editing});

  @override
  State<_LeaveWizard> createState() => _LeaveWizardState();
}

class _LeaveWizardState extends State<_LeaveWizard> {
  int? _typeId;
  final Set<DateTime> _dates = {};
  final _reason = TextEditingController();
  List<Map<String, String>> _docs = [];
  List<Map<String, dynamic>> _approvers = [];
  bool _approversLoading = false;
  bool _uploading = false;
  bool _saving = false;
  bool _submitted = false;
  int _index = 0;
  int _dir = 1;
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    if (e != null) {
      _typeId = asInt(e['leave_type_id']);
      final s = parseDate(e['start_date']);
      final en = parseDate(e['end_date']);
      if (s != null && en != null) {
        var c = _d(s.toLocal());
        final end = _d(en.toLocal());
        while (!c.isAfter(end)) {
          _dates.add(c);
          c = DateTime(c.year, c.month, c.day + 1);
        }
        _month = DateTime(s.toLocal().year, s.toLocal().month);
      }
      _reason.text = stripHtml('${e['reason'] ?? ''}');
      _docs = _docsOf(e);
      _loadApprovers();
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _type => widget.types.where((t) => asInt(t['id']) == _typeId).firstOrNull;
  bool get _needsDoc => asBool(_type?['requires_document']);
  List<_Step> get _steps => [_Step.type, _Step.dates, _Step.reason, if (_needsDoc) _Step.documents, _Step.approvers, _Step.status];
  _Step get _step => _steps[_index.clamp(0, _steps.length - 1)];

  bool get _canNext => switch (_step) {
        _Step.type => _typeId != null,
        _Step.dates => _dates.isNotEmpty,
        _Step.documents => _docs.isNotEmpty && !_uploading,
        _ => true,
      };

  Future<void> _loadApprovers() async {
    final id = _typeId;
    if (id == null) return;
    setState(() => _approversLoading = true);
    try {
      final rows = await widget.service.getApproverChain(id);
      if (mounted && _typeId == id) setState(() => _approvers = rows);
    } catch (_) {
      if (mounted) setState(() => _approvers = []);
    } finally {
      if (mounted) setState(() => _approversLoading = false);
    }
  }

  void _go(int delta) {
    HapticFeedback.selectionClick();
    setState(() {
      _dir = delta;
      _index = (_index + delta).clamp(0, _steps.length - 1);
    });
  }

  bool _isTaken(DateTime d) => widget.taken.any((t) => !d.isBefore(t.start) && !d.isAfter(t.end));

  Future<void> _pickDocs() async {
    final src = await showActionSheet(context, title: 'Add a document', actions: [
      (key: 'camera', label: 'Take a photo', icon: Icons.photo_camera_outlined, destructive: false),
      (key: 'gallery', label: 'Choose from gallery', icon: Icons.photo_library_outlined, destructive: false),
    ]);
    if (src == null) return;
    final picker = ImagePicker();
    List<XFile> files;
    try {
      if (src == 'camera') {
        final f = await picker.pickImage(source: ImageSource.camera, maxWidth: 2400, imageQuality: 85);
        files = f == null ? [] : [f];
      } else {
        files = await picker.pickMultiImage(maxWidth: 2400, imageQuality: 85);
      }
    } catch (_) {
      if (mounted) marketToast(context, 'Could not open the picker', error: true);
      return;
    }
    if (files.isEmpty) return;
    setState(() => _uploading = true);
    try {
      for (final f in files) {
        final doc = await widget.service.uploadLeaveDocument(await f.readAsBytes(), f.name);
        if (!mounted) return;
        setState(() => _docs = [..._docs, doc]);
      }
      if (mounted) marketToast(context, files.length > 1 ? 'Documents uploaded' : 'Document uploaded');
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Failed to upload document'), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    if (_typeId == null || _dates.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.service.saveLeaveRequest(
        editingId: widget.editing == null ? null : asInt(widget.editing!['id']),
        employeeId: widget.employeeId,
        leaveTypeId: _typeId!,
        dates: _dates.toList(),
        reason: _reason.text,
        documents: _docs,
        approvers: _approvers,
      );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _dir = 1;
        _index = _steps.length - 1;
      });
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Failed to save request'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final steps = _steps;
    final isApprovers = _step == _Step.approvers;
    final isLast = _step == _Step.status;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SheetGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
          child: Row(children: [
            Expanded(
              child: Text(widget.editing != null ? 'Edit leave request' : 'Apply for leave',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
            ),
            IconButton(onPressed: () => Navigator.pop(context, _submitted), icon: Icon(Icons.close_rounded, color: p.label)),
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: _Stepper(steps: steps.map((s) => s.label).toList(), index: _index)),
        Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: Offset(0.08 * _dir, 0), end: Offset.zero).animate(a), child: child),
            ),
            child: SingleChildScrollView(
              key: ValueKey(_step),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: _body(p),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: Row(children: [
              if (_index > 0 && !isLast) ...[
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: _saving ? null : () => _go(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                    label: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: 3,
                child: isLast
                    ? GradientButton(label: 'Done', icon: Icons.check_rounded, onTap: () => Navigator.pop(context, _submitted))
                    : isApprovers
                        ? GradientButton(
                            label: widget.editing != null ? 'Save changes' : 'Submit request',
                            icon: Icons.send_rounded,
                            busy: _saving,
                            accent: Accent.emerald,
                            onTap: (_typeId == null || _dates.isEmpty) ? null : _submit,
                          )
                        : GradientButton(label: 'Next', icon: Icons.chevron_right_rounded, onTap: _canNext ? () => _go(1) : null),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _body(MarketPalette p) {
    switch (_step) {
      case _Step.type:
        final bal = widget.balances.where((b) => asInt(b['leave_type_id']) == _typeId).firstOrNull;
        final total = bal != null ? toDouble(bal['allocated'] ?? bal['total']) : toDouble(_type?['max_days_per_year']);
        final used = bal != null ? toDouble(bal['used']) : 0.0;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormLabel(
            label: 'Leave type',
            required: true,
            child: PickerField(
              value: _typeId,
              hint: 'Select leave type',
              icon: Icons.category_outlined,
              allowClear: false,
              options: [for (final t in widget.types) PickOption(asInt(t['id']), '${t['name']}', sub: asBool(t['requires_document']) ? 'Needs a supporting document' : null)],
              onChanged: (v) {
                setState(() {
                  _typeId = v == null ? null : asInt(v);
                  _approvers = [];
                });
                _loadApprovers();
              },
            ),
          ),
          if (_needsDoc)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Icon(Icons.upload_file_rounded, size: 16, color: p.warn),
                const SizedBox(width: 6),
                Expanded(child: Text('This leave type requires a supporting document.', style: TextStyle(fontSize: 12, color: p.warn, fontWeight: FontWeight.w600))),
              ]),
            ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _type == null
                ? Container(
                    key: const ValueKey('none'),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
                    child: Text('Select a leave type to see your balance.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: p.label)),
                  )
                : GlowCard(
                    key: ValueKey(_typeId),
                    child: Row(children: [
                      ProgressRing(
                        value: total > 0 ? used / total : 0,
                        size: 66,
                        color: p.brand,
                        center: Text('${(total - used).clamp(0, double.infinity).round()}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${(total - used).clamp(0, double.infinity).round()} of ${total.round()} days remaining',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                          Text('${used.round()} used', style: TextStyle(fontSize: 12, color: p.label)),
                          if (bal == null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text("No balance allocated yet this year, showing the type's default.", style: TextStyle(fontSize: 11, color: p.label)),
                            ),
                        ]),
                      ),
                    ]),
                  ),
          ),
        ]);
      case _Step.dates:
        final sorted = _dates.toList()..sort();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _MultiDateCalendar(
            month: _month,
            selected: _dates,
            isTaken: _isTaken,
            takenColor: (d) => widget.taken.firstWhere((t) => !d.isBefore(t.start) && !d.isAfter(t.end)).approved ? p.error : p.warn,
            onMonth: (m) => setState(() => _month = m),
            onToggle: (d) {
              HapticFeedback.selectionClick();
              setState(() => _dates.contains(d) ? _dates.remove(d) : _dates.add(d));
            },
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 12, children: [
            _dot(p, p.warn, 'Pending leave'),
            _dot(p, p.error, 'Approved leave'),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Text('${_dates.length} day${_dates.length == 1 ? '' : 's'} selected', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text)),
              const Spacer(),
              if (sorted.isNotEmpty) Text('${DateFormat('d MMM').format(sorted.first)} to ${DateFormat('d MMM yyyy').format(sorted.last)}', style: TextStyle(fontSize: 12, color: p.label)),
            ]),
          ),
        ]);
      case _Step.reason:
        return FormLabel(
          label: 'Reason',
          child: TextField(controller: _reason, minLines: 5, maxLines: 10, decoration: motionInput(context, hint: 'Describe the reason for this leave')),
        );
      case _Step.documents:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('This leave type requires at least one supporting document. You can attach more than one.', style: TextStyle(fontSize: 12.5, color: p.label)),
          const SizedBox(height: 12),
          if (_docs.isNotEmpty) _DocStrip(docs: _docs, onRemove: (url) => setState(() => _docs = _docs.where((d) => d['url'] != url).toList())),
          PressScale(
            onTap: _uploading ? null : _pickDocs,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.brand.withValues(alpha: 0.5)), color: p.brandSoft),
              child: Column(children: [
                _uploading
                    ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4, color: p.brand))
                    : Icon(Icons.cloud_upload_outlined, color: p.brand, size: 28),
                const SizedBox(height: 6),
                Text(_uploading ? 'Uploading' : (_docs.isEmpty ? 'Tap to add document photos' : 'Add another document'),
                    style: TextStyle(fontSize: 13, color: p.brand, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]);
      case _Step.approvers:
        if (_approversLoading) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
        if (_approvers.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
            child: Text('No approval chain configured for this leave type. It will be reviewed directly by HR.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: p.label)),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('This request will be reviewed in order by:', style: TextStyle(fontSize: 12.5, color: p.label)),
          const SizedBox(height: 10),
          for (var i = 0; i < _approvers.length; i++)
            FadeSlideIn(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MotionTile(
                  leading: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: i == 0 ? Accent.ocean.gradient : Accent.ocean.gradient),
                    child: Text('${_approvers[i]['serial']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                  title: '${_approvers[i]['label'] ?? 'Step'}',
                  subtitle: '${_approverName(_approvers[i])}${_approvers[i]['is_required'] == false ? ' · optional' : ''}',
                  trailing: const StatusPill('Pending', tone: MarketTone.warn),
                ),
              ),
            ),
        ]);
      case _Step.status:
        final first = _approvers.isEmpty ? 'HR' : _approverName(_approvers.first);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: _submitted ? Accent.ocean.gradient : Accent.ocean.gradient),
                child: Icon(_submitted ? Icons.hourglass_top_rounded : Icons.error_outline_rounded, color: Colors.white, size: 40),
              ),
            ),
            const SizedBox(height: 16),
            Text(_submitted ? 'Request submitted' : 'Not submitted yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.text)),
            const SizedBox(height: 6),
            Text(
              _submitted ? "Status: pending, awaiting $first's approval." : 'Go back and submit the request to see its status here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: p.label),
            ),
          ]),
        );
    }
  }

  Widget _dot(MarketPalette p, Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11.5, color: p.label)),
      ]);
}

class _Stepper extends StatelessWidget {
  final List<String> steps;
  final int index;
  const _Stepper({required this.steps, required this.index});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Row(children: [
      for (var i = 0; i < steps.length; i++) ...[
        Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: i <= index ? Accent.ocean.gradient : null,
              color: i <= index ? null : p.surface,
            ),
            child: i < index
                ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                : Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: i == index ? Colors.white : p.label)),
          ),
          const SizedBox(height: 4),
          Text(steps[i], style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: i <= index ? Accent.ocean.primary : p.label)),
        ]),
        if (i < steps.length - 1)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16, left: 2, right: 2),
              child: GrowBar(value: i < index ? 1 : 0, color: Accent.ocean.primary, height: 3),
            ),
          ),
      ],
    ]);
  }
}

class _MultiDateCalendar extends StatelessWidget {
  final DateTime month;
  final Set<DateTime> selected;
  final bool Function(DateTime) isTaken;
  final Color Function(DateTime) takenColor;
  final ValueChanged<DateTime> onMonth;
  final ValueChanged<DateTime> onToggle;
  const _MultiDateCalendar({required this.month, required this.selected, required this.isTaken, required this.takenColor, required this.onMonth, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final lead = DateTime(month.year, month.month, 1).weekday % 7;
    final daysIn = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((lead + daysIn) / 7).ceil() * 7;
    final today = _d(DateTime.now());
    return GlowCard(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Column(children: [
        Row(children: [
          IconButton(onPressed: () => onMonth(DateTime(month.year, month.month - 1)), icon: Icon(Icons.chevron_left_rounded, color: p.text)),
          Expanded(child: Text(DateFormat('MMMM yyyy').format(month), textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text))),
          IconButton(onPressed: () => onMonth(DateTime(month.year, month.month + 1)), icon: Icon(Icons.chevron_right_rounded, color: p.text)),
        ]),
        Row(children: [
          for (final d in const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'])
            Expanded(child: Center(child: Text(d, style: TextStyle(fontSize: 11, color: p.label, fontWeight: FontWeight.w600)))),
        ]),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 4, crossAxisSpacing: 4),
          itemCount: cells,
          itemBuilder: (_, i) {
            final n = i - lead + 1;
            if (n < 1 || n > daysIn) return const SizedBox.shrink();
            final date = DateTime(month.year, month.month, n);
            final taken = isTaken(date);
            final sel = selected.contains(date);
            final tc = taken ? takenColor(date) : null;
            return PressScale(
              onTap: taken ? null : () => onToggle(date),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: sel ? Accent.ocean.gradient : null,
                  color: sel ? null : (tc?.withValues(alpha: 0.16)),
                  border: date == today && !sel ? Border.all(color: p.brand, width: 1.4) : null,
                ),
                child: Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                    color: sel ? Colors.white : (tc ?? p.text),
                    decoration: taken ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            );
          },
        ),
      ]),
    );
  }
}
