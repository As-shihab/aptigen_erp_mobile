import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/http_client.dart';
import '../../core/network/socket_client.dart';
import '../models/media_edit_ops.dart';
import '../models/media_library_item.dart';
import 'media_studio_service.dart';

// Batch edit ("Lab") data layer — port of erp/desktop's lab/api.ts and
// useBatchJob.ts. Custom /api routes (isV8 = false).

const labMaxItems = 200;
const labJobPoll = Duration(seconds: 3);
const labBatchProgressEvent = 'media:batch-edit:progress';

/// queued | running | done | cancelled
bool isJobActive(String? status) => status == 'queued' || status == 'running';

class BatchResult {
  final int itemId;
  final String name;
  /// pending | running | done | error | skipped
  final String status;
  /// The new copy, or the replaced original, once done.
  final MediaLibraryItem? item;
  final String? error;
  const BatchResult({required this.itemId, required this.name, required this.status, this.item, this.error});

  factory BatchResult.fromJson(Map<String, dynamic> r) => BatchResult(
        itemId: int.tryParse('${r['item_id']}') ?? 0,
        name: (r['name'] ?? '').toString(),
        status: (r['status'] ?? 'pending').toString(),
        item: r['item'] is Map ? MediaLibraryItem.fromJson((r['item'] as Map).cast<String, dynamic>()) : null,
        error: r['error'] == null ? null : '${r['error']}',
      );

  BatchResult copyWith({String? status, MediaLibraryItem? item, String? error}) =>
      BatchResult(itemId: itemId, name: name, status: status ?? this.status, item: item ?? this.item, error: error ?? this.error);
}

class BatchJob {
  final String jobId;
  final String status;
  final String mode;
  final int total;
  final int done;
  final int failed;
  final List<BatchResult> results;
  const BatchJob({
    required this.jobId,
    required this.status,
    required this.mode,
    required this.total,
    required this.done,
    required this.failed,
    required this.results,
  });

  factory BatchJob.fromJson(dynamic raw) {
    final body = raw is Map && raw['value'] is Map ? raw['value'] as Map : (raw is Map ? raw : const {});
    final results = body['results'];
    return BatchJob(
      jobId: (body['job_id'] ?? '').toString(),
      status: (body['status'] ?? 'queued').toString(),
      mode: (body['mode'] ?? 'copy').toString(),
      total: int.tryParse('${body['total']}') ?? 0,
      done: int.tryParse('${body['done']}') ?? 0,
      failed: int.tryParse('${body['failed']}') ?? 0,
      results: results is List ? results.whereType<Map>().map((r) => BatchResult.fromJson(r.cast<String, dynamic>())).toList() : const [],
    );
  }

  BatchJob copyWith({String? status, int? total, int? done, int? failed, List<BatchResult>? results}) => BatchJob(
        jobId: jobId,
        status: status ?? this.status,
        mode: mode,
        total: total ?? this.total,
        done: done ?? this.done,
        failed: failed ?? this.failed,
        results: results ?? this.results,
      );
}

/// A lightweight, serialisable view of a media item (selection + session resume).
class LabItem {
  final int id;
  final String name;
  final String thumb;
  const LabItem({required this.id, required this.name, required this.thumb});

  factory LabItem.of(MediaLibraryItem item, {String view = 'tiny'}) => LabItem(
        id: item.id,
        name: item.name.trim().isEmpty ? 'Image ${item.id}' : item.name.trim(),
        thumb: mediaView(item, view),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'thumb': thumb};
  factory LabItem.fromJson(Map<String, dynamic> m) =>
      LabItem(id: int.tryParse('${m['id']}') ?? 0, name: (m['name'] ?? '').toString(), thumb: (m['thumb'] ?? '').toString());
}

/// The last started job, remembered so reopening the Lab resumes showing it.
class StoredJob {
  final String jobId;
  final String mode;
  final int? templateId;
  final String? templateName;
  final EditOps? ops;
  final List<LabItem> items;
  final int startedAt;
  const StoredJob({
    required this.jobId,
    required this.mode,
    this.templateId,
    this.templateName,
    this.ops,
    required this.items,
    required this.startedAt,
  });

  Map<String, dynamic> toJson() => {
        'job_id': jobId,
        'mode': mode,
        if (templateId != null) 'template_id': templateId,
        if (templateName != null) 'template_name': templateName,
        if (ops != null) 'ops': ops!.toJson(),
        'items': items.map((i) => i.toJson()).toList(),
        'started_at': startedAt,
      };

  static StoredJob? fromJson(dynamic raw) {
    if (raw is! Map || (raw['job_id'] ?? '').toString().isEmpty) return null;
    final items = raw['items'];
    return StoredJob(
      jobId: raw['job_id'].toString(),
      mode: (raw['mode'] ?? 'copy').toString(),
      templateId: int.tryParse('${raw['template_id']}'),
      templateName: raw['template_name']?.toString(),
      ops: raw['ops'] == null ? null : EditOps.fromJson(raw['ops']),
      items: items is List ? items.whereType<Map>().map((m) => LabItem.fromJson(m.cast<String, dynamic>())).toList() : const [],
      startedAt: int.tryParse('${raw['started_at']}') ?? 0,
    );
  }
}

class MediaLabService {
  static const _storeKey = 'media-lab:last-job';
  final ApiClient _client;
  MediaLabService([ApiClient? client]) : _client = client ?? ApiClient();

  /// Either [templateId] or [ops]. Returns the job id and total.
  Future<({String jobId, int total})> startBatchEdit({required List<int> itemIds, required String mode, int? templateId, EditOps? ops}) async {
    final res = await _client.post(
      'media/batch-edit',
      {
        'item_ids': itemIds,
        'mode': mode,
        if (templateId != null) 'template_id': templateId else 'ops': (ops ?? EditOps.empty).toJson(),
      },
      timeout: const Duration(seconds: 30),
    );
    final body = res is Map && res['value'] is Map ? res['value'] as Map : (res is Map ? res : const {});
    final jobId = (body['job_id'] ?? '').toString();
    if (jobId.isEmpty) throw Exception('The server did not return a job id');
    return (jobId: jobId, total: int.tryParse('${body['total']}') ?? itemIds.length);
  }

  Future<BatchJob> getBatchJob(String jobId) async =>
      BatchJob.fromJson(await _client.get('media/batch-edit/${Uri.encodeComponent(jobId)}', isV8: false));

  Future<void> cancelBatchJob(String jobId) async {
    await _client.post('media/batch-edit/${Uri.encodeComponent(jobId)}/cancel', {});
  }

  static Future<StoredJob?> readStoredJob() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storeKey);
      return raw == null ? null : StoredJob.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeStoredJob(StoredJob? job) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (job == null) {
        await prefs.remove(_storeKey);
      } else {
        await prefs.setString(_storeKey, jsonEncode(job.toJson()));
      }
    } catch (_) {/* storage unavailable — resume just won't work */}
  }
}

/// Live state of one batch-edit job: socket events for instant updates,
/// plus a GET poll every 3s as the source of truth. Polling stops once the
/// job is done or cancelled.
class BatchJobWatcher extends ChangeNotifier {
  final String jobId;
  final MediaLabService _service;
  final void Function(BatchJob job)? onFinished;

  BatchJob? job;
  String? error;
  bool missing = false;

  Timer? _timer;
  bool _stopped = false;
  bool _finishedFired = false;
  final Set<int> _replacedSeen = {};

  BatchJobWatcher(this.jobId, {MediaLabService? service, this.onFinished}) : _service = service ?? MediaLabService() {
    AppSocket.instance?.on(labBatchProgressEvent, _onProgress);
    _poll();
  }

  void _notify() {
    if (_stopped) return;
    _afterChange();
    notifyListeners();
  }

  Future<void> _poll() async {
    _timer?.cancel();
    try {
      final next = await _service.getBatchJob(jobId);
      if (_stopped) return;
      job = next;
      error = null;
      _notify();
      if (!isJobActive(next.status)) return;
    } catch (e) {
      if (_stopped) return;
      if (e is ApiException && e.statusCode == 404) {
        missing = true;
        _notify();
        return;
      }
      error = describeStudioError(e, 'Could not refresh the progress');
      _notify();
    }
    if (!_stopped) _timer = Timer(labJobPoll, _poll);
  }

  void _onProgress(dynamic p) {
    if (_stopped || p is! Map || (p['job_id'] ?? '').toString() != jobId) return;
    final prev = job;
    if (prev == null) return;
    final itemId = int.tryParse('${p['item_id']}');
    final rawItem = p['item'];
    job = prev.copyWith(
      status: p['job_status']?.toString(),
      done: int.tryParse('${p['done']}'),
      failed: int.tryParse('${p['failed']}'),
      total: int.tryParse('${p['total']}'),
      results: [
        for (final r in prev.results)
          r.itemId != itemId
              ? r
              : r.copyWith(
                  status: p['status']?.toString(),
                  item: rawItem is Map ? MediaLibraryItem.fromJson(rawItem.cast<String, dynamic>()) : null,
                  error: p['error']?.toString(),
                ),
      ],
    );
    _notify();
    // Job just ended — fetch the authoritative final state now.
    final jobStatus = p['job_status']?.toString();
    if (jobStatus != null && !isJobActive(jobStatus)) _poll();
  }

  void _afterChange() {
    final j = job;
    if (j == null) return;
    // Replaced originals keep their URL — bust caches so thumbnails show the new pixels.
    if (j.mode == 'replace') {
      for (final r in j.results) {
        if (r.status == 'done' && _replacedSeen.add(r.itemId)) MediaCacheBust.markReplaced(r.itemId);
      }
    }
    if (!isJobActive(j.status) && !_finishedFired) {
      _finishedFired = true;
      final cb = onFinished;
      if (cb != null) scheduleMicrotask(() => cb(j));
    }
  }

  @override
  void dispose() {
    _stopped = true;
    _timer?.cancel();
    AppSocket.instance?.off(labBatchProgressEvent, _onProgress);
    super.dispose();
  }
}
