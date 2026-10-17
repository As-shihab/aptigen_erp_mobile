import 'package:flutter/material.dart';

import '../../../../../shared/data/media_lab_service.dart';
import '../../../../../shared/data/media_studio_service.dart';
import '../../../../../shared/models/media_edit_ops.dart';
import '../../../../../shared/models/media_library_item.dart';
import '../../../../sell/market/presentation/widgets/market_ui.dart';
import '../studio/image_studio_page.dart';
import '../studio/studio_controls.dart';
import 'lab_steps.dart';

/// The Lab — apply one edit template to many images at once. Port of
/// erp/desktop's MediaLabDialog.tsx as a full-screen step flow:
/// 1 Select images · 2 Choose template · 3 Apply (server-side batch job).
/// Resolves true when a batch finished, so the library can reload.
class MediaLabPage extends StatefulWidget {
  const MediaLabPage({super.key});

  @override
  State<MediaLabPage> createState() => _MediaLabPageState();
}

class _MediaLabPageState extends State<MediaLabPage> {
  final _service = MediaLabService();
  final _templates = TemplatesStore();

  int _step = 1;
  final Map<int, MediaLibraryItem> _selected = {};
  int? _chosenId;
  EditOps? _customOps;
  String _mode = 'copy';

  StoredJob? _stored;
  BatchJobWatcher? _watcher;
  bool _starting = false;
  String? _startError;
  bool _cancelling = false;
  bool _resumeChecked = false;
  bool _anyFinished = false;
  /// Jobs seen running while open — only those get a "finished" toast.
  final Set<String> _sawActive = {};

  @override
  void initState() {
    super.initState();
    _templates.addListener(_onChange);
    _templates.reload();
    _resume();
  }

  @override
  void dispose() {
    _templates.removeListener(_onChange);
    _templates.dispose();
    _watcher?.removeListener(_onChange);
    _watcher?.dispose();
    super.dispose();
  }

  void _onChange() {
    final j = _watcher?.job;
    if (j != null && isJobActive(j.status)) _sawActive.add(j.jobId);
    if (mounted) setState(() {});
  }

  /// Resume the last job, if any.
  Future<void> _resume() async {
    final last = await MediaLabService.readStoredJob();
    if (!mounted) return;
    setState(() => _resumeChecked = true);
    if (last != null) {
      _mode = last.mode;
      _step = 3;
      _watch(last);
    }
  }

  void _watch(StoredJob? job) {
    _watcher?.removeListener(_onChange);
    _watcher?.dispose();
    _watcher = null;
    setState(() => _stored = job);
    if (job == null) return;
    final w = BatchJobWatcher(job.jobId, service: _service, onFinished: _handleFinished);
    w.addListener(_onChange);
    _watcher = w;
  }

  void _handleFinished(BatchJob j) {
    if (!mounted) return;
    _anyFinished = true;
    setState(() => _cancelling = false);
    if (j.status == 'done' && _sawActive.contains(j.jobId)) {
      marketToast(context, j.failed > 0 ? 'Finished — ${j.failed} image${j.failed == 1 ? '' : 's'} failed' : 'All images edited');
    }
  }

  BatchJob? get _job => _watcher?.job;
  bool get _missing => _watcher?.missing ?? false;
  bool get _running => _stored != null && !_missing && (_job == null || isJobActive(_job!.status));
  bool get _finished => _stored != null && (_missing || (_job != null && !isJobActive(_job!.status)));

  MediaEditTemplate? get _chosen => _templates.templates.where((t) => t.id == _chosenId).firstOrNull;
  bool get _hasSettings => _chosen != null || (_chosenId == null && _customOps != null);
  List<MediaLibraryItem> get _selectedList => _selected.values.toList();

  // ── Selection ──
  void _toggle(MediaLibraryItem item) {
    setState(() {
      if (_selected.containsKey(item.id)) {
        _selected.remove(item.id);
      } else if (_selected.length >= labMaxItems) {
        marketToast(context, 'You can select up to $labMaxItems images');
      } else {
        _selected[item.id] = item;
      }
    });
  }

  void _selectMany(List<MediaLibraryItem> items) {
    var capped = false;
    setState(() {
      for (final it in items) {
        if (_selected.length >= labMaxItems) {
          capped = true;
          break;
        }
        _selected[it.id] = it;
      }
    });
    if (capped) marketToast(context, 'Only the first $labMaxItems images were selected');
  }

  // ── Templates / settings ──
  Future<void> _openTemplateStudio(MediaEditTemplate? template, {bool custom = false}) async {
    final sample = _selectedList.firstOrNull;
    if (sample == null) return;
    final result = await openImageStudio(
      context,
      sample,
      templateMode: true,
      template: custom ? null : template,
      initialOps: custom ? _customOps : null,
      templates: _templates,
      allowUseOnce: true,
    );
    if (!mounted || result == null) return;
    setState(() {
      if (result.template != null) {
        _chosenId = result.template!.id;
      } else if (result.ops != null) {
        _customOps = result.ops;
        _chosenId = null;
      }
    });
  }

  // ── Starting a job ──
  Future<void> _start(List<LabItem> items, String mode, {int? templateId, String? templateName, EditOps? ops}) async {
    setState(() {
      _starting = true;
      _startError = null;
    });
    try {
      final res = await _service.startBatchEdit(
        itemIds: items.map((i) => i.id).toList(),
        mode: mode,
        templateId: templateId,
        ops: templateId == null ? (ops ?? EditOps.empty) : null,
      );
      final next = StoredJob(
        jobId: res.jobId,
        mode: mode,
        templateId: templateId,
        templateName: templateName,
        ops: ops,
        items: items,
        startedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _sawActive.add(res.jobId);
      await MediaLabService.writeStoredJob(next);
      if (!mounted) return;
      setState(() => _step = 3);
      _watch(next);
    } catch (e) {
      if (mounted) setState(() => _startError = describeStudioError(e, 'Could not start editing the images'));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _apply() async {
    if (!_hasSettings || _selected.isEmpty) return;
    final count = _selected.length;
    if (_mode == 'replace') {
      final ok = await confirmMarket(
        context,
        title: 'Replace the original images?',
        message:
            'This overwrites the files of $count image${count == 1 ? '' : 's'} with the edited versions. Everywhere they are used will show the new images, and the originals can\'t be restored. Choose "Save as new copies" to keep them.',
        confirm: 'Replace $count original${count == 1 ? '' : 's'}',
      );
      if (!ok) return;
    }
    final items = _selectedList.map((i) => LabItem.of(i)).toList();
    final chosen = _chosen;
    if (chosen != null) {
      await _start(items, _mode, templateId: chosen.id, templateName: chosen.name, ops: chosen.ops);
    } else {
      await _start(items, _mode, templateName: 'Custom settings', ops: _customOps);
    }
  }

  List<LabItem> get _failedItems {
    final job = _job;
    final stored = _stored;
    if (job == null || stored == null) return const [];
    final ids = job.results.where((r) => r.status == 'error').map((r) => r.itemId).toSet();
    final known = stored.items.where((i) => ids.contains(i.id)).toList();
    for (final r in job.results) {
      if (r.status == 'error' && !known.any((k) => k.id == r.itemId)) known.add(LabItem(id: r.itemId, name: r.name, thumb: ''));
    }
    return known;
  }

  void _retryFailed() {
    final stored = _stored;
    final failed = _failedItems;
    if (stored == null || failed.isEmpty) return;
    // The template may have been deleted since — fall back to its stored ops.
    final stillExists = stored.templateId != null && _templates.templates.any((t) => t.id == stored.templateId);
    _start(failed, stored.mode, templateId: stillExists ? stored.templateId : null, templateName: stored.templateName, ops: stored.ops);
  }

  Future<void> _cancelJob() async {
    final stored = _stored;
    if (stored == null) return;
    setState(() => _cancelling = true);
    try {
      await _service.cancelBatchJob(stored.jobId);
      if (mounted) marketToast(context, 'Cancelling — images already edited are kept');
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      marketToast(context, describeStudioError(e, 'Could not cancel the job'), error: true);
    }
  }

  void _startOver() {
    MediaLabService.writeStoredJob(null);
    _watch(null);
    setState(() {
      _startError = null;
      _selected.clear();
      _step = 1;
    });
  }

  void _finish() {
    MediaLabService.writeStoredJob(null);
    Navigator.pop(context, true);
  }

  Future<void> _requestClose() async {
    if (_running) {
      final ok = await confirmMarket(
        context,
        title: 'Close the Lab?',
        message: 'The images keep being edited on the server. Open the Lab again to see the progress.',
        confirm: 'Close',
        destructive: false,
      );
      if (!ok || !mounted) return;
    } else if (_finished) {
      MediaLabService.writeStoredJob(null);
    }
    if (mounted) Navigator.pop(context, _anyFinished);
  }

  // ── Build ──
  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final stored = _stored;
    final count = _selected.length;

    Widget body;
    if (!_resumeChecked) {
      body = const SkeletonList(count: 4);
    } else if (stored != null) {
      body = ProgressView(job: _job, stored: stored, error: _watcher?.error, missing: _missing);
    } else if (_step == 1) {
      body = SelectStep(selected: _selected, onToggle: _toggle, onSelectMany: _selectMany, onClear: () => setState(_selected.clear));
    } else if (_step == 2) {
      body = TemplateStep(
        store: _templates,
        chosenId: _chosenId,
        customOps: _customOps,
        onChoose: (id) => setState(() => _chosenId = id),
        onChooseCustom: () => setState(() => _chosenId = null),
        onNew: () => _openTemplateStudio(null),
        onCustom: () => _openTemplateStudio(null, custom: true),
        onEdit: (t) => _openTemplateStudio(t),
        previewItems: _selectedList.take(4).toList(),
      );
    } else {
      final chosen = _chosen;
      body = ApplySetup(
        count: count,
        settingsName: chosen?.name ?? (_customOps != null ? 'Custom settings' : null),
        ops: chosen?.ops ?? _customOps,
        mode: _mode,
        onMode: (m) => setState(() => _mode = m),
        starting: _starting,
        error: _startError,
        onDismissError: () => setState(() => _startError = null),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (stored == null && _step > 1 && !_starting) {
          setState(() => _step--);
          return;
        }
        _requestClose();
      },
      child: MarketScaffold(
        title: 'Lab',
        subtitle: 'Edit many images at once with a template',
        actions: [
          IconButton(tooltip: 'Close', onPressed: _requestClose, icon: const Icon(Icons.close_rounded)),
        ],
        body: Column(children: [
          _StepBar(
            step: stored != null ? 3 : _step,
            locked: stored != null,
            selectedCount: count,
            settingsName: _chosen?.name ?? (_chosenId == null && _customOps != null ? 'Custom settings' : null),
            canGoTo: (s) => stored == null && (s == 1 || (s == 2 && count > 0) || (s == 3 && count > 0 && _hasSettings)),
            onGoTo: (s) => setState(() => _step = s),
          ),
          Expanded(child: body),
          if (stored != null && _startError != null)
            Container(
              color: p.card,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: StudioStrip(_startError!, tone: MarketTone.error),
            ),
          _buildFooter(p),
        ]),
      ),
    );
  }

  Widget _buildFooter(MarketPalette p) {
    final stored = _stored;
    final count = _selected.length;
    final List<Widget> buttons;
    if (!_resumeChecked) {
      buttons = const [];
    } else if (stored != null) {
      final failed = _failedItems.length;
      buttons = _running
          ? [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _cancelling || _job == null ? null : _cancelJob,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: Text(_cancelling ? 'Cancelling…' : 'Cancel job'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: _requestClose, child: const Text('Close'))),
            ]
          : [
              IconButton(
                tooltip: 'Start over',
                onPressed: _starting ? null : _startOver,
                icon: Icon(Icons.restart_alt_rounded, color: p.label),
              ),
              if (failed > 0) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _starting ? null : _retryFailed,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text('Retry failed ($failed)'),
                  ),
                ),
                const SizedBox(width: 10),
              ] else
                const Spacer(),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _starting ? null : _finish,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Done'),
                ),
              ),
            ];
    } else if (_step == 1) {
      buttons = [
        Expanded(child: OutlinedButton(onPressed: _requestClose, child: const Text('Cancel'))),
        const SizedBox(width: 10),
        Expanded(child: FilledButton(onPressed: count > 0 ? () => setState(() => _step = 2) : null, child: const Text('Next'))),
      ];
    } else if (_step == 2) {
      buttons = [
        Expanded(child: OutlinedButton(onPressed: () => setState(() => _step = 1), child: const Text('Back'))),
        const SizedBox(width: 10),
        Expanded(child: FilledButton(onPressed: _hasSettings ? () => setState(() => _step = 3) : null, child: const Text('Next'))),
      ];
    } else {
      buttons = [
        Expanded(child: OutlinedButton(onPressed: _starting ? null : () => setState(() => _step = 2), child: const Text('Back'))),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            style: _mode == 'replace' ? FilledButton.styleFrom(backgroundColor: p.error) : null,
            onPressed: _starting || !_hasSettings || count == 0 ? null : _apply,
            icon: const Icon(Icons.science_outlined, size: 18),
            label: Text('Apply to $count image${count == 1 ? '' : 's'}'),
          ),
        ),
      ];
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(context).bottom),
      child: Row(children: buttons),
    );
  }
}

/// "1 Select · 2 Template · 3 Apply" — completed steps are tappable.
class _StepBar extends StatelessWidget {
  final int step;
  final bool locked;
  final int selectedCount;
  final String? settingsName;
  final bool Function(int s) canGoTo;
  final ValueChanged<int> onGoTo;
  const _StepBar({
    required this.step,
    required this.locked,
    required this.selectedCount,
    required this.settingsName,
    required this.canGoTo,
    required this.onGoTo,
  });

  static const _labels = ['Select images', 'Choose template', 'Apply'];

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      decoration: BoxDecoration(color: p.card, border: Border(bottom: BorderSide(color: p.line))),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(children: [
        for (var i = 1; i <= 3; i++) ...[
          if (i > 1) Icon(Icons.chevron_right_rounded, size: 16, color: p.label),
          Expanded(child: _item(p, i)),
        ],
      ]),
    );
  }

  Widget _item(MarketPalette p, int s) {
    final current = s == step;
    final done = s < step;
    final enabled = !current && canGoTo(s);
    final hint = s == 1 && selectedCount > 0
        ? '$selectedCount selected'
        : s == 2 && settingsName != null
            ? settingsName!
            : null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? () => onGoTo(s) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(color: current ? p.brandSoft : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: current ? p.brand : (done ? p.okBg : p.surface),
              border: current || done ? null : Border.all(color: p.line),
            ),
            child: done
                ? Icon(Icons.check_rounded, size: 13, color: p.ok)
                : Text('$s', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: current ? Colors.white : p.label)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(_labels[s - 1],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: current ? FontWeight.w700 : FontWeight.w500, color: current ? p.text : p.label)),
              if (hint != null)
                Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: p.label)),
            ]),
          ),
        ]),
      ),
    );
  }
}
