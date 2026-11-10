import 'package:flutter/material.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/utils/currency.dart';

// Shared look for the Sell → Online market screens: SAP Horizon-style flat
// cards, semantic status colours, object headers and light, purposeful
// motion (staggered fade/slide-in, count-up KPIs, animated pills). Every
// colour adapts to light / dark through [MarketPalette.of].

/// SAP Horizon semantic palette, light and dark.
class MarketPalette {
  final bool dark;
  const MarketPalette._(this.dark);

  static MarketPalette of(BuildContext context) => MarketPalette._(Theme.of(context).brightness == Brightness.dark);

  Color get bg => dark ? const Color(0xFF12171C) : const Color(0xFFF5F6F7);
  Color get card => dark ? const Color(0xFF1D232A) : Colors.white;
  Color get surface => dark ? const Color(0xFF262D35) : const Color(0xFFF1F3F5);
  Color get line => dark ? const Color(0xFF34404B) : const Color(0xFFE5E8EB);
  Color get text => dark ? const Color(0xFFEAECEE) : const Color(0xFF1D2D3E);
  Color get label => dark ? const Color(0xFFA9B4BE) : const Color(0xFF556B82);
  Color get brand => AppColors.brand;
  Color get brandSoft => dark ? const Color(0xFF13324F) : const Color(0xFFE8F2FD);

  Color get ok => dark ? const Color(0xFF5DC122) : const Color(0xFF256F3A);
  Color get okBg => dark ? const Color(0xFF1C3320) : const Color(0xFFF5FAE5);
  Color get warn => dark ? const Color(0xFFFF8A3D) : const Color(0xFFE76500);
  Color get warnBg => dark ? const Color(0xFF3A2614) : const Color(0xFFFFF8D6);
  Color get error => dark ? const Color(0xFFFF6A6A) : const Color(0xFFAA0808);
  Color get errorBg => dark ? const Color(0xFF3A1A1F) : const Color(0xFFFFEAF4);
  Color get info => dark ? const Color(0xFF4DB1FF) : const Color(0xFF0070F2);
  Color get infoBg => dark ? const Color(0xFF13324F) : const Color(0xFFE1F4FF);
  Color get neutral => dark ? const Color(0xFFA9B4BE) : const Color(0xFF5B738B);
  Color get neutralBg => dark ? const Color(0xFF262D35) : const Color(0xFFEFF1F2);

  ({Color fg, Color bg}) tone(MarketTone t) => switch (t) {
        MarketTone.ok => (fg: ok, bg: okBg),
        MarketTone.warn => (fg: warn, bg: warnBg),
        MarketTone.error => (fg: error, bg: errorBg),
        MarketTone.info => (fg: info, bg: infoBg),
        MarketTone.brand => (fg: brand, bg: brandSoft),
        MarketTone.neutral => (fg: neutral, bg: neutralBg),
      };
}

enum MarketTone { ok, warn, error, info, brand, neutral }

String money(num v, {String? currency}) => formatMoney(v, currencyCode: currency);

double toDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

// ── Motion ──────────────────────────────────────────────────────────────

/// Fades and slides its child in once, staggered by [index] (capped so long
/// lists don't wait). Use for list rows, cards and sections.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration duration;
  final double offsetY;
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.duration = const Duration(milliseconds: 380), this.offsetY = 14});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: 40 * widget.index.clamp(0, 10));
    Future.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        builder: (_, child) => Opacity(
          opacity: _t.value,
          child: Transform.translate(offset: Offset(0, (1 - _t.value) * widget.offsetY), child: child),
        ),
        child: widget.child,
      );
}

/// Counts up to [value] whenever it changes.
class CountUp extends StatelessWidget {
  final num value;
  final String Function(num v) format;
  final TextStyle? style;
  const CountUp({super.key, required this.value, required this.format, this.style});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(format(v), style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}

/// Material page route with a gentle fade + slide (SAP-like, not bouncy).
Route<T> marketRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, anim, _, child) {
        final t = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: t,
          child: SlideTransition(position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(t), child: child),
        );
      },
    );

// ── Building blocks ─────────────────────────────────────────────────────

/// Flat SAP card: white surface, hairline border, 12px radius, optional tap
/// with a subtle press scale.
class MarketCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  const MarketCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap, this.color, this.borderColor});

  @override
  State<MarketCard> createState() => _MarketCardState();
}

class _MarketCardState extends State<MarketCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final card = AnimatedScale(
      scale: _down ? 0.985 : 1,
      duration: const Duration(milliseconds: 120),
      child: Container(
        decoration: BoxDecoration(
          color: widget.color ?? p.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.borderColor ?? p.line),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            onHighlightChanged: widget.onTap == null ? null : (v) => setState(() => _down = v),
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
    return card;
  }
}

/// Small rounded status label, animating colour changes.
class StatusPill extends StatelessWidget {
  final String label;
  final MarketTone tone;
  final IconData? icon;
  const StatusPill(this.label, {super.key, this.tone = MarketTone.neutral, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = MarketPalette.of(context).tone(tone);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: c.fg), const SizedBox(width: 4)],
        Flexible(
          child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.fg)),
        ),
      ]),
    );
  }
}

/// Short form for a small tile: 7000 → 7k, 2450 → 2.4k, 3200000 → 3.2M.
/// Anything the tile's own format adds around the number (currency symbol,
/// unit, "%") is kept, so ৳7,000.00 becomes ৳7k.
String compactTileValue(num v, String Function(num v) format) {
  final full = format(v);
  final abs = v.abs();
  if (abs < 1000) return full;
  final first = full.indexOf(RegExp(r'\d'));
  final last = full.lastIndexOf(RegExp(r'\d'));
  if (first < 0) return full;
  var prefix = full.substring(0, first);
  final suffix = full.substring(last + 1);
  if (v < 0 && !prefix.contains('-')) prefix = '-$prefix';
  const units = [(1e12, 'T'), (1e9, 'B'), (1e6, 'M'), (1e3, 'k')];
  final (size, unit) = units.firstWhere((u) => abs >= u.$1);
  final scaled = abs / size;
  // One decimal below 100 (2.4k, 12.5k), none above (240k); no trailing .0.
  var text = scaled >= 100 ? scaled.floor().toString() : ((scaled * 10).floor() / 10).toString();
  if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
  return '$prefix$text$unit$suffix';
}

/// KPI tile: icon, count-up value, label and optional sub line. Large values
/// are shortened (compactTileValue) so they fit instead of ending in "…".
class KpiTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final num value;
  final String Function(num v)? format;
  final String? sub;
  final MarketTone tone;
  final VoidCallback? onTap;
  const KpiTile({super.key, required this.icon, required this.label, required this.value, this.format, this.sub, this.tone = MarketTone.brand, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final c = p.tone(tone);
    return MarketCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 18, color: c.fg),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            CountUp(
              value: value,
              format: (v) => compactTileValue(v, format ?? (v) => v.round().toString()),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text, height: 1.1),
            ),
            const SizedBox(height: 2),
            Text(sub == null ? label : '$label · $sub',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.label)),
          ]),
        ),
      ]),
    );
  }
}

/// Section title with optional trailing action.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const SectionHeader(this.title, {super.key, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: TextStyle(fontSize: 12, color: p.label)),
            ],
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

/// SAP-style segmented filter with a sliding selection and optional counts.
class MarketSegmented<T> extends StatelessWidget {
  final T value;
  final List<({T id, String label, int? count})> options;
  final ValueChanged<T> onChanged;
  const MarketSegmented({super.key, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
        child: Row(children: [
          for (final o in options)
            GestureDetector(
              onTap: () => onChanged(o.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: o.id == value ? p.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: o.id == value ? [BoxShadow(color: Colors.black.withValues(alpha: p.dark ? 0.3 : 0.06), blurRadius: 4, offset: const Offset(0, 1))] : null,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(o.label,
                      style: TextStyle(fontSize: 12.5, fontWeight: o.id == value ? FontWeight.w700 : FontWeight.w500, color: o.id == value ? p.brand : p.label)),
                  if (o.count != null && o.count! > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: o.id == value ? p.brandSoft : p.neutralBg, borderRadius: BorderRadius.circular(10)),
                      child: Text('${o.count}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: o.id == value ? p.brand : p.neutral)),
                    ),
                  ],
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Illustrated-message style empty / error state.
class MarketEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const MarketEmpty({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return FadeSlideIn(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: p.brandSoft, shape: BoxShape.circle),
            child: Icon(icon, size: 32, color: p.brand),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: p.label, height: 1.4)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      ),
    );
  }
}

/// Pulsing placeholder block for loading states.
class SkeletonBox extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;
  const SkeletonBox({super.key, this.height = 14, this.width, this.radius = 8});

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
  }
}

/// A list of skeleton cards.
class SkeletonList extends StatelessWidget {
  final int count;
  final double itemHeight;
  const SkeletonList({super.key, this.count = 6, this.itemHeight = 76});

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, _) => SkeletonBox(height: itemHeight, radius: 12),
      );
}

/// Label / value row for detail sheets.
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  const InfoRow(this.label, this.value, {super.key, this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 12.5, color: p.label))),
        Expanded(
          child: Text(value,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: emphasize ? 14 : 13, fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500, color: p.text)),
        ),
      ]),
    );
  }
}

/// Standard page scaffold for market screens: SAP shell bar look, pull to
/// refresh, optional floating action.
class MarketScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget>? actions;
  final Widget? fab;
  final Widget? bottom;
  const MarketScaffold({super.key, required this.title, this.subtitle, required this.body, this.actions, this.fab, this.bottom});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: p.line)),
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
        ]),
        actions: actions,
      ),
      floatingActionButton: fab,
      bottomNavigationBar: bottom,
      body: body,
    );
  }
}

/// Confirmation dialog; resolves true on confirm.
Future<bool> confirmMarket(BuildContext context, {required String title, required String message, String confirm = 'Delete', bool destructive = true}) async {
  final p = MarketPalette.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: p.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok == true;
}

void marketToast(BuildContext context, String message, {bool error = false}) {
  final p = MarketPalette.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? p.error : p.text,
      content: Text(message, style: TextStyle(color: p.card)),
    ));
}

/// Rounded-top bottom sheet that stays above the keyboard.
Future<T?> showMarketSheet<T>(BuildContext context, {required Widget Function(BuildContext) builder}) {
  final p = MarketPalette.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: builder(ctx),
    ),
  );
}

/// Light / dark accent pairs cycled through module menu lists so each row's
/// icon gets its own colour (same set the Sales home uses).
const kListAccents = <(Color, Color)>[
  (Color(0xFF0A6ED1), Color(0xFF4DB1FF)), // blue
  (Color(0xFF188918), Color(0xFF5DC122)), // green
  (Color(0xFFD20A0A), Color(0xFFFF6A6A)), // red
  (Color(0xFF0E7490), Color(0xFF38BDF8)), // teal
  (Color(0xFFE76500), Color(0xFFFF8A3D)), // orange
  (Color(0xFF7858FF), Color(0xFFA78BFA)), // violet
  (Color(0xFF4F46E5), Color(0xFF818CF8)), // indigo
  (Color(0xFFDF1278), Color(0xFFF472B6)), // pink
  (Color(0xFF0891B2), Color(0xFF22D3EE)), // cyan
  (Color(0xFFB45309), Color(0xFFFBBF24)), // amber
  (Color(0xFF4D7C0F), Color(0xFFA3E635)), // olive
  (Color(0xFF5B738B), Color(0xFFA9B4BE)), // grey
];

/// Tinted square icon for menu / area list rows; [index] picks the accent.
class AccentListIcon extends StatelessWidget {
  final IconData icon;
  final int index;
  final double size;
  const AccentListIcon(this.icon, {super.key, required this.index, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final (light, dark) = kListAccents[index % kListAccents.length];
    final fg = p.dark ? dark : light;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: fg.withValues(alpha: p.dark ? 0.18 : 0.12), borderRadius: BorderRadius.circular(9)),
      child: Icon(icon, size: size * 0.53, color: fg),
    );
  }
}
