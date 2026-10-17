import 'package:flutter/material.dart';
import '../banners/market_media.dart';
import '../widgets/market_ui.dart';
import 'storefront_widgets.dart';

/// Values the header and the preview render (the saved profile for the
/// header, the live form for the preview).
class StoreLook {
  final String name;
  final String? tagline;
  final String? avatarUrl;
  final String? coverUrl;
  final String? accent;
  final String? city;
  final bool verified;
  final bool active;
  const StoreLook({
    required this.name,
    this.tagline,
    this.avatarUrl,
    this.coverUrl,
    this.accent,
    this.city,
    this.verified = false,
    this.active = true,
  });
}

Widget _avatar(BuildContext context, StoreLook s, double size, {bool round = false}) {
  final p = MarketPalette.of(context);
  final accent = parseHex(s.accent) ?? p.brand;
  final initial = s.name.trim().isEmpty ? 'S' : s.name.trim()[0].toUpperCase();
  final radius = round ? BorderRadius.circular(size) : BorderRadius.circular(14);
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: p.card,
      borderRadius: radius,
      border: Border.all(color: p.card, width: 3),
    ),
    child: ClipRRect(
      borderRadius: radius,
      child: MarketNetImage(
        s.avatarUrl,
        fallback: Container(
          color: accent.withValues(alpha: 0.14),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w800, color: accent),
          ),
        ),
      ),
    ),
  );
}

Widget _cover(BuildContext context, StoreLook s) {
  final p = MarketPalette.of(context);
  final accent = parseHex(s.accent) ?? p.brand;
  return MarketNetImage(
    s.coverUrl,
    fallback: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.30), accent.withValues(alpha: 0.10)],
        ),
      ),
    ),
  );
}

/// SAP object-page header: cover, avatar, name, verified badge and KPI facets.
class StorefrontHeader extends StatelessWidget {
  final StoreLook store;
  final int? listings;
  final int? activeListings;
  final int? followers;
  const StorefrontHeader({super.key, required this.store, this.listings, this.activeListings, this.followers});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    Widget facet(String label, int? v, IconData icon, {bool left = false}) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: left ? Border(left: BorderSide(color: p.line)) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: p.label),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: p.label),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            v == null
                ? Text(
                    '–',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.label),
                  )
                : CountUp(
                    value: v,
                    format: (x) => x.round().toString(),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text),
                  ),
          ],
        ),
      ),
    );

    return MarketCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: SizedBox(height: 128, width: double.infinity, child: _cover(context, store)),
              ),
              Positioned(left: 14, bottom: -30, child: _avatar(context, store, 76)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(102, 8, 14, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          store.name.isEmpty ? 'Your store' : store.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.text),
                        ),
                      ),
                      if (store.verified) ...[const SizedBox(width: 5), Icon(Icons.verified, size: 17, color: p.brand)],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      StatusPill(store.active ? 'Active' : 'Inactive', tone: store.active ? MarketTone.ok : MarketTone.warn),
                      if (store.verified) const StatusPill('Verified', tone: MarketTone.info, icon: Icons.verified_outlined),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (store.tagline ?? '').isEmpty ? 'Add a tagline so buyers know what you sell' : store.tagline!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: p.label, height: 1.35),
                ),
                if ((store.city ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 14, color: p.label),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          store.city!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: p.label),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: p.line)),
            ),
            child: Row(
              children: [
                facet('Listings', listings, Icons.storefront_outlined),
                facet('Active', activeListings, Icons.trending_up, left: true),
                facet('Followers', followers, Icons.group_outlined, left: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live preview of the store header as buyers see it on the market.
class StorePreviewCard extends StatelessWidget {
  final StoreLook store;
  const StorePreviewCard({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final accent = parseHex(store.accent) ?? p.brand;
    return MarketCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_outlined, size: 17, color: p.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Preview',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
                ),
              ),
              Text('On the market', style: TextStyle(fontSize: 11.5, color: p.label)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.line),
              color: p.bg,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AspectRatio(
                      aspectRatio: 3 / 1,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: KeyedSubtree(key: ValueKey('${store.coverUrl}${store.accent}'), child: _cover(context, store)),
                      ),
                    ),
                    Positioned(left: 12, bottom: -24, child: _avatar(context, store, 56, round: true)),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 32, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              store.name.isEmpty ? 'Store name' : store.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.text),
                            ),
                          ),
                          if (store.verified) ...[const SizedBox(width: 4), Icon(Icons.verified, size: 15, color: accent)],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        (store.tagline ?? '').isEmpty ? 'Your tagline shows here' : store.tagline!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.label, height: 1.35),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(20)),
                            child: const Text(
                              'Follow',
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: p.line),
                            ),
                            child: Text(
                              'Message',
                              style: TextStyle(color: p.text, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _tab(context, 'Products', accent, true),
                          const SizedBox(width: 16),
                          _tab(context, 'About', accent, false),
                          const SizedBox(width: 16),
                          _tab(context, 'Reviews', accent, false),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, String label, Color accent, bool on) {
    final p = MarketPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? accent : p.label),
        ),
        const SizedBox(height: 4),
        AnimatedContainer(duration: const Duration(milliseconds: 220), height: 2, width: 28, color: on ? accent : Colors.transparent),
      ],
    );
  }
}
