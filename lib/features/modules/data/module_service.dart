import '../../../core/network/http_client.dart';
import '../../../core/storage/app_storage.dart';

int _toPositiveInt(dynamic value) {
  final parsed = int.tryParse(value?.toString() ?? '');
  return (parsed != null && parsed > 0) ? parsed : 0;
}

int _moduleIdFromPermission(dynamic permissionRow) {
  final map = permissionRow is Map ? permissionRow : {};
  final permission = map['permission'] is Map ? map['permission'] as Map : {};
  return _toPositiveInt(permission['module_id'] ?? permission['moduleId'] ?? map['module_id'] ?? map['moduleId']);
}

/// Ported from erp/desktop's auth/module-permission.ts.
class ModuleService {
  final ApiClient _client;
  ModuleService(this._client);

  Future<Set<int>> resolveAllowedModuleIds() async {
    final storedUser = await AppStorage.getUser();
    final userId = _toPositiveInt(storedUser?['id']);
    if (userId == 0) return {};

    try {
      final directRoleResponse = await _client.get(
        'user_has_role?\$filter=user_id eq $userId&\$expand=role(\$expand=permissions(\$expand=permission(\$select=module_id)))&\$top=100',
      );
      final directRoleRows = unwrapList(directRoleResponse);
      final directModuleIds = <int>{};
      for (final row in directRoleRows) {
        final role = (row as Map)['role'];
        final permissions = role is Map ? role['permissions'] : null;
        if (permissions is List) {
          for (final permissionRow in permissions) {
            final moduleId = _moduleIdFromPermission(permissionRow);
            if (moduleId > 0) directModuleIds.add(moduleId);
          }
        }
      }
      if (directModuleIds.isNotEmpty) return directModuleIds;
    } catch (_) {
      // fall through to workplace_members.role name mapping
    }

    try {
      final memberResponse = await _client.get(
        'workplace_members?\$select=role&\$filter=user_id eq $userId&\$top=1',
      );
      final rolesResponse = await _client.get(
        'Roles?\$expand=permissions(\$expand=permission(\$select=module_id))&\$top=500',
      );
      final member = unwrapList(memberResponse).cast<Map>().firstOrNull;
      final memberRoleName = (member?['role'] ?? '').toString().trim().toLowerCase();
      if (memberRoleName.isEmpty) return {};

      final roles = unwrapList(rolesResponse);
      final role = roles.cast<Map>().firstWhereOrNull((row) => (row['name'] ?? '').toString().trim().toLowerCase() == memberRoleName);
      if (role == null) return {};

      final permissions = role['permissions'];
      final moduleIds = <int>{};
      if (permissions is List) {
        for (final permissionRow in permissions) {
          final moduleId = _moduleIdFromPermission(permissionRow);
          if (moduleId > 0) moduleIds.add(moduleId);
        }
      }
      return moduleIds;
    } catch (_) {
      return {};
    }
  }

  Future<List<dynamic>> loadInstalledModules() async {
    final response = await _client.get('workplace_has_module?\$expand=module');
    return unwrapList(response);
  }
}

extension _FirstOrNullList<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? firstWhereOrNull(bool Function(T) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}
