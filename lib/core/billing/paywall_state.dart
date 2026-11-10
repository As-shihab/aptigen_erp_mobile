import 'package:flutter/foundation.dart';
import '../network/http_client.dart';
import '../storage/app_storage.dart';
import 'entity_module_map.dart';

/// Pending (awaiting admin approval) invoice covering a blocked module.
class PendingInvoiceInfo {
  final int id;
  final String invoiceNo;
  final double total;
  const PendingInvoiceInfo({required this.id, required this.invoiceNo, required this.total});
}

/// What the wall shows when a module is paid but not paid for — mirrors
/// erp/desktop's `PaywallBlock` (paywall.ts).
class PaywallBlock {
  final int moduleId;
  final String moduleCode;
  final String moduleName;
  final double modulePrice;
  final PendingInvoiceInfo? pendingInvoice;

  /// Installed but not paid/pending: covers both "subscription expired" and
  /// "module flipped from free to paid while installed". Changes the wording
  /// ("Subscribe" vs "Complete purchase"); the action is the same months
  /// picker either way, exactly like desktop.
  final bool needsRenewal;

  /// A subscription row exists and its expiry is in the past — only used by
  /// the launcher tile label (desktop's Dashboard "Expired" tag).
  final bool isExpired;

  const PaywallBlock({
    required this.moduleId,
    required this.moduleCode,
    required this.moduleName,
    required this.modulePrice,
    required this.pendingInvoice,
    required this.needsRenewal,
    required this.isExpired,
  });
}

class _ModuleBillingInfo {
  final int id;
  final String code;
  final String name;
  final bool isPaid;
  final double price;
  final bool paid;
  final PendingInvoiceInfo? pendingInvoice;
  final bool needsRenewal;
  final bool isExpired;

  const _ModuleBillingInfo({
    required this.id,
    required this.code,
    required this.name,
    required this.isPaid,
    required this.price,
    required this.paid,
    this.pendingInvoice,
    this.needsRenewal = false,
    this.isExpired = false,
  });
}

/// Thrown by [ApiClient] instead of sending a write that the paywall blocks
/// — same message desktop's HttpClient throws (`PAYMENT_REQUIRED: ...`).
/// Extends [ApiException] so existing `on ApiException catch` handlers show
/// it like any other failed save.
class PaywallException extends ApiException {
  final PaywallBlock block;
  PaywallException(this.block)
      : super(402, '${block.moduleName} requires payment to continue', code: 'PAYMENT_REQUIRED');
}

/// Client-side subscription wall — a port of erp/desktop's
/// `module/market/paywall/paywall.ts`. The backend has no server-side
/// enforcement (no 402 / guard); like desktop, this is a design-level gate
/// that blocks OData writes (POST/PUT/PATCH/DELETE on `/v1/`) against
/// entities owned by a paid module the workplace hasn't paid for. Reads are
/// never blocked.
///
/// The snapshot is loaded once (shell start = login / workplace switch /
/// cold start), on app resume, after creating an invoice from the wall, and
/// on the `billing:invoice-updated` socket push. [check] only reads it — it
/// never makes a network call, so it's safe on every request.
class PaywallState {
  PaywallState._();

  static bool _freeAccess = false;
  static Map<String, _ModuleBillingInfo> _modulesByCode = {};
  static bool _stateLoaded = false;
  static String? _loadedWorkplaceKey;
  static Future<void>? _inFlight;

  /// Bumped every time the snapshot changes — the launcher listens to this
  /// to refresh its locked badges.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// Wired once at app start (bootstrap.dart) to open the wall UI when a
  /// write is blocked — desktop's `openPaywallDialog`.
  static void Function(PaywallBlock block)? onBlocked;

  static bool get freeAccess => _freeAccess;

  static Future<String> _workplaceKey() async {
    final user = await AppStorage.getUser();
    final workplace = (user?['selectedWorkplace'] ?? user?['workplace']);
    return workplace is Map ? (workplace['id'] ?? '').toString() : '';
  }

  /// Drops the snapshot (logout / session clear).
  static void reset() {
    _freeAccess = false;
    _modulesByCode = {};
    _stateLoaded = false;
    _loadedWorkplaceKey = null;
    revision.value++;
  }

  /// Loads the full billing snapshot. Concurrent calls share one load.
  static Future<void> load([ApiClient? client]) {
    return _inFlight ??= _load(client ?? ApiClient()).whenComplete(() => _inFlight = null);
  }

  static Future<void> _load(ApiClient client) async {
    final key = await _workplaceKey();
    if (_loadedWorkplaceKey != null && _loadedWorkplaceKey != key) {
      // Switched workplace — never judge the new one by the old snapshot.
      _freeAccess = false;
      _modulesByCode = {};
      _stateLoaded = false;
    }
    try {
      final results = await Future.wait([
        client.get('workplace_billing_settings?\$top=1'),
        client.get('modules?\$select=id,code,name,is_paid,price&\$top=500'),
      ]);
      final freeRows = unwrapList(results[0]);
      _freeAccess = freeRows.isNotEmpty && (freeRows.first as Map)['is_free_access'] == true;
      final modules = unwrapList(results[1]).whereType<Map>().toList();
      final next = <String, _ModuleBillingInfo>{};

      double toNum(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
      int toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

      if (_freeAccess) {
        for (final m in modules) {
          final code = (m['code'] ?? '').toString().trim();
          if (code.isEmpty) continue;
          next[code.toUpperCase()] = _ModuleBillingInfo(
            id: toInt(m['id']), code: code, name: (m['name'] ?? code).toString(),
            isPaid: m['is_paid'] != false, price: toNum(m['price']), paid: true,
          );
        }
      } else {
        final paidModules = modules.where((m) => m['is_paid'] != false).toList();
        dynamic batchRes;
        if (paidModules.isNotEmpty) {
          final requests = <BatchRequest>[
            for (final m in paidModules) ...[
              BatchRequest(id: 'sub-${m['id']}', method: 'GET', url: 'module_subscriptions?\$filter=module_id eq ${m['id']}&\$top=1'),
              BatchRequest(
                id: 'inv-${m['id']}',
                method: 'GET',
                url: 'module_purchase_invoice_items?\$filter=module_id eq ${m['id']}&\$expand=invoice&\$orderby=created_at desc&\$top=20',
              ),
              BatchRequest(id: 'installed-${m['id']}', method: 'GET', url: 'workplace_has_module?\$filter=module_id eq ${m['id']}&\$top=1'),
            ],
          ];
          try {
            batchRes = await client.batch(requests);
          } catch (_) {
            batchRes = null;
          }
        }
        List<dynamic> rowsOf(String id) => unwrapList(unwrapBatchBody(batchRes, id));

        for (final m in modules) {
          final code = (m['code'] ?? '').toString().trim();
          if (code.isEmpty) continue;
          final id = toInt(m['id']);
          final name = (m['name'] ?? code).toString();
          final price = toNum(m['price']);
          if (m['is_paid'] == false) {
            next[code.toUpperCase()] = _ModuleBillingInfo(id: id, code: code, name: name, isPaid: false, price: price, paid: true);
            continue;
          }

          // Active subscription = paid. Invoice history stays as a fallback
          // for modules paid for before subscriptions existed (desktop rule).
          final subRows = rowsOf('sub-${m['id']}');
          final sub = subRows.isNotEmpty ? subRows.first as Map : null;
          final expiresAt = DateTime.tryParse((sub?['expires_at'] ?? '').toString());
          final subExpired = expiresAt != null && !expiresAt.isAfter(DateTime.now());
          final isSubActive = sub != null && sub['is_active'] == true && !subExpired;

          var paid = isSubActive;
          PendingInvoiceInfo? pending;
          if (!paid) {
            final invoiceRows = rowsOf('inv-${m['id']}').whereType<Map>().toList();
            String statusOf(Map row) => (row['invoice'] is Map ? (row['invoice'] as Map)['status'] : null)?.toString() ?? '';
            if (invoiceRows.any((row) => statusOf(row) == 'paid')) {
              paid = true;
            } else {
              final pendingRow = invoiceRows.where((row) => statusOf(row) == 'pending').firstOrNull;
              final invoice = pendingRow?['invoice'];
              if (invoice is Map) {
                pending = PendingInvoiceInfo(
                  id: toInt(invoice['id']),
                  invoiceNo: (invoice['invoice_no'] ?? '').toString(),
                  total: toNum(invoice['total']),
                );
              }
            }
          }

          final installedRows = rowsOf('installed-${m['id']}');
          final installedRow = installedRows.isNotEmpty ? installedRows.first as Map : null;
          final installed = installedRow != null && installedRow['uninstalled_at'] == null;

          next[code.toUpperCase()] = _ModuleBillingInfo(
            id: id,
            code: code,
            name: name,
            isPaid: true,
            price: price,
            paid: paid,
            pendingInvoice: pending,
            needsRenewal: !paid && pending == null && installed,
            isExpired: sub != null && subExpired,
          );
        }
      }

      _modulesByCode = next;
    } catch (_) {
      // Fail open, like desktop: a gate that can't reach the server must not
      // be able to brick every write in the app.
    }
    _stateLoaded = true;
    _loadedWorkplaceKey = key;
    revision.value++;
  }

  /// Desktop's `resolveModuleCodeForEntity`.
  static String? moduleCodeForEntity(String entity) {
    final key = entity.trim().toLowerCase().replaceFirst(RegExp(r'^/+'), '');
    return entityModuleMap[key];
  }

  /// Block for a module code (case-insensitive), or null when it's free,
  /// paid for, unknown, or the snapshot isn't loaded yet.
  static PaywallBlock? blockForModuleCode(String code) {
    if (!_stateLoaded) return null;
    final info = _modulesByCode[code.trim().toUpperCase()];
    if (info == null || !info.isPaid || info.paid) return null;
    return PaywallBlock(
      moduleId: info.id,
      moduleCode: info.code,
      moduleName: info.name,
      modulePrice: info.price,
      pendingInvoice: info.pendingInvoice,
      needsRenewal: info.needsRenewal,
      isExpired: info.isExpired,
    );
  }

  /// Desktop's `checkPaywall` — null when a write to [entity] may proceed.
  static PaywallBlock? check(String entity) {
    final code = moduleCodeForEntity(entity);
    return code == null ? null : blockForModuleCode(code);
  }

  /// Called by [ApiClient] before an OData mutation. Opens the wall and
  /// throws [PaywallException] when blocked, mirroring desktop's
  /// HttpClient.request().
  static void guardMutation(String endpoint) {
    final entity = endpoint.split(RegExp(r'[(?]')).first.replaceFirst(RegExp(r'^/+'), '').trim();
    if (entity.isEmpty || entity == r'$batch') return;
    final block = check(entity);
    if (block == null) return;
    onBlocked?.call(block);
    throw PaywallException(block);
  }
}
