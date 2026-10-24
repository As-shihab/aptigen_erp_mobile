import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/label_model.dart';
import 'lab_widgets.dart';

typedef LabEdit = void Function(VoidCallback mutate, {bool debounce});

/// Contextual property panel for the selected element — lives inside the
/// designer's draggable bottom sheet ([scrollController] comes from it).
class ElementPanel extends StatelessWidget {
  final LabelElement element;
  final LabelDesign design;
  final Map<String, String> data;
  final ScrollController scrollController;
  final LabEdit onEdit;
  final ValueChanged<String> onAction;
  final ValueChanged<String> onPickImage; // gallery | camera | media | clear
  final VoidCallback onClose;

  const ElementPanel({
    super.key,
    required this.element,
    required this.design,
    required this.data,
    required this.scrollController,
    required this.onEdit,
    required this.onAction,
    required this.onPickImage,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final e = element;
    final error = e.codeError(data);
    final sub = switch (e.type) {
      LabelElementType.barcode || LabelElementType.qr => '${e.symbology.label} · ${MmBox.fmt(e.w)} × ${MmBox.fmt(e.h)} mm',
      _ => '${MmBox.fmt(e.w)} × ${MmBox.fmt(e.h)} mm',
    };

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        const SheetGrabber(),
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(labelElementIcon(e.type), size: 20, color: p.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.type.label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
              Text(sub, style: TextStyle(fontSize: 12, color: p.label)),
            ]),
          ),
          IconButton(tooltip: 'Done', onPressed: onClose, icon: Icon(Icons.close_rounded, color: p.label)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 62,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            LabTool(icon: Icons.copy_all_outlined, label: 'Duplicate', onTap: () => onAction('duplicate')),
            LabTool(icon: Icons.rotate_90_degrees_cw_outlined, label: 'Rotate', onTap: e.locked ? null : () => onAction('rotate')),
            LabTool(icon: Icons.flip_to_front_outlined, label: 'Forward', onTap: () => onAction('forward')),
            LabTool(icon: Icons.flip_to_back_outlined, label: 'Backward', onTap: () => onAction('backward')),
            LabTool(icon: e.locked ? Icons.lock_outline : Icons.lock_open_outlined, label: e.locked ? 'Unlock' : 'Lock', active: e.locked, onTap: () => onAction('lock')),
            LabTool(icon: Icons.delete_outline, label: 'Delete', destructive: true, onTap: () => onAction('delete')),
          ]),
        ),
        const SizedBox(height: 8),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: error == null
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: p.errorBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.error.withValues(alpha: 0.35))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.error_outline, size: 18, color: p.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(error, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.error)),
                        const SizedBox(height: 2),
                        Text('${e.symbology.label}: ${e.symbology.hint}', style: TextStyle(fontSize: 11.5, color: p.label)),
                      ]),
                    ),
                  ]),
                ),
        ),
        ..._typeGroups(context),
        _geometry(context),
      ],
    );
  }

  List<Widget> _typeGroups(BuildContext context) {
    final e = element;
    switch (e.type) {
      case LabelElementType.barcode:
      case LabelElementType.qr:
        return [_codeGroup(context)];
      case LabelElementType.text:
        return [
          LabGroup(title: 'Text', children: [
            _ContentEditor(
              key: ValueKey('content-${e.id}'),
              value: e.content,
              hint: 'Type text, add fields below',
              multiline: true,
              onChanged: (v) => onEdit(() => e.content = v, debounce: true),
            ),
          ]),
          _typeStyle(context, withSize: true),
        ];
      case LabelElementType.price:
        return [_priceGroup(context), _typeStyle(context, withSize: true)];
      case LabelElementType.date:
        return [_dateGroup(context), _typeStyle(context, withSize: true)];
      case LabelElementType.image:
        return [_imageGroup(context)];
      case LabelElementType.line:
        return [
          LabGroup(title: 'Line', children: [
            LabChoice<bool>(
              label: 'Direction',
              value: e.vertical,
              options: const [(false, 'Horizontal'), (true, 'Vertical')],
              onChanged: (v) => onEdit(() {
                if (v == e.vertical) return;
                final cx = e.cx, cy = e.cy;
                e.vertical = v;
                final len = v ? e.w : e.h;
                final thick = v ? e.h : e.w;
                e
                  ..w = v ? thick : len
                  ..h = v ? len : thick
                  ..x = cx - e.w / 2
                  ..y = cy - e.h / 2;
              }),
            ),
            LabSlider(
              label: 'Thickness',
              value: e.stroke,
              min: 0.1,
              max: 3,
              divisions: 29,
              format: (v) => '${v.toStringAsFixed(1)} mm',
              onChanged: (v) => onEdit(() => e.stroke = v, debounce: true),
            ),
          ]),
        ];
      case LabelElementType.rect:
      case LabelElementType.ellipse:
        return [
          LabGroup(title: e.type == LabelElementType.rect ? 'Rectangle' : 'Ellipse', children: [
            LabChoice<bool>(
              label: 'Style',
              value: e.fill,
              options: const [(false, 'Outline'), (true, 'Filled')],
              onChanged: (v) => onEdit(() => e.fill = v),
            ),
            if (!e.fill)
              LabSlider(
                label: 'Outline',
                value: e.stroke,
                min: 0.1,
                max: 3,
                divisions: 29,
                format: (v) => '${v.toStringAsFixed(1)} mm',
                onChanged: (v) => onEdit(() => e.stroke = v, debounce: true),
              ),
            if (e.type == LabelElementType.rect)
              LabSlider(
                label: 'Corner radius',
                value: e.radius,
                min: 0,
                max: 10,
                divisions: 20,
                format: (v) => '${v.toStringAsFixed(1)} mm',
                onChanged: (v) => onEdit(() => e.radius = v, debounce: true),
              ),
          ]),
        ];
    }
  }

  Widget _codeGroup(BuildContext context) {
    final e = element;
    final options = e.type == LabelElementType.qr ? kTwoDSymbologies : [...kOneDSymbologies, ...kTwoDSymbologies];
    return LabGroup(title: e.type == LabelElementType.qr ? '2D code' : 'Barcode', children: [
      FormLabel(
        label: 'Symbology',
        child: PickerField(
          value: e.symbology.name,
          allowClear: false,
          icon: labelElementIcon(e.type),
          options: [for (final s in options) PickOption(s.name, s.label, sub: s.hint)],
          onChanged: (v) {
            final next = LabelSymbology.values.where((s) => s.name == v);
            if (next.isEmpty) return;
            onEdit(() {
              final was2D = e.symbology.isSquare;
              e.symbology = next.first;
              if (e.symbology.isSquare && !was2D) {
                final side = e.h < e.w ? e.h : e.w;
                e
                  ..w = side
                  ..h = side;
              }
            });
          },
        ),
      ),
      FormLabel(
        label: 'Data',
        help: 'Static value or a field such as {barcode}',
        child: _ContentEditor(
          key: ValueKey('code-${e.id}'),
          value: e.content,
          hint: e.symbology.hint,
          onChanged: (v) => onEdit(() => e.content = v, debounce: true),
        ),
      ),
      if (!e.symbology.is2D) ...[
        LabSwitch(label: 'Human readable text', sub: 'Prints the value under the bars', value: e.showHumanText, onChanged: (v) => onEdit(() => e.showHumanText = v)),
        if (e.showHumanText)
          LabSlider(
            label: 'Text size',
            value: e.humanTextSize,
            min: 4,
            max: 24,
            divisions: 40,
            format: (v) => '${v.toStringAsFixed(1)} pt',
            onChanged: (v) => onEdit(() => e.humanTextSize = v, debounce: true),
          ),
      ],
      if (e.symbology.hasErrorLevel)
        LabChoice<String>(
          label: 'Error correction',
          value: e.ecLevel,
          options: const [('L', 'Low'), ('M', 'Medium'), ('Q', 'Quartile'), ('H', 'High')],
          onChanged: (v) => onEdit(() => e.ecLevel = v),
        ),
    ]);
  }

  Widget _priceGroup(BuildContext context) {
    final e = element;
    return LabGroup(title: 'Price', children: [
      LabChoice<String>(
        label: 'Amount',
        value: e.priceField,
        options: const [('price', 'Price'), ('mrp', 'MRP / old'), ('custom', 'Custom')],
        onChanged: (v) => onEdit(() => e.priceField = v),
      ),
      if (e.priceField == 'custom')
        FormLabel(
          label: 'Custom amount',
          child: SyncedField(key: ValueKey('amt-${e.id}'), value: e.content, hint: 'e.g. 99.50', onChanged: (v) => onEdit(() => e.content = v, debounce: true)),
        ),
      LabChoice<String>(
        label: 'Currency',
        value: e.currencyStyle,
        options: const [('symbol', 'Symbol'), ('code', 'Code'), ('none', 'None')],
        onChanged: (v) => onEdit(() => e.currencyStyle = v),
      ),
      LabChoice<int>(
        label: 'Decimals',
        value: e.decimals,
        options: const [(0, 'None'), (2, 'Two')],
        onChanged: (v) => onEdit(() => e.decimals = v),
      ),
      LabSwitch(label: 'Strike through', sub: 'Use for the old price', value: e.strike, onChanged: (v) => onEdit(() => e.strike = v)),
    ]);
  }

  Widget _dateGroup(BuildContext context) {
    final e = element;
    return LabGroup(title: 'Date stamp', children: [
      FormLabel(
        label: 'Text before the date',
        child: SyncedField(key: ValueKey('pre-${e.id}'), value: e.content, hint: 'e.g. Packed: ', onChanged: (v) => onEdit(() => e.content = v, debounce: true)),
      ),
      FormLabel(
        label: 'Format',
        child: PickerField(
          value: kDateFormats.contains(e.dateFormat) ? e.dateFormat : null,
          allowClear: false,
          hint: e.dateFormat,
          icon: Icons.event_outlined,
          options: [for (final f in kDateFormats) PickOption(f, f, sub: _sampleDate(f))],
          onChanged: (v) {
            if (v is String) onEdit(() => e.dateFormat = v);
          },
        ),
      ),
      FormLabel(
        label: 'Custom format',
        help: 'Pattern letters: d, M, y, H, m',
        child: SyncedField(key: ValueKey('fmt-${e.id}'), value: e.dateFormat, hint: 'd MMM yyyy', onChanged: (v) => onEdit(() => e.dateFormat = v, debounce: true)),
      ),
      LabRow(
        label: 'Offset',
        sub: 'Days from today, e.g. best before',
        child: LabStepper(value: e.dateOffsetDays, min: -999, max: 3650, onChanged: (v) => onEdit(() => e.dateOffsetDays = v, debounce: true)),
      ),
    ]);
  }

  static String _sampleDate(String f) {
    try {
      return DateFormat(f).format(DateTime.now());
    } catch (_) {
      return '';
    }
  }

  Widget _imageGroup(BuildContext context) {
    final p = MarketPalette.of(context);
    final e = element;
    Widget src(IconData icon, String label, String key) => Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: p.brand,
              side: BorderSide(color: p.line),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => onPickImage(key),
            icon: Icon(icon, size: 18),
            label: Text(label, style: const TextStyle(fontSize: 12.5)),
          ),
        );
    return LabGroup(title: 'Image', children: [
      Row(children: [
        src(Icons.photo_library_outlined, 'Gallery', 'gallery'),
        const SizedBox(width: 8),
        src(Icons.photo_camera_outlined, 'Camera', 'camera'),
        const SizedBox(width: 8),
        src(Icons.perm_media_outlined, 'Library', 'media'),
      ]),
      const SizedBox(height: 12),
      if (e.imageB64 != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: () => onPickImage('clear'), icon: Icon(Icons.hide_image_outlined, size: 18, color: p.error), label: Text('Remove image', style: TextStyle(color: p.error))),
        ),
      LabChoice<String>(
        label: 'Fit',
        value: e.fit,
        options: const [('contain', 'Contain'), ('cover', 'Cover'), ('fill', 'Stretch')],
        onChanged: (v) => onEdit(() => e.fit = v),
      ),
      LabSwitch(label: 'Grayscale', sub: 'Closer to how it prints', value: e.grayscale, onChanged: (v) => onEdit(() => e.grayscale = v)),
    ]);
  }

  Widget _typeStyle(BuildContext context, {bool withSize = true}) {
    final e = element;
    return LabGroup(title: 'Style', children: [
      if (!e.autoFit)
        LabSlider(
          label: 'Font size',
          value: e.fontSize,
          min: 4,
          max: 96,
          divisions: 184,
          format: (v) => '${v.toStringAsFixed(1)} pt',
          onChanged: (v) => onEdit(() => e.fontSize = v, debounce: true),
        ),
      LabSwitch(label: 'Auto fit', sub: 'Largest size that fits the box', value: e.autoFit, onChanged: (v) => onEdit(() => e.autoFit = v)),
      LabChoice<String>(
        label: 'Alignment',
        value: e.align,
        options: const [('left', 'Left'), ('center', 'Center'), ('right', 'Right')],
        onChanged: (v) => onEdit(() => e.align = v),
      ),
      Row(children: [
        Expanded(child: _toggle(context, Icons.format_bold, 'Bold', e.bold, () => onEdit(() => e.bold = !e.bold))),
        const SizedBox(width: 8),
        Expanded(child: _toggle(context, Icons.format_italic, 'Italic', e.italic, () => onEdit(() => e.italic = !e.italic))),
        const SizedBox(width: 8),
        Expanded(child: _toggle(context, Icons.invert_colors_outlined, 'Invert', e.invert, () => onEdit(() => e.invert = !e.invert))),
      ]),
      const SizedBox(height: 12),
      LabRow(
        label: 'Max lines',
        sub: e.maxLines == 0 ? 'Unlimited' : null,
        child: LabStepper(value: e.maxLines, min: 0, max: 20, format: (v) => v == 0 ? '∞' : '$v', onChanged: (v) => onEdit(() => e.maxLines = v)),
      ),
    ]);
  }

  Widget _toggle(BuildContext context, IconData icon, String label, bool on, VoidCallback onTap) {
    final p = MarketPalette.of(context);
    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: on ? p.brandSoft : p.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? p.brand.withValues(alpha: 0.5) : p.line),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: on ? p.brand : p.label),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? p.brand : p.text)),
        ]),
      ),
    );
  }

  Widget _geometry(BuildContext context) {
    final p = MarketPalette.of(context);
    final e = element;
    final enabled = !e.locked;
    Widget align(IconData icon, String key, String tip) => Expanded(
          child: Tooltip(
            message: tip,
            child: PressScale(
              onTap: enabled ? () => onAction(key) : null,
              child: Container(
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(9), border: Border.all(color: p.line)),
                child: Icon(icon, size: 19, color: enabled ? p.text : p.line),
              ),
            ),
          ),
        );
    return LabGroup(title: 'Position and size', children: [
      Row(children: [
        Expanded(child: MmBox(key: ValueKey('x-${e.id}'), label: 'X mm', value: e.x, enabled: enabled, onChanged: (v) => onEdit(() => e.x = v, debounce: true))),
        const SizedBox(width: 8),
        Expanded(child: MmBox(key: ValueKey('y-${e.id}'), label: 'Y mm', value: e.y, enabled: enabled, onChanged: (v) => onEdit(() => e.y = v, debounce: true))),
        const SizedBox(width: 8),
        Expanded(child: MmBox(key: ValueKey('w-${e.id}'), label: 'Width', value: e.w, enabled: enabled, onChanged: (v) => onEdit(() => e.w = v.clamp(0.5, 400).toDouble(), debounce: true))),
        const SizedBox(width: 8),
        Expanded(child: MmBox(key: ValueKey('h-${e.id}'), label: 'Height', value: e.h, enabled: enabled, onChanged: (v) => onEdit(() => e.h = v.clamp(0.5, 400).toDouble(), debounce: true))),
      ]),
      const SizedBox(height: 12),
      Text('Align to label', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.label)),
      const SizedBox(height: 6),
      Row(children: [
        align(Icons.align_horizontal_left, 'align_left', 'Left'),
        align(Icons.align_horizontal_center, 'align_hcenter', 'Center'),
        align(Icons.align_horizontal_right, 'align_right', 'Right'),
        align(Icons.align_vertical_top, 'align_top', 'Top'),
        align(Icons.align_vertical_center, 'align_vcenter', 'Middle'),
        align(Icons.align_vertical_bottom, 'align_bottom', 'Bottom'),
      ]),
      const SizedBox(height: 12),
      LabRow(label: 'Rotation', child: Text('${e.rotation}°', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text))),
    ]);
  }
}

/// Content text field with merge-field chips that insert at the cursor.
class _ContentEditor extends StatefulWidget {
  final String value;
  final String hint;
  final bool multiline;
  final ValueChanged<String> onChanged;
  const _ContentEditor({super.key, required this.value, required this.hint, required this.onChanged, this.multiline = false});

  @override
  State<_ContentEditor> createState() => _ContentEditorState();
}

class _ContentEditorState extends State<_ContentEditor> {
  late final TextEditingController _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _insert(String key) {
    final token = '{$key}';
    final sel = _c.selection;
    final text = _c.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final next = text.replaceRange(start, end, token);
    _c.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + token.length));
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SyncedField(controller: _c, value: widget.value, hint: widget.hint, maxLines: widget.multiline ? 4 : 1, onChanged: widget.onChanged),
      const SizedBox(height: 8),
      SizedBox(
        height: 32,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final f in kLabelMergeFields)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PressScale(
                onTap: () => _insert(f.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.line)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add, size: 14, color: p.brand),
                    const SizedBox(width: 4),
                    Text(f.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
    ]);
  }
}
