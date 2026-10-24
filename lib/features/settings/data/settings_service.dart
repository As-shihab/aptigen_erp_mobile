import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/http_client.dart';
import '../../../core/network/socket_client.dart';
import '../../../shared/ui/entity_crud.dart';
import '../../../shared/ui/motion_kit.dart';

/// App version shown on the update & data page — mirrors pubspec.yaml's
/// `version:` (no package_info dependency in this app).
const kAppVersion = '1.0.0';
const kAppBuild = '1';

typedef JsonRow = Map<String, dynamic>;

List<JsonRow> rowsOf(dynamic res) => unwrapList(res).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();

int? positiveInt(dynamic v) {
  final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  return n != null && n > 0 ? n : null;
}

bool isOwnerRole(dynamic name) => str(name).trim().toLowerCase() == 'owner';

String _esc(String s) => s.replaceAll("'", "''");

// ── Roles & permissions ─────────────────────────────────────────────────

class PermissionItem {
  final int id;
  final String name;
  const PermissionItem(this.id, this.name);
}

class PermissionModule {
  final String id;
  final String name;
  final List<PermissionItem> permissions;
  const PermissionModule(this.id, this.name, this.permissions);
}

class RolesService {
  final ApiClient _c;
  RolesService([ApiClient? c]) : _c = c ?? ApiClient();

  Future<List<JsonRow>> roles() async => rowsOf(await _c.get('roles?\$top=200&\$orderby=id asc'));

  /// `GET /api/auth/permissions` — installed modules with their permissions.
  Future<List<PermissionModule>> permissionTree() async {
    final res = await _c.get('auth/permissions?top=200', isV8: false);
    final list = res is List ? res : unwrapList(res);
    return [
      for (final m in list.whereType<Map>())
        PermissionModule(
          str(m['id']),
          str(m['module'] ?? m['permission']),
          [
            for (final p in (m['subRows'] is List ? m['subRows'] as List : const []).whereType<Map>())
              if (positiveInt(p['id']) != null) PermissionItem(positiveInt(p['id'])!, str(p['permission'])),
          ],
        ),
    ];
  }

  Future<Set<int>> rolePermissionIds(int roleId) async {
    final res = await _c.get('roles?\$expand=permissions&\$filter=id eq $roleId');
    final list = rowsOf(res);
    final role = list.isNotEmpty ? list.first : (res is Map ? res.cast<String, dynamic>() : <String, dynamic>{});
    final perms = role['permissions'] is List ? role['permissions'] as List : const [];
    return {
      for (final p in perms.whereType<Map>())
        ?positiveInt(p['permission_id'] ?? p['permissionId'] ?? (p['permission'] is Map ? p['permission']['id'] : null) ?? p['id']),
    };
  }

  Future<void> createRole(String name) => _c.post('roles', {'name': name}, isV8: true);
  Future<void> renameRole(int id, String name) => _c.put('roles', id, {'name': name});
  Future<void> deleteRole(int id) => _c.delete('roles', id);

  Future<void> syncPermissions(int roleId, Set<int> ids) =>
      _c.post('auth/role-permissions/sync', {'roleId': roleId, 'permissionIds': ids.toList()});
}

// ── Users (workplace members) ───────────────────────────────────────────

class UsersService {
  final ApiClient _c;
  UsersService([ApiClient? c]) : _c = c ?? ApiClient();

  /// Members and roles in one batch.
  Future<({List<JsonRow> members, List<JsonRow> roles})> load() async {
    final data = await batchLoad(_c, {
      'members': 'workplace_members?\$expand=user&\$orderby=id desc&\$top=500',
      'roles': 'roles?\$top=500&\$orderby=id asc',
    });
    return (members: data['members'] ?? [], roles: data['roles'] ?? []);
  }

  Future<Set<int>> userRoleIds(int userId) async {
    try {
      final rows = rowsOf(await _c.get('user_has_role?\$filter=user_id eq $userId&\$expand=role(\$select=id)&\$top=200'));
      return {for (final r in rows) ?positiveInt(r['role_id'] ?? (r['role'] is Map ? r['role']['id'] : null))};
    } catch (_) {
      return {};
    }
  }

  Future<void> syncRoles(int userId, Set<int> roleIds) =>
      _c.post('auth/user-role/sync', {'userId': userId, 'roleIds': roleIds.toList()});

  /// Same sequence as desktop UserList. Users are global and membership is
  /// per workplace, so an existing account with this email is reused and
  /// only added to this workplace; signup runs only for a new email.
  /// Returns true when an existing account was added.
  Future<bool> create({required String name, required String email, required String password, required bool isActive, String? imageUrl, required Set<int> roleIds}) async {
    final check = await _c.get('auth/find-user?email=${Uri.encodeComponent(email.trim())}', isV8: false);
    final existingId = positiveInt(check is Map ? check['userId'] : null);
    if (existingId != null && check is Map && check['inWorkplace'] == true) {
      throw ApiException(409, 'This user is already a member of this workplace');
    }
    var userId = existingId;
    if (userId == null) {
      if (password.trim().isEmpty) throw ApiException(400, 'Password is required');
      final res = await _c.post('auth/signup', {'name': name, 'email': email, 'password': password});
      userId = positiveInt(res is Map ? (res['user'] is Map ? res['user']['id'] : res['id']) : null);
      if (userId == null) throw ApiException(500, 'User created but the server returned no user id');
    }
    await _c.post('workplace_members', {'user_id': userId, 'is_active': isActive, 'image_url': imageUrl}, isV8: true);
    await syncRoles(userId, roleIds);
    return existingId != null;
  }

  Future<void> update({required int userId, int? memberId, required String name, required String email, String? password, required bool isActive, String? imageUrl, required Set<int> roleIds}) async {
    await _c.put('users', userId, {'name': name, 'email': email, if (password != null && password.isNotEmpty) 'password': password});
    if (memberId != null) await _c.put('workplace_members', memberId, {'is_active': isActive, 'image_url': imageUrl});
    await syncRoles(userId, roleIds);
  }

  Future<void> setActive(int memberId, bool active) => _c.put('workplace_members', memberId, {'is_active': active});

  Future<void> removeMember(int memberId) => _c.delete('workplace_members', memberId);

  /// Desktop's reverse-socket force logout (`reverse:socket` AUTH/LOGOUT).
  bool forceLogout(String targetUser) {
    final s = AppSocket.instance;
    if (s == null || !s.connected) return false;
    s.emit('reverse:socket', {'title': 'AUTH', 'target_user': targetUser, 'action': 'LOGOUT'});
    return true;
  }
}

// ── Audit logs ──────────────────────────────────────────────────────────

class AuditService {
  final ApiClient _c;
  AuditService([ApiClient? c]) : _c = c ?? ApiClient();

  Future<({List<JsonRow> rows, int? total})> page({String? action, String search = '', int top = 40, int skip = 0}) async {
    final filters = <String>[];
    if (action != null) filters.add("action eq '$action'");
    final q = search.trim().toLowerCase();
    if (q.isNotEmpty) {
      final e = _esc(q);
      filters.add("(contains(tolower(entity),'$e') or contains(tolower(user_email),'$e') or contains(record_id,'$e'))");
    }
    final qs = StringBuffer('audit_logs?\$orderby=created_at desc&\$top=$top&\$skip=$skip');
    if (skip == 0) qs.write('&\$count=true');
    if (filters.isNotEmpty) qs.write('&\$filter=${Uri.encodeComponent(filters.join(' and '))}');
    final res = await _c.get(qs.toString());
    final total = res is Map ? int.tryParse('${res['@count'] ?? res['@odata.count'] ?? ''}') : null;
    return (rows: rowsOf(res), total: total);
  }
}

// ── Notification preferences ────────────────────────────────────────────

class PreferenceService {
  final ApiClient _c;
  PreferenceService([ApiClient? c]) : _c = c ?? ApiClient();

  Future<({bool push, bool email})> get() async {
    final res = await _c.get('user/preference', isV8: false);
    final m = res is Map ? res : const {};
    return (push: asBool(m['push_notification'], fallback: true), email: asBool(m['email_notification'], fallback: true));
  }

  Future<void> update(Map<String, dynamic> patch) => _c.post('user/preference', patch);
}

// ── Devices (fingerprint catalog) ───────────────────────────────────────

class DevicesService {
  final ApiClient _c;
  DevicesService([ApiClient? c]) : _c = c ?? ApiClient();

  Future<List<JsonRow>> list() async => rowsOf(await _c.get('devices?\$orderby=id desc&\$top=200'));
  Future<void> create(JsonRow body) => _c.post('devices', body, isV8: true);
  Future<void> update(int id, JsonRow body) => _c.put('devices', id, body);

  /// Custom `DELETE /api/devices/:id` — factory-resets the device over MQTT
  /// before removing the catalog row.
  Future<void> delete(int id) => _c.delete('devices', id, isV8: false);
  Future<void> restart(int id) => _c.post('devices/$id/restart', {});
  Future<void> clearFingerprints(int id) => _c.post('devices/$id/reset-fingerprints', {});
  Future<void> scanNetworks(int id) => _c.post('devices/$id/scan-networks', {});
  Future<void> switchRouter(int id, String ssid, String password) => _c.post('devices/$id/switch-router', {'ssid': ssid, 'password': password});
}

// ── Device access requests ──────────────────────────────────────────────

class DeviceRequestsService {
  final ApiClient _c;
  DeviceRequestsService([ApiClient? c]) : _c = c ?? ApiClient();

  Future<List<JsonRow>> list() async => rowsOf(await _c.get('device_requests?\$expand=user&\$orderby=id desc&\$top=500'));

  Future<void> decide(int id, String status, int? memberId) => _c.put('device_requests', id, {
        'status': status,
        'approved_by': memberId,
        'approved_at': DateTime.now().toUtc().toIso8601String(),
      });

  Future<int?> myMemberId() async {
    try {
      return (await resolveSocketContext(_c))?.memberId;
    } catch (_) {
      return null;
    }
  }
}

// ── Approval chains ─────────────────────────────────────────────────────

class ApproverService {
  final ApiClient _c;
  ApproverService([ApiClient? c]) : _c = c ?? ApiClient();

  Future<List<JsonRow>> approvers(int typeId) async => rowsOf(await _c.get(
      'approve_type_has_approvers?\$filter=approve_type_id eq $typeId&\$expand=approver_emp(\$select=id,first_name,last_name),approver_des(\$select=id,name),workplace_member(\$expand=user(\$select=id,name,email))&\$orderby=serial asc&\$top=100'));

  Future<Map<String, List<JsonRow>>> refs() => batchLoad(_c, {
        'employees': 'employees?\$select=id,first_name,last_name,employee_no&\$filter=is_active eq true&\$top=500',
        'designations': 'designations?\$select=id,name&\$filter=is_active eq true&\$top=200',
        'members': 'workplace_members?\$select=id,user_id&\$expand=user(\$select=id,name,email)&\$top=500',
      });

  Future<void> save(JsonRow body, {int? id}) => id == null ? _c.post('approve_type_has_approvers', body, isV8: true) : _c.put('approve_type_has_approvers', id, body);
  Future<void> delete(int id) => _c.delete('approve_type_has_approvers', id);

  /// Rewrites serials to match [ordered]. `(approve_type_id, serial)` is
  /// unique, so moved rows are parked on high temporary serials first.
  Future<void> resequence(List<JsonRow> ordered) async {
    final changed = <int, int>{};
    for (var i = 0; i < ordered.length; i++) {
      final id = positiveInt(ordered[i]['id']);
      if (id != null && toInt(ordered[i]['serial']) != i + 1) changed[id] = i + 1;
    }
    if (changed.isEmpty) return;
    var park = 10000;
    for (final id in changed.keys) {
      await _c.put('approve_type_has_approvers', id, {'serial': park++});
    }
    for (final e in changed.entries) {
      await _c.put('approve_type_has_approvers', e.key, {'serial': e.value});
    }
  }
}

// ── Device-local preferences (desktop keeps these in localStorage) ──────

class LocalPrefs {
  static const biometricsKey = 'aptigen_settings_device_config_biometrics';
  static const sensorsKey = 'aptigen_settings_device_config_sensors';
  static const switchesKey = 'aptigen_settings_device_config_switches';
  static const allKeys = [biometricsKey, sensorsKey, switchesKey];

  static Future<JsonRow> read(String key, JsonRow defaults) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return {...defaults};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? {...defaults, ...decoded.cast<String, dynamic>()} : {...defaults};
    } catch (_) {
      return {...defaults};
    }
  }

  static Future<void> write(String key, JsonRow value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  /// Number of keys and approximate bytes this app keeps in preferences.
  static Future<({int keys, int bytes})> footprint() async {
    final prefs = await SharedPreferences.getInstance();
    var bytes = 0;
    final keys = prefs.getKeys();
    for (final k in keys) {
      bytes += k.length + '${prefs.get(k)}'.length;
    }
    return (keys: keys.length, bytes: bytes);
  }

  static Future<void> resetDevicePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in allKeys) {
      await prefs.remove(k);
    }
  }
}

String formatBytes(num bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
}
