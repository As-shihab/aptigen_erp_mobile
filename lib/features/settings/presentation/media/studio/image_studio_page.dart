import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../../shared/data/media_studio_service.dart';
import '../../../../../shared/models/media_edit_ops.dart';
import '../../../../../shared/models/media_library_item.dart';
import '../../../../../shared/widgets/media_library_dialog.dart';
import '../../../../sell/market/presentation/widgets/market_ui.dart';
import 'crop_overlay.dart';
import 'image_studio_controller.dart';
import 'studio_constants.dart';
import 'studio_controls.dart';
import 'studio_panels.dart';

/// What the studio hands back when it closes.
class StudioResult {
  /// The saved image (new copy or replaced original) — normal mode.
  final MediaLibraryItem? item;
  /// 'copy' | 'replace' (compress counts as replace).
  final String? mode;
  /// Template mode: the saved template.
  final MediaEditTemplate? template;
  /// Template mode: settings to use once, without saving a template (Lab).
  final EditOps? ops;
  const StudioResult({this.item, this.mode, this.template, this.ops});
}

enum _Tab { adjust, filters, crop, background, layout, compress, templates }

const _tabs = <({_Tab id, String label, IconData icon})>[
  (id: _Tab.adjust, label: 'Adjust', icon: Icons.tune_rounded),
  (id: _Tab.filters, label: 'Filters', icon: Icons.filter_vintage_outlined),
  (id: _Tab.crop, label: 'Crop', icon: Icons.crop_rotate_rounded),
  (id: _Tab.background, label: 'Background', icon: Icons.layers_outlined),
  (id: _Tab.layout, label: 'Layout', icon: Icons.aspect_ratio_rounded),
  (id: _Tab.compress, label: 'Compress', icon: Icons.compress_rounded),
  (id: _Tab.templates, label: 'Templates', icon: Icons.bookmarks_outlined),
];

/// Opens the studio full screen. Resolves with a [StudioResult] when the
/// image (or, in template mode, a template) was saved.
Future<StudioResult?> openImageStudio(
  BuildContext context,
  MediaLibraryItem item, {
  bool templateMode = false,
  MediaEditTemplate? template,
  TemplatesStore? templates,
  EditOps? initialOps,
  bool allowUseOnce = false,
}) =>
    Navigator.of(context).push<StudioResult>(marketRoute(ImageStudioPage(
      item: item,
      templateMode: templateMode,
      template: template,
      templates: templates,
      initialOps: initialOps,
      allowUseOnce: allowUseOnce,
    )));

/// Image studio — port of erp/desktop's ImageStudioDialog.tsx as a mobile
/// photo editor: large preview with before / after, tool tabs at the bottom,
/// debounced server previews, undo / redo, save as copy or replace.
class ImageStudioPage extends StatefulWidget {
  final MediaLibraryItem item;
  /// Template mode (used by the Lab): the image is only a sample — saving
  /// stores the settings as a template, and crop / compress are hidden.
  final bool templateMode;
  /// Template being edited in template mode; its ops seed the studio.
  final MediaEditTemplate? template;
  /// Shared templates list (the Lab passes its own so it stays in sync).
  final TemplatesStore? templates;
  /// Starting settings when no template is being edited (e.g. the Lab's custom settings).
  final EditOps? initialOps;
  /// Template mode: also offer "Use without saving".
  final bool allowUseOnce;

  const ImageStudioPage({
    super.key,
    required this.item,
    this.templateMode = false,
    this.template,
    this.templates,
    this.initialOps,
    this.allowUseOnce = false,
  });

  @override
  State<ImageStudioPage> createState() => _ImageStudioPageState();
}

class _ImageStudioPageState extends State<ImageStudioPage> {
  final _service = MediaStudioService();
  late final ImageStudioController _studio = ImageStudioController(
    widget.item.id,
    initial: widget.templateMode && widget.template != null
        ? stripCrop(widget.template!.ops)
        : (widget.initialOps != null ? stripCrop(widget.initialOps!) : null),
    service: _service,
  );
  late final TemplatesStore _templates = widget.templates ?? TemplatesStore(_service);

  late final String _sourceUrl = mediaView(widget.item, 'large');
  late final String _thumbUrl = mediaView(widget.item, 'small');
  late final ImageProvider _source = CachedNetworkImageProvider(_sourceUrl);

  Size? _natural;
  bool _sourceError = false;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  _Tab _tab = _Tab.adjust;
  bool _showBefore = false;
  bool _holding = false;

  bool _cropMode = false;
  CropRect _cropDraft = CropRect.full;
  String _cropAspect = 'free';

  final Map<int, ({String thumb, String name})> _bgImages = {};

  String? _saving; // 'copy' | 'replace' | 'template'
  bool _compressing = false;
  String? _saveError;
  int? _appliedTemplateId;
  bool _done = false;

  bool get _editingTemplate => widget.templateMode && widget.template != null;
  List<({_Tab id, String label, IconData icon})> get _visibleTabs =>
      widget.templateMode ? _tabs.where((t) => t.id != _Tab.compress).toList() : _tabs;

  @override
  void initState() {
    super.initState();
    _studio.addListener(_onChange);
    _templates.addListener(_onChange);
    _resolveNatural();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _resolveNatural() {
    final stream = _source.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, _) {
        if (mounted) setState(() => _natural = Size(info.image.width.toDouble(), info.image.height.toDouble()));
      },
      onError: (_, _) {
        if (mounted) setState(() => _sourceError = true);
      },
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _studio.removeListener(_onChange);
    _templates.removeListener(_onChange);
    _studio.dispose();
    if (widget.templates == null) _templates.dispose();
    super.dispose();
  }

  // ── Crop ──
  void _startCrop() {
    if (_natural == null) return;
    setState(() {
      _cropDraft = _studio.ops.crop ?? CropRect.full;
      _cropAspect = 'free';
      _showBefore = false;
      _cropMode = true;
    });
  }

  void _chooseCropAspect(String id) {
    final ratio = cropAspects.firstWhere((a) => a.id == id).ratio;
    final n = _natural;
    setState(() {
      _cropAspect = id;
      if (ratio != null && n != null) _cropDraft = centeredCrop(ratio, n.width, n.height);
    });
  }

  void _applyCrop() {
    final draft = _cropDraft;
    _studio.set((prev) => prev.copyWith(crop: draft.isFull ? null : draft.rounded()));
    setState(() => _cropMode = false);
  }

  void _cancelCrop() => setState(() => _cropMode = false);

  // ── Background image ──
  Future<void> _pickBackground() async {
    final picked = await showMediaLibraryDialog(context, title: 'Choose a background image');
    final chosen = picked?.firstOrNull;
    if (chosen == null || !mounted) return;
    if (!chosen.isImage) {
      marketToast(context, 'Choose an image file for the background');
      return;
    }
    setState(() => _bgImages[chosen.id] = (thumb: mediaView(chosen, 'tiny'), name: chosen.name));
    _studio.set((prev) => prev.copyWith(
          background: (prev.background ?? const EditBackground(type: 'image')).copyWith(type: 'image', mediaId: chosen.id),
        ));
  }

  // ── Save ──
  Future<void> _doSave(String mode) async {
    setState(() {
      _saving = mode;
      _saveError = null;
    });
    try {
      final saved = await _service.save(widget.item.id, _studio.effective, mode);
      if (!mounted) return;
      marketToast(context, mode == 'copy' ? 'Saved as a new copy' : 'Original image replaced');
      _done = true;
      Navigator.pop(context, StudioResult(item: saved ?? widget.item, mode: mode));
    } catch (e) {
      if (mounted) setState(() => _saveError = describeStudioError(e, 'Could not save the image'));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  Future<void> _confirmReplace() async {
    final ok = await confirmMarket(
      context,
      title: 'Replace the original image?',
      message:
          'This overwrites the file of "${_name()}" with the edited version. Everywhere it is used will show the new image, and the original cannot be restored. Use "Save as copy" to keep the original.',
      confirm: 'Replace original',
    );
    if (ok) await _doSave('replace');
  }

  Future<void> _doCompress(int targetKb) async {
    setState(() {
      _compressing = true;
      _saveError = null;
    });
    try {
      final result = await _service.compress(widget.item.id, targetKb);
      if (!mounted) return;
      if (!result.compressed) {
        marketToast(context, 'This image is already as small as it can get');
        return;
      }
      marketToast(context, 'Compressed: ${formatBytes(result.before)} → ${formatBytes(result.after)}');
      _done = true;
      Navigator.pop(context, StudioResult(item: result.item ?? widget.item, mode: 'replace'));
    } catch (e) {
      if (mounted) setState(() => _saveError = describeStudioError(e, 'Could not compress the image'));
    } finally {
      if (mounted) setState(() => _compressing = false);
    }
  }

  // ── Templates ──
  bool get _canSaveTemplate => !isEmptyTemplateOps(_studio.ops);

  void _applyTemplate(MediaEditTemplate t) {
    // One undoable step; the current crop (image-specific) is kept.
    _studio.set((prev) => stripCrop(t.ops).copyWith(crop: prev.crop));
    setState(() => _appliedTemplateId = t.id);
    marketToast(context, 'Applied "${t.name}"');
  }

  Future<void> _saveTemplate() async {
    final template = widget.template;
    MediaEditTemplate? result;
    final ok = await showTemplateForm(
      context,
      title: _editingTemplate ? 'Update template' : 'Save as template',
      submitText: _editingTemplate ? 'Update template' : 'Save template',
      initialName: template?.name ?? '',
      initialDescription: template?.description ?? '',
      ops: _studio.ops,
      onSubmit: (name, description) async {
        final ops = templateOps(_studio.ops);
        result = _editingTemplate && template != null
            ? (await _service.updateTemplate(template.id, name: name, description: description, ops: ops)) ??
                template.copyWith(
                    name: name, description: description.isEmpty ? null : description, ops: ops, updatedAt: DateTime.now().toIso8601String())
            : await _service.createTemplate(name: name, description: description, ops: ops);
        _templates.upsert(result!);
      },
    );
    if (!ok || !mounted || result == null) return;
    marketToast(context, _editingTemplate ? 'Template updated' : 'Template saved');
    if (widget.templateMode) {
      _done = true;
      Navigator.pop(context, StudioResult(template: result));
    }
  }

  void _useOnce() {
    _done = true;
    Navigator.pop(context, StudioResult(ops: templateOps(_studio.ops)));
  }

  void _openSaveSheet() {
    final p = MarketPalette.of(context);
    final hasChanges = _studio.hasChanges;
    showMarketSheet<void>(
      context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.templateMode ? 'Save settings' : 'Save image', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 12),
            if (widget.templateMode) ...[
              _SaveOption(
                icon: Icons.bookmark_add_outlined,
                title: _editingTemplate ? 'Update template' : 'Save template',
                subtitle: 'Reuse these settings on other images.',
                enabled: _canSaveTemplate,
                onTap: () {
                  Navigator.pop(ctx);
                  _saveTemplate();
                },
              ),
              if (widget.allowUseOnce) ...[
                const SizedBox(height: 8),
                _SaveOption(
                  icon: Icons.play_arrow_outlined,
                  title: 'Use without saving',
                  subtitle: 'Apply these settings to the selected images once.',
                  enabled: _canSaveTemplate,
                  onTap: () {
                    Navigator.pop(ctx);
                    _useOnce();
                  },
                ),
              ],
            ] else ...[
              _SaveOption(
                icon: Icons.copy_rounded,
                title: 'Save as copy',
                subtitle: 'Keeps the original and adds the edited image next to it.',
                enabled: hasChanges,
                onTap: () {
                  Navigator.pop(ctx);
                  _doSave('copy');
                },
              ),
              const SizedBox(height: 8),
              _SaveOption(
                icon: Icons.sync_rounded,
                title: 'Replace original',
                subtitle: 'Overwrites the file everywhere it is used.',
                enabled: hasChanges,
                destructive: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmReplace();
                },
              ),
              const SizedBox(height: 8),
              _SaveOption(
                icon: Icons.bookmark_add_outlined,
                title: 'Save as template',
                subtitle: _canSaveTemplate ? 'Save these settings to reuse on other images.' : 'Crop-only edits can\'t be saved as a template.',
                enabled: _canSaveTemplate,
                onTap: () {
                  Navigator.pop(ctx);
                  _saveTemplate();
                },
              ),
            ],
            if (!widget.templateMode && !hasChanges) ...[
              const SizedBox(height: 10),
              const StudioHint('Make an edit first.'),
            ],
          ]),
        ),
      ),
    );
  }

  String _name() => widget.item.name.trim().isEmpty ? 'Image' : widget.item.name.trim();

  Future<bool> _confirmDiscard() async {
    if (_done || !_studio.hasChanges) return true;
    return confirmMarket(context,
        title: 'Discard changes?', message: 'Your edits to this image haven\'t been saved.', confirm: 'Discard');
  }

  // ── Build ──
  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final busySaving = _saving != null || _compressing;
    final heading = widget.templateMode ? (_editingTemplate ? 'Edit template' : 'New template') : 'Image studio';
    final subtitle = widget.templateMode
        ? (widget.template != null ? '${widget.template!.name} · previewing on "${_name()}"' : 'Previewing on "${_name()}"')
        : _name();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || busySaving) return;
        if (_cropMode) {
          _cancelCrop();
          return;
        }
        final ok = await _confirmDiscard();
        if (ok && context.mounted) {
          _done = true;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          backgroundColor: p.card,
          surfaceTintColor: Colors.transparent,
          shape: Border(bottom: BorderSide(color: p.line)),
          titleSpacing: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(heading, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
          ]),
          actions: [
            IconButton(
              tooltip: 'Undo',
              onPressed: _studio.canUndo && !busySaving && !_cropMode ? _studio.undo : null,
              icon: const Icon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: 'Redo',
              onPressed: _studio.canRedo && !busySaving && !_cropMode ? _studio.redo : null,
              icon: const Icon(Icons.redo_rounded),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10, left: 4),
              child: FilledButton(
                onPressed: busySaving || _cropMode ? null : _openSaveSheet,
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 16)),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Stack(children: [
            Column(children: [
              Expanded(child: _buildPreview(p)),
              _buildToolbar(p),
              if (_saveError != null)
                Container(
                  color: p.card,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: StudioStrip(_saveError!,
                      tone: MarketTone.error,
                      action: IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _saveError = null),
                          icon: Icon(Icons.close_rounded, size: 18, color: p.label))),
                ),
              _buildPanel(p),
              _buildTabs(p),
            ]),
            if (_saving != null) _buildSavingOverlay(p),
          ]),
        ),
      ),
    );
  }

  Widget _buildPreview(MarketPalette p) {
    final before = _showBefore || _holding;
    final preview = _studio.preview;
    final busy = _studio.loading && !before && !_cropMode;
    final n = _natural;

    Widget content;
    if (_cropMode && n != null) {
      content = CropOverlay(
        image: _source,
        naturalW: n.width,
        naturalH: n.height,
        value: _cropDraft,
        ratio: cropAspects.firstWhere((a) => a.id == _cropAspect).ratio,
        onChanged: (r) => setState(() => _cropDraft = r),
      );
    } else {
      final image = !before && preview != null
          ? Image.memory(preview.bytes, fit: BoxFit.contain, gaplessPlayback: true)
          : Image(image: _source, fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox());
      content = GestureDetector(
        onLongPressStart: (_) => setState(() => _holding = true),
        onLongPressEnd: (_) => setState(() => _holding = false),
        onLongPressCancel: () => setState(() => _holding = false),
        child: InteractiveViewer(
          maxScale: 6,
          child: Padding(padding: const EdgeInsets.all(16), child: Center(child: image)),
        ),
      );
    }

    return CheckerBackground(
      child: Stack(fit: StackFit.expand, children: [
        content,
        if (_sourceError)
          const Positioned(left: 12, right: 12, top: 12, child: StudioStrip('Could not load the original image.', tone: MarketTone.error)),
        if (_studio.error != null && !_cropMode)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: StudioStrip(_studio.error!,
                tone: MarketTone.error, action: TextButton(onPressed: _studio.retry, child: const Text('Retry'))),
          ),
        if (_holding && !_cropMode)
          const Positioned(top: 12, left: 0, right: 0, child: Center(child: StatusPill('Original', tone: MarketTone.neutral))),
        if (busy)
          IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.brand)),
                  const SizedBox(width: 10),
                  Text(_studio.removingBgFirstTime ? 'Removing background…' : 'Updating preview…', style: TextStyle(fontSize: 13, color: p.text)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildToolbar(MarketPalette p) {
    final canCompare = !_studio.identity && _studio.preview != null;
    final preview = _studio.preview;
    return Container(
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(children: [
        if (_cropMode)
          const Expanded(child: StudioHint('Cropping the original image — apply or cancel below.'))
        else ...[
          IgnorePointer(
            ignoring: !canCompare,
            child: Opacity(
              opacity: canCompare ? 1 : 0.5,
              child: MarketSegmented<bool>(
                value: _showBefore,
                options: const [(id: true, label: 'Before', count: null), (id: false, label: 'After', count: null)],
                onChanged: (v) => setState(() => _showBefore = v),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              canCompare ? 'Hold the image to compare' : '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: p.label),
            ),
          ),
          if (preview != null && !_showBefore)
            Text('${preview.width} × ${preview.height}', style: TextStyle(fontSize: 11.5, color: p.label)),
          IconButton(
            tooltip: 'Reset all',
            visualDensity: VisualDensity.compact,
            onPressed: _saving != null || !_studio.hasChanges ? null : _studio.resetAll,
            icon: const Icon(Icons.restart_alt_rounded, size: 20),
          ),
        ],
      ]),
    );
  }

  Widget _buildPanel(MarketPalette p) {
    final height = (MediaQuery.sizeOf(context).height * 0.36).clamp(200.0, 380.0);
    final bgMediaId = _studio.ops.background?.mediaId;
    final Widget panel = switch (_tab) {
      _Tab.adjust => AdjustPanel(studio: _studio),
      _Tab.filters => FiltersPanel(studio: _studio, thumbUrl: _thumbUrl),
      _Tab.crop => CropPanel(
          studio: _studio,
          cropMode: _cropMode,
          cropAspect: _cropAspect,
          canCrop: _natural != null,
          onStartCrop: _startCrop,
          onCropAspect: _chooseCropAspect,
          onApplyCrop: _applyCrop,
          onCancelCrop: _cancelCrop,
          hideCrop: widget.templateMode,
        ),
      _Tab.background => BackgroundPanel(
          studio: _studio,
          bgImageThumb: bgMediaId != null ? _bgImages[bgMediaId]?.thumb : null,
          bgImageName: bgMediaId != null ? _bgImages[bgMediaId]?.name : null,
          onPickImage: _pickBackground,
        ),
      _Tab.layout => LayoutPanel(studio: _studio, hasAlpha: _studio.preview?.hasAlpha ?? false),
      _Tab.compress => CompressPanel(
          size: widget.item.size,
          hasChanges: _studio.hasChanges,
          busy: _compressing,
          onCompress: _doCompress,
        ),
      _Tab.templates => TemplatesPanel(
          store: _templates,
          appliedId: _appliedTemplateId,
          canSave: _canSaveTemplate && !_cropMode,
          onApply: _applyTemplate,
          onSaveAs: _saveTemplate,
        ),
    };
    return Container(
      height: height,
      color: p.card,
      child: SingleChildScrollView(key: PageStorageKey(_tab), child: panel),
    );
  }

  Widget _buildTabs(MarketPalette p) {
    return Container(
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        children: [
          for (final t in _visibleTabs)
            _TabButton(
              icon: t.icon,
              label: t.label,
              selected: _tab == t.id,
              // While cropping only the crop tools stay available.
              enabled: !_cropMode || t.id == _Tab.crop,
              onTap: () {
                setState(() => _tab = t.id);
                if (t.id == _Tab.templates) _templates.ensureLoaded();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSavingOverlay(MarketPalette p) => Positioned.fill(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.25),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: p.brand)),
                const SizedBox(width: 12),
                Text(_saving == 'copy' ? 'Saving a copy…' : 'Replacing the original…', style: TextStyle(fontSize: 13.5, color: p.text)),
              ]),
            ),
          ),
        ),
      );
}

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const _TabButton({required this.icon, required this.label, required this.selected, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final color = !enabled ? p.line : (selected ? p.brand : p.label);
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 78,
        decoration: BoxDecoration(border: Border(top: BorderSide(color: selected ? p.brand : Colors.transparent, width: 2.5))),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 21, color: color),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color)),
        ]),
      ),
    );
  }
}

class _SaveOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final bool destructive;
  final VoidCallback onTap;
  const _SaveOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    this.destructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final c = destructive ? p.tone(MarketTone.error) : p.tone(MarketTone.brand);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: MarketCard(
        onTap: enabled ? onTap : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: c.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
              Text(subtitle, style: TextStyle(fontSize: 12, color: p.label)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: p.label),
        ]),
      ),
    );
  }
}
