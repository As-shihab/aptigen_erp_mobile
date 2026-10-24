import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'label_model.dart';

// One painter for every surface: the interactive designer canvas, template
// thumbnails and the offscreen bitmap that is printed. Works in mm, scaled
// by `pxPerMm`, so the screen preview and the printed dots match exactly.

const double _ptToMm = 25.4 / 72;

/// Decoded images for image elements, keyed by their base64 payload.
/// A [ChangeNotifier] so painters repaint once an image finishes decoding.
class LabelImageCache extends ChangeNotifier {
  LabelImageCache._();
  static final LabelImageCache instance = LabelImageCache._();

  final Map<int, ui.Image> _images = {};
  final Set<int> _pending = {};
  final Set<int> _failed = {};

  static int _key(String b64) => Object.hash(b64.length, b64.hashCode);

  ui.Image? lookup(LabelElement e) {
    final b64 = e.imageB64;
    if (b64 == null || b64.isEmpty) return null;
    final k = _key(b64);
    final img = _images[k];
    if (img == null && !_pending.contains(k) && !_failed.contains(k)) _decode(k, b64);
    return img;
  }

  Future<void> _decode(int k, String b64) async {
    _pending.add(k);
    try {
      final codec = await ui.instantiateImageCodec(base64Decode(b64));
      final frame = await codec.getNextFrame();
      _images[k] = frame.image;
    } catch (_) {
      _failed.add(k);
    } finally {
      _pending.remove(k);
      notifyListeners();
    }
  }

  /// Decodes every image used by [elements] (call before offscreen render).
  Future<void> ensureAll(Iterable<LabelElement> elements) async {
    for (final e in elements) {
      final b64 = e.imageB64;
      if (e.type != LabelElementType.image || b64 == null || b64.isEmpty) continue;
      final k = _key(b64);
      if (_images.containsKey(k) || _failed.contains(k)) continue;
      if (_pending.contains(k)) {
        while (_pending.contains(k)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      } else {
        await _decode(k, b64);
      }
    }
  }
}

/// Paints the whole label into [canvas] at [pxPerMm]. [showErrors] draws
/// inline error/placeholder boxes (designer only); [pixelSnap] aligns
/// barcode modules to whole pixels (printed output).
void paintLabel(
  Canvas canvas,
  LabelDesign d,
  Map<String, String> data,
  double pxPerMm, {
  bool showErrors = false,
  bool pixelSnap = false,
  LabelImageCache? cache,
}) {
  final s = pxPerMm;
  final size = Size(d.widthMm * s, d.heightMm * s);
  final ink = d.blackBackground ? Colors.white : Colors.black;
  final paper = d.blackBackground ? Colors.black : Colors.white;
  final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(d.cornerRadiusMm * s));
  canvas.save();
  canvas.clipRRect(rr);
  canvas.drawRect(Offset.zero & size, Paint()..color = paper);
  for (final e in d.elements) {
    _paintElement(canvas, e, data, s, ink, paper, showErrors, pixelSnap, cache ?? LabelImageCache.instance);
  }
  canvas.restore();
  if (d.border) {
    final bw = math.max(0.35 * s, 1.0);
    canvas.drawRRect(
      rr.deflate(bw / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bw
        ..color = ink,
    );
  }
}

void _paintElement(Canvas c, LabelElement e, Map<String, String> data, double s, Color ink, Color paper, bool showErrors, bool pixelSnap, LabelImageCache cache) {
  final box = Rect.fromLTWH(e.x * s, e.y * s, e.w * s, e.h * s);
  final quarter = e.rotation == 90 || e.rotation == 270;
  final local = Rect.fromCenter(center: Offset.zero, width: quarter ? box.height : box.width, height: quarter ? box.width : box.height);
  c.save();
  c.translate(box.center.dx, box.center.dy);
  if (e.rotation != 0) c.rotate(e.rotation * math.pi / 180);
  switch (e.type) {
    case LabelElementType.barcode:
    case LabelElementType.qr:
      _paintCode(c, local, e, data, s, ink, showErrors, pixelSnap && e.rotation % 180 == 0);
    case LabelElementType.text:
    case LabelElementType.price:
    case LabelElementType.date:
      _paintText(c, local, e, e.displayText(data), s, ink, paper);
    case LabelElementType.image:
      _paintImage(c, local, e, s, showErrors, cache);
    case LabelElementType.line:
      final t = math.max(e.stroke * s, 1.0);
      final paint = Paint()
        ..color = ink
        ..strokeWidth = t;
      if (e.vertical) {
        c.drawLine(Offset(0, local.top), Offset(0, local.bottom), paint);
      } else {
        c.drawLine(Offset(local.left, 0), Offset(local.right, 0), paint);
      }
    case LabelElementType.rect:
      final t = math.max(e.stroke * s, 1.0);
      final paint = Paint()..color = ink;
      if (e.fill) {
        c.drawRRect(RRect.fromRectAndRadius(local, Radius.circular(e.radius * s)), paint);
      } else {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = t;
        c.drawRRect(RRect.fromRectAndRadius(local.deflate(t / 2), Radius.circular(e.radius * s)), paint);
      }
    case LabelElementType.ellipse:
      final t = math.max(e.stroke * s, 1.0);
      final paint = Paint()..color = ink;
      if (e.fill) {
        c.drawOval(local, paint);
      } else {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = t;
        c.drawOval(local.deflate(t / 2), paint);
      }
  }
  c.restore();
}

void _paintError(Canvas c, Rect r, String message, double s) {
  const red = Color(0xFFD20A0A);
  c.drawRect(r, Paint()..color = const Color(0x1FD20A0A));
  c.drawRect(
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = red,
  );
  final tp = TextPainter(
    text: TextSpan(text: message, style: TextStyle(fontSize: math.max(7, math.min(2.4 * s, r.height / 3)), color: red, fontWeight: FontWeight.w600)),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    maxLines: 3,
    ellipsis: '…',
  )..layout(maxWidth: math.max(1, r.width - 4));
  tp.paint(c, Offset(r.left + (r.width - tp.width) / 2, r.top + (r.height - tp.height) / 2));
}

void _paintCode(Canvas c, Rect r, LabelElement e, Map<String, String> data, double s, Color ink, bool showErrors, bool pixelSnap) {
  final sym = e.symbology;
  final value = e.codeData(data);
  final err = validateSymbology(sym, value, ecLevel: e.ecLevel);
  if (err != null) {
    if (showErrors) _paintError(c, r, err, s);
    return;
  }
  final bc = sym.barcode(ecLevel: e.ecLevel);
  final drawText = e.showHumanText && !sym.is2D;
  final fontPx = e.humanTextSize * _ptToMm * s;
  var area = r;
  if (sym.isSquare) {
    final side = math.min(r.width, r.height);
    area = Rect.fromCenter(center: r.center, width: side, height: side);
  }

  List<BarcodeElement> make(double width, double height) =>
      bc.make(value, width: width, height: height, drawText: drawText, fontHeight: drawText ? fontPx : null, textPadding: drawText ? fontPx * 0.15 : null).toList();

  List<BarcodeElement> els;
  try {
    els = make(area.width, area.height);
    if (pixelSnap) {
      // Scale down so the narrowest module is a whole number of pixels —
      // uneven bar widths after thresholding hurt scan rates.
      final bars = els.whereType<BarcodeBar>().where((b) => b.width > 0);
      if (bars.isNotEmpty) {
        final unit = bars.map((b) => b.width).reduce(math.min);
        final target = unit.floorToDouble();
        if (target >= 1 && target < unit) {
          final k = target / unit;
          final nw = area.width * k;
          final nh = sym.isSquare ? area.height * k : area.height;
          area = Rect.fromCenter(center: area.center, width: nw, height: nh);
          els = make(area.width, area.height);
        }
      }
    }
  } catch (_) {
    if (showErrors) _paintError(c, r, 'This value can\'t be encoded as ${sym.label}', s);
    return;
  }

  final bar = Paint()
    ..color = ink
    ..isAntiAlias = !pixelSnap;
  for (final el in els) {
    if (el is BarcodeBar) {
      if (!el.black) continue;
      var rect = Rect.fromLTWH(area.left + el.left, area.top + el.top, el.width, el.height);
      if (pixelSnap) {
        rect = Rect.fromLTRB(rect.left.roundToDouble(), rect.top.roundToDouble(), rect.right.roundToDouble(), rect.bottom.roundToDouble());
      }
      c.drawRect(rect, bar);
    } else if (el is BarcodeText) {
      final tp = TextPainter(
        text: TextSpan(text: el.text, style: TextStyle(fontSize: fontPx, color: ink, height: 1)),
        textAlign: switch (el.align) {
          BarcodeTextAlign.left => TextAlign.left,
          BarcodeTextAlign.right => TextAlign.right,
          BarcodeTextAlign.center => TextAlign.center,
        },
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(minWidth: math.max(0, el.width), maxWidth: math.max(0, el.width));
      tp.paint(c, Offset(area.left + el.left, area.top + el.top));
    }
  }
}

void _paintText(Canvas c, Rect r, LabelElement e, String text, double s, Color ink, Color paper) {
  var color = ink;
  if (e.invert) {
    c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(0.6 * s)), Paint()..color = ink);
    color = paper;
  }
  if (text.isEmpty) return;
  final pad = e.invert ? 0.8 * s : 0.0;
  final maxW = math.max(1.0, r.width - pad * 2);
  final align = switch (e.align) {
    'center' => TextAlign.center,
    'right' => TextAlign.right,
    _ => TextAlign.left,
  };

  TextPainter build(double fs) => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fs,
            height: 1.12,
            color: color,
            fontWeight: e.bold ? FontWeight.w700 : FontWeight.w400,
            fontStyle: e.italic ? FontStyle.italic : FontStyle.normal,
            decoration: e.strike ? TextDecoration.lineThrough : null,
            decorationColor: color,
            decorationThickness: 1.6,
          ),
        ),
        textAlign: align,
        textDirection: TextDirection.ltr,
        maxLines: e.maxLines > 0 ? e.maxLines : null,
        ellipsis: e.maxLines > 0 ? '…' : null,
      )..layout(minWidth: maxW, maxWidth: maxW);

  var fs = e.fontSize * _ptToMm * s;
  var tp = build(fs);
  if (e.autoFit) {
    // Largest size that fits the box (within the line limit).
    fs = math.max(r.height - pad * 2, 1);
    tp = build(fs);
    var guard = 0;
    while ((tp.height > r.height - pad || tp.didExceedMaxLines || _overflowsWidth(tp, maxW)) && fs > 2 && guard++ < 60) {
      fs *= 0.92;
      tp = build(fs);
    }
  }
  c.save();
  c.clipRect(r);
  tp.paint(c, Offset(r.left + pad, r.top + (r.height - tp.height) / 2));
  c.restore();
}

bool _overflowsWidth(TextPainter tp, double maxW) {
  // A single word wider than the box (no break opportunity).
  for (final line in tp.computeLineMetrics()) {
    if (line.width > maxW + 0.5) return true;
  }
  return false;
}

void _paintImage(Canvas c, Rect r, LabelElement e, double s, bool showErrors, LabelImageCache cache) {
  final img = cache.lookup(e);
  if (img == null) {
    if (showErrors) {
      final p = Paint()
        ..color = const Color(0xFF8A9AAA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      c.drawRect(r, Paint()..color = const Color(0x148A9AAA));
      c.drawRect(r, p);
      c.drawLine(r.topLeft, r.bottomRight, p);
      c.drawLine(r.topRight, r.bottomLeft, p);
    }
    return;
  }
  const gray = ColorFilter.matrix(<double>[
    0.299, 0.587, 0.114, 0, 0, //
    0.299, 0.587, 0.114, 0, 0, //
    0.299, 0.587, 0.114, 0, 0, //
    0, 0, 0, 1, 0,
  ]);
  c.save();
  c.clipRect(r);
  paintImage(
    canvas: c,
    rect: r,
    image: img,
    fit: switch (e.fit) {
      'cover' => BoxFit.cover,
      'fill' => BoxFit.fill,
      _ => BoxFit.contain,
    },
    colorFilter: e.grayscale ? gray : null,
    filterQuality: FilterQuality.medium,
  );
  c.restore();
}

/// [CustomPainter] for widgets — scales the label to the paint size.
class LabelPainter extends CustomPainter {
  final LabelDesign design;
  final Map<String, String> data;
  final bool showErrors;
  final int revision;
  LabelPainter({required this.design, required this.data, this.showErrors = false, this.revision = 0}) : super(repaint: LabelImageCache.instance);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / design.widthMm;
    paintLabel(canvas, design, data, s, showErrors: showErrors);
  }

  @override
  bool shouldRepaint(covariant LabelPainter old) => true;
}

/// Renders the label offscreen at [dpi] (defaults to the design's) — one
/// pixel per printer dot.
Future<ui.Image> renderLabelImage(LabelDesign d, Map<String, String> data, {double? dpi}) async {
  await LabelImageCache.instance.ensureAll(d.elements);
  final effDpi = dpi ?? d.dpi.toDouble();
  final s = effDpi / 25.4;
  final wPx = math.max(1, (d.widthMm * s).round());
  final hPx = math.max(1, (d.heightMm * s).round());
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(Rect.fromLTWH(0, 0, wPx.toDouble(), hPx.toDouble()), Paint()..color = Colors.white);
  paintLabel(canvas, d, data, s, pixelSnap: true);
  final picture = rec.endRecording();
  final img = await picture.toImage(wPx, hPx);
  picture.dispose();
  return img;
}

Future<Uint8List> imageToPng(ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}
