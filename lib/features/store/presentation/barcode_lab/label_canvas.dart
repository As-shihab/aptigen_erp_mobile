import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/label_model.dart';
import '../../data/label_render.dart';

/// Interactive label canvas: fit-to-view preview with pinch zoom/pan, grid,
/// tap to select, drag to move, corner handles to resize, snapping to the
/// grid / label centre / other elements with animated guide lines.
///
/// Elements are edited in place (the model is mutable); [onLiveChange] asks
/// the parent to repaint during a drag and [onCommit] marks the end of one
/// undoable change.
class LabelCanvas extends StatefulWidget {
  final LabelDesign design;
  final Map<String, String> data;
  final String? selectedId;
  final bool showGrid;
  final bool snap;
  final double gridMm;
  final double bottomInset;
  final ValueChanged<String?> onSelect;
  final VoidCallback onLiveChange;
  final VoidCallback onCommit;

  const LabelCanvas({
    super.key,
    required this.design,
    required this.data,
    required this.selectedId,
    required this.showGrid,
    required this.snap,
    required this.gridMm,
    required this.onSelect,
    required this.onLiveChange,
    required this.onCommit,
    this.bottomInset = 0,
  });

  @override
  State<LabelCanvas> createState() => _LabelCanvasState();
}

enum _Mode { none, move, resize, pan, zoom }

class _Guide {
  final bool vertical; // vertical line at x = mm, else horizontal at y = mm
  final double mm;
  const _Guide(this.vertical, this.mm);
}

class _LabelCanvasState extends State<LabelCanvas> with TickerProviderStateMixin {
  double _zoom = 1;
  Offset _pan = Offset.zero;
  double _scale = 1;
  Offset _origin = Offset.zero;

  _Mode _mode = _Mode.none;
  Offset _startFocal = Offset.zero;
  Rect _startRect = Rect.zero; // mm
  int _corner = 0;
  double _startZoom = 1;
  Offset _startPan = Offset.zero;
  bool _moved = false;
  String? _activeId; // element being moved/resized (selection may not have rebuilt yet)
  Offset? _downPos; // first pointer down — the scale recognizer starts after the touch slop

  List<_Guide> _guides = const [];
  late final AnimationController _guideAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 160), reverseDuration: const Duration(milliseconds: 260));
  late final AnimationController _selAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));

  LabelDesign get d => widget.design;
  LabelElement? get _sel => d.byId(widget.selectedId);

  @override
  void initState() {
    super.initState();
    if (widget.selectedId != null) _selAnim.value = 1;
  }

  @override
  void didUpdateWidget(covariant LabelCanvas old) {
    super.didUpdateWidget(old);
    if (old.selectedId != widget.selectedId && widget.selectedId != null) _selAnim.forward(from: 0);
    if (old.design.widthMm != widget.design.widthMm || old.design.heightMm != widget.design.heightMm) {
      _zoom = 1;
      _pan = Offset.zero;
    }
  }

  @override
  void dispose() {
    _guideAnim.dispose();
    _selAnim.dispose();
    super.dispose();
  }

  Offset _toMm(Offset local) => (local - _origin) / _scale;

  LabelElement? _hitElement(Offset local) {
    final mm = _toMm(local);
    final slop = 6 / _scale;
    for (final e in d.elements.reversed) {
      final r = Rect.fromLTWH(e.x, e.y, e.w, e.h).inflate(slop);
      if (r.contains(mm)) return e;
    }
    return null;
  }

  int? _hitHandle(Offset local) {
    final e = _sel;
    if (e == null || e.locked) return null;
    final corners = _corners(e);
    for (var i = 0; i < 4; i++) {
      if ((corners[i] - local).distance <= 20) return i;
    }
    return null;
  }

  List<Offset> _corners(LabelElement e) {
    final r = Rect.fromLTWH(_origin.dx + e.x * _scale, _origin.dy + e.y * _scale, e.w * _scale, e.h * _scale);
    return [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
  }

  // ── Snapping ──────────────────────────────────────────────────────────

  /// Snap candidate lines on one axis: label edges + centre, other elements'
  /// edges + centres.
  List<double> _targets(bool xAxis, String exceptId) {
    final size = xAxis ? d.widthMm : d.heightMm;
    final out = <double>[0, size / 2, size];
    for (final o in d.elements) {
      if (o.id == exceptId) continue;
      if (xAxis) {
        out.addAll([o.x, o.cx, o.x + o.w]);
      } else {
        out.addAll([o.y, o.cy, o.y + o.h]);
      }
    }
    return out;
  }

  /// Best shift (mm) bringing one of [edges] onto a target, plus the target.
  (double, double)? _bestSnap(List<double> edges, List<double> targets) {
    final thr = 7 / _scale;
    (double, double)? best;
    for (final edge in edges) {
      for (final t in targets) {
        final diff = t - edge;
        if (diff.abs() <= thr && (best == null || diff.abs() < best.$1.abs())) best = (diff, t);
      }
    }
    return best;
  }

  double _grid(double v) => widget.gridMm <= 0 ? v : (v / widget.gridMm).roundToDouble() * widget.gridMm;

  void _setGuides(List<_Guide> g) {
    _guides = g;
    if (g.isNotEmpty) {
      _guideAnim.forward();
    } else if (_guideAnim.status != AnimationStatus.dismissed) {
      _guideAnim.reverse();
    }
  }

  void _applyMove(LabelElement e, Offset deltaMm) {
    var x = _startRect.left + deltaMm.dx;
    var y = _startRect.top + deltaMm.dy;
    final guides = <_Guide>[];
    if (widget.snap) {
      final sx = _bestSnap([x, x + e.w / 2, x + e.w], _targets(true, e.id));
      if (sx != null) {
        x += sx.$1;
        guides.add(_Guide(true, sx.$2));
      } else if (widget.showGrid) {
        x = _grid(x);
      }
      final sy = _bestSnap([y, y + e.h / 2, y + e.h], _targets(false, e.id));
      if (sy != null) {
        y += sy.$1;
        guides.add(_Guide(false, sy.$2));
      } else if (widget.showGrid) {
        y = _grid(y);
      }
    }
    e
      ..x = x.clamp(-e.w + 1, d.widthMm - 1).toDouble()
      ..y = y.clamp(-e.h + 1, d.heightMm - 1).toDouble();
    _setGuides(guides);
  }

  void _applyResize(LabelElement e, Offset deltaMm) {
    final r = _startRect;
    final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
    final fixed = corners[(_corner + 2) % 4];
    var moving = corners[_corner] + deltaMm;
    final guides = <_Guide>[];
    if (widget.snap) {
      final sx = _bestSnap([moving.dx], _targets(true, e.id));
      final sy = _bestSnap([moving.dy], _targets(false, e.id));
      var mx = moving.dx, my = moving.dy;
      if (sx != null) {
        mx += sx.$1;
        guides.add(_Guide(true, sx.$2));
      } else if (widget.showGrid) {
        mx = _grid(mx);
      }
      if (sy != null) {
        my += sy.$1;
        guides.add(_Guide(false, sy.$2));
      } else if (widget.showGrid) {
        my = _grid(my);
      }
      moving = Offset(mx, my);
    }
    final minW = e.type == LabelElementType.line && e.vertical ? 0.5 : 1.0;
    final minH = e.type == LabelElementType.line && !e.vertical ? 0.5 : 1.0;
    var left = math.min(fixed.dx, moving.dx);
    var top = math.min(fixed.dy, moving.dy);
    var w = (fixed.dx - moving.dx).abs();
    var h = (fixed.dy - moving.dy).abs();
    if (w < minW) {
      if (moving.dx < fixed.dx) left = fixed.dx - minW;
      w = minW;
    }
    if (h < minH) {
      if (moving.dy < fixed.dy) top = fixed.dy - minH;
      h = minH;
    }
    e
      ..x = left
      ..y = top
      ..w = w
      ..h = h;
    _setGuides(guides);
  }

  // ── Gestures ──────────────────────────────────────────────────────────

  void _onTapUp(TapUpDetails details) {
    final hit = _hitElement(details.localPosition);
    widget.onSelect(hit?.id);
  }

  void _onScaleStart(ScaleStartDetails details) {
    final at = details.pointerCount == 1 && _downPos != null ? _downPos! : details.localFocalPoint;
    _startFocal = at;
    _moved = false;
    if (details.pointerCount >= 2) {
      _mode = _Mode.zoom;
      _startZoom = _zoom;
      _startPan = _pan;
      _setGuides(const []);
      return;
    }
    final handle = _hitHandle(at);
    final sel = _sel;
    if (handle != null && sel != null) {
      _mode = _Mode.resize;
      _activeId = sel.id;
      _corner = handle;
      _startRect = Rect.fromLTWH(sel.x, sel.y, sel.w, sel.h);
      return;
    }
    final hit = _hitElement(at);
    if (hit != null) {
      if (hit.id != widget.selectedId) widget.onSelect(hit.id);
      if (hit.locked) {
        _mode = _Mode.none;
        return;
      }
      _mode = _Mode.move;
      _activeId = hit.id;
      _startRect = Rect.fromLTWH(hit.x, hit.y, hit.w, hit.h);
      return;
    }
    _mode = _Mode.pan;
    _startPan = _pan;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final delta = details.localFocalPoint - _startFocal;
    if (details.pointerCount >= 2 && _mode != _Mode.zoom) {
      _mode = _Mode.zoom;
      _startZoom = _zoom;
      _startPan = _pan;
      _startFocal = details.localFocalPoint;
      return;
    }
    switch (_mode) {
      case _Mode.zoom:
        setState(() {
          _zoom = (_startZoom * details.scale).clamp(0.6, 8.0);
          _pan = _startPan + delta;
        });
      case _Mode.pan:
        if (_zoom > 1.01 || delta.distance > 4) setState(() => _pan = _startPan + delta);
      case _Mode.move:
        final e = d.byId(_activeId);
        if (e == null) return;
        if (!_moved && delta.distance < 2) return;
        _moved = true;
        _applyMove(e, delta / _scale);
        widget.onLiveChange();
      case _Mode.resize:
        final e = d.byId(_activeId);
        if (e == null) return;
        _moved = true;
        _applyResize(e, delta / _scale);
        widget.onLiveChange();
      case _Mode.none:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if ((_mode == _Mode.move || _mode == _Mode.resize) && _moved) widget.onCommit();
    _mode = _Mode.none;
    _setGuides(const []);
    setState(() {});
  }

  void _resetView() => setState(() {
    _zoom = 1;
    _pan = Offset.zero;
  });

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return LayoutBuilder(
      builder: (context, cons) {
        return TweenAnimationBuilder<double>(
          tween: Tween(end: widget.bottomInset),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          builder: (context, inset, _) {
            final view = Size(cons.maxWidth, math.max(80, cons.maxHeight - inset));
            final fit = math.min((view.width - 40) / d.widthMm, (view.height - 40) / d.heightMm).clamp(0.5, 400.0);
            _scale = fit * _zoom;
            final ls = Size(d.widthMm * _scale, d.heightMm * _scale);
            _origin = Offset((view.width - ls.width) / 2, (view.height - ls.height) / 2) + _pan;
            return Listener(
              onPointerDown: (e) => _downPos = e.localPosition,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _onTapUp,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                child: ClipRect(
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: p.bg)),
                      Positioned(
                        left: _origin.dx,
                        top: _origin.dy,
                        width: ls.width,
                        height: ls.height,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(d.cornerRadiusMm * _scale),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: p.dark ? 0.45 : 0.10),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: CustomPaint(
                            painter: LabelPainter(design: d, data: widget.data, showErrors: true),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _OverlayPainter(
                              design: d,
                              selected: _sel,
                              scale: _scale,
                              origin: _origin,
                              showGrid: widget.showGrid,
                              gridMm: widget.gridMm,
                              guides: _guides,
                              guideAnim: _guideAnim,
                              selAnim: _selAnim,
                              brand: p.brand,
                              neutral: p.neutral,
                              dragInfo: _mode == _Mode.move || _mode == _Mode.resize ? _mode : null,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 10,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: (_zoom - 1).abs() > 0.02 || _pan != Offset.zero ? 1 : 0,
                          child: IgnorePointer(
                            ignoring: (_zoom - 1).abs() <= 0.02 && _pan == Offset.zero,
                            child: PressScale(
                              onTap: _resetView,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: p.card,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: p.line),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.fit_screen_outlined, size: 16, color: p.brand),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${(_zoom * 100).round()}%',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.text),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final LabelDesign design;
  final LabelElement? selected;
  final double scale;
  final Offset origin;
  final bool showGrid;
  final double gridMm;
  final List<_Guide> guides;
  final Animation<double> guideAnim;
  final Animation<double> selAnim;
  final Color brand;
  final Color neutral;
  final _Mode? dragInfo;

  _OverlayPainter({
    required this.design,
    required this.selected,
    required this.scale,
    required this.origin,
    required this.showGrid,
    required this.gridMm,
    required this.guides,
    required this.guideAnim,
    required this.selAnim,
    required this.brand,
    required this.neutral,
    required this.dragInfo,
  }) : super(repaint: Listenable.merge([guideAnim, selAnim]));

  static const _guideColor = Color(0xFFDF1278);

  @override
  void paint(Canvas canvas, Size size) {
    final label = Rect.fromLTWH(origin.dx, origin.dy, design.widthMm * scale, design.heightMm * scale);

    if (showGrid && gridMm > 0) {
      var step = gridMm;
      while (step * scale < 8) {
        step *= 2;
      }
      final minor = Paint()
        ..color = brand.withValues(alpha: 0.10)
        ..strokeWidth = 0.6;
      final major = Paint()
        ..color = brand.withValues(alpha: 0.20)
        ..strokeWidth = 0.8;
      canvas.save();
      canvas.clipRect(label);
      bool isMajor(double mm) => (mm / 10 - (mm / 10).roundToDouble()).abs() < 0.001;
      for (var i = 1; i * step < design.widthMm; i++) {
        final mm = i * step;
        final x = label.left + mm * scale;
        canvas.drawLine(Offset(x, label.top), Offset(x, label.bottom), isMajor(mm) ? major : minor);
      }
      for (var i = 1; i * step < design.heightMm; i++) {
        final mm = i * step;
        final y = label.top + mm * scale;
        canvas.drawLine(Offset(label.left, y), Offset(label.right, y), isMajor(mm) ? major : minor);
      }
      canvas.restore();
    }

    // Animated guides (fade in on snap, fade out when released).
    final ga = Curves.easeOut.transform(guideAnim.value);
    if (ga > 0 && guides.isNotEmpty) {
      final gp = Paint()
        ..color = _guideColor.withValues(alpha: 0.9 * ga)
        ..strokeWidth = 1;
      for (final g in guides) {
        if (g.vertical) {
          final x = label.left + g.mm * scale;
          _dashed(canvas, Offset(x, label.top - 12), Offset(x, label.bottom + 12), gp);
        } else {
          final y = label.top + g.mm * scale;
          _dashed(canvas, Offset(label.left - 12, y), Offset(label.right + 12, y), gp);
        }
      }
    }

    final e = selected;
    if (e == null) return;
    final t = Curves.easeOutCubic.transform(selAnim.value);
    final r = Rect.fromLTWH(origin.dx + e.x * scale, origin.dy + e.y * scale, e.w * scale, e.h * scale).inflate(1.5 + (1 - t) * 5);
    final color = e.locked ? neutral : brand;
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: t),
    );
    if (!e.locked) {
      final fill = Paint()..color = Colors.white.withValues(alpha: t);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withValues(alpha: t);
      for (final c in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]) {
        canvas.drawCircle(c, 6, fill);
        canvas.drawCircle(c, 6, stroke);
      }
    } else {
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(Icons.lock_outline.codePoint),
          style: TextStyle(
            fontSize: 14,
            fontFamily: Icons.lock_outline.fontFamily,
            color: color.withValues(alpha: t),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, r.topRight + const Offset(4, -16));
    }

    if (dragInfo != null) {
      String f(double v) => v.toStringAsFixed(1);
      final text = dragInfo == _Mode.resize ? '${f(e.w)} × ${f(e.h)} mm' : 'x ${f(e.x)}  y ${f(e.y)} mm';
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final pill = Rect.fromCenter(center: Offset(r.center.dx, r.top - 16), width: tp.width + 14, height: tp.height + 6);
      final shifted = pill.top < 2 ? pill.shift(Offset(0, r.height + 32)) : pill;
      canvas.drawRRect(RRect.fromRectAndRadius(shifted, const Radius.circular(10)), Paint()..color = const Color(0xE61D2D3E));
      tp.paint(canvas, Offset(shifted.left + 7, shifted.top + 3));
    }
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p) {
    const dash = 5.0, gap = 3.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final end = math.min(d + dash, total);
      c.drawLine(a + dir * d, a + dir * end, p);
      d = end + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) => true;
}
