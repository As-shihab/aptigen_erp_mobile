import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/label_model.dart';
import '../../data/label_render.dart';

// Small SAP Horizon building blocks shared by the Barcode lab screens.

/// Flat titled group inside sheets/pages.
class LabGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  const LabGroup({super.key, required this.title, required this.children, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text))),
            ?trailing,
          ]),
          const SizedBox(height: 10),
          ...children,
        ]),
      ),
    );
  }
}

/// Label + control on one row.
class LabRow extends StatelessWidget {
  final String label;
  final Widget child;
  final String? sub;
  const LabRow({super.key, required this.label, required this.child, this.sub});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
            if (sub != null) Text(sub!, style: TextStyle(fontSize: 11.5, color: p.label)),
          ]),
        ),
        const SizedBox(width: 10),
        child,
      ]),
    );
  }
}

class LabSwitch extends StatelessWidget {
  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  const LabSwitch({super.key, required this.label, this.sub, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => LabRow(label: label, sub: sub, child: Switch.adaptive(value: value, onChanged: onChanged));
}

/// Slider with a live value read-out.
class LabSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  const LabSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.format,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text))),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 140),
            child: Text(format(value), key: ValueKey(format(value)), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.brand)),
          ),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: p.brand,
            inactiveTrackColor: p.line,
            thumbColor: p.brand,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ]),
    );
  }
}

/// − value + stepper.
class LabStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String Function(int)? format;
  const LabStepper({super.key, required this.value, this.min = 0, this.max = 999, required this.onChanged, this.format});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    Widget btn(IconData icon, VoidCallback? on) => IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: on,
          icon: Icon(icon, size: 18, color: on == null ? p.line : p.brand),
        );
    return Container(
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.remove, value > min ? () => onChanged(value - 1) : null),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 34),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Text(format?.call(value) ?? '$value',
                key: ValueKey(value), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
          ),
        ),
        btn(Icons.add, value < max ? () => onChanged(value + 1) : null),
      ]),
    );
  }
}

/// Segmented choice with a label above it.
class LabChoice<T> extends StatelessWidget {
  final String? label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  const LabChoice({super.key, this.label, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (label != null) ...[
          Text(label!, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.label)),
          const SizedBox(height: 6),
        ],
        MarketSegmented<T>(
          value: value,
          options: [for (final o in options) (id: o.$1, label: o.$2, count: null)],
          onChanged: onChanged,
        ),
      ]),
    );
  }
}

/// Text field that follows an external value (e.g. changed by dragging on
/// the canvas) while not being edited.
class SyncedField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final IconData? icon;
  final bool numeric;
  final int maxLines;
  final String? suffixText;
  final TextEditingController? controller;
  const SyncedField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
    this.icon,
    this.numeric = false,
    this.maxLines = 1,
    this.suffixText,
    this.controller,
  });

  @override
  State<SyncedField> createState() => _SyncedFieldState();
}

class _SyncedFieldState extends State<SyncedField> {
  late final TextEditingController _c = widget.controller ?? TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.controller != null && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void didUpdateWidget(covariant SyncedField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return TextField(
      controller: _c,
      focusNode: _focus,
      maxLines: widget.maxLines,
      minLines: 1,
      keyboardType: widget.numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : (widget.maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      inputFormatters: widget.numeric ? [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))] : null,
      textCapitalization: TextCapitalization.none,
      style: TextStyle(fontSize: 14, color: p.text),
      decoration: motionInput(context, hint: widget.hint, icon: widget.icon).copyWith(suffixText: widget.suffixText),
      onChanged: widget.onChanged,
    );
  }
}

/// Small number box (mm) used for X / Y / W / H.
class MmBox extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;
  const MmBox({super.key, required this.label, required this.value, required this.onChanged, this.enabled = true});

  static String fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.label)),
      const SizedBox(height: 4),
      IgnorePointer(
        ignoring: !enabled,
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: SyncedField(
            value: fmt(value),
            numeric: true,
            onChanged: (t) {
              final v = double.tryParse(t.replaceAll(',', '.'));
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    ]);
  }
}

/// Icon + caption button for tool strips.
class LabTool extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final bool destructive;
  const LabTool({super.key, required this.icon, required this.label, this.onTap, this.active = false, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final fg = onTap == null ? p.line : (destructive ? p.error : (active ? p.brand : p.text));
    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 66,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? p.brandSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 21, color: destructive ? p.error : (active ? p.brand : (onTap == null ? p.line : p.label))),
          const SizedBox(height: 4),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
        ]),
      ),
    );
  }
}

/// Pill-shaped chip used in the designer's top strip.
class LabChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  const LabChip({super.key, required this.icon, required this.label, this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: active ? p.brandSoft : p.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: active ? p.brand.withValues(alpha: 0.5) : p.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: active ? p.brand : p.label),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: active ? p.brand : p.text)),
        ]),
      ),
    );
  }
}

/// Live thumbnail of a label design (always white/black, never themed).
class LabelThumb extends StatelessWidget {
  final LabelDesign design;
  final Map<String, String> data;
  final double maxHeight;
  const LabelThumb({super.key, required this.design, required this.data, this.maxHeight = 110});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return LayoutBuilder(builder: (context, c) {
      final maxW = c.maxWidth.isFinite ? c.maxWidth : 160.0;
      final scale = [maxW / design.widthMm, maxHeight / design.heightMm].reduce((a, b) => a < b ? a : b);
      final w = design.widthMm * scale;
      final h = design.heightMm * scale;
      return Center(
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(design.cornerRadiusMm * scale),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: p.dark ? 0.35 : 0.08), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: RepaintBoundary(child: CustomPaint(size: Size(w, h), painter: LabelPainter(design: design, data: data))),
        ),
      );
    });
  }
}

/// Single-line text prompt (rename, save as).
Future<String?> promptLabelName(BuildContext context, {required String title, String initial = '', String confirm = 'Save'}) async {
  final c = TextEditingController(text: initial);
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: motionInput(ctx, hint: 'Template name'),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(confirm)),
      ],
    ),
  );
  c.dispose();
  return (res == null || res.isEmpty) ? null : res;
}

IconData labelElementIcon(LabelElementType t) => switch (t) {
      LabelElementType.barcode => Icons.view_week_outlined,
      LabelElementType.qr => Icons.qr_code_2_outlined,
      LabelElementType.text => Icons.text_fields_rounded,
      LabelElementType.price => Icons.sell_outlined,
      LabelElementType.image => Icons.image_outlined,
      LabelElementType.line => Icons.horizontal_rule_rounded,
      LabelElementType.rect => Icons.crop_square_rounded,
      LabelElementType.ellipse => Icons.circle_outlined,
      LabelElementType.date => Icons.event_outlined,
    };
