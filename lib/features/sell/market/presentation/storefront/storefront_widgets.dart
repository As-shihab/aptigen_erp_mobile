import 'package:flutter/material.dart';
import '../widgets/market_ui.dart';

// Storefront building blocks: accent swatches, section card and the
// animated "Saved" confirmation.

const accentSwatches = <String>[
  '#0070F2', // blue
  '#0284C7', // sky
  '#256F3A', // green
  '#65A30D', // lime
  '#E76500', // orange
  '#E11D48', // rose
  '#AA0808', // red
  '#7C3AED', // violet
  '#1D2D3E', // ink
];

Color? parseHex(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// Row of fixed accent swatches; tapping the selected one clears it.
class AccentPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const AccentPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final hex in accentSwatches)
        Builder(builder: (_) {
          final selected = value?.toUpperCase() == hex.toUpperCase();
          final c = parseHex(hex)!;
          return Semantics(
            button: true,
            selected: selected,
            label: 'Accent $hex',
            child: GestureDetector(
              onTap: () => onChanged(selected ? null : hex),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 36,
                height: 36,
                padding: EdgeInsets.all(selected ? 3 : 0),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? c : p.line, width: 2)),
                child: Container(
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: selected ? 1 : 0,
                    child: const Icon(Icons.check, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          );
        }),
    ]);
  }
}

/// Titled card section for the form.
class FormSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> children;
  const FormSection({super.key, required this.title, required this.icon, required this.children, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(children: [
            Icon(icon, size: 18, color: p.brand),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 11.5, color: p.label)),
              ]),
            ),
          ]),
        ),
        Divider(height: 1, color: p.line),
        Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 2), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
      ]),
    );
  }
}

/// Check mark that scales in with a "Saved" label.
class SavedBadge extends StatelessWidget {
  const SavedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Transform.scale(scale: 0.85 + 0.15 * t, child: Opacity(opacity: t.clamp(0, 1), child: child)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: p.ok, shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 15, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Text('Saved', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.ok)),
      ]),
    );
  }
}
