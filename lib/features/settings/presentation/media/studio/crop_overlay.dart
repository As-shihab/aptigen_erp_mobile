import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../shared/models/media_edit_ops.dart';

// Port of erp/desktop's image-studio/CropOverlay.tsx: a draggable crop frame
// with 8 handles over the source image, in fractions of the source
// (before rotate/flip). An optional pixel aspect ratio locks the frame.

const double _minFraction = 0.03;
const double _handleHit = 28;

double _clamp(double v, double lo, double hi) => math.min(hi, math.max(lo, v));

/// Largest centered crop with the given *pixel* aspect ratio, in fractions.
CropRect centeredCrop(double ratio, double naturalW, double naturalH) {
  final rf = ratio * (naturalH == 0 ? 1 : naturalH) / (naturalW == 0 ? 1 : naturalW);
  var w = 1.0;
  var h = 1 / rf;
  if (h > 1) {
    h = 1;
    w = rf;
  }
  return CropRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h);
}

enum _Handle { move, n, s, e, w, ne, nw, se, sw }

extension on _Handle {
  bool get hasW => this == _Handle.w || this == _Handle.nw || this == _Handle.sw;
  bool get hasE => this == _Handle.e || this == _Handle.ne || this == _Handle.se;
  bool get hasN => this == _Handle.n || this == _Handle.ne || this == _Handle.nw;
  bool get hasS => this == _Handle.s || this == _Handle.se || this == _Handle.sw;
}

/// Forces a rect to a fraction-space ratio, anchored at the edge opposite the dragged handle.
CropRect _fitRatio(CropRect r, _Handle handle, double rf) {
  var w = r.width;
  var h = r.height;
  if (handle == _Handle.n || handle == _Handle.s) {
    w = h * rf;
  } else {
    h = w / rf;
  }
  final ax = handle.hasW ? r.x + r.width : handle.hasE ? r.x : r.x + r.width / 2;
  final ay = handle.hasN ? r.y + r.height : handle.hasS ? r.y : r.y + r.height / 2;
  final maxW = handle.hasW ? ax : handle.hasE ? 1 - ax : 2 * math.min(ax, 1 - ax);
  final maxH = handle.hasN ? ay : handle.hasS ? 1 - ay : 2 * math.min(ay, 1 - ay);
  final scale = [1.0, maxW / w, maxH / h].reduce(math.min);
  w *= scale;
  h *= scale;
  final x = handle.hasW ? ax - w : handle.hasE ? ax : ax - w / 2;
  final y = handle.hasN ? ay - h : handle.hasS ? ay : ay - h / 2;
  return CropRect(x: x, y: y, width: w, height: h);
}

class CropOverlay extends StatefulWidget {
  final ImageProvider image;
  final double naturalW;
  final double naturalH;
  final CropRect value;
  /// Pixel aspect ratio (w / h), or null for free-form.
  final double? ratio;
  final ValueChanged<CropRect> onChanged;

  const CropOverlay({
    super.key,
    required this.image,
    required this.naturalW,
    required this.naturalH,
    required this.value,
    required this.ratio,
    required this.onChanged,
  });

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  _Handle? _handle;
  Offset _start = Offset.zero;
  CropRect _startRect = CropRect.full;

  _Handle _hitTest(Offset pos, Size box) {
    final v = widget.value;
    final l = v.x * box.width, t = v.y * box.height;
    final r = (v.x + v.width) * box.width, b = (v.y + v.height) * box.height;
    final nearL = (pos.dx - l).abs() < _handleHit, nearR = (pos.dx - r).abs() < _handleHit;
    final nearT = (pos.dy - t).abs() < _handleHit, nearB = (pos.dy - b).abs() < _handleHit;
    final inX = pos.dx > l - _handleHit && pos.dx < r + _handleHit;
    final inY = pos.dy > t - _handleHit && pos.dy < b + _handleHit;
    if (nearT && nearL) return _Handle.nw;
    if (nearT && nearR) return _Handle.ne;
    if (nearB && nearL) return _Handle.sw;
    if (nearB && nearR) return _Handle.se;
    // Edges only when the frame is big enough that moving stays possible.
    final roomy = (r - l) > _handleHit * 3 && (b - t) > _handleHit * 3;
    if (inX && nearT && roomy) return _Handle.n;
    if (inX && nearB && roomy) return _Handle.s;
    if (inY && nearL && roomy) return _Handle.w;
    if (inY && nearR && roomy) return _Handle.e;
    return _Handle.move;
  }

  void _update(Offset pos, Size box) {
    final handle = _handle;
    if (handle == null || box.width <= 0 || box.height <= 0) return;
    final dx = (pos.dx - _start.dx) / box.width;
    final dy = (pos.dy - _start.dy) / box.height;
    final s = _startRect;

    if (handle == _Handle.move) {
      widget.onChanged(s.copyWith(x: _clamp(s.x + dx, 0, 1 - s.width), y: _clamp(s.y + dy, 0, 1 - s.height)));
      return;
    }
    var left = s.x, top = s.y, right = s.x + s.width, bottom = s.y + s.height;
    if (handle.hasW) left = _clamp(left + dx, 0, right - _minFraction);
    if (handle.hasE) right = _clamp(right + dx, left + _minFraction, 1);
    if (handle.hasN) top = _clamp(top + dy, 0, bottom - _minFraction);
    if (handle.hasS) bottom = _clamp(bottom + dy, top + _minFraction, 1);
    var next = CropRect(x: left, y: top, width: right - left, height: bottom - top);
    final ratio = widget.ratio;
    if (ratio != null) next = _fitRatio(next, handle, ratio * widget.naturalH / widget.naturalW);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(builder: (context, c) {
        final scale = math.min(c.maxWidth / widget.naturalW, c.maxHeight / widget.naturalH);
        final box = Size(math.max(1, widget.naturalW * scale), math.max(1, widget.naturalH * scale));
        final v = widget.value;
        final frame = Rect.fromLTWH(v.x * box.width, v.y * box.height, v.width * box.width, v.height * box.height);
        return Center(
          child: SizedBox.fromSize(
            size: box,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) {
                _handle = _hitTest(d.localPosition, box);
                _start = d.localPosition;
                _startRect = widget.value;
              },
              onPanUpdate: (d) => _update(d.localPosition, box),
              onPanEnd: (_) => _handle = null,
              onPanCancel: () => _handle = null,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: Image(image: widget.image, fit: BoxFit.fill, gaplessPlayback: true)),
                Positioned.fill(child: CustomPaint(painter: _FramePainter(frame))),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

class _FramePainter extends CustomPainter {
  final Rect frame;
  _FramePainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    // Dim outside the frame (image overlay — fixed colours are fine here).
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(frame);
    canvas.drawPath(outside, dim);

    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(frame, border);

    // Rule-of-thirds guides.
    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = frame.left + frame.width * i / 3;
      final y = frame.top + frame.height * i / 3;
      canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), guide);
      canvas.drawLine(Offset(frame.left, y), Offset(frame.right, y), guide);
    }

    // Handles.
    final fill = Paint()..color = Colors.white;
    final edge = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final points = [
      frame.topLeft, frame.topCenter, frame.topRight, frame.centerRight,
      frame.bottomRight, frame.bottomCenter, frame.bottomLeft, frame.centerLeft,
    ];
    for (final pt in points) {
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: pt, width: 14, height: 14), const Radius.circular(3));
      canvas.drawRRect(r, fill);
      canvas.drawRRect(r, edge);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.frame != frame;
}
