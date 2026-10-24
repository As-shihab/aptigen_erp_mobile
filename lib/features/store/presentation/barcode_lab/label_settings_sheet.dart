import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/label_model.dart';
import 'element_panel.dart' show LabEdit;
import 'lab_widgets.dart';

/// Resizes the label, optionally scaling every element with it.
void resizeLabel(LabelDesign d, double w, double h, {bool scaleContent = true}) {
  w = w.clamp(5, 300).toDouble();
  h = h.clamp(5, 400).toDouble();
  if (scaleContent && d.widthMm > 0 && d.heightMm > 0) {
    final kx = w / d.widthMm;
    final ky = h / d.heightMm;
    final k = math.min(kx, ky);
    for (final e in d.elements) {
      e
        ..x *= kx
        ..y *= ky
        ..w *= kx
        ..h *= ky
        ..fontSize = (e.fontSize * k).clamp(3, 200).toDouble()
        ..humanTextSize = (e.humanTextSize * k).clamp(3, 60).toDouble();
      if (e.type.isCode && e.symbology.isSquare || e.type == LabelElementType.ellipse && (e.w - e.h).abs() < 0.01) {
        final side = math.min(e.w, e.h);
        e
          ..x += (e.w - side) / 2
          ..y += (e.h - side) / 2
          ..w = side
          ..h = side;
      }
    }
  }
  d
    ..widthMm = w
    ..heightMm = h;
}

Future<void> showLabelSettingsSheet(
  BuildContext context, {
  required LabelDesign design,
  required LabEdit onEdit,
  required double gridMm,
  required ValueChanged<double> onGridMm,
}) {
  return showMotionSheet<void>(context, (_) => _LabelSettingsSheet(design: design, onEdit: onEdit, gridMm: gridMm, onGridMm: onGridMm));
}

class _LabelSettingsSheet extends StatefulWidget {
  final LabelDesign design;
  final LabEdit onEdit;
  final double gridMm;
  final ValueChanged<double> onGridMm;
  const _LabelSettingsSheet({required this.design, required this.onEdit, required this.gridMm, required this.onGridMm});

  @override
  State<_LabelSettingsSheet> createState() => _LabelSettingsSheetState();
}

class _LabelSettingsSheetState extends State<_LabelSettingsSheet> {
  bool _scale = true;
  late double _grid = widget.gridMm;

  LabelDesign get d => widget.design;

  void _edit(VoidCallback fn, {bool debounce = false}) {
    widget.onEdit(fn, debounce: debounce);
    setState(() {});
  }

  void _preset(LabelPreset p) => _edit(() {
        // Keep the current orientation when switching presets.
        var w = p.w, h = p.h;
        if (!p.roll && d.landscape != (w >= h)) {
          final t = w;
          w = h;
          h = t;
        }
        resizeLabel(d, w, h, scaleContent: _scale);
        d.presetId = p.id;
      });

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return FormSheet(
      title: 'Label settings',
      subtitle: '${d.sizeLabel} · ${d.dpi} dpi',
      children: [
        LabGroup(title: 'Size', children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final preset in kLabelPresets) LabChip(icon: preset.roll ? Icons.receipt_long_outlined : Icons.crop_7_5_outlined, label: preset.label, active: d.presetId == preset.id, onTap: () => _preset(preset)),
            LabChip(icon: Icons.tune_rounded, label: 'Custom', active: d.presetId == 'custom', onTap: () => _edit(() => d.presetId = 'custom')),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: MmBox(
                key: const ValueKey('label-w'),
                label: 'Width mm',
                value: d.widthMm,
                onChanged: (v) {
                  if (v < 5 || v > 300) return;
                  _edit(() {
                    resizeLabel(d, v, d.heightMm, scaleContent: _scale);
                    d.presetId = 'custom';
                  }, debounce: true);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MmBox(
                key: const ValueKey('label-h'),
                label: 'Height mm',
                value: d.heightMm,
                onChanged: (v) {
                  if (v < 5 || v > 400) return;
                  _edit(() {
                    resizeLabel(d, d.widthMm, v, scaleContent: _scale);
                    d.presetId = d.presetId.startsWith('roll') ? d.presetId : 'custom';
                  }, debounce: true);
                },
              ),
            ),
          ]),
          const SizedBox(height: 10),
          LabSwitch(label: 'Scale elements with label', sub: 'Keeps the layout when the size changes', value: _scale, onChanged: (v) => setState(() => _scale = v)),
          LabChoice<bool>(
            label: 'Orientation',
            value: d.landscape,
            options: const [(false, 'Portrait'), (true, 'Landscape')],
            onChanged: (v) {
              if (v == d.landscape) return;
              _edit(() => resizeLabel(d, d.heightMm, d.widthMm, scaleContent: _scale));
            },
          ),
        ]),
        LabGroup(title: 'Look', children: [
          LabChoice<bool>(
            label: 'Background',
            value: d.blackBackground,
            options: const [(false, 'White'), (true, 'Black')],
            onChanged: (v) => _edit(() => d.blackBackground = v),
          ),
          LabSwitch(label: 'Border', sub: 'Outline around the label', value: d.border, onChanged: (v) => _edit(() => d.border = v)),
          LabSlider(
            label: 'Corner radius',
            value: d.cornerRadiusMm,
            min: 0,
            max: 8,
            divisions: 16,
            format: (v) => '${v.toStringAsFixed(1)} mm',
            onChanged: (v) => _edit(() => d.cornerRadiusMm = v, debounce: true),
          ),
        ]),
        LabGroup(title: 'Printing', children: [
          LabChoice<int>(
            label: 'Print resolution',
            value: d.dpi,
            options: const [(203, '203 dpi'), (300, '300 dpi')],
            onChanged: (v) => _edit(() => d.dpi = v),
          ),
          LabSlider(
            label: 'Gap between labels',
            value: d.gapMm,
            min: 0,
            max: 15,
            divisions: 30,
            format: (v) => '${v.toStringAsFixed(1)} mm',
            onChanged: (v) => _edit(() => d.gapMm = v, debounce: true),
          ),
          Text(
            '${d.dots(d.widthMm)} × ${d.dots(d.heightMm)} dots at ${d.dpi} dpi',
            style: TextStyle(fontSize: 12, color: p.label),
          ),
          const SizedBox(height: 10),
        ]),
        LabGroup(title: 'Designer', children: [
          LabChoice<double>(
            label: 'Grid step',
            value: _grid,
            options: const [(0.5, '0.5 mm'), (1.0, '1 mm'), (2.0, '2 mm'), (5.0, '5 mm')],
            onChanged: (v) {
              setState(() => _grid = v);
              widget.onGridMm(v);
            },
          ),
        ]),
      ],
    );
  }
}
