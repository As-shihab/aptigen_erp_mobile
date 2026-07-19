import 'package:flutter/material.dart';

int toNum(dynamic value) {
  final parsed = num.tryParse(value?.toString() ?? '');
  return parsed?.toInt() ?? 0;
}

/// Small category-keyed icon fallback — a lean stand-in for desktop's
/// `resolveAppIcon`, which resolves a `modules.icon` key against a much
/// larger icon-alias table not worth porting 1:1 for a mobile card grid.
const Map<String, IconData> _categoryIcons = {
  'hr': Icons.badge,
  'sales': Icons.point_of_sale,
  'purchase': Icons.shopping_cart,
  'inventory': Icons.inventory_2,
  'accounting': Icons.account_balance,
  'crm': Icons.people_alt,
  'restaurant': Icons.restaurant,
  'hospitality': Icons.hotel,
  'communication': Icons.chat_bubble,
  'productivity': Icons.note_alt,
  'manufacturing': Icons.precision_manufacturing,
  'education': Icons.school,
  'commerce': Icons.storefront,
};

IconData iconForCategory(String? category) {
  final key = (category ?? '').trim().toLowerCase();
  return _categoryIcons[key] ?? Icons.extension_outlined;
}

Color _parseColor(String? raw) {
  if (raw == null || raw.isEmpty) return AppMarketPalette.next();
  final match = RegExp(r'#([0-9a-fA-F]{6})').firstMatch(raw);
  final hex = match?.group(1);
  if (hex != null) return Color(int.parse('FF$hex', radix: 16));
  return AppMarketPalette.next();
}

/// Deterministic fallback accent palette for modules with no `color` set —
/// desktop falls back to a category-based gradient class; a small rotating
/// palette gives the same "every card looks distinct" effect on mobile.
class AppMarketPalette {
  static const _colors = [
    Color(0xFF0A6ED1),
    Color(0xFFF97316),
    Color(0xFF8B5CF6),
    Color(0xFF22C55E),
    Color(0xFFE11D48),
    Color(0xFF14B8A6),
  ];
  static int _i = 0;
  static Color next() => _colors[(_i++) % _colors.length];
}

/// Ported from erp/desktop's Market.tsx `mapModuleToMarketApp` — a `modules`
/// row plus its `workplace_has_module` install state.
class MarketApp {
  final int id;
  final String name;
  final String? shortInfo;
  final String? description;
  final String category;
  final IconData icon;
  final Color color;
  final String status; // free-form badge text from modules.status
  final bool isInstallable;
  final bool isUninstallable;
  final bool isFeatured;
  bool installed;

  MarketApp({
    required this.id,
    required this.name,
    this.shortInfo,
    this.description,
    required this.category,
    required this.icon,
    required this.color,
    required this.status,
    required this.isInstallable,
    required this.isUninstallable,
    required this.isFeatured,
    this.installed = false,
  });

  factory MarketApp.fromJson(Map<String, dynamic> json) {
    final category = (json['category'] ?? 'General').toString().trim();
    return MarketApp(
      id: toNum(json['id']),
      name: (json['name'] ?? 'Module').toString(),
      shortInfo: json['short_info']?.toString(),
      description: json['description']?.toString(),
      category: category.isEmpty ? 'General' : category,
      icon: iconForCategory(category),
      color: _parseColor(json['color']?.toString()),
      status: (json['status'] ?? 'active').toString(),
      isInstallable: json['is_installable'] != false,
      isUninstallable: json['is_uninstallable'] != false,
      isFeatured: json['is_featured'] == true,
    );
  }
}
