import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../../core/network/http_client.dart';
import '../../../../../shared/data/media_lab_service.dart';
import '../../../../../shared/data/media_library_service.dart';
import '../../../../../shared/data/media_studio_service.dart';
import '../../../../../shared/models/media_edit_ops.dart';
import '../../../../../shared/models/media_library_item.dart';
import '../../../../sell/market/presentation/widgets/market_ui.dart';
import '../studio/studio_controls.dart';

// The Lab's step bodies — ports of desktop's lab/SelectStep, TemplateStep,
// PreviewStrip and ApplyStep (ApplySetup + ProgressView).

Widget _thumb(MarketPalette p, String url, {BoxFit fit = BoxFit.cover}) => url.isEmpty
    ? Container(color: p.surface, child: Icon(Icons.image_outlined, color: p.label, size: 20))
    : CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, _) => Container(color: p.surface),
        errorWidget: (_, _, _) => Container(color: p.surface, child: Icon(Icons.broken_image_outlined, color: p.label, size: 20)),
      );

// ── 1 · Select ──

class SelectStep extends StatefulWidget {
  /// id → item
  final Map<int, MediaLibraryItem> selected;
  final ValueChanged<MediaLibraryItem> onToggle;
  final ValueChanged<List<MediaLibraryItem>> onSelectMany;
  final VoidCallback onClear;
  const SelectStep({super.key, required this.selected, required this.onToggle, required this.onSelectMany, required this.onClear});

  @override
  State<SelectStep> createState() => _SelectStepState();
}

class _SelectStepState extends State<SelectStep> {
  static const _page = 60;
  final _service = MediaLibraryService(ApiClient());
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  List<MediaLibraryItem> _items = [];
  List<MediaCategory> _categories = [];
  int? _total;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  int? _categoryId;
  String _visibility = 'all';
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300 && !_loading && _hasMore) _load(reset: false);
    });
    _service.loadCategories().then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((_) {});
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (_loading && !reset) return;
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final skip = reset ? 0 : _items.length;
    try {
      final page = await _service.loadItems(
        search: _search.text,
        categoryId: _categoryId,
        visibility: _visibility,
        kind: 'image',
        newestFirst: true,
        top: _page,
        skip: skip,
        withCount: reset,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        if (reset) _total = page.total;
        _hasMore = page.items.length == _page;
      });
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = describeStudioError(e, 'Could not load images'));
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final selected = widget.selected;
    final atLimit = selected.length >= labMaxItems;
    final unselected = _items.where((i) => !selected.containsKey(i.id)).toList();
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 6 : (width >= 600 ? 5 : 3);

    return Column(children: [
      Container(
        color: p.card,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () => _load(reset: true));
            },
            decoration: InputDecoration(
              hintText: 'Search images',
              prefixIcon: Icon(Icons.search_rounded, color: p.label),
              isDense: true,
              filled: true,
              fillColor: p.bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _chip(p, 'All categories', _categoryId == null, () => _pickCategory(null)),
              for (final c in _categories) _chip(p, c.name.isEmpty ? 'Untitled' : c.name, _categoryId == c.id, () => _pickCategory(c.id)),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            MarketSegmented<String>(
              value: _visibility,
              options: const [(id: 'all', label: 'All', count: null), (id: 'public', label: 'Public', count: null), (id: 'private', label: 'Private', count: null)],
              onChanged: (v) {
                setState(() => _visibility = v);
                _load(reset: true);
              },
            ),
            const Spacer(),
            StatusPill('${selected.length} of $labMaxItems selected', tone: selected.isEmpty ? MarketTone.neutral : MarketTone.info),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            TextButton.icon(
              onPressed: unselected.isEmpty || atLimit ? null : () => widget.onSelectMany(unselected),
              icon: const Icon(Icons.select_all_rounded, size: 18),
              label: const Text('Select all loaded'),
            ),
            TextButton.icon(
              onPressed: selected.isEmpty ? null : widget.onClear,
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Clear'),
            ),
          ]),
        ]),
      ),
      Container(height: 1, color: p.line),
      if (atLimit)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: StudioStrip('You can edit up to $labMaxItems images at once. Clear some to choose others.', tone: MarketTone.warn),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: StudioStrip(_error!, tone: MarketTone.error, action: TextButton(onPressed: () => _load(reset: true), child: const Text('Retry'))),
        ),
      Expanded(
        child: RefreshIndicator(
          color: p.brand,
          onRefresh: () => _load(reset: true),
          child: !_loading && _items.isEmpty && _error == null
              ? ListView(children: const [
                  MarketEmpty(icon: Icons.image_search_outlined, title: 'No images found', message: 'Try another search, category or visibility.'),
                ])
              : CustomScrollView(controller: _scroll, physics: const AlwaysScrollableScrollPhysics(), slivers: [
                  if (_total != null)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      sliver: SliverToBoxAdapter(child: StudioHint(_total == 1 ? '1 image' : '$_total images')),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    sliver: SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisSpacing: 8, crossAxisSpacing: 8),
                      itemCount: _items.length + (_loading ? columns : 0),
                      itemBuilder: (_, i) {
                        if (i >= _items.length) return const SkeletonBox(height: double.infinity, radius: 10);
                        final item = _items[i];
                        final isSelected = selected.containsKey(item.id);
                        return _SelectTile(
                          item: item,
                          selected: isSelected,
                          disabled: !isSelected && atLimit,
                          onTap: () => widget.onToggle(item),
                        );
                      },
                    ),
                  ),
                ]),
        ),
      ),
    ]);
  }

  Widget _chip(MarketPalette p, String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? p.brandSoft : p.card,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: selected ? p.brand : p.line),
            ),
            child: Text(label,
                style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? p.brand : p.text)),
          ),
        ),
      );

  void _pickCategory(int? id) {
    if (_categoryId == id) return;
    setState(() => _categoryId = id);
    _load(reset: true);
  }
}

class _SelectTile extends StatelessWidget {
  final MediaLibraryItem item;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;
  const _SelectTile({required this.item, required this.selected, required this.disabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? p.brand : p.line, width: selected ? 2.5 : 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(fit: StackFit.expand, children: [
              _thumb(p, mediaView(item, 'tiny')),
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? p.brand : Colors.black.withValues(alpha: 0.3),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: selected ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── 2 · Template ──

class TemplateStep extends StatelessWidget {
  final TemplatesStore store;
  final int? chosenId;
  /// Settings set up once without saving a template ("Custom settings").
  final EditOps? customOps;
  final ValueChanged<int?> onChoose;
  final VoidCallback onChooseCustom;
  final VoidCallback onNew;
  final VoidCallback onCustom;
  final ValueChanged<MediaEditTemplate> onEdit;
  /// Up to 4 selected images to preview the chosen settings on.
  final List<MediaLibraryItem> previewItems;

  const TemplateStep({
    super.key,
    required this.store,
    required this.chosenId,
    required this.customOps,
    required this.onChoose,
    required this.onChooseCustom,
    required this.onNew,
    required this.onCustom,
    required this.onEdit,
    required this.previewItems,
  });

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final list = store.templates;
    final chosen = list.where((t) => t.id == chosenId).firstOrNull;
    final usingCustom = chosenId == null && customOps != null;
    final previewOps = chosen?.ops ?? (usingCustom ? customOps : null);

    return RefreshIndicator(
      color: p.brand,
      onRefresh: store.reload,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        Row(children: [
          Expanded(child: Text('Templates', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text))),
          IconButton(
            tooltip: 'Reload templates',
            onPressed: store.loading ? null : store.reload,
            icon: Icon(Icons.refresh_rounded, color: p.label),
          ),
        ]),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: onNew, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New template')),
          OutlinedButton.icon(
            onPressed: onCustom,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: Text(customOps != null ? 'Edit custom settings' : 'Custom settings'),
          ),
        ]),
        const SizedBox(height: 12),
        if (store.error != null) ...[
          StudioStrip(store.error!, tone: MarketTone.error, action: TextButton(onPressed: store.reload, child: const Text('Retry'))),
          const SizedBox(height: 10),
        ],
        if (customOps != null) ...[
          MarketCard(
            onTap: onChooseCustom,
            color: usingCustom ? p.brandSoft : null,
            borderColor: usingCustom ? p.brand : null,
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(usingCustom ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 18, color: usingCustom ? p.brand : p.label),
                const SizedBox(width: 8),
                Expanded(child: Text('Custom settings', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text))),
              ]),
              const SizedBox(height: 6),
              TemplateChips(ops: customOps!),
            ]),
          ),
          const SizedBox(height: 8),
        ],
        if (store.loading && list.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        else if (list.isEmpty && store.error == null && customOps == null)
          const MarketEmpty(
            icon: Icons.bookmarks_outlined,
            title: 'No templates yet',
            message: 'Create one from your first selected image, then apply it to all of them.',
          )
        else
          for (final t in list) ...[
            TemplateCard(
              template: t,
              selected: t.id == chosenId,
              leading: t.id == chosenId ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              onTap: () => onChoose(t.id),
              editTooltip: 'Edit',
              onEdit: () => onEdit(t),
              onDelete: () async {
                final deleted = await deleteTemplateFlow(context, store, t);
                if (deleted && chosenId == t.id) onChoose(null);
              },
            ),
            const SizedBox(height: 8),
          ],
        if (previewOps != null) ...[
          const SizedBox(height: 8),
          PreviewStrip(ops: previewOps, items: previewItems),
          const SizedBox(height: 6),
          StudioHint(
              'Previews use the first ${previewItems.length} selected image${previewItems.length == 1 ? '' : 's'}. Templates never crop.'),
        ] else if (list.isNotEmpty) ...[
          const SizedBox(height: 8),
          const StudioHint('Choose a template to preview it on your images.'),
        ],
      ]),
    );
  }
}

// ── Preview strip ──

class _PreviewTile {
  final String status; // loading | done | error
  final StudioPreview? image;
  final String? error;
  const _PreviewTile(this.status, {this.image, this.error});
}

/// Server-rendered previews of a template on a few sample images. Requests
/// run one at a time (background removal is heavy); results are cached per
/// template version so switching back and forth doesn't refetch.
class PreviewStrip extends StatefulWidget {
  final EditOps ops;
  final List<MediaLibraryItem> items;
  const PreviewStrip({super.key, required this.ops, required this.items});

  @override
  State<PreviewStrip> createState() => _PreviewStripState();
}

class _PreviewStripState extends State<PreviewStrip> {
  static final Map<String, _PreviewTile> _cache = {};
  final _service = MediaStudioService();
  Map<int, _PreviewTile> _tiles = {};
  bool _before = false;
  int _run = 0;

  String get _key => opsKey(widget.ops);
  String get _itemsKey => widget.items.map((i) => i.id).join(',');

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(PreviewStrip old) {
    super.didUpdateWidget(old);
    if (opsKey(old.ops) != _key || old.items.map((i) => i.id).join(',') != _itemsKey) _start();
  }

  @override
  void dispose() {
    _run++;
    super.dispose();
  }

  Future<void> _start() async {
    final run = ++_run;
    final key = _key;
    final body = templateOps(widget.ops);
    setState(() {
      _tiles = {for (final it in widget.items) it.id: _cache['$key:${it.id}'] ?? const _PreviewTile('loading')};
    });
    if (isEmptyTemplateOps(widget.ops)) return;
    for (final it in widget.items) {
      if (run != _run || !mounted) return;
      final k = '$key:${it.id}';
      if (_cache[k]?.status == 'done') continue;
      setState(() => _tiles[it.id] = const _PreviewTile('loading'));
      _PreviewTile tile;
      try {
        final res = await _service.preview(it.id, body);
        tile = _PreviewTile('done', image: res);
        _cache[k] = tile;
      } catch (e) {
        tile = _PreviewTile('error', error: describeStudioError(e, 'Preview failed'));
      }
      if (run != _run || !mounted) return;
      setState(() => _tiles[it.id] = tile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final identity = isEmptyTemplateOps(widget.ops);
    final anyError = _tiles.values.any((t) => t.status == 'error');
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 600 ? 4 : 2;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Preview on your images', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text))),
        if (anyError) TextButton(onPressed: _start, child: const Text('Retry')),
        MarketSegmented<bool>(
          value: _before,
          options: const [(id: true, label: 'Before', count: null), (id: false, label: 'After', count: null)],
          onChanged: (v) => setState(() => _before = v),
        ),
      ]),
      if (identity) ...[
        const SizedBox(height: 6),
        const StudioHint('These settings don\'t change the pixels — the previews match the originals.'),
      ],
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.85,
        children: [
          for (final it in widget.items)
            Container(
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: CheckerBackground(cell: 8, child: _tile(p, it, identity))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
                ),
              ]),
            ),
        ],
      ),
    ]);
  }

  Widget _tile(MarketPalette p, MediaLibraryItem it, bool identity) {
    final tile = _tiles[it.id];
    if (_before || identity) return _thumb(p, mediaView(it, 'small'), fit: BoxFit.contain);
    if (tile?.status == 'done' && tile?.image != null) {
      return Image.memory(tile!.image!.bytes, fit: BoxFit.contain, gaplessPlayback: true);
    }
    if (tile?.status == 'error') {
      return Container(
        color: p.errorBg,
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.error_outline_rounded, color: p.error, size: 20),
          const SizedBox(height: 4),
          Text(tile!.error ?? 'Preview failed',
              textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.error)),
        ]),
      );
    }
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: p.brand)),
      const SizedBox(height: 8),
      Text('Rendering preview…', style: TextStyle(fontSize: 11, color: p.label)),
    ]);
  }
}

// ── 3 · Apply ──

class ApplySetup extends StatelessWidget {
  final int count;
  final String? settingsName;
  final EditOps? ops;
  final String mode;
  final ValueChanged<String> onMode;
  final bool starting;
  final String? error;
  final VoidCallback onDismissError;
  const ApplySetup({
    super.key,
    required this.count,
    required this.settingsName,
    required this.ops,
    required this.mode,
    required this.onMode,
    required this.starting,
    required this.error,
    required this.onDismissError,
  });

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      MarketCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Template', style: TextStyle(fontSize: 12, color: p.label)),
          const SizedBox(height: 2),
          Text(settingsName ?? 'No template chosen', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
          if (ops != null) ...[const SizedBox(height: 8), TemplateChips(ops: ops!)],
          const SizedBox(height: 8),
          Text('$count image${count == 1 ? '' : 's'} selected', style: TextStyle(fontSize: 12.5, color: p.label)),
        ]),
      ),
      const SizedBox(height: 12),
      MarketCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('How should the results be saved?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
          const SizedBox(height: 10),
          IgnorePointer(
            ignoring: starting,
            child: MarketSegmented<String>(
              value: mode,
              options: const [(id: 'copy', label: 'Save as new copies', count: null), (id: 'replace', label: 'Replace originals', count: null)],
              onChanged: onMode,
            ),
          ),
          const SizedBox(height: 10),
          if (mode == 'copy')
            const StudioHint('Each image gets an edited copy next to it. The originals stay as they are.')
          else
            const StudioStrip(
              'The original files are overwritten and can\'t be restored. Everywhere these images are used will show the edited version.',
              tone: MarketTone.error,
            ),
        ]),
      ),
      if (error != null) ...[
        const SizedBox(height: 12),
        StudioStrip(error!,
            tone: MarketTone.error,
            action: IconButton(visualDensity: VisualDensity.compact, onPressed: onDismissError, icon: Icon(Icons.close_rounded, size: 18, color: p.label))),
      ],
      if (starting) ...[
        const SizedBox(height: 14),
        Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.brand)),
          const SizedBox(width: 10),
          Text('Starting…', style: TextStyle(color: p.text)),
        ]),
      ],
    ]);
  }
}

const _statusMeta = <String, ({String text, MarketTone tone, IconData icon})>{
  'pending': (text: 'Waiting', tone: MarketTone.neutral, icon: Icons.schedule_rounded),
  'running': (text: 'Processing', tone: MarketTone.info, icon: Icons.sync_rounded),
  'done': (text: 'Done', tone: MarketTone.ok, icon: Icons.check_circle_outline_rounded),
  'error': (text: 'Failed', tone: MarketTone.error, icon: Icons.error_outline_rounded),
  'skipped': (text: 'Skipped', tone: MarketTone.warn, icon: Icons.warning_amber_rounded),
};

class ProgressView extends StatelessWidget {
  final BatchJob? job;
  final StoredJob stored;
  final String? error;
  final bool missing;
  const ProgressView({super.key, required this.job, required this.stored, required this.error, required this.missing});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    if (missing) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: StudioStrip(
          'This job is no longer available on the server. It may have finished a while ago — check the media library for the results.',
          tone: MarketTone.warn,
        ),
      );
    }
    final j = job;
    if (j == null) {
      return Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: p.brand)),
          const SizedBox(width: 12),
          Text('Loading progress…', style: TextStyle(color: p.text)),
        ]),
      );
    }

    final byId = {for (final i in stored.items) i.id: i};
    final total = j.total > 0 ? j.total : (j.results.isNotEmpty ? j.results.length : stored.items.length);
    final finished = j.done + j.failed;
    final fraction = total > 0 ? (finished / total).clamp(0.0, 1.0) : 0.0;
    final active = isJobActive(j.status);
    final skipped = j.results.where((r) => r.status == 'skipped').length;
    final headline = switch (j.status) {
      'queued' => 'Waiting to start…',
      'running' => 'Editing images — $finished of $total',
      'cancelled' => 'Cancelled',
      _ => j.failed > 0 ? 'Finished with errors' : 'All done',
    };
    final barColor = j.failed > 0 ? p.warn : (j.status == 'done' ? p.ok : p.brand);

    return Column(children: [
      Container(
        color: p.card,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (active) ...[
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.brand)),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(headline, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text))),
          ]),
          const SizedBox(height: 4),
          Text(
            '${stored.templateName != null ? '"${stored.templateName}" · ' : ''}${j.mode == 'replace' ? 'Replacing originals' : 'Saving new copies'}',
            style: TextStyle(fontSize: 12, color: p.label),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: fraction),
                  duration: const Duration(milliseconds: 300),
                  builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 8, backgroundColor: p.surface, color: barColor),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('$finished of $total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            StatusPill('${j.done} done', tone: MarketTone.ok, icon: Icons.check_circle_outline_rounded),
            StatusPill('${j.failed} failed', tone: j.failed > 0 ? MarketTone.error : MarketTone.neutral, icon: Icons.error_outline_rounded),
            if (skipped > 0) StatusPill('$skipped skipped', tone: MarketTone.warn, icon: Icons.warning_amber_rounded),
          ]),
          if (error != null && active) ...[
            const SizedBox(height: 10),
            StudioStrip('$error — still trying.', tone: MarketTone.warn),
          ],
        ]),
      ),
      Container(height: 1, color: p.line),
      Expanded(
        child: ListView.separated(
          itemCount: j.results.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: p.line),
          itemBuilder: (_, i) {
            final r = j.results[i];
            final meta = byId[r.itemId];
            final name = r.name.isNotEmpty ? r.name : (meta?.name ?? 'Image ${r.itemId}');
            final s = _statusMeta[r.status] ?? _statusMeta['pending']!;
            final result = r.status == 'done' && r.item != null ? LabItem.of(r.item!) : null;
            // Replaced originals: the item's URL now serves the edited file.
            final thumb = j.mode == 'replace' && result != null ? result.thumb : (meta?.thumb ?? '');
            return Container(
              color: p.card,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 42, height: 42, child: _thumb(p, thumb))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.text)),
                    if (r.error != null)
                      Text(r.error!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.error)),
                  ]),
                ),
                if (j.mode == 'copy' && result != null) ...[
                  Icon(Icons.arrow_forward_rounded, size: 15, color: p.label),
                  const SizedBox(width: 4),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: p.brand)),
                    clipBehavior: Clip.antiAlias,
                    child: _thumb(p, result.thumb),
                  ),
                  const SizedBox(width: 8),
                ],
                StatusPill(s.text, tone: s.tone, icon: s.icon),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}
