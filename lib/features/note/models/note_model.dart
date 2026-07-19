int toNum(dynamic value) {
  final parsed = num.tryParse(value?.toString() ?? '');
  return parsed?.toInt() ?? 0;
}

/// `getPlainText` port — strips the HTML the desktop's rich-text editor
/// produces down to plain text (mobile edits/displays plain text only,
/// wrapped in a single `<p>` tag on save for desktop-side compatibility).
String getPlainText(String value) {
  return value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'</(p|div|li|ul|ol|h[1-6])>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp('&nbsp;', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class NoteChecklistItem {
  final int id;
  final String content;
  final bool isDone;
  final int sortOrder;

  const NoteChecklistItem({required this.id, required this.content, required this.isDone, required this.sortOrder});

  factory NoteChecklistItem.fromJson(Map json) => NoteChecklistItem(
        id: toNum(json['id']),
        content: (json['content'] ?? '').toString(),
        isDone: json['is_done'] == true,
        sortOrder: toNum(json['sort_order']),
      );
}

/// Working copy used while editing — `id == null` means "not persisted yet".
class NoteDraftChecklistItem {
  int? id;
  String content;
  bool isDone;
  NoteDraftChecklistItem({this.id, required this.content, this.isDone = false});
}

class NoteMemberAccess {
  final int id;
  final int memberId;
  const NoteMemberAccess({required this.id, required this.memberId});

  factory NoteMemberAccess.fromJson(Map json) => NoteMemberAccess(
        id: toNum(json['id']),
        memberId: toNum(json['member_id'] ?? (json['member'] is Map ? (json['member'] as Map)['id'] : null)),
      );
}

typedef NoteVisibility = String; // 'shared' | 'private' | 'specific'

class NoteItem {
  final String id;
  final int? categoryId;
  final String title;
  final String content;
  final String label;
  final bool pinned;
  final bool private;
  final NoteVisibility visibility;
  final bool hasReminder;
  final String? reminder;
  final String? reminderValue;
  final List<NoteChecklistItem> checklist;
  final List<NoteMemberAccess> memberAccess;
  final String owner;
  final String updatedAt;

  const NoteItem({
    required this.id,
    this.categoryId,
    required this.title,
    required this.content,
    required this.label,
    required this.pinned,
    required this.private,
    required this.visibility,
    required this.hasReminder,
    this.reminder,
    this.reminderValue,
    required this.checklist,
    required this.memberAccess,
    required this.owner,
    required this.updatedAt,
  });

  factory NoteItem.fromJson(Map json) {
    final visibility = (json['visibility'] ?? 'shared').toString().trim().toLowerCase();
    final isPrivate = visibility != 'shared';
    final creator = (json['creator'] as Map?);
    final creatorUser = (creator?['user'] as Map?);
    final checklist = ((json['checklist_items'] as List?) ?? [])
        .map((row) => NoteChecklistItem.fromJson(row as Map))
        .where((item) => item.id > 0)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final accessRows = (json['member_access'] as List?) ?? (json['note_member_access'] as List?) ?? [];
    final memberAccess = accessRows
        .map((row) => NoteMemberAccess.fromJson(row as Map))
        .where((row) => row.id > 0 && row.memberId > 0)
        .toList();
    final reminderAt = json['reminder_at'];

    return NoteItem(
      id: (json['id'] ?? '').toString(),
      categoryId: json['category_id'] != null ? toNum(json['category_id']) : null,
      title: (json['title'] ?? 'Untitled note').toString(),
      content: (json['content'] ?? '<p>Add more details later.</p>').toString(),
      label: ((json['category'] as Map?)?['name'] ?? json['label'] ?? 'General').toString(),
      pinned: json['is_pinned'] == true,
      private: isPrivate,
      visibility: visibility,
      hasReminder: json['reminder_enabled'] == true || reminderAt != null,
      reminder: _formatReminderAt(reminderAt),
      reminderValue: _formatReminderValue(reminderAt),
      checklist: checklist,
      memberAccess: memberAccess,
      owner: (creatorUser?['name'] ?? creatorUser?['email'] ?? (isPrivate ? 'You' : 'Workspace')).toString(),
      updatedAt: _formatUpdatedAt(json['updated_at']),
    );
  }
}

String? _formatReminderAt(dynamic value) {
  if (value == null) return null;
  final date = DateTime.tryParse(value.toString());
  if (date == null) return null;
  final local = date.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final ampm = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.month}/${local.day}, $hour:$minute $ampm';
}

String? _formatReminderValue(dynamic value) {
  if (value == null) return null;
  final date = DateTime.tryParse(value.toString());
  if (date == null) return null;
  final local = date.toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${p(local.month)}-${p(local.day)} ${p(local.hour)}:${p(local.minute)}';
}

String _formatUpdatedAt(dynamic value) {
  final date = DateTime.tryParse((value ?? '').toString());
  if (date == null) return 'Updated recently';
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'Updated just now';
  if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes} min ago';
  if (diff.inHours < 24) return 'Updated ${diff.inHours} h ago';
  if (diff.inHours < 48) return 'Updated yesterday';
  if (diff.inDays < 7) return 'Updated ${diff.inDays} days ago';
  return 'Updated ${date.month}/${date.day}/${date.year}';
}

class NoteCategoryOption {
  final String id;
  final String name;
  final String? color;
  const NoteCategoryOption({required this.id, required this.name, this.color});

  factory NoteCategoryOption.fromJson(Map json) => NoteCategoryOption(
        id: (json['id'] ?? json['name'] ?? '').toString(),
        name: (json['name'] ?? '').toString().trim(),
        color: json['color']?.toString(),
      );
}

class NoteMemberOption {
  final int id;
  final int userId;
  final String name;
  final String email;
  const NoteMemberOption({required this.id, required this.userId, required this.name, required this.email});

  factory NoteMemberOption.fromJson(Map json) {
    final user = json['user'] as Map?;
    return NoteMemberOption(
      id: toNum(json['id']),
      userId: toNum(json['user_id'] ?? user?['id']),
      name: (user?['name'] ?? user?['email'] ?? 'Member').toString().trim(),
      email: (user?['email'] ?? '').toString().trim(),
    );
  }
}

class NoteContext {
  final int userId;
  final int memberId;
  final String workplaceName;
  final String userName;
  const NoteContext({required this.userId, required this.memberId, required this.workplaceName, required this.userName});
}

enum NoteMode { notes, private, reminders }
