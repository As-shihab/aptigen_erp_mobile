import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../data/note_service.dart';
import '../models/note_model.dart';
import 'note_ui.dart';

/// Create / edit a note — writing surface on top (title + body), then cards
/// for category, sharing, reminder and checklist, with a sticky save bar.
/// Save flow is unchanged: note, then checklist diff, then member access.
class NoteEditorPage extends StatefulWidget {
  final NoteContext context;
  final List<NoteCategoryOption> categories;
  final List<NoteMemberOption> members;
  final NoteItem? existing;

  const NoteEditorPage({
    super.key,
    required this.context,
    required this.categories,
    required this.members,
    this.existing,
  });

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  final _service = NoteService(ApiClient());
  late final _titleController = TextEditingController(text: widget.existing?.title ?? '');
  late final _contentController = TextEditingController(text: widget.existing != null ? _initialBody(widget.existing!.content) : '');
  final _newChecklistController = TextEditingController();
  final _memberSearch = TextEditingController();

  String? _categoryId;
  NoteVisibility _visibility = 'shared';
  bool _hasReminder = false;
  DateTime? _reminderDateTime;
  late List<NoteDraftChecklistItem> _checklistDrafts;
  final Set<int> _deletedChecklistIds = {};
  Set<int> _selectedMemberIds = {};
  bool _saving = false;
  bool _deleting = false;

  bool get _isEditing => widget.existing != null;

  // The default placeholder body the backend fills in shouldn't show up as text.
  static String _initialBody(String html) {
    final text = getPlainText(html);
    return text == 'Add more details later.' ? '' : text;
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _categoryId = existing?.categoryId?.toString();
    _visibility = existing?.visibility ?? 'shared';
    _hasReminder = existing?.hasReminder ?? false;
    if (existing?.reminderValue != null) {
      _reminderDateTime = DateTime.tryParse(existing!.reminderValue!.replaceFirst(' ', 'T'));
    }
    _checklistDrafts = (existing?.checklist ?? [])
        .map((item) => NoteDraftChecklistItem(id: item.id, content: item.content, isDone: item.isDone))
        .toList();
    _selectedMemberIds = (existing?.memberAccess ?? []).map((row) => row.memberId).toSet();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _newChecklistController.dispose();
    _memberSearch.dispose();
    super.dispose();
  }

  void _addChecklistItem() {
    final text = _newChecklistController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _checklistDrafts.add(NoteDraftChecklistItem(content: text));
      _newChecklistController.clear();
    });
  }

  void _removeChecklistItem(int index) {
    final item = _checklistDrafts[index];
    setState(() {
      if (item.id != null) _deletedChecklistIds.add(item.id!);
      _checklistDrafts.removeAt(index);
    });
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _reminderDateTime ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_reminderDateTime ?? now.add(const Duration(hours: 1))));
    if (time == null) return;
    setState(() {
      _reminderDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _hasReminder = true;
    });
  }

  void _quickReminder(Duration offset, {int? atHour}) {
    final now = DateTime.now();
    var d = now.add(offset);
    if (atHour != null) d = DateTime(d.year, d.month, d.day, atHour);
    setState(() {
      _reminderDateTime = d;
      _hasReminder = true;
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      marketToast(context, 'Give the note a title.', error: true);
      return;
    }
    if (_hasReminder && _reminderDateTime == null) {
      marketToast(context, 'Pick a time for the reminder.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final content = '<p>${_contentController.text.trim()}</p>';
      final categoryIdInt = _categoryId != null ? int.tryParse(_categoryId!) : null;
      final reminderIso = _hasReminder && _reminderDateTime != null ? _reminderDateTime!.toUtc().toIso8601String() : null;

      String noteId;
      if (_isEditing) {
        noteId = widget.existing!.id;
        await _service.updateNote(
          noteId: noteId,
          memberId: widget.context.memberId,
          categoryId: categoryIdInt,
          title: title,
          content: content,
          visibility: _visibility,
          hasReminder: _hasReminder,
          reminderIso: reminderIso,
        );
      } else {
        await _service.createNote(
          memberId: widget.context.memberId,
          categoryId: categoryIdInt,
          title: title,
          content: content,
          visibility: _visibility,
          hasReminder: _hasReminder,
          reminderIso: reminderIso,
        );
        // Re-fetch to resolve the created note's id for checklist/sharing sync.
        final result = await _service.loadNotes(widget.context, mode: NoteMode.notes, search: title);
        noteId = result.notes.isNotEmpty ? result.notes.first.id : '';
      }

      if (noteId.isNotEmpty) {
        for (final id in _deletedChecklistIds) {
          await _service.deleteChecklistItem(id);
        }
        for (var i = 0; i < _checklistDrafts.length; i++) {
          final item = _checklistDrafts[i];
          if (item.id == null) {
            await _service.createChecklistItem(noteId, item.content, i);
          } else {
            await _service.updateChecklistItem(item.id!, content: item.content, isDone: item.isDone, sortOrder: i);
          }
        }

        if (_visibility == 'specific') {
          await _service.syncMemberAccess(noteId, _selectedMemberIds.toList(), widget.existing?.memberAccess ?? []);
        }
      }

      if (!mounted) return;
      marketToast(context, _isEditing ? 'Note saved' : 'Note created');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      marketToast(context, 'Could not save note.', error: true);
    }
  }

  Future<void> _delete() async {
    final note = widget.existing;
    if (note == null) return;
    final ok = await confirmMarket(context, title: 'Delete note', message: '"${note.title}" will be permanently deleted. This can\'t be undone.');
    if (!ok) return;
    setState(() => _deleting = true);
    try {
      await _service.deleteNote(note.id);
      if (!mounted) return;
      marketToast(context, 'Note deleted');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      marketToast(context, 'Could not delete note.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final busy = _saving || _deleting;
    return MarketScaffold(
      title: _isEditing ? 'Edit note' : 'New note',
      subtitle: _isEditing ? widget.existing!.updatedAt : null,
      actions: [
        if (_isEditing)
          IconButton(tooltip: 'Delete note', icon: Icon(Icons.delete_outline, color: p.error), onPressed: busy ? null : _delete),
      ],
      bottom: _saveBar(p, busy),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _writingCard(p),
          const SizedBox(height: 12),
          _categoryCard(p),
          const SizedBox(height: 12),
          _sharingCard(p),
          const SizedBox(height: 12),
          _reminderCard(p),
          const SizedBox(height: 12),
          _checklistCard(p),
        ],
      ),
    );
  }

  Widget _card(MarketPalette p, {required IconData icon, required String title, String? subtitle, Widget? trailing, required Widget child}) {
    return MarketCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 17, color: p.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
              if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 11.5, color: p.label)),
            ]),
          ),
          ?trailing,
        ]),
        const SizedBox(height: 10),
        Divider(height: 1, color: p.line),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  Widget _writingCard(MarketPalette p) {
    final plain = InputDecoration(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      filled: false,
      isDense: true,
      contentPadding: EdgeInsets.zero,
      hintStyle: TextStyle(color: p.label),
    );
    return MarketCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _titleController,
          autofocus: !_isEditing,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text),
          decoration: plain.copyWith(hintText: 'Title'),
        ),
        const SizedBox(height: 10),
        Divider(height: 1, color: p.line),
        const SizedBox(height: 10),
        TextField(
          controller: _contentController,
          textCapitalization: TextCapitalization.sentences,
          minLines: 6,
          maxLines: null,
          style: TextStyle(fontSize: 14.5, height: 1.5, color: p.text),
          decoration: plain.copyWith(hintText: 'Write your note…'),
        ),
      ]),
    );
  }

  Widget _categoryCard(MarketPalette p) {
    return _card(
      p,
      icon: Icons.label_outline,
      title: 'Category',
      subtitle: widget.categories.isEmpty ? 'Create categories from the notes board' : null,
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        NoteTag('None', color: p.neutral, selected: _categoryId == null, onTap: () => setState(() => _categoryId = null)),
        for (final c in widget.categories)
          NoteTag(c.name, color: noteCategoryColor(c.color, c.name, p), selected: _categoryId == c.id, onTap: () => setState(() => _categoryId = c.id)),
      ]),
    );
  }

  Widget _sharingCard(MarketPalette p) {
    final q = _memberSearch.text.trim().toLowerCase();
    final members = widget.members.where((m) => q.isEmpty || m.name.toLowerCase().contains(q) || m.email.toLowerCase().contains(q)).toList();
    return _card(
      p,
      icon: noteVisibilityIcon(_visibility),
      title: 'Who can see it',
      subtitle: noteVisibilityLabel(_visibility),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MarketSegmented<NoteVisibility>(
          value: _visibility,
          onChanged: (v) => setState(() => _visibility = v),
          options: [
            (id: 'private', label: 'Only me', count: null),
            (id: 'shared', label: 'Everyone', count: null),
            (id: 'specific', label: 'Selected', count: _selectedMemberIds.isEmpty ? null : _selectedMemberIds.length),
          ],
        ),
        if (_visibility == 'specific') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _memberSearch,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Search people', prefixIcon: Icon(Icons.search), isDense: true),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: members.isEmpty
                ? Padding(padding: const EdgeInsets.all(12), child: Text('No people match.', style: TextStyle(color: p.label, fontSize: 12.5)))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: members.length,
                    itemBuilder: (_, i) {
                      final m = members[i];
                      final selected = _selectedMemberIds.contains(m.id);
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => selected ? _selectedMemberIds.remove(m.id) : _selectedMemberIds.add(m.id)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: Row(children: [
                            CircleAvatar(
                              radius: 15,
                              backgroundColor: selected ? p.brand : p.surface,
                              child: Text(m.name.isEmpty ? '?' : m.name[0].toUpperCase(),
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : p.label)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(m.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
                                if (m.email.isNotEmpty) Text(m.email, style: TextStyle(fontSize: 11, color: p.label)),
                              ]),
                            ),
                            Icon(selected ? Icons.check_circle : Icons.circle_outlined, size: 20, color: selected ? p.brand : p.line),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ]),
    );
  }

  Widget _reminderCard(MarketPalette p) {
    final at = _reminderDateTime;
    return _card(
      p,
      icon: Icons.alarm,
      title: 'Reminder',
      subtitle: _hasReminder && at != null ? noteReminderLabel(at) : 'No reminder',
      trailing: Switch(
        value: _hasReminder,
        onChanged: (v) {
          if (v) {
            if (_reminderDateTime == null) {
              _pickReminder();
            } else {
              setState(() => _hasReminder = true);
            }
          } else {
            setState(() => _hasReminder = false);
          }
        },
      ),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        ActionChip(label: const Text('In 1 hour'), onPressed: () => _quickReminder(const Duration(hours: 1))),
        ActionChip(label: const Text('Tomorrow 9:00'), onPressed: () => _quickReminder(const Duration(days: 1), atHour: 9)),
        ActionChip(label: const Text('Next week'), onPressed: () => _quickReminder(const Duration(days: 7), atHour: 9)),
        ActionChip(avatar: Icon(Icons.event, size: 16, color: p.brand), label: const Text('Pick date and time'), onPressed: _pickReminder),
      ]),
    );
  }

  Widget _checklistCard(MarketPalette p) {
    final done = _checklistDrafts.where((c) => c.isDone).length;
    final total = _checklistDrafts.length;
    return _card(
      p,
      icon: Icons.checklist,
      title: 'Checklist',
      subtitle: total == 0 ? 'Break it into steps' : '$done of $total done',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (total > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: done / total, minHeight: 4, backgroundColor: p.surface, color: done == total ? p.ok : p.brand),
          ),
          const SizedBox(height: 8),
        ],
        for (var i = 0; i < _checklistDrafts.length; i++)
          Dismissible(
            key: ObjectKey(_checklistDrafts[i]),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 12),
              color: p.errorBg,
              child: Icon(Icons.delete_outline, color: p.error),
            ),
            onDismissed: (_) => _removeChecklistItem(i),
            child: Row(children: [
              Checkbox(value: _checklistDrafts[i].isDone, onChanged: (v) => setState(() => _checklistDrafts[i].isDone = v ?? false)),
              Expanded(
                child: Text(
                  _checklistDrafts[i].content,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: _checklistDrafts[i].isDone ? p.label : p.text,
                    decoration: _checklistDrafts[i].isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              IconButton(icon: Icon(Icons.close, size: 18, color: p.label), tooltip: 'Remove', onPressed: () => _removeChecklistItem(i)),
            ]),
          ),
        Row(children: [
          Icon(Icons.add, size: 20, color: p.label),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _newChecklistController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Add an item', isDense: true),
              onSubmitted: (_) => _addChecklistItem(),
            ),
          ),
          TextButton(onPressed: _addChecklistItem, child: const Text('Add')),
        ]),
      ]),
    );
  }

  Widget _saveBar(MarketPalette p, bool busy) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
        child: Row(children: [
          Expanded(
            child: Text(
              [
                if (_checklistDrafts.isNotEmpty) '${_checklistDrafts.length} item${_checklistDrafts.length == 1 ? '' : 's'}',
                noteVisibilityLabel(_visibility),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: p.label),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: busy ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check, size: 18),
            label: Text(_isEditing ? 'Save note' : 'Create note'),
          ),
        ]),
      ),
    );
  }
}
