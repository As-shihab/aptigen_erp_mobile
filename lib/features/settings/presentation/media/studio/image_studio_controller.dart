import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../../shared/data/media_studio_service.dart';
import '../../../../../shared/models/media_edit_ops.dart';

/// Port of erp/desktop's useImageStudio.ts: the current ops with undo / redo
/// history (slider drags are one step), plus a debounced server preview whose
/// stale responses are ignored.
class ImageStudioController extends ChangeNotifier {
  final int itemId;
  final MediaStudioService _service;

  ImageStudioController(this.itemId, {EditOps? initial, MediaStudioService? service})
      : _service = service ?? MediaStudioService(),
        _present = initial ?? EditOps.empty {
    _onOpsChanged();
  }

  // ── History ──
  List<EditOps> _past = [];
  List<EditOps> _future = [];
  EditOps _present;
  /// State before an in-flight transient change (slider drag); committed as one step.
  EditOps? _base;

  EditOps get ops => _present;
  bool get canUndo => _past.isNotEmpty || (_base != null && !_base!.sameAs(_present));
  bool get canRedo => _future.isNotEmpty;

  List<EditOps> _cap(List<EditOps> list, {bool tail = true}) {
    if (list.length <= studioHistoryLimit) return list;
    return tail ? list.sublist(list.length - studioHistoryLimit) : list.sublist(0, studioHistoryLimit);
  }

  /// Applies an updater to the ops. `transient` = mid-drag; call [commit] when it ends.
  void set(EditOps Function(EditOps prev) next, {bool transient = false}) {
    final value = next(_present);
    if (transient) {
      _base ??= _present;
      _present = value;
    } else {
      final from = _base ?? _present;
      if (!from.sameAs(value)) {
        _past = _cap([..._past, from]);
        _future = [];
      }
      _present = value;
      _base = null;
    }
    _onOpsChanged();
  }

  void commit() {
    final base = _base;
    if (base == null) return;
    if (!base.sameAs(_present)) {
      _past = _cap([..._past, base]);
      _future = [];
    }
    _base = null;
    notifyListeners();
  }

  void undo() {
    final base = _base;
    if (base != null && !base.sameAs(_present)) {
      // Undo an uncommitted drag: just snap back to where it started.
      _future = _cap([_present, ..._future], tail: false);
      _present = base;
      _base = null;
    } else {
      if (_past.isEmpty) return;
      final from = base ?? _present;
      final prev = _past.last;
      _past = _past.sublist(0, _past.length - 1);
      _future = _cap([from, ..._future], tail: false);
      _present = prev;
      _base = null;
    }
    _onOpsChanged();
  }

  void redo() {
    if (_future.isEmpty) return;
    final next = _future.first;
    _past = _cap([..._past, _base ?? _present]);
    _future = _future.sublist(1);
    _present = next;
    _base = null;
    _onOpsChanged();
  }

  void resetAll() => set((_) => EditOps.empty);

  // ── Preview ──
  EditOps effective = EditOps.empty;
  String _effectiveKey = '{}';
  bool identity = true;

  StudioPreview? _preview;
  String _previewKey = '';
  bool loading = false;
  String? error;
  bool _bgRemovedOnce = false;
  int _seq = 0;
  Timer? _timer;
  bool _disposed = false;

  /// The server preview, only when the ops change pixels (null → show the source image).
  StudioPreview? get preview => identity ? null : _preview;
  /// True while the shown preview no longer matches the current ops.
  bool get stale => !identity && _effectiveKey != _previewKey;
  bool get removingBgFirstTime => _present.removeBg == true && !_bgRemovedOnce;
  bool get hasChanges => !isOpsEmpty(effective);

  void _onOpsChanged({bool immediate = false}) {
    effective = effectiveOps(_present);
    final key = effective.key;
    final keyChanged = key != _effectiveKey;
    _effectiveKey = key;
    identity = isVisualIdentity(_present);
    if (keyChanged || immediate) _schedule(immediate: immediate);
    if (!_disposed) notifyListeners();
  }

  void _schedule({bool immediate = false}) {
    final seq = ++_seq;
    _timer?.cancel();
    if (identity) {
      loading = false;
      error = null;
      return;
    }
    // Already showing exactly this result (e.g. undo back to it) — nothing to fetch.
    if (_effectiveKey == _previewKey && !immediate) {
      loading = false;
      error = null;
      return;
    }
    loading = true;
    error = null;
    final body = effective;
    final key = _effectiveKey;
    _timer = Timer(immediate ? Duration.zero : studioPreviewDebounce, () async {
      try {
        final res = await _service.preview(itemId, body);
        if (_disposed || seq != _seq) return;
        _preview = res;
        _previewKey = key;
        if (body.removeBg == true) _bgRemovedOnce = true;
      } catch (e) {
        if (_disposed || seq != _seq) return;
        error = describeStudioError(e, 'Preview failed');
      }
      if (_disposed || seq != _seq) return;
      loading = false;
      notifyListeners();
    });
  }

  void retry() => _onOpsChanged(immediate: true);

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
