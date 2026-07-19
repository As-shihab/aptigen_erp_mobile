import '../../../core/network/http_client.dart';
import '../../../core/storage/app_storage.dart';
import '../models/note_model.dart';

/// Ported from erp/desktop's note/data.ts + note_model.ts.
class NoteService {
  final ApiClient _client;
  NoteService(this._client);

  Future<NoteContext?> resolveContext() async {
    final storedUser = await AppStorage.getUser();
    if (storedUser == null) return null;
    final userId = toNum(storedUser['id']);
    final workplaceMap = (storedUser['selectedWorkplace'] ?? storedUser['workplace']) as Map?;
    final workplaceId = toNum(workplaceMap?['id']);
    if (userId == 0 || workplaceId == 0) return null;

    final res = await _client.get('workplace_members?\$filter=workplace_id eq $workplaceId and user_id eq $userId&\$expand=user&\$top=1');
    final row = unwrapList(res).cast<Map>().firstOrNull;
    final memberId = toNum(row?['id']);
    if (memberId == 0) return null;

    return NoteContext(
      userId: userId,
      memberId: memberId,
      workplaceName: (workplaceMap?['name'] ?? 'Workspace').toString().trim(),
      userName: ((row?['user'] as Map?)?['name'] ?? storedUser['name'] ?? 'You').toString().trim(),
    );
  }

  /// One batch: context member row + categories + full member list (for the
  /// "Specific people" sharing picker).
  Future<({NoteContext? context, List<NoteCategoryOption> categories, List<NoteMemberOption> members})> loadBootstrap() async {
    final storedUser = await AppStorage.getUser();
    if (storedUser == null) return (context: null, categories: <NoteCategoryOption>[], members: <NoteMemberOption>[]);
    final userId = toNum(storedUser['id']);
    final workplaceMap = (storedUser['selectedWorkplace'] ?? storedUser['workplace']) as Map?;
    final workplaceId = toNum(workplaceMap?['id']);
    if (userId == 0 || workplaceId == 0) {
      return (context: null, categories: <NoteCategoryOption>[], members: <NoteMemberOption>[]);
    }

    final result = await _client.batch([
      BatchRequest(id: '1', method: 'GET', url: 'workplace_members?\$filter=workplace_id eq $workplaceId and user_id eq $userId&\$expand=user&\$top=1'),
      BatchRequest(id: '2', method: 'GET', url: 'note_categories?\$orderby=sort_order asc,name asc&\$top=200'),
      BatchRequest(id: '3', method: 'GET', url: 'workplace_members?\$filter=workplace_id eq $workplaceId&\$expand=user&\$top=500'),
    ]);

    final memberRow = unwrapList(unwrapBatchBody(result, '1')).cast<Map>().firstOrNull;
    final memberId = toNum(memberRow?['id']);
    if (memberId == 0) return (context: null, categories: <NoteCategoryOption>[], members: <NoteMemberOption>[]);

    final context = NoteContext(
      userId: userId,
      memberId: memberId,
      workplaceName: (workplaceMap?['name'] ?? 'Workspace').toString().trim(),
      userName: ((memberRow?['user'] as Map?)?['name'] ?? storedUser['name'] ?? 'You').toString().trim(),
    );

    final categories = unwrapList(unwrapBatchBody(result, '2'))
        .map((row) => NoteCategoryOption.fromJson(row as Map))
        .where((row) => row.name.isNotEmpty)
        .toList();

    final members = unwrapList(unwrapBatchBody(result, '3'))
        .map((row) => NoteMemberOption.fromJson(row as Map))
        .where((row) => row.id > 0 && row.id != memberId)
        .toList();

    return (context: context, categories: categories, members: members);
  }

  String _escapeOData(String value) => value.replaceAll("'", "''");

  /// One batch: filtered note rows + filtered total count.
  Future<({List<NoteItem> notes, int totalCount})> loadNotes(
    NoteContext context, {
    required NoteMode mode,
    String? categoryId,
    String search = '',
  }) async {
    final filterParts = <String>['is_trashed eq false'];
    if (mode == NoteMode.reminders) filterParts.add('reminder_enabled eq true');
    if (mode == NoteMode.private) filterParts.add("visibility ne 'shared'");
    if (categoryId != null && categoryId.isNotEmpty) {
      filterParts.add('category_id eq $categoryId');
    }
    final query = search.trim().toLowerCase();
    if (query.isNotEmpty) {
      final escaped = _escapeOData(query);
      filterParts.add(
        "(contains(tolower(title), '$escaped') or contains(tolower(content), '$escaped') or contains(tolower(category/name), '$escaped'))",
      );
    }
    final filterClause = '&\$filter=${filterParts.join(' and ')}';
    final listUrl = 'notes?\$expand=category,creator(\$expand=user),checklist_items,member_access&\$orderby=is_pinned desc,updated_at desc&\$top=300$filterClause';
    final countUrl = 'notes?\$count=true&\$top=0$filterClause';

    final result = await _client.batch([
      BatchRequest(id: '1', method: 'GET', url: listUrl),
      BatchRequest(id: '2', method: 'GET', url: countUrl),
    ]);

    final rows = unwrapList(unwrapBatchBody(result, '1'));
    final notes = rows
        .where((row) => _canAccess(row as Map, context))
        .map((row) => NoteItem.fromJson(row as Map))
        .toList();

    final countBody = unwrapBatchBody(result, '2');
    final totalCount = toNum(countBody?['@count']);

    return (notes: notes, totalCount: totalCount);
  }

  bool _canAccess(Map row, NoteContext context) {
    final visibility = (row['visibility'] ?? 'shared').toString().trim().toLowerCase();
    if (visibility == 'shared') return true;
    final createdBy = toNum(row['created_by'] ?? (row['creator'] as Map?)?['id']);
    if (createdBy == context.memberId) return true;
    final accessRows = (row['member_access'] as List?) ?? (row['note_member_access'] as List?) ?? [];
    return accessRows.any((access) {
      final map = access as Map;
      final memberId = toNum(map['member_id'] ?? (map['member'] as Map?)?['id']);
      return memberId == context.memberId && map['can_view'] != false;
    });
  }

  Future<void> createNote({
    required int memberId,
    required int? categoryId,
    required String title,
    required String content,
    required NoteVisibility visibility,
    required bool hasReminder,
    String? reminderIso,
    bool isPinned = false,
  }) async {
    await _client.post('notes', {
      'category_id': categoryId,
      'content': content,
      'reminder_at': hasReminder ? reminderIso : null,
      'reminder_enabled': hasReminder && reminderIso != null,
      'title': title,
      'created_by': memberId,
      'updated_by': memberId,
      'is_pinned': isPinned,
      'visibility': visibility,
    }, isV8: true);
  }

  Future<void> updateNote({
    required String noteId,
    required int memberId,
    required int? categoryId,
    required String title,
    required String content,
    required NoteVisibility visibility,
    required bool hasReminder,
    String? reminderIso,
  }) async {
    await _client.put('notes', noteId, {
      'category_id': categoryId,
      'content': content,
      'reminder_at': hasReminder ? reminderIso : null,
      'reminder_enabled': hasReminder && reminderIso != null,
      'title': title,
      'updated_by': memberId,
      'visibility': visibility,
    }, isV8: true);
  }

  Future<void> togglePin(String noteId, int memberId, bool isPinned) async {
    await _client.put('notes', noteId, {'is_pinned': isPinned, 'updated_by': memberId}, isV8: true);
  }

  Future<void> deleteNote(String noteId) async {
    await _client.delete('notes', noteId, isV8: true);
  }

  Future<void> createChecklistItem(String noteId, String content, int sortOrder) async {
    await _client.post('note_checklists', {'note_id': int.tryParse(noteId), 'content': content, 'sort_order': sortOrder, 'is_done': false}, isV8: true);
  }

  Future<void> updateChecklistItem(int id, {String? content, bool? isDone, int? sortOrder}) async {
    await _client.put('note_checklists', id, {
      if (content != null) 'content': content,
      if (isDone != null) 'is_done': isDone,
      if (sortOrder != null) 'sort_order': sortOrder,
    }, isV8: true);
  }

  Future<void> deleteChecklistItem(int id) async {
    await _client.delete('note_checklists', id, isV8: true);
  }

  Future<void> syncMemberAccess(String noteId, List<int> desiredMemberIds, List<NoteMemberAccess> currentAccess) async {
    final desired = desiredMemberIds.toSet();
    final current = currentAccess.map((row) => row.memberId).toSet();

    for (final memberId in desiredMemberIds) {
      if (current.contains(memberId)) continue;
      await _client.post('note_member_access', {'note_id': int.tryParse(noteId), 'member_id': memberId, 'can_view': true}, isV8: true);
    }
    for (final row in currentAccess) {
      if (desired.contains(row.memberId)) continue;
      await _client.delete('note_member_access', row.id, isV8: true);
    }
  }

  Future<void> createCategory(String name, int sortOrder, int createdBy) async {
    await _client.post('note_categories', {'name': name, 'sort_order': sortOrder, 'is_active': true, 'created_by': createdBy}, isV8: true);
  }

  Future<void> renameCategory(String id, String name) async {
    await _client.put('note_categories', id, {'name': name}, isV8: true);
  }

  Future<void> deleteCategory(String id) async {
    await _client.delete('note_categories', id, isV8: true);
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
