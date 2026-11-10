import '../../../core/network/http_client.dart';
import '../models/market_app.dart';

/// Ported from erp/desktop's Market.tsx + cloud's market.controller.ts —
/// the "App Marketplace" (browse/install/uninstall the workplace's own ERP
/// modules), not a 3rd-party plugin store.
class MarketService {
  final ApiClient _client;
  MarketService(this._client);

  String _escapeOData(String value) => value.replaceAll("'", "''");

  Future<List<MarketApp>> loadCatalog({String search = '', String category = 'all'}) async {
    // is_mobile gates modules that don't have a mobile screen built for them
    // yet (same flag the home launcher already filters on — see
    // module_model.dart's buildLaunchpadModules) — the marketplace shouldn't
    // let someone "install" a desktop-only module from the phone.
    final filters = ['is_active eq true', 'is_mobile eq true'];
    if (category != 'all') {
      filters.add("contains(tolower(category),'${_escapeOData(category.toLowerCase())}')");
    }
    if (search.trim().isNotEmpty) {
      final q = _escapeOData(search.trim().toLowerCase());
      filters.add("(contains(tolower(name),'$q') or contains(tolower(category),'$q'))");
    }
    final results = await Future.wait<Object?>([
      _client.get('modules?\$filter=${filters.join(' and ')}&\$top=200'),
      // Price / subscription / welcome-offer state, computed server-side —
      // the same call desktop's Market.tsx makes. Optional: a failure just
      // leaves the raw modules.price / is_paid from the OData row.
      _client.get('market/catalog', isV8: false).then<Object?>((v) => v).catchError((_) => null),
    ]);
    final apps = unwrapList(results[0]).cast<Map<String, dynamic>>().map(MarketApp.fromJson).toList();
    final catalog = results[1];
    final rows = catalog is Map && catalog['modules'] is List ? (catalog['modules'] as List) : const [];
    final byId = {for (final r in rows.whereType<Map>()) toNum(r['id']): Map<String, dynamic>.from(r)};
    for (final app in apps) {
      final row = byId[app.id];
      if (row != null) app.applyCatalog(row);
    }
    return apps;
  }

  /// First paid module ever — granted server-side at the welcome discount,
  /// no admin approval (desktop: POST market/:id/welcome-offer).
  Future<void> claimWelcomeOffer(int moduleId) async {
    await _client.post('market/$moduleId/welcome-offer', {}, isV8: false);
  }

  /// Active payment accounts for one method ('bank' | 'mobile').
  Future<List<Map<String, dynamic>>> loadPaymentAccounts(String method) async {
    final res = await _client.get("payment_accounts?\$filter=is_active eq true and method_type eq '${_escapeOData(method)}'&\$orderby=sort_order asc&\$top=200");
    return unwrapList(res).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  Future<List<String>> loadCategories() async {
    final res = await _client.get(r"modules?$filter=is_active eq true and is_mobile eq true&$top=200");
    final rows = unwrapList(res).cast<Map<String, dynamic>>();
    final categories = rows.map((r) => (r['category'] ?? '').toString().trim()).where((c) => c.isNotEmpty).toSet().toList();
    categories.sort();
    return categories;
  }

  /// Row counts as installed unless disabled or its status marks removal —
  /// mirrors desktop's `isActiveModuleRow`.
  bool _isActiveRow(Map<String, dynamic> row) {
    if (row['is_enabled'] == false) return false;
    final status = (row['status'] ?? '').toString().toLowerCase();
    if (status.contains('uninstall') || status.contains('remove')) return false;
    return true;
  }

  Future<Set<int>> loadInstalledModuleIds() async {
    final res = await _client.get(r"workplace_has_module?$expand=module&$top=500");
    final rows = unwrapList(res).cast<Map<String, dynamic>>();
    final ids = <int>{};
    for (final row in rows) {
      if (!_isActiveRow(row)) continue;
      final moduleId = toNum(row['module_id'] ?? (row['module'] as Map?)?['id']);
      if (moduleId > 0) ids.add(moduleId);
    }
    return ids;
  }

  Future<void> install(int moduleId) async {
    await _client.post('market/$moduleId/install', {}, isV8: false);
  }

  Future<void> uninstall(int moduleId) async {
    await _client.post('market/$moduleId/uninstall', {}, isV8: false);
  }
}
