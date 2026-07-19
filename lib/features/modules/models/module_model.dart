import 'package:flutter/material.dart';

int _toPositiveInt(dynamic value) {
  final parsed = int.tryParse(value?.toString() ?? '');
  return (parsed != null && parsed > 0) ? parsed : 0;
}

/// Keyed by the real `modules.code` values (lowercased) from
/// cloud/src/seed/permission.seed.ts — not guessed route slugs.
const Map<String, IconData> _moduleIcons = {
  'dashboard': Icons.dashboard,
  'hr': Icons.badge,
  'purchase': Icons.shopping_cart,
  'sell': Icons.point_of_sale,
  'restaurant': Icons.restaurant,
  'settings': Icons.settings,
  'profile': Icons.person,
  'market': Icons.storefront,
  'aptigen': Icons.hotel,
  'inventory': Icons.inventory_2,
  'accounting': Icons.account_balance,
  'crm': Icons.people_alt,
  'chat': Icons.chat_bubble,
  'note': Icons.note_alt,
  'b2b': Icons.business_center,
  'hospitality': Icons.hotel,
  'machine': Icons.precision_manufacturing,
  'institutions': Icons.school,
  'store': Icons.warehouse,
  'excel': Icons.grid_on,
};

/// Ported from erp/desktop's launchpadModules.ts (buildLaunchpadModules).
class LaunchpadModule {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final String? route;

  const LaunchpadModule({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    this.route,
  });

  bool get isHr => id == 'hr';
}

Color _parseColor(String raw) {
  final match = RegExp(r'bg-\[([^\]]+)\]', caseSensitive: false).firstMatch(raw);
  final hex = (match?.group(1) ?? raw).trim();
  if (hex.startsWith('#')) {
    final cleaned = hex.substring(1);
    final value = int.tryParse(cleaned.length == 6 ? 'FF$cleaned' : cleaned, radix: 16);
    if (value != null) return Color(value);
  }
  return const Color(0xFF475569);
}

List<LaunchpadModule> buildLaunchpadModules(List<dynamic> installedRows, Set<int> allowedModuleIds) {
  final mapped = <LaunchpadModule>[];
  final seenKeys = <String>{};

  for (final row in installedRows) {
    final map = (row as Map).cast<String, dynamic>();
    final moduleRow = (map['module'] ?? map['modules'] ?? {}) as Map;
    final moduleId = _toPositiveInt(moduleRow['id'] ?? map['module_id'] ?? map['moduleId']);
    final status = (map['status'] ?? 'installed').toString().trim().toLowerCase();
    final permitted = allowedModuleIds.isEmpty || allowedModuleIds.contains(moduleId);
    final enabled = map['is_enabled'] != false && status != 'uninstalled';
    if (moduleId == 0 || !permitted || !enabled) continue;

    final code = (moduleRow['code'] ?? moduleRow['slug'] ?? moduleRow['id'] ?? '').toString().trim().toLowerCase();
    final routeRaw = (moduleRow['route'] ?? '').toString().trim();
    final route = routeRaw.isEmpty ? null : (routeRaw.startsWith('/') ? routeRaw : '/$routeRaw');
    final key = route ?? code;
    if (code.isEmpty || seenKeys.contains(key)) continue;
    seenKeys.add(key);

    mapped.add(LaunchpadModule(
      id: code,
      label: (moduleRow['name'] ?? code).toString().trim(),
      icon: _moduleIcons[code] ?? Icons.apps,
      color: _parseColor((moduleRow['color'] ?? '').toString()),
      route: route,
    ));
  }

  return mapped;
}
