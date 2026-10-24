import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/network/http_client.dart';
import '../../features/sell/market/presentation/widgets/market_ui.dart';

export '../../features/sell/market/presentation/widgets/market_ui.dart';

// SAP Horizon kit shared by HR, Settings and the form wizards: flat shell
// bar, hairline cards, soft tone icons, solid brand actions and light,
// purposeful motion (staggered fade-in, count-up, gentle press feedback).
// Same look as the Store / Sell screens (market_ui.dart). Colours come from [MarketPalette] so everything
// follows light / dark. Text stays sentence case — no uppercase, no
// letter-spacing.

// ── Accent gradients ────────────────────────────────────────────────────

/// Named accent gradients for hero headers, hub tiles and avatars.
enum Accent { ocean, violet, emerald, sunset, rose, amber, teal, slate, indigo, sky }

extension AccentColors on Accent {
  List<Color> get colors => switch (this) {
        Accent.ocean => const [Color(0xFF0070F2), Color(0xFF0070F2)],
        Accent.violet => const [Color(0xFF7858FF), Color(0xFF7858FF)],
        Accent.emerald => const [Color(0xFF188918), Color(0xFF188918)],
        Accent.sunset => const [Color(0xFFE76500), Color(0xFFE76500)],
        Accent.rose => const [Color(0xFFDF1278), Color(0xFFDF1278)],
        Accent.amber => const [Color(0xFFC87B00), Color(0xFFC87B00)],
        Accent.teal => const [Color(0xFF049F9A), Color(0xFF049F9A)],
        Accent.slate => const [Color(0xFF556B82), Color(0xFF556B82)],
        Accent.indigo => const [Color(0xFF5D36FF), Color(0xFF5D36FF)],
        Accent.sky => const [Color(0xFF1B90FF), Color(0xFF1B90FF)],
      };
  Color get primary => colors.first;

  /// Flat fill (kept as a gradient type for callers that take one).
  LinearGradient get gradient => LinearGradient(colors: colors);
}

/// Stable accent for a string (e.g. an employee name) so avatars keep colour.
Accent accentFor(String seed) => Accent.values[seed.hashCode.abs() % Accent.values.length];

// ── Routes ──────────────────────────────────────────────────────────────

/// Gentle fade + slide push (SAP-like, not bouncy).
Route<T> motionRoute<T>(Widget page) => PageRouteBuilder<T>(
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

Future<T?> pushMotion<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(motionRoute<T>(page));

// ── Press feedback ──────────────────────────────────────────────────────

/// Springy press-to-scale wrapper with a light haptic tick.
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  const PressScale({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.985});

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

// ── Surfaces ────────────────────────────────────────────────────────────

/// Flat SAP card: card surface, hairline border, 12px radius. A
/// [gradient] tints the card with its colour instead (used for highlights).
class GlowCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Gradient? gradient;
  final Color? color;
  final double radius;
  const GlowCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap, this.onLongPress, this.gradient, this.color, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final tint = gradient?.colors.first;
    final box = Container(
      decoration: BoxDecoration(
        color: tint ?? color ?? p.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: tint ?? p.line),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap == null ? null : () {
            HapticFeedback.selectionClick();
            onTap!();
          },
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (onTap == null && onLongPress == null) return box;
    return PressScale(onTap: null, onLongPress: null, child: box);
  }
}

/// SAP-style icon badge: soft tinted square with the accent-coloured icon.
class AccentIcon extends StatelessWidget {
  final IconData icon;
  final Accent accent;
  final double size;
  const AccentIcon(this.icon, {super.key, this.accent = Accent.ocean, this.size = 42});

  @override
  Widget build(BuildContext context) {
    final dark = MarketPalette.of(context).dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.primary.withValues(alpha: dark ? 0.22 : 0.1),
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Icon(icon, color: dark ? Color.lerp(accent.primary, Colors.white, 0.35) : accent.primary, size: size * 0.5),
    );
  }
}

/// Circular initials avatar (or network photo) with a stable gradient.
class InitialsAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double size;
  const InitialsAvatar(this.name, {super.key, this.imageUrl, this.size = 44});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final accent = accentFor(name);
    final url = imageUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: accent.primary.withValues(alpha: MarketPalette.of(context).dark ? 0.25 : 0.12)),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: url != null && url.isNotEmpty
          ? Image.network(url, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => _text(accent))
          : _text(accent),
    );
  }

  Widget _text(Accent accent) => Text(_initials, style: TextStyle(color: accent.primary, fontWeight: FontWeight.w700, fontSize: size * 0.36));
}

// ── Page scaffold ───────────────────────────────────────────────────────

/// Page with a collapsing gradient hero header. Pass [slivers] for the body.
/// Pull to refresh when [onRefresh] is set; the extended FAB shrinks to an
/// icon while scrolling down.
class MotionScaffold extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Accent accent;
  final List<Widget> slivers;
  final List<Widget>? actions;
  final Future<void> Function()? onRefresh;
  final String? fabLabel;
  final IconData fabIcon;
  final VoidCallback? onFab;
  final Widget? headerExtra;
  final double expandedHeight;
  final Widget? bottomBar;
  const MotionScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.accent = Accent.ocean,
    required this.slivers,
    this.actions,
    this.onRefresh,
    this.fabLabel,
    this.fabIcon = Icons.add_rounded,
    this.onFab,
    this.headerExtra,
    this.expandedHeight = 150,
    this.bottomBar,
  });

  @override
  State<MotionScaffold> createState() => _MotionScaffoldState();
}

class _MotionScaffoldState extends State<MotionScaffold> {
  bool _fabExtended = true;

  bool _onScroll(UserScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final ext = n.direction != ScrollDirection.reverse;
    if (ext != _fabExtended && n.direction != ScrollDirection.idle) setState(() => _fabExtended = ext);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    Widget scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: p.card,
          foregroundColor: p.text,
          surfaceTintColor: Colors.transparent,
          shape: Border(bottom: BorderSide(color: p.line)),
          titleSpacing: 0,
          actions: widget.actions,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
          ]),
        ),
        if (widget.headerExtra != null)
          SliverPadding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), sliver: SliverToBoxAdapter(child: widget.headerExtra!)),
        ...widget.slivers,
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
    if (widget.onRefresh != null) {
      scroll = RefreshIndicator(onRefresh: widget.onRefresh!, color: p.brand, child: scroll);
    }
    return Scaffold(
      backgroundColor: p.bg,
      bottomNavigationBar: widget.bottomBar,
      floatingActionButton: widget.onFab == null
          ? null
          : _MotionFab(label: widget.fabLabel ?? 'New', icon: widget.fabIcon, extended: _fabExtended, accent: widget.accent, onTap: widget.onFab!),
      body: NotificationListener<UserScrollNotification>(onNotification: _onScroll, child: scroll),
    );
  }
}

class _MotionFab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool extended;
  final Accent accent;
  final VoidCallback onTap;
  const _MotionFab({required this.label, required this.icon, required this.extended, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return FadeSlideIn(
      child: PressScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: extended ? 18 : 13),
          decoration: BoxDecoration(
            color: p.brand,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: p.dark ? 0.35 : 0.12), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 20),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: extended
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                    )
                  : const SizedBox.shrink(),
            ),
          ]),
        ),
      ),
    );
  }
}

/// SAP search field shown under the shell bar.
class HeaderSearch extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  const HeaderSearch({super.key, this.hint = 'Search', required this.onChanged, this.controller});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: w));
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(color: p.text, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: p.card,
        hintText: hint,
        hintStyle: TextStyle(color: p.label.withValues(alpha: 0.8), fontSize: 14),
        prefixIcon: Icon(Icons.search_rounded, color: p.label, size: 20),
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
        enabledBorder: b(p.line),
        border: b(p.line),
        focusedBorder: b(p.brand, 1.5),
      ),
    );
  }
}

/// Wraps a box widget as a padded sliver.
Widget sliverBox(Widget child, {EdgeInsets padding = const EdgeInsets.fromLTRB(16, 16, 16, 0)}) =>
    SliverPadding(padding: padding, sliver: SliverToBoxAdapter(child: child));

/// Staggered sliver list.
Widget sliverStagger({required int count, required Widget Function(BuildContext, int) builder, EdgeInsets padding = const EdgeInsets.fromLTRB(16, 12, 16, 0), double gap = 10}) =>
    SliverPadding(
      padding: padding,
      sliver: SliverList.separated(
        itemCount: count,
        separatorBuilder: (_, _) => SizedBox(height: gap),
        itemBuilder: (ctx, i) => FadeSlideIn(index: i, offsetY: 22, child: builder(ctx, i)),
      ),
    );

/// Loading / error / empty states as slivers.
Widget sliverSkeleton({int count = 6, double height = 78}) => SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      sliver: SliverList.separated(
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, _) => SkeletonBox(height: height, radius: 12),
      ),
    );

Widget sliverEmpty({required IconData icon, required String title, String? message, String? actionLabel, VoidCallback? onAction}) =>
    SliverToBoxAdapter(child: MarketEmpty(icon: icon, title: title, message: message, actionLabel: actionLabel, onAction: onAction));

// ── Rows & tiles ────────────────────────────────────────────────────────

/// Modern list row: leading avatar/icon, title, subtitle, meta line,
/// trailing pill, swipe-to-delete (with confirm) and tap.
class MotionTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? meta;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Future<bool> Function()? onDelete;
  const MotionTile({super.key, this.leading, required this.title, this.subtitle, this.meta, this.trailing, this.onTap, this.onLongPress, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final card = GlowCard(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.label, height: 1.3)),
            ],
            if (meta != null && meta!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(meta!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label.withValues(alpha: 0.85))),
            ],
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
    if (onDelete == null) return card;
    return Dismissible(
      key: ValueKey('${title}_${subtitle}_${identityHashCode(this)}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onDelete!(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(color: p.errorBg, borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.delete_outline_rounded, color: p.error),
      ),
      child: card,
    );
  }
}

/// Feature tile for hub grids.
class HubTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? caption;
  final Accent accent;
  final VoidCallback onTap;
  final String? badge;
  const HubTile({super.key, required this.icon, required this.label, this.caption, this.accent = Accent.ocean, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return GlowCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AccentIcon(icon, accent: accent, size: 40),
          const Spacer(),
          if (badge != null) StatusPill(badge!, tone: MarketTone.brand),
        ]),
        const Spacer(),
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text, height: 1.2)),
        if (caption != null) ...[
          const SizedBox(height: 2),
          Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
        ],
      ]),
    );
  }
}

/// Section of hub tiles in a 2-column grid, as a sliver.
Widget sliverHubSection({required String title, String? subtitle, required List<HubTile> tiles, int startIndex = 0}) => SliverMainAxisGroup(slivers: [
      SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 16), sliver: SliverToBoxAdapter(child: SectionHeader(title, subtitle: subtitle))),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.35),
          itemCount: tiles.length,
          itemBuilder: (_, i) => FadeSlideIn(index: startIndex + i, offsetY: 24, child: tiles[i]),
        ),
      ),
    ]);

/// SAP KPI tile: tone icon, count-up value and label.
class GradientKpi extends StatelessWidget {
  final IconData icon;
  final String label;
  final num value;
  final String Function(num v)? format;
  final Accent accent;
  final VoidCallback? onTap;
  const GradientKpi({super.key, required this.icon, required this.label, required this.value, this.format, this.accent = Accent.ocean, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return GlowCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        AccentIcon(icon, accent: accent, size: 34),
        const SizedBox(height: 10),
        CountUp(
          value: value,
          format: format ?? (v) => NumberFormat.decimalPattern().format(v.round()),
          style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w700, height: 1.1),
        ),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.label, fontSize: 11.5)),
      ]),
    );
  }
}

/// Horizontal strip of KPI cards.
class KpiStrip extends StatelessWidget {
  final List<Widget> children;
  final double height;
  const KpiStrip({super.key, required this.children, this.height = 112});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => FadeSlideIn(index: i, child: SizedBox(width: 150, child: children[i])),
        ),
      );
}

/// KPI tiles in a 2-column grid — the Store home's layout (store_home_page.dart).
/// Use with [KpiTile]s; sits in a box sliver with the page's 16px gutter.
class KpiGrid extends StatelessWidget {
  final List<Widget> children;
  const KpiGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.35,
          children: [for (var i = 0; i < children.length; i++) FadeSlideIn(index: i, child: children[i])],
        ),
      );
}

/// Animated circular progress ring with centered label.
class ProgressRing extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final double stroke;
  final Color? color;
  final Widget? center;
  const ProgressRing({super.key, required this.value, this.size = 64, this.stroke = 7, this.color, this.center});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, color ?? p.brand, p.surface, stroke),
          child: Center(child: center),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color;
  final Color track;
  final double stroke;
  _RingPainter(this.v, this.color, this.track, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v || old.color != color || old.track != track;
}

/// Horizontal chip filter with animated selection.
class ChipFilter<T> extends StatelessWidget {
  final T value;
  final List<({T id, String label, int? count})> options;
  final ValueChanged<T> onChanged;
  final EdgeInsets padding;
  const ChipFilter({super.key, required this.value, required this.options, required this.onChanged, this.padding = const EdgeInsets.symmetric(horizontal: 16)});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        physics: const BouncingScrollPhysics(),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final o = options[i];
          final sel = o.id == value;
          return PressScale(
            onTap: () => onChanged(o.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? p.brandSoft : p.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: sel ? p.brand : p.line),
              ),
              child: Text(
                o.count == null ? o.label : '${o.label}  ${o.count}',
                style: TextStyle(fontSize: 12.5, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? p.brand : p.text),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Form kit ────────────────────────────────────────────────────────────

String errorMessage(Object e, [String fallback = 'Something went wrong']) =>
    e is ApiException && e.message.trim().isNotEmpty ? e.message : fallback;

InputDecoration motionInput(BuildContext context, {String? hint, IconData? icon, Widget? suffix}) {
  final p = MarketPalette.of(context);
  OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(color: p.label.withValues(alpha: 0.75), fontSize: 14),
    prefixIcon: icon == null ? null : Icon(icon, size: 19, color: p.label),
    suffixIcon: suffix,
    filled: true,
    fillColor: p.card,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    enabledBorder: b(p.line),
    border: b(p.line),
    focusedBorder: b(p.brand, 1.6),
    errorBorder: b(p.error),
    focusedErrorBorder: b(p.error, 1.6),
  );
}

/// Labelled field wrapper.
class FormLabel extends StatelessWidget {
  final String label;
  final bool required;
  final Widget child;
  final String? help;
  const FormLabel({super.key, required this.label, required this.child, this.required = false, this.help});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(
          TextSpan(children: [TextSpan(text: label), if (required) TextSpan(text: ' *', style: TextStyle(color: p.error))]),
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.label),
        ),
        const SizedBox(height: 6),
        child,
        if (help != null) ...[const SizedBox(height: 4), Text(help!, style: TextStyle(fontSize: 11.5, color: p.label))],
      ]),
    );
  }
}

String fmtDate(DateTime? d) => d == null ? '' : DateFormat('d MMM yyyy').format(d.toLocal());
String fmtDateTime(DateTime? d) => d == null ? '' : DateFormat('d MMM yyyy, h:mm a').format(d.toLocal());
String fmtTime(DateTime? d) => d == null ? '' : DateFormat('h:mm a').format(d.toLocal());
DateTime? parseDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

/// Tap-to-pick date (and optionally time) field.
class DatePickField extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool withTime;
  final String hint;
  final DateTime? firstDate;
  final DateTime? lastDate;
  const DatePickField({super.key, required this.value, required this.onChanged, this.withTime = false, this.hint = 'Pick a date', this.firstDate, this.lastDate});

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: firstDate ?? DateTime(now.year - 60),
      lastDate: lastDate ?? DateTime(now.year + 10),
    );
    if (d == null) return;
    if (!withTime) {
      onChanged(d);
      return;
    }
    if (!context.mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(value ?? now));
    onChanged(DateTime(d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final text = value == null ? '' : (withTime ? fmtDateTime(value) : fmtDate(value));
    return PressScale(
      scale: 0.98,
      onTap: () => _pick(context),
      child: InputDecorator(
        decoration: motionInput(context, hint: hint, icon: withTime ? Icons.schedule_rounded : Icons.event_rounded,
            suffix: value == null ? null : IconButton(icon: Icon(Icons.close_rounded, size: 18, color: p.label), onPressed: () => onChanged(null))),
        isEmpty: value == null,
        child: Text(text, style: TextStyle(fontSize: 14, color: p.text)),
      ),
    );
  }
}

/// Tap-to-pick time of day field (value as "HH:mm").
class TimePickField extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final String hint;
  const TimePickField({super.key, required this.value, required this.onChanged, this.hint = 'Pick a time'});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    TimeOfDay? parsed;
    final v = value;
    if (v != null && v.contains(':')) {
      final parts = v.split(':');
      parsed = TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
    }
    return PressScale(
      scale: 0.98,
      onTap: () async {
        final t = await showTimePicker(context: context, initialTime: parsed ?? const TimeOfDay(hour: 9, minute: 0));
        if (t != null) onChanged('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
      },
      child: InputDecorator(
        decoration: motionInput(context, hint: hint, icon: Icons.access_time_rounded),
        isEmpty: parsed == null,
        child: Text(parsed == null ? '' : parsed.format(context), style: TextStyle(fontSize: 14, color: p.text)),
      ),
    );
  }
}

/// Searchable picker option.
class PickOption {
  final Object id;
  final String label;
  final String? sub;
  const PickOption(this.id, this.label, {this.sub});
}

/// Field that opens a searchable bottom-sheet picker.
class PickerField extends StatelessWidget {
  final Object? value;
  final List<PickOption> options;
  final ValueChanged<Object?> onChanged;
  final String hint;
  final IconData? icon;
  final bool allowClear;
  const PickerField({super.key, required this.value, required this.options, required this.onChanged, this.hint = 'Select', this.icon, this.allowClear = true});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final sel = options.where((o) => o.id.toString() == value?.toString()).firstOrNull;
    return PressScale(
      scale: 0.98,
      onTap: () async {
        final picked = await showPickerSheet(context, title: hint, options: options, selected: value);
        if (picked != null) onChanged(picked.id);
      },
      child: InputDecorator(
        decoration: motionInput(context,
            hint: hint,
            icon: icon,
            suffix: sel != null && allowClear
                ? IconButton(icon: Icon(Icons.close_rounded, size: 18, color: p.label), onPressed: () => onChanged(null))
                : Icon(Icons.expand_more_rounded, color: p.label)),
        isEmpty: sel == null,
        child: Text(sel?.label ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.text)),
      ),
    );
  }
}

Future<PickOption?> showPickerSheet(BuildContext context, {required String title, required List<PickOption> options, Object? selected}) =>
    showMarketSheet<PickOption>(context, builder: (ctx) => _PickerSheet(title: title, options: options, selected: selected));

class _PickerSheet extends StatefulWidget {
  final String title;
  final List<PickOption> options;
  final Object? selected;
  const _PickerSheet({required this.title, required this.options, this.selected});

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final q = _q.toLowerCase();
    final list = widget.options.where((o) => q.isEmpty || o.label.toLowerCase().contains(q) || (o.sub ?? '').toLowerCase().contains(q)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(children: [
        const SheetGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(children: [
            Expanded(child: Text(widget.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text))),
          ]),
        ),
        if (widget.options.length > 6)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(autofocus: false, onChanged: (v) => setState(() => _q = v), decoration: motionInput(context, hint: 'Search', icon: Icons.search_rounded)),
          ),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text('No matches', style: TextStyle(color: p.label)))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final o = list[i];
                    final sel = o.id.toString() == widget.selected?.toString();
                    return ListTile(
                      title: Text(o.label, style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? p.brand : p.text)),
                      subtitle: o.sub == null ? null : Text(o.sub!, style: TextStyle(color: p.label, fontSize: 12)),
                      trailing: sel ? Icon(Icons.check_circle_rounded, color: p.brand) : null,
                      onTap: () => Navigator.pop(context, o),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

/// Small drag handle for bottom sheets.
class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Container(width: 40, height: 4, decoration: BoxDecoration(color: MarketPalette.of(context).line, borderRadius: BorderRadius.circular(2))),
        ),
      );
}

/// Switch row for forms.
class SwitchField extends StatelessWidget {
  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  const SwitchField({super.key, required this.label, this.sub, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
            if (sub != null) Text(sub!, style: TextStyle(fontSize: 11.5, color: p.label)),
          ]),
        ),
        Switch.adaptive(value: value, onChanged: onChanged),
      ]),
    );
  }
}

/// Bottom-sheet form shell: title, scrollable body, sticky primary button
/// with a busy spinner.
class FormSheet extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final String submitLabel;
  final bool busy;
  final VoidCallback? onSubmit;
  final Widget? extraAction;
  const FormSheet({super.key, required this.title, this.subtitle, required this.children, this.submitLabel = 'Save', this.busy = false, this.onSubmit, this.extraAction});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SheetGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
                if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12.5, color: p.label)),
              ]),
            ),
            ?extraAction,
            IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: p.label)),
          ]),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < children.length; i++) FadeSlideIn(index: i, offsetY: 10, child: children[i]),
            ]),
          ),
        ),
        if (onSubmit != null || busy)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: GradientButton(label: submitLabel, busy: busy, onTap: onSubmit),
            ),
          ),
      ]),
    );
  }
}

/// Full-width SAP emphasized button (solid brand), with a busy spinner.
class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool busy;
  final VoidCallback? onTap;
  final Accent accent;
  const GradientButton({super.key, required this.label, this.icon, this.busy = false, this.onTap, this.accent = Accent.ocean});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final enabled = onTap != null && !busy;
    // SAP button semantics: rose = reject / destructive, sunset / amber =
    // critical; every other accent is the emphasized brand button.
    final color = switch (accent) {
      Accent.rose => p.error,
      Accent.sunset || Accent.amber => p.warn,
      _ => p.brand,
    };
    return PressScale(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled || busy ? 1 : 0.5,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: busy
                ? const SizedBox(key: ValueKey('busy'), width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Row(key: const ValueKey('label'), mainAxisSize: MainAxisSize.min, children: [
                    if (icon != null) ...[Icon(icon, color: Colors.white, size: 19), const SizedBox(width: 8)],
                    Text(label, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600)),
                  ]),
          ),
        ),
      ),
    );
  }
}

/// Opens a full-height-capable bottom sheet (keyboard-aware).
Future<T?> showMotionSheet<T>(BuildContext context, Widget Function(BuildContext) builder) => showMarketSheet<T>(context, builder: builder);

/// Action sheet with icon rows; returns the picked key.
Future<String?> showActionSheet(BuildContext context, {String? title, required List<({String key, String label, IconData icon, bool destructive})> actions}) {
  return showMarketSheet<String>(context, builder: (ctx) {
    final p = MarketPalette.of(ctx);
    return SafeArea(
      top: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SheetGrabber(),
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text))),
          ),
        for (var i = 0; i < actions.length; i++)
          FadeSlideIn(
            index: i,
            offsetY: 8,
            child: ListTile(
              leading: Icon(actions[i].icon, color: actions[i].destructive ? p.error : p.brand),
              title: Text(actions[i].label, style: TextStyle(fontWeight: FontWeight.w600, color: actions[i].destructive ? p.error : p.text)),
              onTap: () => Navigator.pop(ctx, actions[i].key),
            ),
          ),
        const SizedBox(height: 10),
      ]),
    );
  });
}

// ── Misc helpers ────────────────────────────────────────────────────────

bool asBool(dynamic v, {bool fallback = false}) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == '1';
  return fallback;
}

String str(dynamic v) => v == null ? '' : v.toString();

/// Reads a nested name like row['department']['name'].
String nested(Map<String, dynamic> row, String rel, [String key = 'name']) {
  final r = row[rel];
  return r is Map ? str(r[key]) : '';
}

/// Tone for common status words.
MarketTone toneForStatus(String? status) {
  final s = (status ?? '').toLowerCase();
  if (s.isEmpty) return MarketTone.neutral;
  if (['approved', 'active', 'paid', 'present', 'completed', 'done', 'hired', 'success', 'accepted', 'open', 'online', 'yes'].any(s.contains)) {
    return MarketTone.ok;
  }
  if (['pending', 'draft', 'late', 'waiting', 'processing', 'review', 'partial', 'hold', 'shortlist', 'interview'].any(s.contains)) {
    return MarketTone.warn;
  }
  if (['reject', 'cancel', 'absent', 'failed', 'inactive', 'blocked', 'denied', 'closed', 'offline', 'expired', 'no'].any(s.contains)) {
    return MarketTone.error;
  }
  return MarketTone.info;
}

/// Sentence-cases a raw enum/status string: "on_leave" → "On leave".
String humanize(String? s) {
  final t = (s ?? '').replaceAll(RegExp(r'[_\-]+'), ' ').trim().toLowerCase();
  if (t.isEmpty) return '';
  return t[0].toUpperCase() + t.substring(1);
}
