import '../../../core/network/http_client.dart';
import '../../../core/storage/app_storage.dart';
import '../models/user_model.dart';
import '../models/workplace_model.dart';

int _toPositiveInt(dynamic value) {
  final parsed = int.tryParse(value?.toString() ?? '');
  return (parsed != null && parsed > 0) ? parsed : 0;
}

/// Auth flow ported from erp/desktop's WelcomeScreen.tsx step handlers.
/// All calls are isV8=false (`/api/` base) — same as desktop.
class AuthService {
  final ApiClient _client;
  AuthService(this._client);

  /// Step: email + password. Returns the raw user JSON on success.
  Future<Map<String, dynamic>> login(String email, String password) async {
    final data = await _client.post(
      'auth/login',
      {'email': email.trim(), 'password': password},
      isV8: false,
    );
    final token = (data?['access_token'] ?? '').toString().trim();
    if (token.isEmpty) throw ApiException(0, 'Login failed. Invalid server response.');

    final user = (data['user'] as Map?)?.cast<String, dynamic>() ?? {};
    final userId = _toPositiveInt(user['id']);
    if (userId == 0) throw ApiException(0, 'Login failed. Invalid user information.');

    await AppStorage.setToken(token);
    await AppStorage.setUser(user);
    return user;
  }

  /// Step: load the user's workplaces after login.
  Future<List<WorkplaceOption>> fetchWorkplaces(int currentUserId) async {
    final data = await _client.get('auth/workplaces', isV8: false);
    final rows = unwrapList(data);
    return rows
        .map((row) {
          final map = (row as Map).cast<String, dynamic>();
          final ownerId = _toPositiveInt(map['owner_id'] ?? map['ownerId']);
          return WorkplaceOption(
            id: (map['id'] ?? map['workplaceid'] ?? '').toString(),
            name: (map['name'] ?? '').toString().trim(),
            isOwn: currentUserId > 0 && ownerId == currentUserId,
          );
        })
        .where((option) => option.id.isNotEmpty && option.name.isNotEmpty)
        .toList();
  }

  /// Step: create a new workplace for the given owner.
  Future<WorkplaceOption> createWorkplace(String name, int ownerId) async {
    final data = await _client.post(
      'auth/workplaces',
      {'name': name, 'owner_id': ownerId},
      isV8: false,
    );
    final created = (data is Map ? data['value'] ?? data : data) as Map?;
    if (created == null) throw ApiException(0, 'Could not create workplace.');
    final map = created.cast<String, dynamic>();
    final createdId = _toPositiveInt(map['id'] ?? map['workplaceid'] ?? map['workplace_id']);
    if (createdId == 0) throw ApiException(0, 'Workplace created but invalid workplace id returned.');
    return WorkplaceOption(
      id: createdId.toString(),
      name: (map['name'] ?? name).toString().trim().isNotEmpty ? map['name'].toString() : name,
      isOwn: true,
    );
  }

  /// Step: activate the selected/created workplace — swaps the access
  /// token for one scoped to that workplace and merges it into the
  /// stored user, matching desktop's `auth/workplce_token` step.
  Future<String> activateWorkplace(WorkplaceOption workplace) async {
    final workplaceId = int.tryParse(workplace.id) ?? 0;
    if (workplaceId == 0) throw ApiException(0, 'Invalid workplace selected.');

    final data = await _client.post(
      'auth/workplce_token',
      {'workplaceId': workplaceId},
      isV8: false,
    );
    final token = (data?['access_token'] ?? '').toString().trim();
    if (token.isEmpty) throw ApiException(0, 'Could not activate selected workplace.');

    await AppStorage.setToken(token);
    final storedUser = await AppStorage.getUser() ?? <String, dynamic>{};
    await AppStorage.setUser({
      ...storedUser,
      'workplace': workplace.toJson(),
      'selectedWorkplace': workplace.toJson(),
    });
    return token;
  }

  /// Step: sign up — creates the account (workplace/token activation is
  /// handled by the caller via login + createWorkplace + activateWorkplace,
  /// exactly like desktop's handleSignUpCompleteStep chains them).
  Future<void> signup(String name, String email, String password) async {
    await _client.post(
      'auth/signup',
      {'name': name, 'email': email.trim(), 'password': password},
      isV8: false,
    );
  }

  Future<bool> isLoggedIn() async {
    final token = await AppStorage.getToken();
    if (token == null || token.isEmpty) return false;
    final storedUser = await AppStorage.getUser();
    return storedUser?['selectedWorkplace'] != null || storedUser?['workplace'] != null;
  }

  Future<UserModel?> getStoredUser() async {
    final raw = await AppStorage.getUser();
    if (raw == null) return null;
    return UserModel.fromJson(raw);
  }

  Future<void> logout() async {
    await AppStorage.clearSession();
  }
}
