import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/data/media_library_service.dart';
import '../../../../shared/data/media_studio_service.dart';
import '../../../../shared/models/media_library_item.dart';
import '../../../sell/market/presentation/widgets/market_ui.dart';
import 'lab/media_lab_page.dart';
import 'studio/image_studio_page.dart';

/// Settings → Media: the workplace's media library (same `media_items`
/// data as erp/desktop's Media page) — browse by type and folder, search,
/// upload from the gallery or camera, and open a file to copy its link,
/// edit it in the Image studio or delete it. The Lab (app bar) edits many
/// images at once with a template.
class MediaLibraryPage extends StatefulWidget {
  const MediaLibraryPage({super.key});

  @override
  State<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

enum _Kind { all, image, document, video }

class _MediaLibraryPageState extends State<MediaLibraryPage> {
  final _service = MediaLibraryService(ApiClient());
  final _picker = ImagePicker();
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;

  List<MediaLibraryItem> _items = [];
  List<MediaCategory> _categories = [];
  int _total = 0;
  int? _categoryId;
  _Kind _kind = _Kind.all;
  bool _loading = true;
  bool _loadingMore = false;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _bootstrap();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      _categories = await _service.loadCategories();
    } catch (_) {
      _categories = [];
    }
    await _load(reset: true);
  }

  String? get _kindFilter => switch (_kind) {
        _Kind.all => null,
        _Kind.image => 'image',
        _Kind.document => 'document',
        _Kind.video => 'video',
      };

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      if (_loadingMore || _items.length >= _total) return;
      setState(() => _loadingMore = true);
    }
    try {
      final page = await _service.loadItems(
        search: _search.text,
        categoryId: _categoryId,
        kind: _kindFilter,
        newestFirst: true,
        skip: reset ? 0 : _items.length,
        withCount: reset,
      );
      if (!mounted) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        if (reset) _total = page.total;
      });
    } catch (_) {
      if (mounted && reset) setState(() => _error = 'Could not load media.');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _load();
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(reset: true));
  }

  Future<void> _upload(ImageSource source) async {
    if (_uploading) return;
    final List<XFile> picked;
    try {
      if (source == ImageSource.camera) {
        final shot = await _picker.pickImage(source: ImageSource.camera, imageQuality: 88, maxWidth: 2400);
        picked = shot == null ? [] : [shot];
      } else {
        picked = await _picker.pickMultiImage(imageQuality: 88, maxWidth: 2400);
      }
    } catch (_) {
      if (mounted) marketToast(context, 'Could not open the camera or photo library', error: true);
      return;
    }
    if (picked.isEmpty) return;

    setState(() => _uploading = true);
    var done = 0;
    try {
      // Uploads land in the folder being viewed, or "General" from "All".
      final categoryId = _categoryId ?? (await _service.ensureCategoryByName('General')).id;
      for (final file in picked) {
        final item = await _service.uploadFile(bytes: await file.readAsBytes(), filename: file.name, categoryId: categoryId);
        if (item != null) done++;
      }
      if (!mounted) return;
      marketToast(context, done == 1 ? '1 file uploaded' : '$done files uploaded');
      if (_categoryId == null && !_categories.any((c) => c.id == categoryId)) {
        _categories = await _service.loadCategories();
      }
      await _load(reset: true);
    } catch (_) {
      if (mounted) marketToast(context, done > 0 ? 'Uploaded $done, the rest failed' : 'Upload failed', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _openUploadSheet() {
    final p = MarketPalette.of(context);
    showMarketSheet<void>(
      context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Upload media', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 4),
            Text(
              _categoryId == null
                  ? 'Files go to the General folder'
                  : 'Files go to ${_categories.where((c) => c.id == _categoryId).map((c) => c.name).firstOrNull ?? 'this folder'}',
              style: TextStyle(fontSize: 12.5, color: p.label),
            ),
            const SizedBox(height: 14),
            _SheetAction(
              icon: Icons.photo_library_outlined,
              label: 'Choose from gallery',
              onTap: () {
                Navigator.pop(ctx);
                _upload(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
            _SheetAction(
              icon: Icons.photo_camera_outlined,
              label: 'Take a photo',
              onTap: () {
                Navigator.pop(ctx);
                _upload(ImageSource.camera);
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _openItem(MediaLibraryItem item) async {
    final result = await showMarketSheet<Object>(
      context,
      builder: (ctx) => _MediaDetail(
        item: item,
        onDelete: () => _delete(ctx, item),
        onEdit: item.isImage ? () => Navigator.pop(ctx, 'edit') : null,
      ),
    );
    if (!mounted) return;
    if (result == true) {
      setState(() {
        _items = _items.where((i) => i.id != item.id).toList();
        _total = (_total - 1).clamp(0, 1 << 30);
      });
    } else if (result == 'edit') {
      await _openStudio(item);
    }
  }

  Future<void> _openStudio(MediaLibraryItem item) async {
    final result = await openImageStudio(context, item);
    if (result != null && mounted) await _load(reset: true);
  }

  Future<void> _openLab() async {
    final changed = await Navigator.of(context).push<bool>(marketRoute(const MediaLabPage()));
    if (changed == true && mounted) await _load(reset: true);
  }

  Future<void> _delete(BuildContext sheetContext, MediaLibraryItem item) async {
    final ok = await confirmMarket(sheetContext,
        title: 'Delete file', message: '"${item.name}" will be removed from the media library. Anything using it will lose the image.');
    if (!ok) return;
    try {
      await _service.deleteItem(item.id);
      if (sheetContext.mounted) Navigator.pop(sheetContext, true);
      if (mounted) marketToast(context, 'File deleted');
    } catch (_) {
      if (sheetContext.mounted) marketToast(sheetContext, 'Could not delete the file', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 6 : (width >= 600 ? 4 : 3);

    return MarketScaffold(
      title: 'Media',
      subtitle: _loading ? 'Loading…' : (_total == 1 ? '1 file' : '$_total files'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton.icon(
            onPressed: _openLab,
            icon: const Icon(Icons.science_outlined, size: 19),
            label: const Text('Lab'),
          ),
        ),
      ],
      fab: FloatingActionButton.extended(
        onPressed: _uploading ? null : _openUploadSheet,
        backgroundColor: p.brand,
        foregroundColor: Colors.white,
        icon: _uploading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.cloud_upload_outlined),
        label: Text(_uploading ? 'Uploading…' : 'Upload'),
      ),
      body: RefreshIndicator(
        color: p.brand,
        onRefresh: () => _load(reset: true),
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search files',
                      prefixIcon: Icon(Icons.search_rounded, color: p.label),
                      isDense: true,
                      filled: true,
                      fillColor: p.card,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  MarketSegmented<_Kind>(
                    value: _kind,
                    options: const [
                      (id: _Kind.all, label: 'All', count: null),
                      (id: _Kind.image, label: 'Images', count: null),
                      (id: _Kind.document, label: 'Documents', count: null),
                      (id: _Kind.video, label: 'Videos', count: null),
                    ],
                    onChanged: (k) {
                      setState(() => _kind = k);
                      _load(reset: true);
                    },
                  ),
                  if (_categories.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _FolderChip(label: 'All folders', selected: _categoryId == null, onTap: () => _pickCategory(null)),
                          for (final c in _categories)
                            _FolderChip(label: c.name, selected: _categoryId == c.id, onTap: () => _pickCategory(c.id)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ]),
              ),
            ),
            if (_loading)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid.count(
                  crossAxisCount: columns,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: List.generate(columns * 4, (_) => const SkeletonBox(height: double.infinity)),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: MarketEmpty(icon: Icons.cloud_off_outlined, title: _error!, actionLabel: 'Try again', onAction: () => _load(reset: true)),
              )
            else if (_items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: MarketEmpty(
                  icon: Icons.perm_media_outlined,
                  title: _search.text.isEmpty ? 'No media yet' : 'No files match',
                  message: _search.text.isEmpty ? 'Photos you upload here can be used for products, listings and banners.' : 'Try a different name.',
                  actionLabel: _search.text.isEmpty ? 'Upload' : null,
                  onAction: _search.text.isEmpty ? _openUploadSheet : null,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: _items.length + (_loadingMore ? columns : 0),
                  itemBuilder: (_, i) => i >= _items.length
                      ? const SkeletonBox(height: double.infinity)
                      : _MediaTile(item: _items[i], onTap: () => _openItem(_items[i])),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _pickCategory(int? id) {
    if (_categoryId == id) return;
    setState(() => _categoryId = id);
    _load(reset: true);
  }
}

/// `?view=` variant of an image (cache-busted after an in-place replace).
String _thumb(MediaLibraryItem item, String view) => mediaView(item, view);

String _formatSize(int bytes) {
  if (bytes <= 0) return '—';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

IconData _kindIcon(String kind) => switch (kind) {
      'image' => Icons.image_outlined,
      'video' => Icons.movie_outlined,
      'document' => Icons.description_outlined,
      _ => Icons.insert_drive_file_outlined,
    };

class _MediaTile extends StatelessWidget {
  final MediaLibraryItem item;
  final VoidCallback onTap;
  const _MediaTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final fallback = Container(
      color: p.surface,
      padding: const EdgeInsets.all(8),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(_kindIcon(item.kind), color: p.label, size: 26),
        const SizedBox(height: 6),
        Text(
          item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10.5, height: 1.25, color: p.label),
        ),
      ]),
    );
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(fit: StackFit.expand, children: [
          if (item.isImage)
            CachedNetworkImage(
              imageUrl: _thumb(item, 'small'),
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (_, _) => Container(color: p.surface),
              errorWidget: (_, _, _) => fallback,
            )
          else
            fallback,
          if (item.visibility == 'public')
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                child: const Icon(Icons.public, size: 11, color: Colors.white),
              ),
            ),
        ]),
      ),
    );
  }
}

class _FolderChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FolderChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? p.brandSoft : p.card,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: selected ? p.brand : p.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(selected ? Icons.folder_rounded : Icons.folder_outlined, size: 15, color: selected ? p.brand : p.label),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? p.brand : p.text)),
          ]),
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SheetAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 19, color: p.brand),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text))),
        Icon(Icons.chevron_right_rounded, color: p.label),
      ]),
    );
  }
}

class _MediaDetail extends StatelessWidget {
  final MediaLibraryItem item;
  final VoidCallback onDelete;
  /// Opens the Image studio (images only).
  final VoidCallback? onEdit;
  const _MediaDetail({required this.item, required this.onDelete, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: p.surface,
              height: 240,
              width: double.infinity,
              child: item.isImage
                  ? CachedNetworkImage(
                      imageUrl: _thumb(item, 'large'),
                      fit: BoxFit.contain,
                      placeholder: (_, _) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      errorWidget: (_, _, _) => Icon(Icons.broken_image_outlined, color: p.label, size: 40),
                    )
                  : Icon(_kindIcon(item.kind), color: p.label, size: 48),
            ),
          ),
          const SizedBox(height: 14),
          Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            StatusPill(item.visibility == 'public' ? 'Public' : 'Private',
                tone: item.visibility == 'public' ? MarketTone.info : MarketTone.neutral,
                icon: item.visibility == 'public' ? Icons.public : Icons.lock_outline),
            StatusPill(_formatSize(item.size), tone: MarketTone.neutral),
            if (item.extension != null && item.extension!.isNotEmpty) StatusPill(item.extension!.toLowerCase(), tone: MarketTone.neutral),
            if (item.categoryName != null) StatusPill(item.categoryName!, tone: MarketTone.neutral, icon: Icons.folder_outlined),
          ]),
          const SizedBox(height: 16),
          if (onEdit != null) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                label: const Text('Edit in image studio'),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: item.fileUrl));
                  if (context.mounted) marketToast(context, 'Link copied');
                },
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Copy link'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: p.error, side: BorderSide(color: p.error)),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
