import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/settings_service.dart';
import '../widgets/settings_widgets.dart';

/// Settings → Audit logs. Every OData create / update / delete in the
/// workplace (see cloud/src/module/audit), as a day-grouped timeline with an
/// event filter, server-side search and paging, and a detail sheet showing
/// the before / after field diff — same data as desktop AuditLogs.tsx.
class AuditLogsPage extends StatefulWidget {
  const AuditLogsPage({super.key});

  @override
  State<AuditLogsPage> createState() => _AuditLogsPageState();
}

const _pageSize = 40;

class _AuditLogsPageState extends State<AuditLogsPage> {
  final _svc = AuditService();
  final List<JsonRow> _rows = [];
  int? _total;
  bool _loading = true;
  bool _more = false;
  bool _end = false;
  String? _error;
  String? _action;
  String _q = '';
  Timer? _debounce;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final req = ++_req;
    setState(() {
      _loading = true;
      _error = null;
      _end = false;
    });
    try {
      final res = await _svc.page(action: _action, search: _q, top: _pageSize);
      if (!mounted || req != _req) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(res.rows);
        _total = res.total;
        _end = res.rows.length < _pageSize;
      });
    } catch (e) {
      if (mounted && req == _req) setState(() => _error = errorMessage(e, 'Could not load audit logs'));
    } finally {
      if (mounted && req == _req) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_more || _end || _loading) return;
    final req = _req;
    setState(() => _more = true);
    try {
      final res = await _svc.page(action: _action, search: _q, top: _pageSize, skip: _rows.length);
      if (!mounted || req != _req) return;
      setState(() {
        _rows.addAll(res.rows);
        _end = res.rows.length < _pageSize;
      });
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not load more'), error: true);
    } finally {
      if (mounted) setState(() => _more = false);
    }
  }

  void _search(String v) {
    _q = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    // Flatten into day headers + rows.
    final items = <Object>[];
    String? lastDay;
    for (final r in _rows) {
      final d = dayLabel(parseDate(r['created_at']));
      if (d != lastDay) {
        items.add(d);
        lastDay = d;
      }
      items.add(r);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis == Axis.vertical && n.metrics.pixels > n.metrics.maxScrollExtent - 400) _loadMore();
        return false;
      },
      child: MotionScaffold(
        title: 'Audit logs',
        subtitle: _total == null ? 'Every create, update and delete' : '$_total events recorded',
        icon: Icons.history_edu_rounded,
        accent: Accent.slate,
        onRefresh: _load,
        headerExtra: HeaderSearch(hint: 'Search section, actor or record', onChanged: _search),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.only(top: 14),
            sliver: SliverToBoxAdapter(
              child: ChipFilter<String?>(
                value: _action,
                options: const [
                  (id: null, label: 'All events', count: null),
                  (id: 'CREATE', label: 'Created', count: null),
                  (id: 'UPDATE', label: 'Updated', count: null),
                  (id: 'DELETE', label: 'Deleted', count: null),
                ],
                onChanged: (v) {
                  setState(() => _action = v);
                  _load();
                },
              ),
            ),
          ),
          if (_loading)
            sliverSkeleton(count: 7, height: 70)
          else if (_error != null)
            sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
          else if (_rows.isEmpty)
            sliverEmpty(icon: Icons.history_toggle_off_rounded, title: 'No events', message: _q.isNotEmpty || _action != null ? 'Try a different filter.' : 'Changes made in this workplace will appear here.')
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverList.builder(
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final it = items[i];
                  if (it is String) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                      child: Text(it, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.label)),
                    );
                  }
                  final r = it as JsonRow;
                  final next = i + 1 < items.length ? items[i + 1] : null;
                  return FadeSlideIn(
                    index: i % 12,
                    offsetY: 16,
                    child: _TimelineRow(row: r, last: next == null || next is String, onTap: () => showAuditDetail(context, r)),
                  );
                },
              ),
            ),
            sliverBox(
              Center(
                child: _more
                    ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)))
                    : _end
                        ? Text('${_rows.length} events shown', style: TextStyle(fontSize: 12, color: p.label))
                        : TextButton.icon(onPressed: _loadMore, icon: const Icon(Icons.expand_more_rounded), label: const Text('Load more')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

({String label, MarketTone tone, IconData icon}) _actionStyle(String a) => switch (a.toUpperCase()) {
      'CREATE' => (label: 'Created', tone: MarketTone.ok, icon: Icons.add_circle_outline_rounded),
      'UPDATE' => (label: 'Updated', tone: MarketTone.info, icon: Icons.edit_note_rounded),
      'DELETE' => (label: 'Deleted', tone: MarketTone.error, icon: Icons.delete_outline_rounded),
      _ => (label: humanize(a), tone: MarketTone.neutral, icon: Icons.bolt_rounded),
    };

class _TimelineRow extends StatelessWidget {
  final JsonRow row;
  final bool last;
  final VoidCallback onTap;
  const _TimelineRow({required this.row, required this.last, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final s = _actionStyle(str(row['action']));
    final c = p.tone(s.tone);
    final actor = str(row['user_email']).isEmpty ? 'System' : str(row['user_email']);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 34,
          child: Column(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: c.bg, shape: BoxShape.circle, border: Border.all(color: c.fg.withValues(alpha: 0.4))),
              child: Icon(s.icon, size: 16, color: c.fg),
            ),
            if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: p.line)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlowCard(
              onTap: onTap,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${humanize(str(row['entity']))} #${str(row['record_id'])}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                    const SizedBox(height: 2),
                    Text('$actor · ${fmtTime(parseDate(row['created_at']))}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
                  ]),
                ),
                StatusPill(s.label, tone: s.tone),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

String _fieldValue(dynamic v) {
  if (v == null || (v is String && v.isEmpty)) return '-';
  if (v is bool) return v ? 'Yes' : 'No';
  if (v is Map || v is List) return jsonEncode(v);
  return v.toString();
}

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map) return v.cast<String, dynamic>();
  if (v is String && v.isNotEmpty) {
    try {
      final d = jsonDecode(v);
      if (d is Map) return d.cast<String, dynamic>();
    } catch (_) {}
  }
  return {};
}

/// Detail sheet with header facts and the per-field before / after diff.
void showAuditDetail(BuildContext context, JsonRow r) {
  showMotionSheet<void>(context, (ctx) => _AuditDetail(row: r));
}

class _AuditDetail extends StatefulWidget {
  final JsonRow row;
  const _AuditDetail({required this.row});

  @override
  State<_AuditDetail> createState() => _AuditDetailState();
}

class _AuditDetailState extends State<_AuditDetail> {
  bool _changedOnly = true;

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final r = widget.row;
    final s = _actionStyle(str(r['action']));
    final before = _asMap(r['before']);
    final after = _asMap(r['after']);
    final keys = {...before.keys, ...after.keys}.toList()..sort();
    final diffs = [
      for (final k in keys) (key: k, before: before[k], after: after[k], changed: jsonEncode(before[k]) != jsonEncode(after[k])),
    ];
    final changedCount = diffs.where((d) => d.changed).length;
    final shown = _changedOnly ? diffs.where((d) => d.changed).toList() : diffs;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.86,
      child: Column(children: [
        const SheetGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 6),
          child: Row(children: [
            AccentIcon(s.icon, accent: switch (s.tone) { MarketTone.ok => Accent.emerald, MarketTone.error => Accent.rose, _ => Accent.ocean }, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${humanize(str(r['entity']))} #${str(r['record_id'])}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
                Text(fmtDateTime(parseDate(r['created_at'])), style: TextStyle(fontSize: 12.5, color: p.label)),
              ]),
            ),
            IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: p.label)),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
            children: [
              FadeSlideIn(
                child: GlowCard(
                  child: Column(children: [
                    InfoRow('Section', humanize(str(r['entity']))),
                    InfoRow('Record', '#${str(r['record_id'])}'),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        Expanded(child: Text('Event', style: TextStyle(fontSize: 12.5, color: p.label))),
                        StatusPill(s.label, tone: s.tone),
                      ]),
                    ),
                    InfoRow('Actor', str(r['user_email']).isEmpty ? 'System' : str(r['user_email'])),
                    InfoRow('IP address', str(r['ip_address']).isEmpty ? '-' : str(r['ip_address'])),
                    InfoRow('Timestamp', fmtDateTime(parseDate(r['created_at']))),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Text('Changes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text))),
                if (keys.isNotEmpty)
                  ChoiceChip(
                    label: Text(_changedOnly ? 'Changed only  $changedCount' : 'All fields  ${keys.length}'),
                    selected: _changedOnly,
                    onSelected: (_) => setState(() => _changedOnly = !_changedOnly),
                  ),
              ]),
              const SizedBox(height: 10),
              if (keys.isEmpty)
                Text('No field data recorded for this change.', style: TextStyle(fontSize: 13, color: p.label))
              else if (shown.isEmpty)
                Text('No fields changed.', style: TextStyle(fontSize: 13, color: p.label))
              else
                for (var i = 0; i < shown.length; i++)
                  FadeSlideIn(
                    index: i,
                    offsetY: 10,
                    child: _DiffCard(
                      field: humanize(shown[i].key),
                      before: _fieldValue(shown[i].before),
                      after: _fieldValue(shown[i].after),
                      changed: shown[i].changed,
                    ),
                  ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _DiffCard extends StatelessWidget {
  final String field;
  final String before;
  final String after;
  final bool changed;
  const _DiffCard({required this.field, required this.before, required this.after, required this.changed});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    Widget side(String label, String value, Color fg, Color bg) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: changed ? bg : p.surface, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 11, color: changed ? fg : p.label)),
              const SizedBox(height: 3),
              SelectableText(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: changed ? fg : p.label)),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlowCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(field, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            side('Before', before, p.error, p.errorBg),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14), child: Icon(Icons.arrow_forward_rounded, size: 16, color: p.label)),
            side('After', after, p.ok, p.okBg),
          ]),
        ]),
      ),
    );
  }
}
