import 'dart:async';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/network/http_client.dart';
import '../../core/theme/app_theme.dart';
import '../data/media_library_service.dart';
import '../models/media_library_item.dart';

/// Opens the reusable media library as a modal bottom sheet — a Flutter port
/// of erp/desktop's `MediaLibraryDialog.tsx` used as a standalone picker
/// (Browse existing files / Upload new ones), not the full Media Library
/// module page. Resolves with the chosen items, or null if cancelled.
Future<List<MediaLibraryItem>?> showMediaLibraryDialog(
  BuildContext context, {
  String title = 'Media Library',
  bool multiSelect = false,
  String? defaultCategoryName,
}) {
  return showModalBottomSheet<List<MediaLibraryItem>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _MediaLibraryDialog(title: title, multiSelect: multiSelect, defaultCategoryName: defaultCategoryName),
  );
}

class _PendingUpload {
  final Uint8List bytes;
  final String name;
  const _PendingUpload({required this.bytes, required this.name});
}

class _MediaLibraryDialog extends StatefulWidget {
  final String title;
  final bool multiSelect;
  final String? defaultCategoryName;

  const _MediaLibraryDialog({required this.title, required this.multiSelect, this.defaultCategoryName});

  @override
  State<_MediaLibraryDialog> createState() => _MediaLibraryDialogState();
}

class _MediaLibraryDialogState extends State<_MediaLibraryDialog> with SingleTickerProviderStateMixin {
  final _service = MediaLibraryService(ApiClient());
  final _picker = ImagePicker();
  late final TabController _tabController;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  List<MediaCategory> _categories = [];
  int? _filterCategoryId;
  String _filterVisibility = 'all';
  List<MediaLibraryItem> _items = [];
  int _total = 0;
  bool _loadingItems = true;
  bool _loadingMore = false;

  final List<MediaLibraryItem> _selected = [];

  int? _uploadCategoryId;
  String _uploadVisibility = 'private';
  final List<_PendingUpload> _pendingUploads = [];
  bool _uploading = false;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)..addListener(() => mounted ? setState(() {}) : null);
    _scrollController.addListener(_onScroll);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    List<MediaCategory> categories = [];
    try {
      categories = await _service.loadCategories();
    } catch (_) {
      // continue with an empty category list — browse/search still works
    }
    MediaCategory? preferred;
    if (widget.defaultCategoryName != null) {
      try {
        preferred = categories.firstWhere((c) => c.name.toLowerCase() == widget.defaultCategoryName!.toLowerCase());
      } catch (_) {
        try {
          preferred = await _service.createCategory(widget.defaultCategoryName!);
          categories = [...categories, preferred];
        } catch (_) {
          // leave preferred unset — user can still pick a category manually
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _uploadCategoryId = preferred?.id ?? (categories.isNotEmpty ? categories.first.id : null);
    });
    await _loadItems(reset: true);
  }

  Future<void> _loadItems({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loadingItems = true;
        _items = [];
      });
    }
    try {
      final result = await _service.loadItems(
        search: _searchController.text,
        categoryId: _filterCategoryId,
        visibility: _filterVisibility,
        skip: reset ? 0 : _items.length,
        withCount: reset,
      );
      if (!mounted) return;
      setState(() {
        _items = reset ? result.items : [..._items, ...result.items];
        if (reset) _total = result.total;
      });
    } catch (_) {
      // leave whatever's already loaded on failure
    } finally {
      if (mounted) {
        setState(() {
          _loadingItems = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _onScroll() {
    if (_loadingMore || _loadingItems) return;
    if (_items.length >= _total) return;
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 200) {
      setState(() => _loadingMore = true);
      _loadItems();
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _loadItems(reset: true));
  }

  void _toggleSelect(MediaLibraryItem item) {
    setState(() {
      final idx = _selected.indexWhere((i) => i.id == item.id);
      if (idx >= 0) {
        _selected.removeAt(idx);
      } else {
        if (!widget.multiSelect) _selected.clear();
        _selected.add(item);
      }
    });
  }

  Future<void> _pickFiles() async {
    final picked = await _picker.pickMultiImage(imageQuality: 85);
    if (picked.isEmpty) return;
    final pending = <_PendingUpload>[];
    for (final file in picked) {
      pending.add(_PendingUpload(bytes: await file.readAsBytes(), name: file.name));
    }
    if (!mounted) return;
    setState(() => _pendingUploads.addAll(pending));
  }

  Future<void> _uploadAndUse() async {
    if (_pendingUploads.isEmpty || _uploadCategoryId == null || _uploading) return;
    setState(() {
      _uploading = true;
      _uploadError = null;
    });
    final uploaded = <MediaLibraryItem>[];
    try {
      for (final pending in _pendingUploads) {
        final item = await _service.uploadFile(
          bytes: pending.bytes,
          filename: pending.name,
          categoryId: _uploadCategoryId!,
          visibility: _uploadVisibility,
        );
        if (item != null) uploaded.add(item);
      }
      if (!mounted) return;
      Navigator.of(context).pop(uploaded);
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadError = 'Could not upload files.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _createCategoryPrompt() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Category'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Category name')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final created = await _service.createCategory(name);
      if (!mounted) return;
      setState(() {
        _categories = [..._categories, created];
        _uploadCategoryId = created.id;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create category.')));
    }
  }

  Future<void> _confirmDelete(MediaLibraryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text('Remove "${item.name}" from the media library?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteItem(item.id);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((i) => i.id == item.id);
        _selected.removeWhere((i) => i.id == item.id);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete file.')));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.9,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: AppColors.slate400.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          TabBar(controller: _tabController, tabs: const [Tab(text: 'Browse'), Tab(text: 'Upload')]),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildBrowseTab(), _buildUploadTab()],
            ),
          ),
          SafeArea(top: false, child: _buildFooter()),
        ],
      ),
    );
  }

  Widget _buildBrowseTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search files', isDense: true),
            onChanged: _onSearchChanged,
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _visibilityChip('all', 'All'),
              _visibilityChip('public', 'Public'),
              _visibilityChip('private', 'Private'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _categoryChip(null, 'All categories'),
              ..._categories.map((c) => _categoryChip(c.id, c.name)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _loadingItems
              ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
              : _items.isEmpty
                  ? Center(child: Text('No files found.', style: TextStyle(color: AppColors.slate600)))
                  : GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: _items.length + (_loadingMore ? 3 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _items.length) {
                          return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand));
                        }
                        return _buildMediaTile(_items[index]);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _visibilityChip(String value, String label) {
    final selected = _filterVisibility == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _filterVisibility = value);
          _loadItems(reset: true);
        },
      ),
    );
  }

  Widget _categoryChip(int? id, String label) {
    final selected = _filterCategoryId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _filterCategoryId = id);
          _loadItems(reset: true);
        },
      ),
    );
  }

  Widget _buildMediaTile(MediaLibraryItem item) {
    final selected = _selected.any((i) => i.id == item.id);
    return GestureDetector(
      onTap: () => _toggleSelect(item),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? AppColors.brand : AppColors.slate400.withValues(alpha: 0.2), width: selected ? 2 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: item.isImage
                      ? CachedNetworkImage(
                          imageUrl: item.previewUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => const Icon(Icons.broken_image),
                        )
                      : Container(color: AppColors.slate100, child: Icon(_kindIcon(item.kind), size: 32, color: AppColors.slate600)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          if (selected)
            const Positioned(
              right: 4,
              top: 4,
              child: CircleAvatar(radius: 10, backgroundColor: AppColors.brand, child: Icon(Icons.check, size: 13, color: Colors.white)),
            ),
          Positioned(
            left: 2,
            top: 2,
            child: GestureDetector(
              onTap: () => _confirmDelete(item),
              child: const CircleAvatar(radius: 11, backgroundColor: Colors.black45, child: Icon(Icons.close, size: 13, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  IconData _kindIcon(String kind) {
    switch (kind) {
      case 'document':
        return Icons.description_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Widget _buildUploadTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(onPressed: _pickFiles, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Choose photos')),
          if (_pendingUploads.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _pendingUploads
                  .map((p) => Stack(
                        children: [
                          ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(p.bytes, width: 72, height: 72, fit: BoxFit.cover)),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: GestureDetector(
                              onTap: () => setState(() => _pendingUploads.remove(p)),
                              child: const CircleAvatar(radius: 9, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 11, color: Colors.white)),
                            ),
                          ),
                        ],
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 16),
          const Text('Category', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _uploadCategoryId,
                  items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: (value) => setState(() => _uploadCategoryId = value),
                  decoration: const InputDecoration(isDense: true),
                ),
              ),
              IconButton(icon: const Icon(Icons.add), tooltip: 'New category', onPressed: _createCategoryPrompt),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Visibility', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'private', label: Text('Private')),
              ButtonSegment(value: 'public', label: Text('Public')),
            ],
            selected: {_uploadVisibility},
            onSelectionChanged: (s) => setState(() => _uploadVisibility = s.first),
          ),
          if (_uploadError != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_uploadError!, style: const TextStyle(color: AppColors.error))),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final isUploadTab = _tabController.index == 1;
    final canConfirmBrowse = _selected.isNotEmpty;
    final canUpload = _pendingUploads.isNotEmpty && _uploadCategoryId != null && !_uploading;
    final label = isUploadTab
        ? (_uploading ? 'Uploading…' : 'Upload & Use')
        : (widget.multiSelect && _selected.length > 1 ? 'Use ${_selected.length} selected' : 'Use selected');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.slate400.withValues(alpha: 0.2)))),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isUploadTab
                  ? (_pendingUploads.isEmpty ? 'Choose photos to upload' : '${_pendingUploads.length} file(s) ready')
                  : (_selected.isEmpty ? 'Tap a file to select' : '${_selected.length} selected'),
              style: const TextStyle(color: AppColors.slate600, fontSize: 12),
            ),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: isUploadTab
                ? (canUpload ? _uploadAndUse : null)
                : (canConfirmBrowse ? () => Navigator.of(context).pop(List<MediaLibraryItem>.from(_selected)) : null),
            child: Text(label),
          ),
        ],
      ),
    );
  }
}
