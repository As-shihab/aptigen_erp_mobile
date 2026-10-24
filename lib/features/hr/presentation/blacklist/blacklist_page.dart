import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/storage/app_storage.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';

/// Employee black list — port of erp/desktop's BlackList.tsx: list with
/// employee, reason, added by, status and revoke reason; blacklist an
/// employee (deactivates their workplace_members row); view details; and
/// revert with a revoke reason (re-activates the member).
class BlacklistPage extends StatefulWidget {
  const BlacklistPage({super.key});

  @override
  State<BlacklistPage> createState() => _BlacklistPageState();
}

/// Desktop remarks are rich-text HTML; show them as plain text.
String _htmlToText(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</(p|div|li)>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

/// Plain text → minimal HTML so the desktop rich-text view renders lines.
String _textToHtml(String text) => const HtmlEscape().convert(text.trim()).replaceAll('\n', '<br>');

Map<String, dynamic> _map(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

String _empLabel(Map<String, dynamic> e) {
  final name = '${str(e['first_name'])} ${str(e['last_name'])}'.trim();
  final no = str(e['employee_no']);
  return no.isEmpty ? (name.isEmpty ? 'Unknown' : name) : '$no - $name';
}

Future<void> _setMemberActive(ApiClient client, dynamic userId, bool active) async {
  if (userId == null || toInt(userId) == 0) return;
  final res = await client.get('workplace_members?\$filter=user_id eq $userId&\$top=1');
  final rows = unwrapList(res);
  final id = rows.isNotEmpty ? _map(rows.first)['id'] : null;
  if (id != null) await client.put('workplace_members', id, {'is_active': active});
}

class _BlacklistPageState extends State<BlacklistPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _employees = [];
  int? _memberId;
  String _q = '';
  String _status = 'all';

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
    try {
      final user = await AppStorage.getUser();
      final userId = toInt(user?['id']);
      final wp = _map(user?['selectedWorkplace'] ?? user?['workplace']);
      final wpId = toInt(wp['id']);
      final data = await batchLoad(_client, {
        'rows': 'employee_blacklists?\$expand=employee,adder(\$expand=user)&\$orderby=id desc&\$top=1000',
        'employees': 'employees?\$select=id,employee_no,first_name,last_name,user_id&\$orderby=first_name asc&\$top=1000',
        if (userId > 0) 'me': 'workplace_members?\$filter=${wpId > 0 ? 'workplace_id eq $wpId and ' : ''}user_id eq $userId&\$top=1',
      });
      if (!mounted) return;
      setState(() {
        _rows = data['rows'] ?? [];
        _employees = data['employees'] ?? [];
        final me = data['me'] ?? const <Map<String, dynamic>>[];
        _memberId = me.isEmpty ? null : toInt(me.first['id']);
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load black list'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    return _rows.where((r) {
      final reverted = asBool(r['status']);
      if (_status == 'blacklisted' && reverted) return false;
      if (_status == 'reverted' && !reverted) return false;
      if (q.isEmpty) return true;
      return [_empLabel(_map(r['employee'])), str(r['reason']), str(r['revoke_reason'])].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _create() async {
    if (_memberId == null) {
      marketToast(context, 'Your workplace membership could not be resolved', error: true);
      return;
    }
    final ok = await showMotionSheet<bool>(context, (_) => _BlacklistForm(employees: _employees, memberId: _memberId!));
    if (ok == true) {
      if (mounted) marketToast(context, 'Employee blacklisted');
      _load();
    }
  }

  Future<void> _revert(Map<String, dynamic> row) async {
    final ok = await showMotionSheet<bool>(context, (_) => _RevertForm(row: row));
    if (ok == true) {
      if (mounted) marketToast(context, 'Blacklist reverted');
      _load();
    }
  }

  Future<void> _view(Map<String, dynamic> row) async {
    final revert = await showMotionSheet<bool>(context, (_) => _DetailSheet(row: row));
    if (revert == true && mounted) _revert(row);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final reverted = _rows.where((r) => asBool(r['status'])).length;
    return MotionScaffold(
      title: 'Black list',
      subtitle: '${_rows.length - reverted} blacklisted, $reverted reverted',
      icon: Icons.block_outlined,
      accent: Accent.ocean,
      onRefresh: _load,
      onFab: _loading ? null : _create,
      fabLabel: 'Blacklist',
      fabIcon: Icons.person_off_outlined,
      headerExtra: HeaderSearch(hint: 'Search employee or reason', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _status,
              options: [
                (id: 'all', label: 'All', count: _rows.length),
                (id: 'blacklisted', label: 'Blacklisted', count: _rows.length - reverted),
                (id: 'reverted', label: 'Reverted', count: reverted),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton(height: 92)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(icon: Icons.verified_user_outlined, title: _rows.isEmpty ? 'Black list is empty' : 'No matches', message: _rows.isEmpty ? 'No employee has been blacklisted.' : null)
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final e = _map(r['employee']);
              final isReverted = asBool(r['status']);
              final adder = str(_map(_map(r['adder'])['user'])['name']);
              return MotionTile(
                key: ValueKey(r['id']),
                leading: InitialsAvatar('${str(e['first_name'])} ${str(e['last_name'])}'.trim(), size: 44),
                title: _empLabel(e),
                subtitle: str(r['reason']),
                meta: [
                  fmtDate(parseDate(r['created_at'])),
                  if (adder.isNotEmpty) 'Added by $adder',
                ].where((s) => s.isNotEmpty).join(' · '),
                trailing: StatusPill(isReverted ? 'Reverted' : 'Blacklisted',
                    tone: isReverted ? MarketTone.ok : MarketTone.error, icon: isReverted ? Icons.undo_rounded : Icons.block_rounded),
                onTap: () => _view(r),
                onLongPress: isReverted ? null : () => _revert(r),
              );
            },
          ),
      ],
    );
  }
}

class _DetailSheet extends StatelessWidget {
  final Map<String, dynamic> row;
  const _DetailSheet({required this.row});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final e = _map(row['employee']);
    final reverted = asBool(row['status']);
    final adder = str(_map(_map(row['adder'])['user'])['name']);
    Widget box(String label, String value) => FormLabel(
          label: label,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
            child: Text(value.isEmpty ? '—' : value, style: TextStyle(fontSize: 13.5, color: p.text, height: 1.4)),
          ),
        );
    return FormSheet(
      title: 'Blacklist details',
      subtitle: _empLabel(e),
      submitLabel: 'Revert blacklist',
      onSubmit: reverted ? null : () => Navigator.pop(context, true),
      children: [
        Row(children: [
          StatusPill(reverted ? 'Reverted' : 'Blacklisted', tone: reverted ? MarketTone.ok : MarketTone.error),
          const Spacer(),
          Text(fmtDateTime(parseDate(row['created_at'])), style: TextStyle(fontSize: 12, color: p.label)),
        ]),
        const SizedBox(height: 14),
        box('Employee', _empLabel(e)),
        box('Reason', str(row['reason'])),
        box('Remarks', _htmlToText(str(row['remarks']))),
        if (adder.isNotEmpty) box('Added by', adder),
        if (reverted) box('Revoke reason', str(row['revoke_reason'])),
      ],
    );
  }
}

class _BlacklistForm extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final int memberId;
  const _BlacklistForm({required this.employees, required this.memberId});

  @override
  State<_BlacklistForm> createState() => _BlacklistFormState();
}

class _BlacklistFormState extends State<_BlacklistForm> {
  final _client = ApiClient();
  final _reason = TextEditingController();
  final _remarks = TextEditingController();
  Object? _employeeId;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_employeeId == null || _reason.text.trim().isEmpty || _remarks.text.trim().isEmpty) {
      marketToast(context, 'Employee, reason, and remarks are required', error: true);
      return;
    }
    final ok = await confirmMarket(context,
        title: 'Blacklist employee?', message: 'Their workplace access will be deactivated until the blacklist is reverted.', confirm: 'Blacklist');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final id = int.tryParse(_employeeId.toString());
      await _client.post(
        'employee_blacklists',
        {'employee_id': id, 'reason': _reason.text.trim(), 'remarks': _textToHtml(_remarks.text), 'status': false, 'added_by': widget.memberId},
        isV8: true,
      );
      final emp = widget.employees.where((e) => e['id'].toString() == _employeeId.toString()).firstOrNull;
      if (emp != null) await _setMemberActive(_client, emp['user_id'], false);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(e, 'Failed to blacklist employee'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => FormSheet(
        title: 'Blacklist employee',
        busy: _busy,
        onSubmit: _save,
        submitLabel: 'Blacklist',
        children: [
          FormLabel(
            label: 'Employee',
            required: true,
            child: PickerField(
              value: _employeeId,
              hint: 'Select an employee',
              icon: Icons.person_search_outlined,
              options: [for (final e in widget.employees) PickOption(e['id'], _empLabel(e))],
              onChanged: (v) => setState(() => _employeeId = v),
            ),
          ),
          FormLabel(label: 'Reason', required: true, child: TextField(controller: _reason, decoration: motionInput(context, hint: 'Short reason', icon: Icons.report_outlined))),
          FormLabel(
            label: 'Remarks',
            required: true,
            child: TextField(
              controller: _remarks,
              minLines: 4,
              maxLines: 10,
              decoration: motionInput(context, hint: 'Describe the circumstances for this blacklist entry...'),
            ),
          ),
        ],
      );
}

class _RevertForm extends StatefulWidget {
  final Map<String, dynamic> row;
  const _RevertForm({required this.row});

  @override
  State<_RevertForm> createState() => _RevertFormState();
}

class _RevertFormState extends State<_RevertForm> {
  final _client = ApiClient();
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_reason.text.trim().isEmpty) {
      marketToast(context, 'Revoke reason is required', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await _client.put('employee_blacklists', widget.row['id'], {'status': true, 'revoke_reason': _reason.text.trim()});
      await _setMemberActive(_client, _map(widget.row['employee'])['user_id'], true);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(e, 'Failed to revert blacklist'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => FormSheet(
        title: 'Revert blacklist',
        subtitle: _empLabel(_map(widget.row['employee'])),
        busy: _busy,
        onSubmit: _save,
        submitLabel: 'Revert',
        children: [
          FormLabel(
            label: 'Revoke reason',
            required: true,
            child: TextField(controller: _reason, minLines: 4, maxLines: 8, decoration: motionInput(context, hint: 'Why is this employee being reinstated?')),
          ),
        ],
      );
}
