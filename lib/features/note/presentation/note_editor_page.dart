import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/note_service.dart';
import '../models/note_model.dart';

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
  late final _contentController = TextEditingController(text: widget.existing != null ? getPlainText(widget.existing!.content) : '');
  final _newChecklistController = TextEditingController();

  String? _categoryId;
  NoteVisibility _visibility = 'shared';
  bool _hasReminder = false;
  DateTime? _reminderDateTime;
  late List<NoteDraftChecklistItem> _checklistDrafts;
  final Set<int> _deletedChecklistIds = {};
  Set<int> _selectedMemberIds = {};
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

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
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_reminderDateTime ?? now));
    if (time == null) return;
    setState(() {
      _reminderDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _hasReminder = true;
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a title.')));
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
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save note.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Note' : 'New Note'),
        actions: [
          IconButton(
            icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Title'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contentController,
            decoration: const InputDecoration(labelText: 'Content', alignLabelWithHint: true),
            maxLines: 8,
            minLines: 4,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: widget.categories.any((c) => c.id == _categoryId) ? _categoryId : null,
            decoration: const InputDecoration(labelText: 'Category'),
            items: widget.categories.map((category) => DropdownMenuItem(value: category.id, child: Text(category.name))).toList(),
            onChanged: (value) => setState(() => _categoryId = value),
          ),
          const SizedBox(height: 16),
          const Text('Visibility', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          SegmentedButton<NoteVisibility>(
            segments: const [
              ButtonSegment(value: 'private', label: Text('Private')),
              ButtonSegment(value: 'shared', label: Text('Shared')),
              ButtonSegment(value: 'specific', label: Text('Specific')),
            ],
            selected: {_visibility},
            onSelectionChanged: (selection) => setState(() => _visibility = selection.first),
          ),
          if (_visibility == 'specific') ...[
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(border: Border.all(color: AppColors.slate400.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(12)),
              child: ListView(
                shrinkWrap: true,
                children: widget.members.map((member) {
                  final selected = _selectedMemberIds.contains(member.id);
                  return CheckboxListTile(
                    value: selected,
                    title: Text(member.name),
                    subtitle: member.email.isNotEmpty ? Text(member.email, style: const TextStyle(fontSize: 11)) : null,
                    dense: true,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedMemberIds.add(member.id);
                        } else {
                          _selectedMemberIds.remove(member.id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reminder'),
            subtitle: Text(_hasReminder && _reminderDateTime != null ? _reminderDateTime.toString() : 'No reminder set'),
            value: _hasReminder,
            onChanged: (value) {
              if (value) {
                _pickReminder();
              } else {
                setState(() => _hasReminder = false);
              }
            },
          ),
          const SizedBox(height: 16),
          const Text('Checklist', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          ..._checklistDrafts.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Row(
              children: [
                Checkbox(
                  value: item.isDone,
                  onChanged: (value) => setState(() => item.isDone = value ?? false),
                ),
                Expanded(
                  child: Text(item.content, style: TextStyle(decoration: item.isDone ? TextDecoration.lineThrough : null)),
                ),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => _removeChecklistItem(index)),
              ],
            );
          }),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newChecklistController,
                  decoration: const InputDecoration(hintText: 'Add checklist item'),
                  onSubmitted: (_) => _addChecklistItem(),
                ),
              ),
              IconButton(icon: const Icon(Icons.add), onPressed: _addChecklistItem),
            ],
          ),
        ],
      ),
    );
  }
}
