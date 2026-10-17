import '../../../core/network/http_client.dart';
import '../../../core/storage/app_storage.dart';
import '../models/job_model.dart';

int _toNum(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

/// `GET /api/public/jobs` — the same unauthenticated endpoint `frontend`'s
/// customer-facing site calls (`cloud/src/module/hrm/recruitment-public.*`).
/// It has no workplace_id auto-scoping (it's public, no auth guard), so the
/// current workplace id has to be resolved from the stored session and
/// passed explicitly as `?workplace=`.
class JobsService {
  final ApiClient _client;
  JobsService(this._client);

  Future<int?> _resolveWorkplaceId() async {
    final storedUser = await AppStorage.getUser();
    if (storedUser == null) return null;
    final workplaceMap = (storedUser['selectedWorkplace'] ?? storedUser['workplace']) as Map?;
    final workplaceId = _toNum(workplaceMap?['id']);
    return workplaceId == 0 ? null : workplaceId;
  }

  Future<List<Job>> loadJobs({String? status, String? query}) async {
    final workplaceId = await _resolveWorkplaceId();
    if (workplaceId == null) return const [];

    final params = <String, String>{'workplace': workplaceId.toString()};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');

    final res = await _client.get('public/jobs?$qs', isV8: false);
    return unwrapList(res).cast<Map<String, dynamic>>().map(Job.fromJson).toList();
  }

  Future<Job?> loadJob(int id) async {
    final workplaceId = await _resolveWorkplaceId();
    if (workplaceId == null) return null;
    final res = await _client.get('public/jobs/$id?workplace=$workplaceId', isV8: false);
    if (res is! Map<String, dynamic>) return null;
    return Job.fromJson(res);
  }
}
