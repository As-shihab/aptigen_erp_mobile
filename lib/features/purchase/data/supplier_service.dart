import '../../../core/network/http_client.dart';
import '../../../shared/ui/entity_crud.dart';
import '../../../shared/ui/motion_kit.dart';

// Suppliers and supplier groups — port of desktop Supplier.tsx /
// SupplierGroup.tsx. Plain OData CRUD on `suppliers` / `supplier_groups`;
// the backend scopes workplace_id, so it's never sent.

/// Turns a unique-constraint failure into the same friendly message desktop
/// shows; otherwise the backend's own message.
String supplierErrorMessage(Object e, String fallback, {required String codeColumn, required String codeLabel}) {
  final msg = e is ApiException ? e.message : e.toString();
  if (msg.contains(codeColumn) && msg.toLowerCase().contains('unique')) {
    return 'That $codeLabel is already in use for this workplace — use a different code';
  }
  return errorMessage(e, fallback);
}

class SupplierService {
  final ApiClient _client;
  SupplierService([ApiClient? client]) : _client = client ?? ApiClient();

  late final _suppliers = EntityApi(_client, 'suppliers');
  late final _groups = EntityApi(_client, 'supplier_groups');

  /// Supplier list (with group) and the active groups for the picker, in one batch.
  Future<({List<Map<String, dynamic>> suppliers, List<Map<String, dynamic>> groups})> loadSuppliers() async {
    final d = await batchLoad(_client, {
      'suppliers': 'suppliers?\$expand=group&\$orderby=id desc&\$top=2000',
      'groups': "supplier_groups?\$select=id,group_name&\$filter=status eq 'ACTIVE'&\$top=500",
    });
    return (suppliers: d['suppliers'] ?? <Map<String, dynamic>>[], groups: d['groups'] ?? <Map<String, dynamic>>[]);
  }

  Future<List<Map<String, dynamic>>> loadGroups() async {
    final res = await _client.get('supplier_groups?\$orderby=id desc&\$top=1000');
    return unwrapList(res).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  /// Next supplier code (e.g. SUP-2026-0001) — best effort, null on failure.
  Future<String?> generateSupplierCode() async {
    try {
      final res = await _client.post('generate-code', {'code': 'SUP', 'table': 'suppliers', 'column': 'supplier_code'}, isV8: false);
      final code = res is Map ? res['code']?.toString() : null;
      return code == null || code.isEmpty ? null : code;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> saveSupplier(Map<String, dynamic> body, {Object? id}) =>
      id == null ? _suppliers.create(body) : _suppliers.update(id, body);

  Future<void> deleteSupplier(Object id) => _suppliers.delete(id);

  Future<Map<String, dynamic>> saveGroup(Map<String, dynamic> body, {Object? id}) => id == null ? _groups.create(body) : _groups.update(id, body);

  Future<void> deleteGroup(Object id) => _groups.delete(id);

  /// Purchase orders raised against one supplier (newest first), with line
  /// quantities / prices so the detail view can show order values.
  Future<List<Map<String, dynamic>>> supplierOrders(Object supplierId) async {
    final res = await _client.get(
        'purchase_orders?\$select=id,po_no,status,order_date,expected_date&\$expand=items(\$select=quantity,unit_price)&\$filter=supplier_id eq $supplierId&\$orderby=id desc&\$top=500');
    return unwrapList(res).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }
}

/// Order value from expanded items (quantity × unit price).
double purchaseOrderValue(Map<String, dynamic> po) {
  final items = po['items'];
  if (items is! List) return 0;
  var v = 0.0;
  for (final i in items) {
    if (i is! Map) continue;
    v += (double.tryParse('${i['quantity']}') ?? 0) * (double.tryParse('${i['unit_price']}') ?? 0);
  }
  return v;
}
