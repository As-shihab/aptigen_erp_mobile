import 'dart:convert';

// Edit operations sent to POST /api/media/items/:id/edit/{preview,save} —
// a Dart port of erp/desktop's image-studio/types.ts `EditOps`. JSON keys
// match the backend contract exactly; every field is optional and an empty
// object means "no change". String ids are used for the enum-like fields
// (filter, background type, scene, aspect, ...) so they serialise as-is.

const Object _unset = Object();

double? _d(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
int? _i(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
bool? _b(dynamic v) => v == null ? null : (v == true || v == 'true' || v == 1);
String? _s(dynamic v) => v == null ? null : '$v';
Map<String, dynamic>? _m(dynamic v) => v is Map ? v.cast<String, dynamic>() : null;

/// Fractions 0..1 of the source image (before rotate/flip).
class CropRect {
  final double x;
  final double y;
  final double width;
  final double height;
  const CropRect({required this.x, required this.y, required this.width, required this.height});

  static const full = CropRect(x: 0, y: 0, width: 1, height: 1);

  bool get isFull => x <= 0.0005 && y <= 0.0005 && width >= 0.999 && height >= 0.999;

  CropRect copyWith({double? x, double? y, double? width, double? height}) =>
      CropRect(x: x ?? this.x, y: y ?? this.y, width: width ?? this.width, height: height ?? this.height);

  /// Rounded to 4 decimals, as desktop does before applying a crop.
  CropRect rounded() {
    double r(double v) => (v * 10000).round() / 10000;
    return CropRect(x: r(x), y: r(y), width: r(width), height: r(height));
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'width': width, 'height': height};

  static CropRect? fromJson(dynamic raw) {
    final m = _m(raw);
    if (m == null) return null;
    return CropRect(x: _d(m['x']) ?? 0, y: _d(m['y']) ?? 0, width: _d(m['width']) ?? 1, height: _d(m['height']) ?? 1);
  }
}

/// Keys of `adjust`, in the order desktop's ADJUST_SLIDERS lists them.
const adjustKeys = ['brightness', 'contrast', 'saturation', 'sharpness', 'blur'];

/// `adjust: { brightness?, contrast?, saturation?, sharpness?, blur? }`.
class EditAdjust {
  final Map<String, double> values;
  const EditAdjust([this.values = const {}]);

  double? operator [](String key) => values[key];

  EditAdjust withValue(String key, double value) => EditAdjust({...values, key: value});
  EditAdjust without(String key) => EditAdjust({...values}..remove(key));

  Map<String, dynamic> toJson() => {
        for (final k in adjustKeys)
          if (values[k] != null) k: values[k],
      };

  static EditAdjust? fromJson(dynamic raw) {
    final m = _m(raw);
    if (m == null) return null;
    return EditAdjust({
      for (final k in adjustKeys)
        if (_d(m[k]) != null) k: _d(m[k])!,
    });
  }
}

class EditGradient {
  final String from;
  final String to;
  final double angle;
  const EditGradient({required this.from, required this.to, required this.angle});

  EditGradient copyWith({String? from, String? to, double? angle}) =>
      EditGradient(from: from ?? this.from, to: to ?? this.to, angle: angle ?? this.angle);

  Map<String, dynamic> toJson() => {'from': from, 'to': to, 'angle': angle};

  static EditGradient? fromJson(dynamic raw) {
    final m = _m(raw);
    if (m == null) return null;
    return EditGradient(from: _s(m['from']) ?? '#ffffff', to: _s(m['to']) ?? '#d4d4d8', angle: _d(m['angle']) ?? 180);
  }
}

/// `background: { type, color?, gradient?, blur_radius?, media_id?, scene? }`.
/// type: original | transparent | color | gradient | blur | image | scene.
class EditBackground {
  final String type;
  final String? color;
  final EditGradient? gradient;
  final double? blurRadius;
  final int? mediaId;
  final String? scene;
  const EditBackground({required this.type, this.color, this.gradient, this.blurRadius, this.mediaId, this.scene});

  EditBackground copyWith({String? type, String? color, EditGradient? gradient, double? blurRadius, int? mediaId, String? scene}) =>
      EditBackground(
        type: type ?? this.type,
        color: color ?? this.color,
        gradient: gradient ?? this.gradient,
        blurRadius: blurRadius ?? this.blurRadius,
        mediaId: mediaId ?? this.mediaId,
        scene: scene ?? this.scene,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        if (color != null) 'color': color,
        if (gradient != null) 'gradient': gradient!.toJson(),
        if (blurRadius != null) 'blur_radius': blurRadius,
        if (mediaId != null) 'media_id': mediaId,
        if (scene != null) 'scene': scene,
      };

  static EditBackground? fromJson(dynamic raw) {
    final m = _m(raw);
    if (m == null) return null;
    return EditBackground(
      type: _s(m['type']) ?? 'original',
      color: _s(m['color']),
      gradient: EditGradient.fromJson(m['gradient']),
      blurRadius: _d(m['blur_radius']),
      mediaId: _i(m['media_id']),
      scene: _s(m['scene']),
    );
  }
}

/// `shadow: { enabled, strength?, style?: 'soft' | 'floor' }`.
class EditShadow {
  final bool enabled;
  final double? strength;
  final String? style;
  const EditShadow({required this.enabled, this.strength, this.style});

  EditShadow copyWith({bool? enabled, double? strength, String? style}) =>
      EditShadow(enabled: enabled ?? this.enabled, strength: strength ?? this.strength, style: style ?? this.style);

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (strength != null) 'strength': strength,
        if (style != null) 'style': style,
      };

  static EditShadow? fromJson(dynamic raw) {
    final m = _m(raw);
    if (m == null) return null;
    return EditShadow(enabled: _b(m['enabled']) ?? false, strength: _d(m['strength']), style: _s(m['style']));
  }
}

/// `subject: { scale?, position?: 'center' | 'bottom' }`.
class EditSubject {
  final double? scale;
  final String? position;
  const EditSubject({this.scale, this.position});

  EditSubject copyWith({double? scale, String? position}) => EditSubject(scale: scale ?? this.scale, position: position ?? this.position);

  Map<String, dynamic> toJson() => {
        if (scale != null) 'scale': scale,
        if (position != null) 'position': position,
      };

  static EditSubject? fromJson(dynamic raw) {
    final m = _m(raw);
    if (m == null) return null;
    return EditSubject(scale: _d(m['scale']), position: _s(m['position']));
  }
}

/// `canvas: { aspect?, padding? }` — aspect: original | 1:1 | 4:5 | 3:4 | 16:9 | 9:16.
class EditCanvas {
  final String? aspect;
  final double? padding;
  const EditCanvas({this.aspect, this.padding});

  EditCanvas copyWith({String? aspect, double? padding}) => EditCanvas(aspect: aspect ?? this.aspect, padding: padding ?? this.padding);

  Map<String, dynamic> toJson() => {
        if (aspect != null) 'aspect': aspect,
        if (padding != null) 'padding': padding,
      };

  static EditCanvas? fromJson(dynamic raw) {
    final m = _m(raw);
    if (m == null) return null;
    return EditCanvas(aspect: _s(m['aspect']), padding: _d(m['padding']));
  }
}

/// `output: { format?: 'png' | 'webp' | 'jpeg', quality? }`.
class EditOutput {
  final String? format;
  final int? quality;
  const EditOutput({this.format, this.quality});

  EditOutput copyWith({String? format, int? quality}) => EditOutput(format: format ?? this.format, quality: quality ?? this.quality);

  Map<String, dynamic> toJson() => {
        if (format != null) 'format': format,
        if (quality != null) 'quality': quality,
      };

  static EditOutput? fromJson(dynamic raw) {
    final m = _m(raw);
    if (m == null) return null;
    return EditOutput(format: _s(m['format']), quality: _i(m['quality']));
  }
}

class EditOps {
  final CropRect? crop;
  /// 0 | 90 | 180 | 270
  final int? rotate;
  final bool? flipH;
  final bool? flipV;
  final EditAdjust? adjust;
  /// none | mono | sepia | vivid | warm | cool | fade | noir
  final String? filter;
  final bool? removeBg;
  final EditBackground? background;
  final EditShadow? shadow;
  final EditSubject? subject;
  final EditCanvas? canvas;
  final EditOutput? output;

  const EditOps({
    this.crop,
    this.rotate,
    this.flipH,
    this.flipV,
    this.adjust,
    this.filter,
    this.removeBg,
    this.background,
    this.shadow,
    this.subject,
    this.canvas,
    this.output,
  });

  static const empty = EditOps();

  /// Pass `null` explicitly to clear a field; omit it to keep the current value.
  EditOps copyWith({
    Object? crop = _unset,
    Object? rotate = _unset,
    Object? flipH = _unset,
    Object? flipV = _unset,
    Object? adjust = _unset,
    Object? filter = _unset,
    Object? removeBg = _unset,
    Object? background = _unset,
    Object? shadow = _unset,
    Object? subject = _unset,
    Object? canvas = _unset,
    Object? output = _unset,
  }) =>
      EditOps(
        crop: identical(crop, _unset) ? this.crop : crop as CropRect?,
        rotate: identical(rotate, _unset) ? this.rotate : rotate as int?,
        flipH: identical(flipH, _unset) ? this.flipH : flipH as bool?,
        flipV: identical(flipV, _unset) ? this.flipV : flipV as bool?,
        adjust: identical(adjust, _unset) ? this.adjust : adjust as EditAdjust?,
        filter: identical(filter, _unset) ? this.filter : filter as String?,
        removeBg: identical(removeBg, _unset) ? this.removeBg : removeBg as bool?,
        background: identical(background, _unset) ? this.background : background as EditBackground?,
        shadow: identical(shadow, _unset) ? this.shadow : shadow as EditShadow?,
        subject: identical(subject, _unset) ? this.subject : subject as EditSubject?,
        canvas: identical(canvas, _unset) ? this.canvas : canvas as EditCanvas?,
        output: identical(output, _unset) ? this.output : output as EditOutput?,
      );

  Map<String, dynamic> toJson() => {
        if (crop != null) 'crop': crop!.toJson(),
        if (rotate != null) 'rotate': rotate,
        if (flipH != null) 'flip_h': flipH,
        if (flipV != null) 'flip_v': flipV,
        if (adjust != null) 'adjust': adjust!.toJson(),
        if (filter != null) 'filter': filter,
        if (removeBg != null) 'remove_bg': removeBg,
        if (background != null) 'background': background!.toJson(),
        if (shadow != null) 'shadow': shadow!.toJson(),
        if (subject != null) 'subject': subject!.toJson(),
        if (canvas != null) 'canvas': canvas!.toJson(),
        if (output != null) 'output': output!.toJson(),
      };

  /// Accepts a map or a JSON string (templates store ops as Json); anything else → empty.
  static EditOps fromJson(dynamic raw) {
    if (raw is String) {
      try {
        return fromJson(jsonDecode(raw));
      } catch (_) {
        return empty;
      }
    }
    final m = _m(raw);
    if (m == null) return empty;
    final rotate = _i(m['rotate']);
    return EditOps(
      crop: CropRect.fromJson(m['crop']),
      rotate: rotate == null ? null : ((rotate % 360) + 360) % 360,
      flipH: _b(m['flip_h']),
      flipV: _b(m['flip_v']),
      adjust: EditAdjust.fromJson(m['adjust']),
      filter: _s(m['filter']),
      removeBg: _b(m['remove_bg']),
      background: EditBackground.fromJson(m['background']),
      shadow: EditShadow.fromJson(m['shadow']),
      subject: EditSubject.fromJson(m['subject']),
      canvas: EditCanvas.fromJson(m['canvas']),
      output: EditOutput.fromJson(m['output']),
    );
  }

  /// Stable string form — used for equality (undo history) and cache keys.
  String get key => jsonEncode(toJson());

  bool sameAs(EditOps other) => key == other.key;
}

// ── Normalisation (port of useImageStudio.ts / templates.ts helpers) ──

/// Neutral value of each adjust slider.
const adjustNeutral = {'brightness': 1.0, 'contrast': 1.0, 'saturation': 1.0, 'sharpness': 1.0, 'blur': 0.0};

/// Drops every no-op field (neutral sliders, filter 'none', rotate 0, ...)
/// and the background/shadow/subject groups when background removal is off
/// (the backend ignores them then). Used both as the request body and as the
/// cache key that decides whether a new preview is needed at all.
EditOps effectiveOps(EditOps ops) {
  CropRect? crop;
  final c = ops.crop;
  if (c != null && (c.x > 0.0005 || c.y > 0.0005 || c.width < 0.999 || c.height < 0.999)) crop = c;

  EditAdjust? adjust;
  if (ops.adjust != null) {
    final values = <String, double>{};
    for (final k in adjustKeys) {
      final v = ops.adjust![k];
      if (v != null && (v - adjustNeutral[k]!).abs() > 1e-6) values[k] = v;
    }
    if (values.isNotEmpty) adjust = EditAdjust(values);
  }

  final removeBg = ops.removeBg == true;
  EditSubject? subject;
  final s = ops.subject;
  if (removeBg && s != null && ((s.scale != null && s.scale! < 1) || s.position == 'bottom')) subject = s;

  EditCanvas? canvas;
  final cv = ops.canvas;
  if (cv != null && ((cv.aspect != null && cv.aspect != 'original') || (cv.padding ?? 0) > 0)) canvas = cv;

  return EditOps(
    crop: crop,
    rotate: (ops.rotate ?? 0) != 0 ? ops.rotate : null,
    flipH: ops.flipH == true ? true : null,
    flipV: ops.flipV == true ? true : null,
    adjust: adjust,
    filter: ops.filter != null && ops.filter != 'none' ? ops.filter : null,
    removeBg: removeBg ? true : null,
    background: removeBg ? ops.background : null,
    shadow: removeBg && ops.shadow?.enabled == true ? ops.shadow : null,
    subject: subject,
    canvas: canvas,
    output: ops.output?.format != null ? ops.output : null,
  );
}

bool isOpsEmpty(EditOps ops) => ops.toJson().isEmpty;

/// True when the ops wouldn't change the pixels (output re-encoding aside).
bool isVisualIdentity(EditOps ops) => isOpsEmpty(effectiveOps(ops).copyWith(output: null));

/// Removes the (image-specific) crop from a set of ops.
EditOps stripCrop(EditOps ops) => ops.copyWith(crop: null);

/// Normalised, crop-free ops — what actually gets stored in a template.
EditOps templateOps(EditOps ops) => stripCrop(effectiveOps(stripCrop(ops)));

/// True when the ops have nothing a template could keep (no edits, or only a crop).
bool isEmptyTemplateOps(EditOps ops) => isOpsEmpty(templateOps(ops));

/// Stable key for "these ops" — used to cache previews per template version.
String opsKey(EditOps ops) => templateOps(ops).key;

const _filterLabels = {
  'none': 'None', 'mono': 'Mono', 'sepia': 'Sepia', 'vivid': 'Vivid',
  'warm': 'Warm', 'cool': 'Cool', 'fade': 'Fade', 'noir': 'Noir',
};
const _sceneLabels = {
  'studio_white': 'Studio white', 'studio_gray': 'Studio gray', 'spotlight': 'Spotlight', 'pastel_pink': 'Pastel pink',
  'mint': 'Mint', 'sunset': 'Sunset', 'night': 'Night', 'marble': 'Marble', 'wood': 'Wood', 'gradient_glow': 'Gradient glow',
};
const _backgroundLabels = {
  'original': 'Keep original', 'transparent': 'Transparent', 'color': 'Color', 'gradient': 'Gradient',
  'blur': 'Blur', 'image': 'Image', 'scene': 'Scene',
};

/// Human-readable list of what a set of ops changes (sentence case).
List<String> summarizeOps(EditOps ops) {
  final o = templateOps(ops);
  final out = <String>[];
  if (o.adjust != null) out.add('Adjustments');
  if (o.rotate != null || o.flipH == true || o.flipV == true) out.add('Rotate and flip');
  if (o.filter != null) out.add('Filter: ${(_filterLabels[o.filter] ?? o.filter!).toLowerCase()}');
  if (o.removeBg == true) out.add('Background removal');
  final bg = o.background;
  if (bg != null && bg.type != 'original') {
    out.add(bg.type == 'scene'
        ? 'Scene: ${(_sceneLabels[bg.scene] ?? bg.scene ?? '').toLowerCase()}'
        : 'Background: ${(_backgroundLabels[bg.type] ?? bg.type).toLowerCase()}');
  }
  if (o.shadow?.enabled == true) out.add('Shadow');
  if (o.subject != null || o.canvas != null) out.add('Layout');
  if (o.output?.format != null) out.add('Output: ${o.output!.format!.toUpperCase()}');
  return out;
}
