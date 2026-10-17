import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../../shared/data/media_studio_service.dart';
import '../../../../../shared/models/media_edit_ops.dart';
import '../../../../sell/market/presentation/widgets/market_ui.dart';
import 'image_studio_controller.dart';
import 'studio_constants.dart';
import 'studio_controls.dart';

// The Image studio's tool panels — ports of desktop's AdjustPanel,
// FiltersPanel, BackgroundPanel, LayoutPanel, CompressPanel and
// TemplatesPanel. The crop + rotate/flip tools (desktop's Adjust tab) live in
// their own "Crop" panel here, like a mobile photo editor.

String _fixed(double v, int d) => v.toStringAsFixed(d);

// ── Adjust ──

class AdjustPanel extends StatelessWidget {
  final ImageStudioController studio;
  const AdjustPanel({super.key, required this.studio});

  void _setAdjust(String key, double value, bool transient) =>
      studio.set((prev) => prev.copyWith(adjust: (prev.adjust ?? const EditAdjust()).withValue(key, value)), transient: transient);

  @override
  Widget build(BuildContext context) {
    final ops = studio.ops;
    return StudioSection(
      title: 'Light and color',
      action: studio.effective.adjust != null
          ? TextButton.icon(
              onPressed: () => studio.set((prev) => prev.copyWith(adjust: null)),
              icon: const Icon(Icons.restart_alt_rounded, size: 17),
              label: const Text('Reset all'),
            )
          : null,
      children: [
        for (final s in adjustSliders)
          StudioSlider(
            label: s.label,
            min: s.min,
            max: s.max,
            step: s.step,
            neutral: s.neutral,
            value: ops.adjust?[s.key] ?? s.neutral,
            format: (v) => _fixed(v, s.key == 'blur' ? 1 : 2),
            onInput: (v) => _setAdjust(s.key, v, true),
            onCommit: (v) {
              _setAdjust(s.key, v, true);
              studio.commit();
            },
            onReset: () => studio.set((prev) => prev.copyWith(adjust: (prev.adjust ?? const EditAdjust()).without(s.key))),
          ),
      ],
    );
  }
}

// ── Filters ──

class FiltersPanel extends StatelessWidget {
  final ImageStudioController studio;
  final String thumbUrl;
  const FiltersPanel({super.key, required this.studio, required this.thumbUrl});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final current = studio.ops.filter ?? 'none';
    return StudioSection(title: 'Filters', children: [
      const StudioHint('Tiles show an approximate look; the preview shows the exact result.'),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final f in studioFilters)
          StudioTile(
            label: f.label,
            selected: current == f.id,
            onTap: () => studio.set((prev) => prev.copyWith(filter: f.id)),
            child: thumbUrl.isEmpty
                ? Container(color: p.surface)
                : _filtered(
                    f.look,
                    CachedNetworkImage(
                      imageUrl: thumbUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(color: p.surface),
                      errorWidget: (_, _, _) => Container(color: p.surface),
                    ),
                  ),
          ),
      ]),
    ]);
  }

  Widget _filtered(ColorFilter? look, Widget child) => look == null ? child : ColorFiltered(colorFilter: look, child: child);
}

// ── Crop and rotate ──

class CropPanel extends StatelessWidget {
  final ImageStudioController studio;
  final bool cropMode;
  final String cropAspect;
  final bool canCrop;
  final VoidCallback onStartCrop;
  final ValueChanged<String> onCropAspect;
  final VoidCallback onApplyCrop;
  final VoidCallback onCancelCrop;
  /// Template mode: crops aren't saved in templates, so the crop tools are hidden.
  final bool hideCrop;

  const CropPanel({
    super.key,
    required this.studio,
    required this.cropMode,
    required this.cropAspect,
    required this.canCrop,
    required this.onStartCrop,
    required this.onCropAspect,
    required this.onApplyCrop,
    required this.onCancelCrop,
    this.hideCrop = false,
  });

  void _rotate(int delta) => studio.set((prev) => prev.copyWith(rotate: (((prev.rotate ?? 0) + delta) % 360 + 360) % 360));

  @override
  Widget build(BuildContext context) {
    final ops = studio.ops;
    final hasCrop = studio.effective.crop != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!hideCrop)
        StudioSection(
          title: 'Crop',
          action: !cropMode && hasCrop
              ? TextButton.icon(
                  onPressed: () => studio.set((prev) => prev.copyWith(crop: null)),
                  icon: const Icon(Icons.restart_alt_rounded, size: 17),
                  label: const Text('Clear crop'),
                )
              : null,
          children: cropMode
              ? [
                  const StudioHint('Drag the frame or its corners on the image.'),
                  StudioChoices(value: cropAspect, options: [for (final a in cropAspects) (id: a.id, label: a.label)], onChanged: onCropAspect),
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: onCancelCrop, child: const Text('Cancel'))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(onPressed: onApplyCrop, icon: const Icon(Icons.check_rounded, size: 18), label: const Text('Apply crop')),
                    ),
                  ]),
                ]
              : [
                  Row(children: [
                    OutlinedButton.icon(
                      onPressed: canCrop ? onStartCrop : null,
                      icon: const Icon(Icons.crop_rounded, size: 18),
                      label: Text(hasCrop ? 'Adjust crop' : 'Crop image'),
                    ),
                    const SizedBox(width: 10),
                    if (hasCrop) const StatusPill('Crop applied', tone: MarketTone.ok, icon: Icons.check_rounded),
                  ]),
                ],
        ),
      StudioSection(title: 'Rotate and flip', children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: cropMode ? null : () => _rotate(-90),
            icon: const Icon(Icons.rotate_left_rounded, size: 18),
            label: const Text('Left'),
          ),
          OutlinedButton.icon(
            onPressed: cropMode ? null : () => _rotate(90),
            icon: const Icon(Icons.rotate_right_rounded, size: 18),
            label: const Text('Right'),
          ),
          _ToggleButton(
            selected: ops.flipH == true,
            icon: Icons.flip_rounded,
            label: 'Flip horizontal',
            onPressed: cropMode ? null : () => studio.set((prev) => prev.copyWith(flipH: !(prev.flipH ?? false))),
          ),
          _ToggleButton(
            selected: ops.flipV == true,
            icon: Icons.flip_rounded,
            quarterTurns: 1,
            label: 'Flip vertical',
            onPressed: cropMode ? null : () => studio.set((prev) => prev.copyWith(flipV: !(prev.flipV ?? false))),
          ),
        ]),
        if ((ops.rotate ?? 0) != 0) StudioHint('Rotated ${ops.rotate}°'),
      ]),
    ]);
  }
}

class _ToggleButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final int quarterTurns;
  final String label;
  final VoidCallback? onPressed;
  const _ToggleButton({required this.selected, required this.icon, this.quarterTurns = 0, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final i = RotatedBox(quarterTurns: quarterTurns, child: Icon(icon, size: 18));
    return selected
        ? FilledButton.icon(onPressed: onPressed, icon: i, label: Text(label))
        : OutlinedButton.icon(onPressed: onPressed, icon: i, label: Text(label));
  }
}

// ── Background ──

/// Hex input that only commits valid #rrggbb values.
class _HexField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onCommit;
  const _HexField({required this.label, required this.value, required this.onCommit});

  @override
  State<_HexField> createState() => _HexFieldState();
}

class _HexFieldState extends State<_HexField> {
  late final _c = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_HexField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _c.text.toLowerCase() != widget.value.toLowerCase()) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final valid = hexRe.hasMatch(_c.text);
    return Row(children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: hexColor(valid ? _c.text : widget.value),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: p.line),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: TextField(
          controller: _c,
          maxLength: 7,
          style: TextStyle(fontSize: 13.5, color: p.text),
          decoration: InputDecoration(
            labelText: widget.label,
            counterText: '',
            isDense: true,
            errorText: valid ? null : 'Use the #rrggbb format',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.line)),
          ),
          onChanged: (raw) {
            var v = raw.trim();
            if (v.isNotEmpty && !v.startsWith('#')) {
              v = '#$v';
              _c.value = TextEditingValue(text: v, selection: TextSelection.collapsed(offset: v.length));
            }
            setState(() {});
            if (hexRe.hasMatch(v)) widget.onCommit(v.toLowerCase());
          },
        ),
      ),
    ]);
  }
}

class BackgroundPanel extends StatelessWidget {
  final ImageStudioController studio;
  final String? bgImageThumb;
  final String? bgImageName;
  final VoidCallback onPickImage;
  const BackgroundPanel({super.key, required this.studio, this.bgImageThumb, this.bgImageName, required this.onPickImage});

  EditBackground get _bg => studio.ops.background ?? const EditBackground(type: 'original');

  void _setBg(EditBackground Function(EditBackground b) next, {bool transient = false}) => studio.set(
        (prev) => prev.copyWith(background: next(prev.background ?? const EditBackground(type: 'original'))),
        transient: transient,
      );

  void _chooseType(String type) {
    final bg = _bg;
    _setBg((b) => b.copyWith(
          type: type,
          color: type == 'color' && b.color == null ? defaultColor : null,
          gradient: type == 'gradient' && b.gradient == null ? _defaultGradient : null,
          blurRadius: type == 'blur' && b.blurRadius == null ? defaultBlurRadius : null,
          scene: type == 'scene' && b.scene == null ? studioScenes.first.id : null,
        ));
    if (type == 'image' && bg.mediaId == null) onPickImage();
  }

  static final _defaultGradient =
      EditGradient(from: gradientPresets.first.from, to: gradientPresets.first.to, angle: defaultGradientAngle);

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final ops = studio.ops;
    final enabled = ops.removeBg == true;
    final bg = _bg;
    final gradient = bg.gradient ?? _defaultGradient;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StudioSection(title: 'Remove background', children: [
        Row(children: [
          Expanded(child: Text('Cut out the main subject', style: TextStyle(fontSize: 13, color: p.text))),
          Switch(
            value: enabled,
            activeTrackColor: p.brand,
            onChanged: (on) => studio.set((prev) => on && prev.background == null
                ? prev.copyWith(removeBg: true, background: const EditBackground(type: 'transparent'))
                : prev.copyWith(removeBg: on)),
          ),
        ]),
        if (enabled && studio.removingBgFirstTime && studio.loading)
          Row(children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: p.brand)),
            const SizedBox(width: 8),
            const Expanded(child: StudioHint('Removing background… the first run can take a little while.')),
          ]),
        if (!enabled) const StudioStrip('Turn on remove background to replace the background, add a shadow or resize the subject.'),
      ]),
      StudioSection(title: 'New background', children: [
        StudioChoices(value: bg.type, options: backgroundTypes, onChanged: _chooseType, disabled: !enabled),
      ]),
      if (enabled && bg.type == 'color')
        StudioSection(title: 'Color', children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in colorSwatches)
              GestureDetector(
                onTap: () => _setBg((b) => b.copyWith(color: c)),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: hexColor(c),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: bg.color == c ? p.brand : p.line, width: bg.color == c ? 2.5 : 1),
                  ),
                ),
              ),
          ]),
          _HexField(label: 'Hex color', value: bg.color ?? defaultColor, onCommit: (c) => _setBg((b) => b.copyWith(color: c))),
        ]),
      if (enabled && bg.type == 'gradient')
        StudioSection(title: 'Gradient', children: [
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final g in gradientPresets)
              StudioTile(
                label: g.label,
                size: 64,
                selected: gradient.from == g.from && gradient.to == g.to,
                onTap: () => _setBg((b) => b.copyWith(gradient: gradient.copyWith(from: g.from, to: g.to))),
                child: DecoratedBox(decoration: BoxDecoration(gradient: cssLinear(gradient.angle, [hexColor(g.from), hexColor(g.to)]))),
              ),
          ]),
          Row(children: [
            Expanded(
                child: _HexField(
                    label: 'From', value: gradient.from, onCommit: (v) => _setBg((b) => b.copyWith(gradient: gradient.copyWith(from: v))))),
            const SizedBox(width: 10),
            Expanded(
                child: _HexField(label: 'To', value: gradient.to, onCommit: (v) => _setBg((b) => b.copyWith(gradient: gradient.copyWith(to: v))))),
          ]),
          StudioSlider(
            label: 'Angle',
            min: 0,
            max: 360,
            step: 15,
            neutral: defaultGradientAngle,
            value: gradient.angle,
            format: (v) => '${v.round()}°',
            onInput: (a) => _setBg((b) => b.copyWith(gradient: gradient.copyWith(angle: a)), transient: true),
            onCommit: (a) {
              _setBg((b) => b.copyWith(gradient: gradient.copyWith(angle: a)), transient: true);
              studio.commit();
            },
            onReset: () => _setBg((b) => b.copyWith(gradient: gradient.copyWith(angle: defaultGradientAngle))),
          ),
        ]),
      if (enabled && bg.type == 'blur')
        StudioSection(title: 'Blur', children: [
          StudioSlider(
            label: 'Blur amount',
            min: 0,
            max: 60,
            step: 1,
            neutral: defaultBlurRadius,
            value: bg.blurRadius ?? defaultBlurRadius,
            format: (v) => '${v.round()}',
            onInput: (v) => _setBg((b) => b.copyWith(blurRadius: v), transient: true),
            onCommit: (v) {
              _setBg((b) => b.copyWith(blurRadius: v), transient: true);
              studio.commit();
            },
            onReset: () => _setBg((b) => b.copyWith(blurRadius: defaultBlurRadius)),
          ),
        ]),
      if (enabled && bg.type == 'image')
        StudioSection(title: 'Background image', children: [
          if (bg.mediaId != null)
            MarketCard(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 52,
                    height: 52,
                    color: p.surface,
                    child: bgImageThumb == null
                        ? Icon(Icons.image_outlined, color: p.label)
                        : CachedNetworkImage(imageUrl: bgImageThumb!, fit: BoxFit.cover, errorWidget: (_, _, _) => const SizedBox()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(bgImageName?.isNotEmpty == true ? bgImageName! : 'Media #${bg.mediaId}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.text)),
                ),
              ]),
            )
          else
            const StudioHint('No image chosen yet.'),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onPickImage,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text(bg.mediaId != null ? 'Change image' : 'Choose image'),
            ),
          ),
        ]),
      if (enabled && bg.type == 'scene')
        StudioSection(title: 'Scene', children: [
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final s in studioScenes)
              StudioTile(
                label: s.label,
                size: 70,
                selected: bg.scene == s.id,
                onTap: () => _setBg((b) => b.copyWith(scene: s.id)),
                child: DecoratedBox(decoration: BoxDecoration(gradient: s.look)),
              ),
          ]),
        ]),
    ]);
  }
}

// ── Layout ──

class LayoutPanel extends StatelessWidget {
  final ImageStudioController studio;
  final bool hasAlpha;
  const LayoutPanel({super.key, required this.studio, required this.hasAlpha});

  void _canvas(EditCanvas Function(EditCanvas c) f, {bool transient = false}) =>
      studio.set((prev) => prev.copyWith(canvas: f(prev.canvas ?? const EditCanvas())), transient: transient);
  void _subject(EditSubject Function(EditSubject s) f, {bool transient = false}) =>
      studio.set((prev) => prev.copyWith(subject: f(prev.subject ?? const EditSubject())), transient: transient);
  void _shadow(EditShadow Function(EditShadow s) f, {bool transient = false}) =>
      studio.set((prev) => prev.copyWith(shadow: f(prev.shadow ?? const EditShadow(enabled: false))), transient: transient);
  void _output(EditOutput Function(EditOutput o) f, {bool transient = false}) =>
      studio.set((prev) => prev.copyWith(output: f(prev.output ?? const EditOutput())), transient: transient);

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final ops = studio.ops;
    final removeBg = ops.removeBg == true;
    final shadowOn = ops.shadow?.enabled == true;
    final format = ops.output?.format ?? 'auto';
    final transparentBg = removeBg && (ops.background?.type ?? 'original') == 'transparent';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StudioSection(title: 'Canvas', children: [
        const StudioHint('Aspect ratio'),
        StudioChoices(value: ops.canvas?.aspect ?? 'original', options: canvasAspects, onChanged: (a) => _canvas((c) => c.copyWith(aspect: a))),
        StudioSlider(
          label: 'Padding',
          min: 0,
          max: 0.3,
          step: 0.01,
          neutral: 0,
          value: ops.canvas?.padding ?? 0,
          format: pct,
          onInput: (v) => _canvas((c) => c.copyWith(padding: v), transient: true),
          onCommit: (v) {
            _canvas((c) => c.copyWith(padding: v), transient: true);
            studio.commit();
          },
          onReset: () => _canvas((c) => c.copyWith(padding: 0)),
        ),
      ]),
      StudioSection(title: 'Subject', children: [
        if (!removeBg) const StudioStrip('Subject size, position and shadow need remove background (Background tab).'),
        StudioSlider(
          label: 'Subject size',
          min: 0.4,
          max: 1,
          step: 0.01,
          neutral: 1,
          value: ops.subject?.scale ?? 1,
          format: pct,
          disabled: !removeBg,
          onInput: (v) => _subject((s) => s.copyWith(scale: v), transient: true),
          onCommit: (v) {
            _subject((s) => s.copyWith(scale: v), transient: true);
            studio.commit();
          },
          onReset: () => _subject((s) => s.copyWith(scale: 1)),
        ),
        const StudioHint('Position'),
        StudioChoices(
          value: ops.subject?.position ?? 'center',
          options: const [(id: 'center', label: 'Center'), (id: 'bottom', label: 'Bottom')],
          disabled: !removeBg,
          onChanged: (v) => _subject((s) => s.copyWith(position: v)),
        ),
      ]),
      StudioSection(
        title: 'Shadow',
        action: Switch(
          value: shadowOn,
          activeTrackColor: p.brand,
          onChanged: removeBg
              ? (on) => _shadow((s) => EditShadow(enabled: on, style: s.style ?? 'soft', strength: s.strength ?? defaultShadowStrength))
              : null,
        ),
        children: [
          StudioChoices(
            value: ops.shadow?.style ?? 'soft',
            options: const [(id: 'soft', label: 'Soft'), (id: 'floor', label: 'Floor')],
            disabled: !removeBg || !shadowOn,
            onChanged: (v) => _shadow((s) => s.copyWith(style: v)),
          ),
          StudioSlider(
            label: 'Strength',
            min: 0,
            max: 1,
            step: 0.05,
            neutral: defaultShadowStrength,
            value: ops.shadow?.strength ?? defaultShadowStrength,
            format: pct,
            disabled: !removeBg || !shadowOn,
            onInput: (v) => _shadow((s) => s.copyWith(strength: v), transient: true),
            onCommit: (v) {
              _shadow((s) => s.copyWith(strength: v), transient: true);
              studio.commit();
            },
            onReset: () => _shadow((s) => s.copyWith(strength: defaultShadowStrength)),
          ),
        ],
      ),
      StudioSection(title: 'Output', children: [
        StudioChoices(
          value: format,
          options: outputFormats,
          onChanged: (f) => studio.set((prev) => prev.copyWith(
                output: f == 'auto' ? null : EditOutput(format: f, quality: f == 'png' ? null : prev.output?.quality ?? defaultQuality),
              )),
        ),
        if (format == 'webp' || format == 'jpeg')
          StudioSlider(
            label: 'Quality',
            min: 40,
            max: 100,
            step: 1,
            neutral: defaultQuality.toDouble(),
            value: (ops.output?.quality ?? defaultQuality).toDouble(),
            format: (v) => '${v.round()}',
            onInput: (v) => _output((o) => o.copyWith(quality: v.round()), transient: true),
            onCommit: (v) {
              _output((o) => o.copyWith(quality: v.round()), transient: true);
              studio.commit();
            },
            onReset: () => _output((o) => o.copyWith(quality: defaultQuality)),
          ),
        if (format == 'jpeg' && (hasAlpha || transparentBg))
          const StudioStrip('JPEG has no transparency — transparent areas will be filled.', tone: MarketTone.warn),
      ]),
    ]);
  }
}

// ── Compress ──

/// Shrinks the saved image on the server (sharp) to roughly a target size
/// and writes it over the original. Separate from the edit pipeline on
/// purpose: unsaved edits in the other tabs have to be saved (or reset) first.
class CompressPanel extends StatefulWidget {
  /// Current file size in bytes (0 when unknown).
  final int size;
  final bool hasChanges;
  final bool busy;
  final ValueChanged<int> onCompress;
  const CompressPanel({super.key, required this.size, required this.hasChanges, required this.busy, required this.onCompress});

  @override
  State<CompressPanel> createState() => _CompressPanelState();
}

class _CompressPanelState extends State<CompressPanel> {
  int _target = 100;

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final size = widget.size;
    final alreadySmall = size > 0 && size <= _target * 1024;
    final heavy = size > 100 * 1024;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StudioSection(title: 'File size', children: [
        MarketCard(
          color: p.surface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Expanded(child: Text('Current size', style: TextStyle(fontSize: 12.5, color: p.label))),
            Text(formatBytes(size), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
            if (size > 0) ...[
              const SizedBox(width: 8),
              StatusPill(heavy ? 'Heavy' : 'Light', tone: heavy ? MarketTone.warn : MarketTone.ok),
            ],
          ]),
        ),
        const StudioHint('Images over 100 KB load slowly in product cards, listings and banners.'),
      ]),
      StudioSection(title: 'Target size', children: [
        MarketSegmented<int>(
          value: _target,
          options: [for (final kb in compressTargets) (id: kb, label: '$kb KB', count: null)],
          onChanged: (kb) => setState(() => _target = kb),
        ),
        const StudioHint(
            'Lowers quality first, then the dimensions, until the file is at or under the target. The format stays the same and the file is never made larger.'),
      ]),
      StudioSection(title: 'Compress', children: [
        if (widget.hasChanges)
          const StudioStrip('Compression works on the saved image. Save or reset your edits in the other tabs first.')
        else if (alreadySmall)
          StudioStrip('Already under $_target KB — pick a smaller target to compress further.', tone: MarketTone.ok)
        else
          const StudioStrip('Replaces the original file. Everything using this image shows the compressed version.', tone: MarketTone.warn),
        FilledButton.icon(
          onPressed: widget.busy || widget.hasChanges || alreadySmall ? null : () => widget.onCompress(_target),
          icon: widget.busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.compress_rounded, size: 18),
          label: Text(widget.busy ? 'Compressing…' : 'Compress to $_target KB'),
        ),
      ]),
    ]);
  }
}

// ── Templates ──

/// Apply, rename or delete saved templates; save the current settings as one.
class TemplatesPanel extends StatelessWidget {
  final TemplatesStore store;
  final int? appliedId;
  final bool canSave;
  final ValueChanged<MediaEditTemplate> onApply;
  final VoidCallback onSaveAs;
  const TemplatesPanel({super.key, required this.store, required this.appliedId, required this.canSave, required this.onApply, required this.onSaveAs});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final list = store.templates;
    return StudioSection(
      title: 'Templates',
      action: IconButton(
        tooltip: 'Reload templates',
        visualDensity: VisualDensity.compact,
        onPressed: store.loading ? null : store.reload,
        icon: Icon(Icons.refresh_rounded, size: 19, color: p.label),
      ),
      children: [
        const StudioHint('Applying a template replaces the current settings, except the crop. You can undo it.'),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: canSave ? onSaveAs : null,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Save current as template'),
          ),
        ),
        if (!canSave) const StudioHint('Make an edit other than crop first to save a template.'),
        if (store.error != null)
          StudioStrip(store.error!, tone: MarketTone.error, action: TextButton(onPressed: store.reload, child: const Text('Retry'))),
        if (store.loading && list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: p.brand))),
          )
        else if (list.isEmpty && store.error == null)
          MarketCard(
            color: p.bg,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            child: const Center(child: StudioHint('No templates yet. Save your current settings to reuse them on other images.')),
          )
        else
          for (final t in list)
            TemplateCard(
              template: t,
              selected: appliedId == t.id,
              onEdit: () => showTemplateForm(
                context,
                title: 'Rename template',
                submitText: 'Save',
                initialName: t.name,
                initialDescription: t.description ?? '',
                onSubmit: (name, description) async {
                  await store.rename(t, name, description);
                  if (context.mounted) marketToast(context, 'Template renamed');
                },
              ),
              onDelete: () => deleteTemplateFlow(context, store, t),
              footer: Align(
                alignment: Alignment.centerRight,
                child: appliedId == t.id
                    ? OutlinedButton.icon(
                        onPressed: () => onApply(t), icon: const Icon(Icons.check_rounded, size: 18), label: const Text('Apply again'))
                    : FilledButton.icon(onPressed: () => onApply(t), icon: const Icon(Icons.check_rounded, size: 18), label: const Text('Apply')),
              ),
            ),
      ],
    );
  }
}
