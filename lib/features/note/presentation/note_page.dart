import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../data/note_service.dart';
import '../models/note_model.dart';
import 'note_editor_page.dart';
import 'note_ui.dart';

/// Notes board — modes (all / private / reminders), category filter, live
/// search, pinned notes first, a two-column card grid (or compact list).
class NotePage extends StatefulWidget {
  const NotePage({super.key});

  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
  final _service = NoteService(ApiClient());

  NoteContext? _context;
  List<NoteCategoryOption> _categories = [];
  List<NoteMemberOption> _members = [];
  List<NoteItem> _notes = [];
  int _totalCount = 0;

  NoteMode _mode = NoteMode.notes;
  String? _categoryId;
  final _searchController = TextEditingController();
  String _search = '';
  Timer? _debounce;
  bool _grid = true;

  bool _loadingBootstrap = true;
  bool _loadingNotes = true;
  String? _error;
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final bootstrap = await _service.loadBootstrap();
      if (!mounted) return;
      setState(() {
        _context = bootstrap.context;
        _categories = bootstrap.categories;
        _members = bootstrap.members;
        _loadingBootstrap = false;
      });
      if (bootstrap.context != null) {
        await _loadNotes();
      } else {
        setState(() {
          _loadingNotes = false;
          _error = 'Could not resolve your workspace.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load notes.';
        _loadingBootstrap = false;
        _loadingNotes = false;
      });
    }
  }

  Future<void> _loadNotes() async {
    final context = _context;
    if (context == null) return;
    final seq = ++_loadSeq;
    setState(() {
      _loadingNotes = true;
      _error = null;
    });
    try {
      final result = await _service.loadNotes(context, mode: _mode, categoryId: _categoryId, search: _search);
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _notes = result.notes;
        _totalCount = result.totalCount;
      });
    } catch (_) {
      if (!mounted || seq != _loadSeq) return;
      setState(() => _error = 'Could not load notes.');
    } finally {
      if (mounted && seq == _loadSeq) setState(() => _loadingNotes = false);
    }
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (_search == value.trim()) return;
      _search = value.trim();
      _loadNotes();
    });
  }

  Future<void> _reloadCategories() async {
    final bootstrap = await _service.loadBootstrap();
    if (!mounted) return;
    setState(() => _categories = bootstrap.categories);
  }

  Future<String?> _askName({required String title, String initial = '', String action = 'Create'}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Category name'),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()), child: Text(action)),
        ],
      ),
    );
  }

  Future<void> _createCategory() async {
    final name = await _askName(title: 'New category');
    if (name == null || name.isEmpty || _context == null) return;
    try {
      await _service.createCategory(name, _categories.length, _context!.memberId);
      await _reloadCategories();
      if (mounted) marketToast(context, 'Category "$name" created');
    } catch (_) {
      if (mounted) marketToast(context, 'Could not create category.', error: true);
    }
  }

  // Long-press a category: rename or delete it.
  Future<void> _manageCategory(NoteCategoryOption category) async {
    final p = MarketPalette.of(context);
    final action = await showMarketSheet<String>(
      context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2))),
          ListTile(
            title: Text(category.name, style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
            subtitle: Text('Category', style: TextStyle(color: p.label)),
          ),
          Divider(height: 1, color: p.line),
          ListTile(leading: Icon(Icons.edit_outlined, color: p.text), title: const Text('Rename'), onTap: () => Navigator.pop(ctx, 'rename')),
          ListTile(
            leading: Icon(Icons.delete_outline, color: p.error),
            title: Text('Delete', style: TextStyle(color: p.error)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'rename') {
        final name = await _askName(title: 'Rename category', initial: category.name, action: 'Save');
        if (name == null || name.isEmpty || name == category.name) return;
        await _service.renameCategory(category.id, name);
      } else {
        final ok = await confirmMarket(
          context,
          title: 'Delete category',
          message: 'Delete "${category.name}"? Notes in it stay, just without a category.',
        );
        if (!ok) return;
        await _service.deleteCategory(category.id);
        if (_categoryId == category.id) _categoryId = null;
      }
      await _reloadCategories();
      _loadNotes();
    } catch (_) {
      if (mounted) marketToast(context, 'Could not update category.', error: true);
    }
  }

  Future<void> _openEditor({NoteItem? note}) async {
    if (_context == null) return;
    final changed = await Navigator.of(context).push<bool>(
      marketRoute(NoteEditorPage(context: _context!, categories: _categories, members: _members, existing: note)),
    );
    if (changed == true) _loadNotes();
  }

  Future<void> _togglePin(NoteItem note) async {
    if (_context == null) return;
    try {
      await _service.togglePin(note.id, _context!.memberId, !note.pinned);
      if (mounted) marketToast(context, note.pinned ? 'Unpinned' : 'Pinned to top');
      _loadNotes();
    } catch (_) {
      if (mounted) marketToast(context, 'Could not update note.', error: true);
    }
  }

  Future<void> _deleteNote(NoteItem note) async {
    final ok = await confirmMarket(context, title: 'Delete note', message: '"${note.title}" will be permanently deleted. This can\'t be undone.');
    if (!ok) return;
    try {
      await _service.deleteNote(note.id);
      if (mounted) marketToast(context, 'Note deleted');
      _loadNotes();
    } catch (_) {
      if (mounted) marketToast(context, 'Could not delete note.', error: true);
    }
  }

  Future<void> _noteActions(NoteItem note) async {
    final p = MarketPalette.of(context);
    final action = await showMarketSheet<String>(
      context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2))),
          ListTile(
            title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
            subtitle: Text(note.updatedAt, style: TextStyle(color: p.label)),
          ),
          Divider(height: 1, color: p.line),
          ListTile(leading: Icon(Icons.edit_outlined, color: p.text), title: const Text('Open'), onTap: () => Navigator.pop(ctx, 'open')),
          ListTile(
            leading: Icon(note.pinned ? Icons.push_pin_outlined : Icons.push_pin, color: p.text),
            title: Text(note.pinned ? 'Unpin' : 'Pin to top'),
            onTap: () => Navigator.pop(ctx, 'pin'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: p.error),
            title: Text('Delete', style: TextStyle(color: p.error)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (action == 'open') _openEditor(note: note);
    if (action == 'pin') _togglePin(note);
    if (action == 'delete') _deleteNote(note);
  }

  NoteCategoryOption? _categoryOf(NoteItem note) {
    for (final c in _categories) {
      if (c.id == note.categoryId?.toString()) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketScaffold(
      title: 'Notes',
      subtitle: _loadingNotes && _notes.isEmpty ? 'Loading…' : '$_totalCount note${_totalCount == 1 ? '' : 's'}',
      actions: [
        IconButton(
          tooltip: _grid ? 'List view' : 'Grid view',
          icon: Icon(_grid ? Icons.view_agenda_outlined : Icons.grid_view_outlined),
          onPressed: () => setState(() => _grid = !_grid),
        ),
      ],
      fab: _context == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              backgroundColor: p.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit_note),
              label: const Text('New note'),
            ),
      body: _loadingBootstrap
          ? const SkeletonList(count: 5, itemHeight: 110)
          : RefreshIndicator(
              onRefresh: _loadNotes,
              child: CustomScrollView(slivers: [
                SliverToBoxAdapter(child: _filters(p)),
                ..._content(p),
              ]),
            ),
    );
  }

  Widget _filters(MarketPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search notes',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            fillColor: p.card,
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  ),
          ),
        ),
        const SizedBox(height: 10),
        MarketSegmented<NoteMode>(
          value: _mode,
          onChanged: (m) {
            setState(() => _mode = m);
            _loadNotes();
          },
          options: const [
            (id: NoteMode.notes, label: 'All notes', count: null),
            (id: NoteMode.private, label: 'Private', count: null),
            (id: NoteMode.reminders, label: 'Reminders', count: null),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              NoteTag('All', color: p.neutral, selected: _categoryId == null, onTap: () {
                setState(() => _categoryId = null);
                _loadNotes();
              }),
              for (final c in _categories) ...[
                const SizedBox(width: 8),
                NoteTag(
                  c.name,
                  color: noteCategoryColor(c.color, c.name, p),
                  selected: _categoryId == c.id,
                  onTap: () {
                    setState(() => _categoryId = c.id);
                    _loadNotes();
                  },
                  onLongPress: () => _manageCategory(c),
                ),
              ],
              const SizedBox(width: 8),
              ActionChip(
                avatar: Icon(Icons.add, size: 16, color: p.brand),
                label: Text('Category', style: TextStyle(color: p.brand, fontSize: 12.5)),
                backgroundColor: p.card,
                side: BorderSide(color: p.line),
                shape: const StadiumBorder(),
                onPressed: _createCategory,
              ),
            ],
          ),
        ),
      ]),
    );
  }

  List<Widget> _content(MarketPalette p) {
    if (_loadingNotes && _notes.isEmpty) {
      return const [SliverFillRemaining(hasScrollBody: false, child: SkeletonList(count: 4, itemHeight: 110))];
    }
    if (_error != null) {
      return [SliverFillRemaining(hasScrollBody: false, child: MarketEmpty(icon: Icons.cloud_off_outlined, title: _error!, actionLabel: 'Try again', onAction: _init))];
    }
    if (_notes.isEmpty) {
      final filtered = _search.isNotEmpty || _categoryId != null || _mode != NoteMode.notes;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: MarketEmpty(
            icon: _mode == NoteMode.reminders ? Icons.alarm_outlined : Icons.sticky_note_2_outlined,
            title: filtered ? 'Nothing here' : 'No notes yet',
            message: filtered ? 'Try another search, category or view.' : 'Capture ideas, checklists and reminders. They sync with the desktop app.',
            actionLabel: filtered ? null : 'New note',
            onAction: filtered ? null : () => _openEditor(),
          ),
        ),
      ];
    }

    final pinned = _notes.where((n) => n.pinned).toList();
    final others = _notes.where((n) => !n.pinned).toList();
    return [
      if (pinned.isNotEmpty) ...[
        SliverToBoxAdapter(child: _groupHeader(p, Icons.push_pin, 'Pinned')),
        _section(pinned, 0),
      ],
      if (others.isNotEmpty) ...[
        if (pinned.isNotEmpty) SliverToBoxAdapter(child: _groupHeader(p, Icons.notes, 'Others')),
        _section(others, pinned.length),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 96)),
    ];
  }

  Widget _groupHeader(MarketPalette p, IconData icon, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
        child: Row(children: [
          Icon(icon, size: 14, color: p.label),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.label)),
        ]),
      );

  Widget _section(List<NoteItem> notes, int indexOffset) {
    if (!_grid) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.separated(
          itemCount: notes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => FadeSlideIn(index: indexOffset + i, child: _card(notes[i], compact: true)),
        ),
      );
    }
    // Two-column staggered grid: cards keep their natural height.
    final left = <Widget>[];
    final right = <Widget>[];
    for (var i = 0; i < notes.length; i++) {
      final card = Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FadeSlideIn(index: indexOffset + i, child: _card(notes[i])),
      );
      (i.isEven ? left : right).add(card);
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverToBoxAdapter(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(children: left)),
          const SizedBox(width: 10),
          Expanded(child: Column(children: right)),
        ]),
      ),
    );
  }

  Widget _card(NoteItem note, {bool compact = false}) {
    final p = MarketPalette.of(context);
    final category = _categoryOf(note);
    final catColor = noteCategoryColor(category?.color, note.label, p);
    final preview = getPlainText(note.content);
    final done = note.checklist.where((c) => c.isDone).length;
    final total = note.checklist.length;
    final reminderAt = note.reminderValue == null ? null : DateTime.tryParse(note.reminderValue!.replaceFirst(' ', 'T'));
    final overdue = reminderAt != null && reminderAt.isBefore(DateTime.now());

    return GestureDetector(
      onLongPress: () => _noteActions(note),
      child: MarketCard(
        onTap: () => _openEditor(note: note),
        padding: EdgeInsets.zero,
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: catColor, width: 3))),
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(note.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text, height: 1.25)),
              ),
              if (note.pinned) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.push_pin, size: 14, color: p.brand)),
            ]),
            if (preview.isNotEmpty && preview != 'Add more details later.') ...[
              const SizedBox(height: 6),
              Text(preview,
                  maxLines: compact ? 2 : 6, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.label, height: 1.4)),
            ],
            if (total > 0) ...[
              const SizedBox(height: 10),
              if (!compact)
                ...note.checklist.take(3).map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(children: [
                        Icon(c.isDone ? Icons.check_box : Icons.check_box_outline_blank, size: 14, color: c.isDone ? p.ok : p.label),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(c.content,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: c.isDone ? p.label : p.text, decoration: c.isDone ? TextDecoration.lineThrough : null)),
                        ),
                      ]),
                    )),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : done / total,
                      minHeight: 4,
                      backgroundColor: p.surface,
                      color: done == total ? p.ok : p.brand,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('$done/$total', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.label)),
              ]),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusPill(note.label, tone: MarketTone.neutral),
              if (note.hasReminder && reminderAt != null)
                StatusPill(noteReminderLabel(reminderAt), tone: overdue ? MarketTone.error : MarketTone.warn, icon: Icons.alarm),
              Icon(noteVisibilityIcon(note.visibility), size: 13, color: p.label),
            ]),
            const SizedBox(height: 8),
            Text('${note.owner} · ${note.updatedAt.replaceFirst('Updated ', '')}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.label)),
          ]),
        ),
      ),
    );
  }
}
