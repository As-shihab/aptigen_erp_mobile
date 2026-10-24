import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../../../shared/widgets/media_library_dialog.dart';
import '../leave/hr_extras.dart';
import 'recruitment_common.dart';

// Applications — port of desktop ResumesList.tsx: candidates grouped by
// pipeline stage (applied → shortlisted → interviewed → offered → hired,
// or rejected), quick stage moves, applicant profile, CV opener and a
// 5-step create / edit wizard. Optionally filtered to one job posting.

class ResumesPage extends StatefulWidget {
  final Object? hiringId;
  final String? hiringTitle;
  const ResumesPage({super.key, this.hiringId, this.hiringTitle});

  @override
  State<ResumesPage> createState() => _ResumesPageState();
}

class _ResumesPageState extends State<ResumesPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _jobs = [];
  late Object? _hiringId = widget.hiringId;
  String _stage = 'all';
  String _q = '';

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
      final d = await batchLoad(_client, {
        'rows': 'resumes?\$expand=hiring&\$orderby=id desc&\$top=500',
        'jobs': 'hiring?\$select=id,title&\$top=200',
      });
      if (!mounted) return;
      setState(() {
        _rows = d['rows'] ?? [];
        _jobs = d['jobs'] ?? [];
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Failed to load applications'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _scoped =>
      _hiringId == null ? _rows : _rows.where((r) => r['hiring_id']?.toString() == _hiringId.toString()).toList();

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    return _scoped.where((r) {
      if (_stage != 'all' && str(r['status']) != _stage) return false;
      if (q.isEmpty) return true;
      return [r['first_name'], r['last_name'], r['email'], r['phone'], nested(r, 'hiring', 'title'), r['current_company']]
          .any((v) => str(v).toLowerCase().contains(q));
    }).toList();
  }

  String _jobTitle() {
    if (widget.hiringTitle != null && widget.hiringId?.toString() == _hiringId?.toString()) return widget.hiringTitle!;
    final j = _jobs.where((j) => j['id'].toString() == _hiringId.toString()).firstOrNull;
    return j == null ? '#$_hiringId' : str(j['title']);
  }

  Future<void> _form([Map<String, dynamic>? row]) async {
    final ok = await showMotionSheet<bool>(context, (_) => _ResumeWizard(existing: row, jobs: _jobs, presetJob: row == null ? _hiringId : null));
    if (ok == true) {
      if (mounted) marketToast(context, row == null ? 'Application created' : 'Application updated');
      _load();
    }
  }

  Future<bool> _delete(Map<String, dynamic> r) async {
    final name = '${str(r['first_name'])} ${str(r['last_name'])}'.trim();
    final ok = await confirmMarket(context, title: 'Delete application?', message: 'Delete resume of "$name"?');
    if (!ok) return false;
    try {
      await _client.delete('resumes', r['id']);
      if (mounted) {
        setState(() => _rows.removeWhere((x) => x['id'] == r['id']));
        marketToast(context, 'Resume deleted');
      }
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete'), error: true);
      return false;
    }
  }

  Future<void> _move(Map<String, dynamic> r, String stage) async {
    final prev = r['status'];
    setState(() => r['status'] = stage);
    try {
      await _client.put('resumes', r['id'], {'status': stage});
      if (mounted) marketToast(context, 'Moved to ${humanize(stage).toLowerCase()}');
    } catch (e) {
      if (mounted) {
        setState(() => r['status'] = prev);
        marketToast(context, errorMessage(e, 'Could not update stage'), error: true);
      }
    }
  }

  Future<void> _profile(Map<String, dynamic> r) async {
    final res = await showMotionSheet<String>(context, (_) => _ProfileSheet(row: r));
    if (!mounted || res == null) return;
    if (res == 'edit') {
      _form(r);
    } else if (res == 'delete') {
      _delete(r);
    } else if (res.startsWith('stage:')) {
      _move(r, res.substring(6));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final scoped = _scoped;
    final rows = _visible;
    final counts = {for (final s in resumeStages) s: scoped.where((r) => str(r['status']) == s).length};
    return MotionScaffold(
      title: 'Applications',
      subtitle: '${rows.length} of ${scoped.length} applicants',
      icon: Icons.assignment_ind_rounded,
      accent: Accent.ocean,
      onRefresh: _load,
      onFab: () => _form(),
      fabLabel: 'New application',
      headerExtra: HeaderSearch(hint: 'Search applicants', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        if (_hiringId != null)
          sliverBox(
            FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                decoration: BoxDecoration(color: p.infoBg, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Icon(Icons.filter_alt_rounded, size: 18, color: p.info),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Filtered by job: ${_jobTitle()}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.info, fontWeight: FontWeight.w600))),
                  TextButton(onPressed: () => setState(() => _hiringId = null), child: const Text('Clear')),
                ]),
              ),
            ),
          ),
        if (!_loading && _error == null)
          SliverPadding(
            padding: const EdgeInsets.only(top: 16),
            sliver: SliverToBoxAdapter(
              child: SizedBox(
                height: 104,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: resumeStages.length + 1,
                  separatorBuilder: (_, i) => i == 0 || i >= pipelineStages.length
                      ? const SizedBox(width: 10)
                      : Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Icon(Icons.chevron_right_rounded, color: p.label, size: 18)),
                  itemBuilder: (_, i) {
                    final s = i == 0 ? 'all' : resumeStages[i - 1];
                    final n = s == 'all' ? scoped.length : counts[s]!;
                    return FadeSlideIn(index: i, child: _stageCard(p, s, n, scoped.length));
                  },
                ),
              ),
            ),
          ),
        if (!_loading && _error == null && scoped.isNotEmpty) sliverBox(PipelineBar(counts: counts, height: 10), padding: const EdgeInsets.fromLTRB(16, 12, 16, 0)),
        if (_loading)
          sliverSkeleton(height: 86)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(icon: Icons.person_search_rounded, title: 'No applications found', message: 'Try adjusting your search or filters.')
        else
          KeyedSubtree(
            key: ValueKey('list-$_stage-$_hiringId'),
            child: sliverStagger(
              count: rows.length,
              builder: (_, i) {
                final r = rows[i];
                final name = '${str(r['first_name'])} ${str(r['last_name'])}'.trim();
                final s = str(r['status']);
                final photo = str(r['photo_url']);
                return MotionTile(
                  key: ValueKey(r['id']),
                  leading: InitialsAvatar(name.isEmpty ? '?' : name, imageUrl: photo.isEmpty ? null : mediaUrl(photo), size: 46),
                  title: name.isEmpty ? 'Unnamed applicant' : name,
                  subtitle: nested(r, 'hiring', 'title').isEmpty ? 'No job linked' : nested(r, 'hiring', 'title'),
                  meta: [
                    [str(r['current_position']), str(r['current_company'])].where((x) => x.isNotEmpty).join(' at '),
                    if (r['experience_years'] != null) '${r['experience_years']} yrs',
                    if (str(r['email']).isNotEmpty) str(r['email']) else if (str(r['phone']).isNotEmpty) str(r['phone']),
                  ].where((x) => x.isNotEmpty).join(' · '),
                  trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    StatusPill(humanize(s), tone: stageTone(s), icon: stageIcon(s)),
                    if (!asBool(r['is_active'], fallback: true)) ...[const SizedBox(height: 4), const StatusPill('Inactive')],
                  ]),
                  onTap: () => _profile(r),
                  onLongPress: () => _quickMove(r),
                  onDelete: () => _delete(r),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _quickMove(Map<String, dynamic> r) async {
    final cur = str(r['status']);
    final key = await showActionSheet(context, title: 'Move to stage', actions: [
      for (final s in resumeStages)
        if (s != cur) (key: s, label: humanize(s), icon: stageIcon(s), destructive: s == 'rejected'),
    ]);
    if (key != null && mounted) _move(r, key);
  }

  Widget _stageCard(MarketPalette p, String s, int n, int total) {
    final sel = _stage == s;
    final c = s == 'all' ? p.brand : stageColor(s);
    return PressScale(
      onTap: () => setState(() => _stage = s),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        width: 108,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sel ? c : p.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? c : p.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(s == 'all' ? Icons.all_inbox_rounded : stageIcon(s), size: 20, color: sel ? Colors.white : c),
          const Spacer(),
          CountUp(value: n, format: (v) => '${v.round()}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: sel ? Colors.white : p.text)),
          Text(s == 'all' ? 'All' : humanize(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: sel ? Colors.white.withValues(alpha: 0.9) : p.label)),
        ]),
      ),
    );
  }
}

// ── Profile ─────────────────────────────────────────────────────────────

class _ProfileSheet extends StatelessWidget {
  final Map<String, dynamic> row;
  const _ProfileSheet({required this.row});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final r = row;
    final name = '${str(r['first_name'])} ${str(r['last_name'])}'.trim();
    final s = str(r['status']);
    final idx = pipelineStages.indexOf(s);
    final next = idx >= 0 && idx < pipelineStages.length - 1 ? pipelineStages[idx + 1] : null;
    final photo = str(r['photo_url']);
    final applied = parseDate(r['created_at']);
    return FormSheet(
      title: 'Applicant profile',
      extraAction: IconButton(tooltip: 'Edit', onPressed: () => Navigator.pop(context, 'edit'), icon: Icon(Icons.edit_outlined, color: p.label)),
      children: [
        Row(children: [
          InitialsAvatar(name.isEmpty ? '?' : name, imageUrl: photo.isEmpty ? null : mediaUrl(photo), size: 64),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name.isEmpty ? 'Unnamed applicant' : name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                StatusPill(humanize(s), tone: stageTone(s), icon: stageIcon(s)),
                if (!asBool(r['is_active'], fallback: true)) const StatusPill('Inactive'),
                if (str(r['custom_id']).isNotEmpty) StatusPill(str(r['custom_id']), tone: MarketTone.neutral),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        _PipelineTrack(stage: s),
        const SizedBox(height: 14),
        Row(children: [
          if (next != null)
            Expanded(
              child: GradientButton(
                label: 'Move to ${humanize(next).toLowerCase()}',
                icon: stageIcon(next),
                accent: Accent.emerald,
                onTap: () => Navigator.pop(context, 'stage:$next'),
              ),
            ),
          if (next != null && s != 'rejected') const SizedBox(width: 10),
          if (s != 'rejected' && next == null) Expanded(child: _rejectBtn(context, p)),
          if (s != 'rejected' && next != null) _rejectBtn(context, p),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final st in resumeStages)
            if (st != s)
              ActionChip(
                avatar: Icon(stageIcon(st), size: 16, color: stageColor(st)),
                label: Text(humanize(st)),
                onPressed: () => Navigator.pop(context, 'stage:$st'),
              ),
        ]),
        const SizedBox(height: 16),
        GlowCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(children: [
            _info(p, Icons.mail_outline_rounded, 'Email', str(r['email'])),
            _info(p, Icons.phone_outlined, 'Phone', str(r['phone'])),
            _info(p, Icons.work_outline_rounded, 'Job posting', nested(r, 'hiring', 'title')),
            _info(p, Icons.event_outlined, 'Applied', applied == null ? '' : fmtDate(applied)),
            _info(p, Icons.business_rounded, 'Current position', [str(r['current_position']), str(r['current_company'])].where((x) => x.isNotEmpty).join(' at ')),
            _info(p, Icons.history_rounded, 'Experience', r['experience_years'] == null ? '' : '${r['experience_years']} yrs'),
          ]),
        ),
        if (str(r['cover_letter']).isNotEmpty) ...[
          const SizedBox(height: 14),
          FormLabel(label: 'Cover letter', child: _textBox(p, htmlToText(str(r['cover_letter'])))),
        ],
        if (str(r['notes']).isNotEmpty) FormLabel(label: 'Notes', child: _textBox(p, htmlToText(str(r['notes'])))),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: p.error,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(context, 'delete'),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GradientButton(
              label: 'Open CV',
              icon: Icons.description_outlined,
              accent: Accent.ocean,
              onTap: str(r['resume_file']).isEmpty ? null : () => openResumeFile(context, str(r['resume_file']), name: '${name.isEmpty ? 'Applicant' : name} CV'),
            ),
          ),
        ]),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 10),
      ],
    );
  }

  Widget _rejectBtn(BuildContext context, MarketPalette p) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.error,
          side: BorderSide(color: p.error.withValues(alpha: 0.5)),
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () => Navigator.pop(context, 'stage:rejected'),
        icon: const Icon(Icons.block_rounded, size: 18),
        label: const Text('Reject'),
      );

  Widget _info(MarketPalette p, IconData i, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(i, size: 18, color: p.label),
          const SizedBox(width: 10),
          SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12.5, color: p.label))),
          Expanded(child: Text(value.isEmpty ? '—' : value, textAlign: TextAlign.right, style: TextStyle(fontSize: 13.5, color: p.text, fontWeight: FontWeight.w500))),
        ]),
      );

  Widget _textBox(MarketPalette p, String t) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
        child: Text(t, style: TextStyle(fontSize: 13.5, height: 1.5, color: p.text)),
      );
}

/// Applied → hired progress track; rejected shows as a red end state.
class _PipelineTrack extends StatelessWidget {
  final String stage;
  const _PipelineTrack({required this.stage});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final rejected = stage == 'rejected';
    final idx = pipelineStages.indexOf(stage);
    return Row(children: [
      for (var i = 0; i < pipelineStages.length; i++) ...[
        Expanded(
          child: Column(children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: !rejected && i <= idx ? 1 : 0),
              duration: Duration(milliseconds: 300 + i * 120),
              curve: Curves.easeOutCubic,
              builder: (_, t, _) => Container(
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: Color.lerp(p.surface, stageColor(pipelineStages[i]), t),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(humanize(pipelineStages[i]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, fontWeight: i == idx ? FontWeight.w700 : FontWeight.w500, color: i == idx ? p.text : p.label)),
          ]),
        ),
        if (i < pipelineStages.length - 1) const SizedBox(width: 4),
      ],
      if (rejected) ...[
        const SizedBox(width: 6),
        Icon(Icons.block_rounded, size: 20, color: stageColor('rejected')),
      ],
    ]);
  }
}

// ── Wizard ──────────────────────────────────────────────────────────────

class _ResumeWizard extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> jobs;
  final Object? presetJob;
  const _ResumeWizard({this.existing, required this.jobs, this.presetJob});

  @override
  State<_ResumeWizard> createState() => _ResumeWizardState();
}

class _ResumeWizardState extends State<_ResumeWizard> {
  static const _steps = ['Basics', 'Contact', 'Background', 'Documents', 'Review'];
  Map<String, dynamic>? get e => widget.existing;
  late final _first = TextEditingController(text: str(e?['first_name']));
  late final _last = TextEditingController(text: str(e?['last_name']));
  late final _customId = TextEditingController(text: str(e?['custom_id']));
  late final _email = TextEditingController(text: str(e?['email']));
  late final _phone = TextEditingController(text: str(e?['phone']));
  late final _company = TextEditingController(text: str(e?['current_company']));
  late final _position = TextEditingController(text: str(e?['current_position']));
  late final _file = TextEditingController(text: str(e?['resume_file']));
  late final _cover = TextEditingController(text: str(e?['cover_letter']));
  late final _notes = TextEditingController(text: str(e?['notes']));
  late int _exp = toInt(e?['experience_years']);
  late bool _hasExp = e?['experience_years'] != null;
  late String _photo = str(e?['photo_url']);
  late String _status = str(e?['status']).isEmpty ? 'applied' : str(e?['status']);
  late bool _active = asBool(e?['is_active'], fallback: true);
  late Object? _job = e == null ? widget.presetJob : e!['hiring_id'];
  int _step = 0;
  int _dir = 1;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _first.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _customId, _email, _phone, _company, _position, _file, _cover, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(int i) {
    if (i == _step || i < 0 || i >= _steps.length) return;
    if (i > 0 && _first.text.trim().isEmpty) {
      marketToast(context, 'First name is required', error: true);
      return;
    }
    setState(() {
      _dir = i > _step ? 1 : -1;
      _step = i;
    });
  }

  Future<void> _pickPhoto() async {
    final picked = await showMediaLibraryDialog(context, title: 'Select profile photo');
    if (picked == null || picked.isEmpty) return;
    setState(() => _photo = picked.first.fileUrl.isNotEmpty ? picked.first.fileUrl : picked.first.previewUrl);
  }

  Future<void> _pickFile() async {
    final picked = await showMediaLibraryDialog(context, title: 'Select resume file');
    if (picked == null || picked.isEmpty) return;
    setState(() => _file.text = picked.first.fileUrl);
  }

  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (_first.text.trim().isEmpty) {
      marketToast(context, 'First name is required', error: true);
      return;
    }
    setState(() => _busy = true);
    final body = {
      'custom_id': _t(_customId),
      'photo_url': _photo.trim().isEmpty ? null : _photo.trim(),
      'first_name': _first.text.trim(),
      'last_name': _t(_last),
      'email': _t(_email),
      'phone': _t(_phone),
      'experience_years': _hasExp ? _exp : null,
      'current_company': _t(_company),
      'current_position': _t(_position),
      'resume_file': _t(_file),
      'cover_letter': _t(_cover),
      'notes': _t(_notes),
      'status': _status,
      'is_active': _active,
      'hiring_id': _job,
    };
    try {
      final api = EntityApi(ApiClient(), 'resumes');
      if (e == null) {
        await api.create(body);
      } else {
        await api.update(e!['id'], body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(err, 'Failed to save resume'), error: true);
      }
    }
  }

  String get _name => '${_first.text.trim()} ${_last.text.trim()}'.trim();

  @override
  Widget build(BuildContext context) => WizardShell(
        title: e == null ? 'New application' : 'Edit application',
        steps: _steps,
        step: _step,
        direction: _dir,
        busy: _busy,
        onStep: _go,
        onBack: () => _step == 0 ? Navigator.pop(context) : _go(_step - 1),
        onNext: _first.text.trim().isEmpty ? null : () => _go(_step + 1),
        finalActions: [Expanded(child: GradientButton(label: 'Submit', icon: Icons.check_rounded, busy: _busy, onTap: _busy ? null : _save))],
        body: switch (_step) { 0 => _basics(context), 1 => _contact(context), 2 => _background(context), 3 => _docs(context), _ => _review(context) },
      );

  Widget _basics(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _photo.isEmpty
                ? Container(
                    key: const ValueKey('none'),
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: p.card, shape: BoxShape.circle, border: Border.all(color: p.line)),
                    child: Icon(Icons.person_outline_rounded, size: 30, color: p.label),
                  )
                : InitialsAvatar(_name.isEmpty ? '?' : _name, key: ValueKey(_photo), imageUrl: mediaUrl(_photo), size: 64),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Profile photo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
              Wrap(spacing: 4, children: [
                TextButton.icon(
                  onPressed: _pickPhoto,
                  icon: Icon(_photo.isEmpty ? Icons.add_a_photo_outlined : Icons.edit_outlined, size: 18),
                  label: Text(_photo.isEmpty ? 'Upload photo' : 'Change photo'),
                ),
                if (_photo.isNotEmpty) TextButton(onPressed: () => setState(() => _photo = ''), child: const Text('Remove')),
              ]),
            ]),
          ),
        ]),
      ),
      FormLabel(
        label: 'Stage',
        child: ToggleChips<String>(
          options: [for (final s in resumeStages) (s, humanize(s))],
          isOn: (s) => _status == s,
          onTap: (s) => setState(() => _status = s),
          color: stageColor(_status),
        ),
      ),
      SwitchField(label: 'Active', value: _active, onChanged: (v) => setState(() => _active = v)),
      FormLabel(
        label: 'Job posting',
        child: PickerField(
          value: _job,
          hint: 'Select job (optional)',
          icon: Icons.work_outline_rounded,
          options: [for (final j in widget.jobs) PickOption(j['id'], str(j['title']))],
          onChanged: (v) => setState(() => _job = v),
        ),
      ),
      FormLabel(label: 'Custom ID', child: TextField(controller: _customId, decoration: motionInput(context, hint: 'Optional', icon: Icons.tag_rounded))),
      FormLabel(label: 'First name', required: true, child: TextField(controller: _first, decoration: motionInput(context, hint: 'First name', icon: Icons.badge_outlined))),
      FormLabel(label: 'Last name', child: TextField(controller: _last, decoration: motionInput(context, hint: 'Last name'))),
    ]);
  }

  Widget _contact(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FormLabel(
          label: 'Email',
          child: TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: motionInput(context, hint: 'candidate@email.com', icon: Icons.mail_outline_rounded)),
        ),
        FormLabel(label: 'Phone', child: TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: motionInput(context, hint: '+880 ...', icon: Icons.phone_outlined))),
      ]);

  Widget _background(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SwitchField(label: 'Has work experience', value: _hasExp, onChanged: (v) => setState(() => _hasExp = v)),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          child: _hasExp
              ? FormLabel(label: 'Experience (years)', child: StepperField(value: _exp, min: 0, max: 60, onChanged: (v) => setState(() => _exp = v)))
              : const SizedBox(width: double.infinity),
        ),
        FormLabel(label: 'Current company', child: TextField(controller: _company, decoration: motionInput(context, hint: 'Company name', icon: Icons.business_rounded))),
        FormLabel(label: 'Current position', child: TextField(controller: _position, decoration: motionInput(context, hint: 'Job title', icon: Icons.work_history_outlined))),
        FormLabel(
          label: 'Resume file',
          help: 'Paste a link or pick a file from the media library.',
          child: TextField(
            controller: _file,
            keyboardType: TextInputType.url,
            decoration: motionInput(
              context,
              hint: 'https://…',
              icon: Icons.link_rounded,
              suffix: IconButton(tooltip: 'Media library', onPressed: _pickFile, icon: const Icon(Icons.perm_media_outlined)),
            ),
          ),
        ),
      ]);

  Widget _docs(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FormLabel(label: 'Cover letter', child: TextField(controller: _cover, minLines: 5, maxLines: 10, decoration: motionInput(context, hint: 'Cover letter text'))),
        FormLabel(label: 'Notes', child: TextField(controller: _notes, minLines: 3, maxLines: 8, decoration: motionInput(context, hint: 'Internal notes'))),
      ]);

  Widget _review(BuildContext context) {
    final p = MarketPalette.of(context);
    final job = lookupName(widget.jobs, _job, 'title');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GlowCard(
        child: Row(children: [
          InitialsAvatar(_name.isEmpty ? '?' : _name, imageUrl: _photo.isEmpty ? null : mediaUrl(_photo), size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name.isEmpty ? 'Unnamed applicant' : _name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
              Text([job, _position.text.trim(), _company.text.trim()].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.label)),
            ]),
          ),
          StatusPill(humanize(_status), tone: stageTone(_status)),
        ]),
      ),
      const SizedBox(height: 12),
      reviewGrid([
        ('Email', _email.text.trim()),
        ('Phone', _phone.text.trim()),
        ('Experience', _hasExp ? '$_exp yrs' : ''),
        ('Resume file', _file.text.trim().isEmpty ? '' : 'Attached'),
      ]),
      if (_cover.text.trim().isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(_cover.text.trim(), maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.label, height: 1.4)),
      ],
      const SizedBox(height: 12),
      Text('Review the details above, then submit to save this application.', style: TextStyle(fontSize: 12, color: p.label)),
    ]);
  }
}
