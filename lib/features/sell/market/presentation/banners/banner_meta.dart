import 'package:flutter/material.dart';
import '../widgets/market_ui.dart';
import 'form_kit.dart';

// Banner placements, tones and the save body — mirrors erp/desktop's
// CreateBanner.tsx (PLACEMENTS, TONES, payload).

class BannerPlacement {
  final String id;
  final String label;
  final String segment;
  final String desc;
  final IconData icon;
  final double aspect;
  const BannerPlacement(this.id, this.label, this.segment, this.desc, this.icon, this.aspect);
}

const bannerPlacements = <BannerPlacement>[
  BannerPlacement('hero', 'Hero slider', 'Hero', 'Full width, top of the market home page', Icons.view_carousel_outlined, 16 / 9),
  BannerPlacement('promo_card', 'Promo card', 'Promo cards', 'Small card in the promo grid', Icons.dashboard_outlined, 4 / 3),
  BannerPlacement('strip', 'Banner strip', 'Strip', 'Wide banner between sections', Icons.view_stream_outlined, 3 / 1),
];

BannerPlacement bannerPlacement(String? id) => bannerPlacements.firstWhere((p) => p.id == id, orElse: () => bannerPlacements.first);

const bannerTones = ['blue', 'rose', 'amber', 'lime', 'sky', 'violet'];

const bannerCtaLabels = ['Shop now', 'Buy now', 'View listing', 'Explore now', 'Learn more', 'Get started', 'Claim offer'];

/// Accent for a tone key (fixed, not theme dependent) and a tinted surface.
({Color fg, Color bg}) bannerTone(BuildContext context, String? tone) {
  final dark = MarketPalette.of(context).dark;
  final base = switch (tone) {
    'rose' => const Color(0xFFE11D48),
    'amber' => const Color(0xFFD97706),
    'lime' => const Color(0xFF65A30D),
    'sky' => const Color(0xFF0284C7),
    'violet' => const Color(0xFF7C3AED),
    _ => const Color(0xFF2563EB),
  };
  return (fg: base, bg: base.withValues(alpha: dark ? 0.22 : 0.12));
}

String sentence(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Full body for POST / PUT. approval_status is platform-owned — never sent.
Map<String, dynamic> bannerBody(Map<String, dynamic> b) {
  String? iso(dynamic v) {
    final d = v is DateTime ? v : parseDate(v);
    return d?.toUtc().toIso8601String();
  }

  return {
    'placement': b['placement'] ?? 'hero',
    'title': '${b['title'] ?? ''}'.trim(),
    'subtitle': orNull('${b['subtitle'] ?? ''}'),
    'cta_label': orNull('${b['cta_label'] ?? ''}'),
    'link_url': orNull('${b['link_url'] ?? ''}'),
    'image_url': orNull('${b['image_url'] ?? ''}'),
    'mobile_image_url': orNull('${b['mobile_image_url'] ?? ''}'),
    'tone': orNull('${b['tone'] ?? ''}'),
    'sort_order': toInt(b['sort_order']),
    'is_active': b['is_active'] == true,
    'starts_at': iso(b['starts_at']),
    'ends_at': iso(b['ends_at']),
  };
}
