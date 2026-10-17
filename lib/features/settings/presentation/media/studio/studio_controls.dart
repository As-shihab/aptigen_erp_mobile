import 'package:flutter/material.dart';

import '../../../../../shared/data/media_studio_service.dart';
import '../../../../../shared/models/media_edit_ops.dart';
import '../../../../sell/market/presentation/widgets/market_ui.dart';

// Small building blocks shared by the Image studio panels and the Lab —
// the Flutter side of desktop's image-studio/controls.tsx and
// TemplateDialogs.tsx, styled with the SAP Horizon market kit.

/// A titled group inside a studio panel.
class StudioSection extends StatelessWidget {
  final String title;
  final Widget? action;
  final List<Widget> children;
  const StudioSection({super.key, required this.title, this.action, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 30,
          child: Row(children: [
            Expanded(child: Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text))),
            ?action,
          ]),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          children[i],
        ],
      ]),
    );
  }
}

/// Small helper text.
class StudioHint extends StatelessWidget {
  final String text;
  const StudioHint(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 12, height: 1.35, color: MarketPalette.of(context).label));
}

/// SAP message strip (information / warning / error / success).
class StudioStrip extends StatelessWidget {
  final String text;
  final MarketTone tone;
  final Widget? action;
  const StudioStrip(this.text, {super.key, this.tone = MarketTone.info, this.action});

  @override
  Widget build(BuildContext context) {
    final c = MarketPalette.of(context).tone(tone);
    final icon = switch (tone) {
      MarketTone.error => Icons.error_outline_rounded,
      MarketTone.warn => Icons.warning_amber_rounded,
      MarketTone.ok => Icons.check_circle_outline_rounded,
      _ => Icons.info_outline_rounded,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.fg.withValues(alpha: 0.35))),
      child: Row(children: [
        Icon(icon, size: 17, color: c.fg),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, height: 1.35, color: MarketPalette.of(context).text))),
        ?action,
      ]),
    );
  }
}

/// Labelled slider with a live value and a per-slider reset.
class StudioSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  /// Value the reset button returns to; reset is hidden while already there.
  final double? neutral;
  final String Function(double v)? format;
  final bool disabled;
  /// Fired while dragging (transient, not an undo step).
  final ValueChanged<double> onInput;
  /// Fired when the drag ends (commits an undo step).
  final ValueChanged<double> onCommit;
  final VoidCallback? onReset;

  const StudioSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    this.neutral,
    this.format,
    this.disabled = false,
    required this.onInput,
    required this.onCommit,
    this.onReset,
  });

  double _snap(double v) {
    final snapped = (v / step).round() * step;
    return double.parse(snapped.clamp(min, max).toStringAsFixed(4));
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final changed = neutral != null && (value - neutral!).abs() > 1e-6;
    final divisions = ((max - min) / step).round();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: disabled ? p.label : p.text))),
        Text(format != null ? format!(value) : value.toStringAsFixed(2),
            style: TextStyle(fontSize: 12, color: p.label, fontFeatures: const [FontFeature.tabularFigures()])),
        if (onReset != null)
          SizedBox(
            width: 32,
            height: 28,
            child: Visibility(
              visible: changed,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 17,
                tooltip: 'Reset ${label.toLowerCase()}',
                onPressed: disabled ? null : onReset,
                icon: Icon(Icons.restart_alt_rounded, color: p.label),
              ),
            ),
          ),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          activeTrackColor: p.brand,
          inactiveTrackColor: p.line,
          thumbColor: p.brand,
          overlayColor: p.brand.withValues(alpha: 0.12),
          showValueIndicator: ShowValueIndicator.never,
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        ),
        child: SizedBox(
          height: 30,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions > 0 && divisions <= 1000 ? divisions : null,
            onChanged: disabled ? null : (v) => onInput(_snap(v)),
            onChangeEnd: disabled ? null : (v) => onCommit(_snap(v)),
          ),
        ),
      ),
    ]);
  }
}

/// Wrap of selectable choice chips (desktop's ChoiceGrid).
class StudioChoices extends StatelessWidget {
  final String value;
  final List<({String id, String label})> options;
  final ValueChanged<String> onChanged;
  final bool disabled;
  const StudioChoices({super.key, required this.value, required this.options, required this.onChanged, this.disabled = false});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final o in options)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: disabled ? null : () => onChanged(o.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: o.id == value ? p.brandSoft : p.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: o.id == value ? p.brand : p.line),
              ),
              child: Text(o.label,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: o.id == value ? FontWeight.w700 : FontWeight.w500, color: o.id == value ? p.brand : p.text)),
            ),
          ),
      ]),
    );
  }
}

/// Selectable square tile with a label below (filters, scenes, gradients).
class StudioTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final double size;
  const StudioTile({super.key, required this.label, required this.selected, required this.onTap, required this.child, this.size = 74});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return SizedBox(
      width: size,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: size,
            height: size,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? p.brand : p.line, width: selected ? 2 : 1),
            ),
            child: ClipRRect(borderRadius: BorderRadius.circular(7), child: SizedBox.expand(child: child)),
          ),
          const SizedBox(height: 4),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? p.brand : p.text)),
        ]),
      ),
    );
  }
}

/// Checkerboard behind previews so transparent areas are visible.
class CheckerBackground extends StatelessWidget {
  final Widget child;
  final double cell;
  const CheckerBackground({super.key, required this.child, this.cell = 10});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return CustomPaint(painter: _CheckerPainter(p.surface, p.line, cell), child: child);
  }
}

class _CheckerPainter extends CustomPainter {
  final Color a;
  final Color b;
  final double cell;
  _CheckerPainter(this.a, this.b, this.cell);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = a);
    final paint = Paint()..color = b.withValues(alpha: 0.55);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = (y % 2); x * cell < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => old.a != a || old.b != b || old.cell != cell;
}

/// Chips listing what a template / set of ops changes.
class TemplateChips extends StatelessWidget {
  final EditOps ops;
  final String emptyText;
  const TemplateChips({super.key, required this.ops, this.emptyText = 'No changes'});

  @override
  Widget build(BuildContext context) {
    final labels = summarizeOps(ops);
    if (labels.isEmpty) return StudioHint(emptyText);
    return Wrap(spacing: 4, runSpacing: 4, children: [for (final l in labels) StatusPill(l, tone: MarketTone.info)]);
  }
}

/// Name + description form for creating, renaming or updating a template
/// (desktop's TemplateFormDialog). [onSubmit] errors are shown in the sheet.
/// Resolves true once submitted.
Future<bool> showTemplateForm(
  BuildContext context, {
  required String title,
  required String submitText,
  String initialName = '',
  String initialDescription = '',
  EditOps? ops,
  required Future<void> Function(String name, String description) onSubmit,
}) async {
  final ok = await showMarketSheet<bool>(
    context,
    builder: (ctx) => _TemplateForm(
      title: title,
      submitText: submitText,
      initialName: initialName,
      initialDescription: initialDescription,
      ops: ops,
      onSubmit: onSubmit,
    ),
  );
  return ok == true;
}

class _TemplateForm extends StatefulWidget {
  final String title;
  final String submitText;
  final String initialName;
  final String initialDescription;
  final EditOps? ops;
  final Future<void> Function(String name, String description) onSubmit;
  const _TemplateForm({
    required this.title,
    required this.submitText,
    required this.initialName,
    required this.initialDescription,
    required this.ops,
    required this.onSubmit,
  });

  @override
  State<_TemplateForm> createState() => _TemplateFormState();
}

class _TemplateFormState extends State<_TemplateForm> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _description = TextEditingController(text: widget.initialDescription);
  bool _touched = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _touched = true);
    if (_name.text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_name.text.trim(), _description.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = describeStudioError(e, 'Could not save the template'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration(MarketPalette p, String label, {String? hint, String? errorText}) => InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        isDense: true,
        filled: true,
        fillColor: p.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
      );

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final missing = _touched && _name.text.trim().isEmpty;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: widget.initialName.isEmpty,
            maxLength: 120,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: _decoration(p, 'Name', hint: 'For example: white studio product shot', errorText: missing ? 'Enter a name' : null),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _description,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            enabled: !_busy,
            decoration: _decoration(p, 'Description', hint: 'Optional'),
          ),
          if (widget.ops != null) ...[
            const SizedBox(height: 4),
            Text('Included settings', style: TextStyle(fontSize: 12, color: p.label)),
            const SizedBox(height: 6),
            TemplateChips(ops: widget.ops!),
            const SizedBox(height: 8),
            const StudioStrip("Crop isn't saved in templates."),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            StudioStrip(_error!, tone: MarketTone.error),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel'))),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(widget.submitText),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Confirms and deletes a template; resolves true when deleted.
Future<bool> deleteTemplateFlow(BuildContext context, TemplatesStore store, MediaEditTemplate t) async {
  final ok = await confirmMarket(
    context,
    title: 'Delete template?',
    message: '"${t.name}" will be removed for everyone in this workplace. Images already edited with it are not affected.',
  );
  if (!ok) return false;
  try {
    await store.remove(t);
    if (context.mounted) marketToast(context, 'Template deleted');
    return true;
  } catch (e) {
    if (context.mounted) marketToast(context, describeStudioError(e, 'Could not delete the template'), error: true);
    return false;
  }
}

/// One template row: name, description, included settings and actions.
class TemplateCard extends StatelessWidget {
  final MediaEditTemplate template;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final String editTooltip;
  final VoidCallback? onDelete;
  final Widget? footer;
  final IconData? leading;
  const TemplateCard({
    super.key,
    required this.template,
    this.selected = false,
    this.onTap,
    this.onEdit,
    this.editTooltip = 'Rename',
    this.onDelete,
    this.footer,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final t = template;
    return MarketCard(
      onTap: onTap,
      color: selected ? p.brandSoft : null,
      borderColor: selected ? p.brand : null,
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (leading != null) ...[
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(leading, size: 18, color: selected ? p.brand : p.label)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
              if (t.description != null)
                Text(t.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
            ]),
          ),
          if (onEdit != null)
            IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: editTooltip,
                onPressed: onEdit,
                icon: Icon(Icons.edit_outlined, size: 19, color: p.label)),
          if (onDelete != null)
            IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline_rounded, size: 19, color: p.label)),
        ]),
        const SizedBox(height: 6),
        Padding(padding: const EdgeInsets.only(right: 8), child: TemplateChips(ops: t.ops)),
        if (footer != null) ...[const SizedBox(height: 8), Padding(padding: const EdgeInsets.only(right: 8), child: footer!)],
      ]),
    );
  }
}
