import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/aptigen_app_bar.dart';
import '../data/note_service.dart';
import '../models/note_model.dart';
import 'note_editor_page.dart';

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

  bool _loadingBootstrap = true;
  bool _loadingNotes = true;
  String? _error;
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _init();
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
      if (bootstrap.context != null) await _loadNotes();
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

  Future<void> _createCategory() async {
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
    if (name == null || name.isEmpty || _context == null) return;
    try {
      await _service.createCategory(name, _categories.length, _context!.memberId);
      final bootstrap = await _service.loadBootstrap();
      if (!mounted) return;
      setState(() => _categories = bootstrap.categories);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create category.')));
    }
  }

  Future<void> _openEditor({NoteItem? note}) async {
    if (_context == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NoteEditorPage(
          context: _context!,
          categories: _categories,
          members: _members,
          existing: note,
        ),
      ),
    );
    if (changed == true) _loadNotes();
  }

  Future<void> _togglePin(NoteItem note) async {
    if (_context == null) return;
    try {
      await _service.togglePin(note.id, _context!.memberId, !note.pinned);
      _loadNotes();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update note.')));
    }
  }

  Future<void> _deleteNote(NoteItem note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text('This note will be permanently deleted. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteNote(note.id);
      _loadNotes();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete note.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AptigenAppBar(title: 'Notes', showBack: true),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: _loadingBootstrap
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: SegmentedButton<NoteMode>(
                    segments: const [
                      ButtonSegment(value: NoteMode.notes, label: Text('Notes')),
                      ButtonSegment(value: NoteMode.private, label: Text('Private')),
                      ButtonSegment(value: NoteMode.reminders, label: Text('Reminders')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (selection) {
                      setState(() => _mode = selection.first);
                      _loadNotes();
                    },
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _categoryId == null,
                        onSelected: (_) {
                          setState(() => _categoryId = null);
                          _loadNotes();
                        },
                      ),
                      const SizedBox(width: 8),
                      ..._categories.expand((category) => [
                            ChoiceChip(
                              label: Text(category.name),
                              selected: _categoryId == category.id,
                              onSelected: (_) {
                                setState(() => _categoryId = category.id);
                                _loadNotes();
                              },
                            ),
                            const SizedBox(width: 8),
                          ]),
                      ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text('New'), onPressed: _createCategory),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search notes'),
                    onSubmitted: (value) {
                      _search = value;
                      _loadNotes();
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$_totalCount note${_totalCount == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 11, color: AppColors.slate600),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(child: _buildList()),
              ],
            ),
    );
  }

  Widget _buildList() {
    if (_loadingNotes) {
      return const Center(child: CircularProgressIndicator(color: AppColors.brand));
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: TextStyle(color: AppColors.slate600)));
    }
    if (_notes.isEmpty) {
      return Center(child: Text('No notes yet — tap + to create one.', style: TextStyle(color: AppColors.slate600)));
    }
    return RefreshIndicator(
      onRefresh: _loadNotes,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
        itemCount: _notes.length,
        itemBuilder: (context, index) {
          final note = _notes[index];
          final doneCount = note.checklist.where((item) => item.isDone).length;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              onTap: () => _openEditor(note: note),
              title: Row(
                children: [
                  if (note.pinned) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.push_pin, size: 14, color: AppColors.brand)),
                  Expanded(child: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(getPlainText(note.content), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      Chip(label: Text(note.label, style: const TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact),
                      if (note.checklist.isNotEmpty)
                        Chip(label: Text('$doneCount/${note.checklist.length}', style: const TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact),
                      if (note.hasReminder && note.reminder != null)
                        Chip(
                          avatar: const Icon(Icons.alarm, size: 12),
                          label: Text(note.reminder!, style: const TextStyle(fontSize: 10)),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: AppColors.warning.withValues(alpha: 0.15),
                        ),
                    ],
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'pin') _togglePin(note);
                  if (value == 'delete') _deleteNote(note);
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'pin', child: Text(note.pinned ? 'Unpin' : 'Pin')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
