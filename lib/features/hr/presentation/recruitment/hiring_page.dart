import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../leave/hr_extras.dart';
import 'recruitment_common.dart';
import 'resumes_page.dart';

// Job postings — port of desktop HiringList.tsx: posting cards with the
// application window phase, candidate pipeline per posting, quick close /
// reopen, and a 6-step create / edit wizard (save as draft or publish /
// schedule).

const _employmentTypes = ['Full-time', 'Part-time', 'Contract', 'Internship', 'Freelance'];
const _statusOptions = ['open', 'on_hold', 'closed'];

enum _Phase { draft, scheduled, accepting, onHold, closed }

_Phase _phase(Map<String, dynamic> r) {
  final now = DateTime.now();
  if (!asBool(r['is_active'], fallback: true)) return _Phase.draft;
  if (r['status'] == 'closed') return _Phase.closed;
  final dl = parseDate(r['deadline']);
  if (dl != null && dl.isBefore(now)) return _Phase.closed;
  if (r['status'] == 'on_hold') return _Phase.onHold;
  final op = parseDate(r['opens_at']);
  if (op != null && op.isAfter(now)) return _Phase.scheduled;
  return _Phase.accepting;
}

({String label, MarketTone tone}) _phaseMeta(_Phase p) => switch (p) {
      _Phase.draft => (label: 'Draft', tone: MarketTone.neutral),
      _Phase.scheduled => (label: 'Scheduled', tone: MarketTone.info),
      _Phase.accepting => (label: 'Accepting applications', tone: MarketTone.ok),
      _Phase.onHold => (label: 'On hold', tone: MarketTone.warn),
      _Phase.closed => (label: 'Applications closed', tone: MarketTone.error),
    };

String? _salary(num? min, num? max) {
  if ((min ?? 0) == 0 && (max ?? 0) == 0) return null;
  String f(num n) => n >= 1000 ? '${(n / 1000).round()}k' : n.round().toString();
  if ((min ?? 0) > 0 && (max ?? 0) > 0) return '${f(min!)} – ${f(max!)}';
  return f((min ?? 0) > 0 ? min! : max!);
}

class HiringPage extends StatefulWidget {
  const HiringPage({super.key});

  @override
  State<HiringPage> createState() => _HiringPageState();
}

class _HiringPageState extends State<HiringPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _filter = 'all';
  String _q = '';
  Object? _toggling;

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
      final res = await _client.get('hiring?\$expand=resumes(\$select=id,status)&\$orderby=id desc&\$top=500');
      if (!mounted) return;
      setState(() => _rows = unwrapList(res).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList());
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Failed to load job postings'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _match(Map<String, dynamic> r, String f) => switch (f) {
        'active' => asBool(r['is_active'], fallback: true),
        'inactive' => !asBool(r['is_active'], fallback: true),
        _ => true,
      };

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    return _rows.where((r) => _match(r, _filter)).where((r) {
      if (q.isEmpty) return true;
      return [r['title'], r['department'], r['location'], r['custom_id']].any((v) => str(v).toLowerCase().contains(q));
    }).toList();
  }

  List<Map> _resumes(Map<String, dynamic> r) => r['resumes'] is List ? (r['resumes'] as List).whereType<Map>().toList() : const [];

  Future<void> _form([Map<String, dynamic>? row]) async {
    final msg = await showMotionSheet<String>(context, (_) => _HiringWizard(existing: row));
    if (msg != null) {
      if (mounted) marketToast(context, msg);
      _load();
    }
  }

  Future<void> _toggle(Map<String, dynamic> r) async {
    final closing = _phase(r) != _Phase.closed;
    final dl = parseDate(r['deadline']);
    final body = closing
        ? {'status': 'closed'}
        : {'status': 'open', if (dl != null && dl.isBefore(DateTime.now())) 'deadline': null};
    setState(() => _toggling = r['id']);
    try {
      await _client.put('hiring', r['id'], body);
      if (mounted) marketToast(context, closing ? 'Applications closed' : 'Applications reopened');
      await _load();
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, closing ? 'Could not close applications' : 'Could not reopen applications'), error: true);
    } finally {
      if (mounted) setState(() => _toggling = null);
    }
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await confirmMarket(context, title: 'Delete job posting?', message: 'Delete job posting "${str(r['title'])}"?');
    if (!ok) return;
    try {
      await _client.delete('hiring', r['id']);
      if (mounted) {
        setState(() => _rows.removeWhere((x) => x['id'] == r['id']));
        marketToast(context, 'Job posting deleted');
      }
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete'), error: true);
    }
  }

  Future<void> _more(Map<String, dynamic> r) async {
    final ph = _phase(r);
    final key = await showActionSheet(context, title: str(r['title']), actions: [
      (key: 'apps', label: 'View applications', icon: Icons.people_alt_outlined, destructive: false),
      (key: 'edit', label: 'Edit', icon: Icons.edit_outlined, destructive: false),
      if (ph != _Phase.draft)
        (key: 'toggle', label: ph == _Phase.closed ? 'Reopen applications' : 'Close applications', icon: ph == _Phase.closed ? Icons.lock_open_rounded : Icons.lock_outline_rounded, destructive: false),
      (key: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted) return;
    switch (key) {
      case 'apps':
        _openApps(r);
      case 'edit':
        _form(r);
      case 'toggle':
        _toggle(r);
      case 'delete':
        _delete(r);
    }
  }

  void _openApps(Map<String, dynamic> r) => pushMotion(context, ResumesPage(hiringId: r['id'], hiringTitle: str(r['title']))).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final accepting = _rows.where((r) => _phase(r) == _Phase.accepting).length;
    final apps = _rows.fold<int>(0, (a, r) => a + _resumes(r).length);
    final vacancies = _rows.where((r) => _phase(r) == _Phase.accepting).fold<int>(0, (a, r) => a + toInt(r['vacancies']));
    return MotionScaffold(
      title: 'Job postings',
      subtitle: '${rows.length} of ${_rows.length} postings',
      icon: Icons.work_rounded,
      accent: Accent.ocean,
      onRefresh: _load,
      onFab: () => _form(),
      fabLabel: 'New posting',
      headerExtra: HeaderSearch(hint: 'Search postings', onChanged: (v) => setState(() => _q = v)),
      actions: [
        IconButton(tooltip: 'All applications', icon: const Icon(Icons.people_alt_outlined), onPressed: () => pushMotion(context, const ResumesPage()).then((_) => _load())),
      ],
      slivers: [
        if (!_loading && _error == null)
          SliverPadding(
            padding: const EdgeInsets.only(top: 16),
            sliver: SliverToBoxAdapter(
              child: KpiGrid(children: [
                KpiTile(icon: Icons.campaign_rounded, label: 'Accepting now', value: accepting, tone: MarketTone.ok),
                KpiTile(icon: Icons.event_seat_rounded, label: 'Open vacancies', value: vacancies, tone: MarketTone.brand),
                KpiTile(icon: Icons.description_rounded, label: 'Applications', value: apps, tone: MarketTone.brand, onTap: () => pushMotion(context, const ResumesPage()).then((_) => _load())),
              ]),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _filter,
              options: [
                for (final f in const [('all', 'All'), ('active', 'Published'), ('inactive', 'Drafts')]) (id: f.$1, label: f.$2, count: _rows.where((r) => _match(r, f.$1)).length),
              ],
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton(height: 200, count: 3)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.person_add_alt_rounded,
            title: 'No job postings found',
            message: 'Try adjusting your search or create a new posting.',
            actionLabel: 'New job posting',
            onAction: _form,
          )
        else
          sliverStagger(count: rows.length, gap: 12, builder: (ctx, i) => _card(ctx, rows[i])),
      ],
    );
  }

  Widget _card(BuildContext context, Map<String, dynamic> r) {
    final p = MarketPalette.of(context);
    final ph = _phase(r);
    final meta = _phaseMeta(ph);
    final resumes = _resumes(r);
    final counts = <String, int>{};
    for (final x in resumes) {
      counts[str(x['status'])] = (counts[str(x['status'])] ?? 0) + 1;
    }
    final sal = _salary(toNum(r['salary_min']), toNum(r['salary_max']));
    final opens = parseDate(r['opens_at']);
    final dl = parseDate(r['deadline']);
    final expired = dl != null && dl.isBefore(DateTime.now());
    final desc = htmlToText(str(r['description']));
    final vac = toInt(r['vacancies']);
    return GlowCard(
      onTap: () => _openApps(r),
      onLongPress: () => _more(r),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AccentIcon(Icons.work_outline_rounded, accent: accentFor(str(r['title'])), size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(str(r['title']), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
              const SizedBox(height: 2),
              Text([str(r['department']), str(r['employment_type'])].where((s) => s.isNotEmpty).join(' · ').ifEmpty('—'),
                  style: TextStyle(fontSize: 12.5, color: p.label)),
              const SizedBox(height: 6),
              StatusPill(meta.label, tone: meta.tone),
            ]),
          ),
          IconButton(onPressed: () => _more(r), icon: Icon(Icons.more_vert_rounded, color: p.label)),
        ]),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Wrap(spacing: 12, runSpacing: 6, children: [
            if (str(r['location']).isNotEmpty) _meta(p, Icons.place_outlined, str(r['location'])),
            _meta(p, Icons.groups_2_outlined, '$vac ${vac == 1 ? 'vacancy' : 'vacancies'}'),
            if (sal != null) _meta(p, Icons.account_balance_wallet_outlined, sal),
            _meta(p, Icons.visibility_outlined, '${toInt(r['views_count'])} views'),
            if (str(r['custom_id']).isNotEmpty) _meta(p, Icons.tag_rounded, str(r['custom_id'])),
          ]),
        ),
        const SizedBox(height: 10),
        Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _meta(p, Icons.event_available_outlined, 'Opens: ${opens == null ? 'On publish' : fmtDateTime(opens)}'),
            const SizedBox(height: 4),
            _meta(p, Icons.event_busy_outlined, 'Closes: ${dl == null ? 'When closed manually' : fmtDateTime(dl)}', color: expired ? p.error : null),
          ]),
        ),
        if (desc.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 8, 0),
            child: Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.label, height: 1.4)),
          ),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.only(right: 8), child: PipelineBar(counts: counts)),
        if (resumes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
            child: Wrap(spacing: 10, runSpacing: 4, children: [
              for (final s in resumeStages)
                if ((counts[s] ?? 0) > 0)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: stageColor(s), shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('${humanize(s)} ${counts[s]}', style: TextStyle(fontSize: 11.5, color: p.label)),
                  ]),
            ]),
          ),
        Divider(height: 18, color: p.line),
        Row(children: [
          TextButton.icon(
            onPressed: () => _openApps(r),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: Text('${resumes.length} ${resumes.length == 1 ? 'application' : 'applications'}'),
          ),
          const Spacer(),
          if (ph != _Phase.draft)
            _toggling == r['id']
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(
                    tooltip: ph == _Phase.closed ? 'Reopen' : 'Close applications',
                    onPressed: () => _toggle(r),
                    icon: Icon(ph == _Phase.closed ? Icons.lock_open_rounded : Icons.lock_outline_rounded, color: p.label),
                  ),
          IconButton(tooltip: 'Edit', onPressed: () => _form(r), icon: Icon(Icons.edit_outlined, color: p.label)),
          IconButton(tooltip: 'Delete', onPressed: () => _delete(r), icon: Icon(Icons.delete_outline_rounded, color: p.error)),
        ]),
      ]),
    );
  }

  Widget _meta(MarketPalette p, IconData i, String t, {Color? color}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 14, color: color ?? p.label),
        const SizedBox(width: 4),
        Flexible(child: Text(t, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: color ?? p.label))),
      ]);
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

// ── Wizard ──────────────────────────────────────────────────────────────

class _HiringWizard extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _HiringWizard({this.existing});

  @override
  State<_HiringWizard> createState() => _HiringWizardState();
}

class _HiringWizardState extends State<_HiringWizard> {
  static const _steps = ['Basics', 'Pay', 'Schedule', 'About', 'Needs', 'Review'];
  Map<String, dynamic>? get e => widget.existing;
  late final _title = TextEditingController(text: str(e?['title']));
  late final _customId = TextEditingController(text: str(e?['custom_id']));
  late final _dept = TextEditingController(text: str(e?['department']));
  late final _location = TextEditingController(text: str(e?['location']));
  late final _min = TextEditingController(text: e?['salary_min'] == null ? '' : _plain(e!['salary_min']));
  late final _max = TextEditingController(text: e?['salary_max'] == null ? '' : _plain(e!['salary_max']));
  late final _desc = TextEditingController(text: htmlToText(str(e?['description'])));
  late final _req = TextEditingController(text: htmlToText(str(e?['requirements'])));
  late final String _descOrig = _desc.text;
  late final String _reqOrig = _req.text;
  late String _type = str(e?['employment_type']);
  late int _vacancies = e == null ? 1 : (toInt(e!['vacancies']) < 1 ? 1 : toInt(e!['vacancies']));
  late DateTime? _opens = parseDate(e?['opens_at'])?.toLocal();
  late DateTime? _deadline = parseDate(e?['deadline'])?.toLocal();
  late String _status = str(e?['status']).isEmpty ? 'open' : str(e?['status']);
  int _step = 0;
  int _dir = 1;
  bool _busy = false;

  static String _plain(dynamic v) {
    final n = toNum(v);
    if (n == null) return '';
    return n == n.roundToDouble() ? n.round().toString() : n.toString();
  }

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_title, _customId, _dept, _location, _min, _max, _desc, _req]) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(int i) {
    if (i == _step || i < 0 || i >= _steps.length) return;
    if (i > 0 && _title.text.trim().isEmpty) {
      marketToast(context, 'Job title is required', error: true);
      return;
    }
    setState(() {
      _dir = i > _step ? 1 : -1;
      _step = i;
    });
  }

  bool get _scheduledLater => _opens != null && _opens!.isAfter(DateTime.now());

  String? _rich(TextEditingController c, String orig, String field) {
    final t = c.text.trim();
    if (t == orig.trim() && e != null) return str(e![field]).isEmpty ? null : str(e![field]);
    return t.isEmpty ? null : textToHtml(t);
  }

  Future<void> _save(bool publish) async {
    if (_title.text.trim().isEmpty) {
      marketToast(context, 'Job title is required', error: true);
      _go(0);
      return;
    }
    if (_opens != null && _deadline != null && !_deadline!.isAfter(_opens!)) {
      marketToast(context, 'Applications must close after they open', error: true);
      setState(() {
        _dir = -1;
        _step = 2;
      });
      return;
    }
    setState(() => _busy = true);
    final body = {
      'custom_id': _customId.text.trim().isEmpty ? null : _customId.text.trim(),
      'title': _title.text.trim(),
      'department': _dept.text.trim().isEmpty ? null : _dept.text.trim(),
      'employment_type': _type.trim().isEmpty ? null : _type.trim(),
      'vacancies': _vacancies,
      'salary_min': _min.text.trim().isEmpty ? null : double.tryParse(_min.text.trim()),
      'salary_max': _max.text.trim().isEmpty ? null : double.tryParse(_max.text.trim()),
      'location': _location.text.trim().isEmpty ? null : _location.text.trim(),
      'opens_at': _opens?.toUtc().toIso8601String(),
      'deadline': _deadline?.toUtc().toIso8601String(),
      'description': _rich(_desc, _descOrig, 'description'),
      'requirements': _rich(_req, _reqOrig, 'requirements'),
      'status': publish ? 'open' : _status,
      'is_active': publish,
    };
    try {
      final api = EntityApi(ApiClient(), 'hiring');
      if (e == null) {
        await api.create(body);
      } else {
        await api.update(e!['id'], body);
      }
      if (mounted) {
        Navigator.pop(context, publish ? (_scheduledLater ? 'Job posting scheduled' : 'Job posting published') : (e == null ? 'Job posting saved as draft' : 'Job posting saved'));
      }
    } catch (err) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(err, 'Failed to save job posting'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => WizardShell(
        title: e == null ? 'New job posting' : 'Edit job posting',
        steps: _steps,
        step: _step,
        direction: _dir,
        busy: _busy,
        onStep: _go,
        onBack: () => _step == 0 ? Navigator.pop(context) : _go(_step - 1),
        onNext: _title.text.trim().isEmpty ? null : () => _go(_step + 1),
        finalActions: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _busy ? null : () => _save(false),
              child: const Text('Save as draft'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GradientButton(
              label: _scheduledLater ? 'Schedule' : 'Publish',
              icon: _scheduledLater ? Icons.schedule_send_rounded : Icons.rocket_launch_rounded,
              busy: _busy,
              onTap: _busy ? null : () => _save(true),
            ),
          ),
        ],
        body: switch (_step) {
          0 => _basics(context),
          1 => _pay(context),
          2 => _schedule(context),
          3 => FormLabel(
              label: 'Description',
              child: TextField(controller: _desc, minLines: 10, maxLines: 18, decoration: motionInput(context, hint: 'Describe the role, responsibilities and team')),
            ),
          4 => FormLabel(
              label: 'Requirements',
              child: TextField(controller: _req, minLines: 10, maxLines: 18, decoration: motionInput(context, hint: 'Skills, qualifications and experience')),
            ),
          _ => _review(context),
        },
      );

  Widget _basics(BuildContext context) {
    final types = [..._employmentTypes, if (_type.isNotEmpty && !_employmentTypes.contains(_type)) _type];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FormLabel(label: 'Job title', required: true, child: TextField(controller: _title, decoration: motionInput(context, hint: 'e.g. Senior developer', icon: Icons.work_outline_rounded))),
      FormLabel(label: 'Custom ID', child: TextField(controller: _customId, decoration: motionInput(context, hint: 'Optional', icon: Icons.tag_rounded))),
      FormLabel(label: 'Department', child: TextField(controller: _dept, decoration: motionInput(context, hint: 'e.g. Engineering', icon: Icons.apartment_rounded))),
      FormLabel(
        label: 'Employment type',
        child: ToggleChips<String>(
          options: [for (final t in types) (t, t)],
          isOn: (t) => _type == t,
          onTap: (t) => setState(() => _type = _type == t ? '' : t),
        ),
      ),
      FormLabel(label: 'Vacancies', child: StepperField(value: _vacancies, min: 1, max: 999, onChanged: (v) => setState(() => _vacancies = v))),
      FormLabel(label: 'Location', child: TextField(controller: _location, decoration: motionInput(context, hint: 'e.g. Dhaka, remote', icon: Icons.place_outlined))),
    ]);
  }

  Widget _pay(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FormLabel(
          label: 'Salary min',
          child: TextField(controller: _min, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: motionInput(context, hint: '0', icon: Icons.south_rounded)),
        ),
        FormLabel(
          label: 'Salary max',
          child: TextField(controller: _max, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: motionInput(context, hint: '0', icon: Icons.north_rounded)),
        ),
      ]);

  Widget _schedule(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FormLabel(
        label: 'Applications open',
        help: "Leave empty to open as soon as it's published.",
        child: DatePickField(value: _opens, withTime: true, hint: 'When published', firstDate: DateTime(2000), onChanged: (d) => setState(() => _opens = d)),
      ),
      FormLabel(
        label: 'Applications close',
        help: 'Leave empty to keep it open until you close it.',
        child: DatePickField(value: _deadline, withTime: true, hint: 'No end date', firstDate: DateTime(2000), onChanged: (d) => setState(() => _deadline = d)),
      ),
      FormLabel(
        label: 'Status',
        child: MarketSegmented<String>(
          value: _status,
          options: [for (final s in _statusOptions) (id: s, label: humanize(s), count: null)],
          onChanged: (v) => setState(() => _status = v),
        ),
      ),
      Text(
        'The careers page shows this posting and accepts applications only between these times. You can also close applications any time from the posting card.',
        style: TextStyle(fontSize: 12, color: p.label, height: 1.4),
      ),
    ]);
  }

  Widget _review(BuildContext context) {
    final p = MarketPalette.of(context);
    final sal = _salary(double.tryParse(_min.text.trim()), double.tryParse(_max.text.trim()));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GlowCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(_title.text.trim().isEmpty ? 'Untitled posting' : _title.text.trim(), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text))),
            StatusPill(_scheduledLater && _status == 'open' ? 'Scheduled' : humanize(_status), tone: toneForStatus(_status == 'on_hold' ? 'hold' : _status)),
          ]),
          const SizedBox(height: 3),
          Text([_dept.text.trim(), _type, _location.text.trim()].where((s) => s.isNotEmpty).join(' · ').ifEmpty('—'), style: TextStyle(fontSize: 12.5, color: p.label)),
        ]),
      ),
      const SizedBox(height: 12),
      reviewGrid([
        ('Vacancies', '$_vacancies'),
        ('Salary', sal ?? '—'),
        ('Opens', _opens == null ? 'On publish' : fmtDateTime(_opens)),
        ('Closes', _deadline == null ? 'When closed manually' : fmtDateTime(_deadline)),
      ]),
      if (_desc.text.trim().isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(_desc.text.trim(), maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.label, height: 1.4)),
      ],
      const SizedBox(height: 14),
      Text(
        _scheduledLater
            ? 'Save as draft keeps this hidden from candidates. Schedule makes it go live automatically when applications open.'
            : 'Save as draft keeps this hidden from candidates. Publish makes it live immediately.',
        style: TextStyle(fontSize: 12, color: p.label, height: 1.4),
      ),
    ]);
  }
}
