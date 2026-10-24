import '../../../core/network/http_client.dart';
import '../../../shared/ui/entity_crud.dart';

// Purchase settings — port of desktop settings/PurchaseSettings.tsx. The
// workplace's single purchase_settings row plus the active approve types
// (approver chains), read in one batch; each change is a partial PUT.

class PurchaseSettingsService {
  final ApiClient _client;
  PurchaseSettingsService([ApiClient? client]) : _client = client ?? ApiClient();

  Future<({Map<String, dynamic>? settings, List<Map<String, dynamic>> approveTypes})> load() async {
    final d = await batchLoad(_client, {
      'settings': 'purchase_settings?\$top=1',
      'approve': 'approve_types?\$select=id,name&\$filter=is_active eq true&\$top=200',
    });
    final rows = d['settings'] ?? const [];
    return (settings: rows.isEmpty ? null : {...rows.first}, approveTypes: d['approve'] ?? <Map<String, dynamic>>[]);
  }

  Future<void> patch(Object id, Map<String, dynamic> partial) => _client.put('purchase_settings', id, partial);
}
