import '../../../core/network/http_client.dart';
import '../../store/data/store_util.dart';
import 'client_model.dart';

/// Plain OData CRUD on `clients` — mirrors desktop's ClientForm.tsx
/// (mutations are direct/online, same as every other mobile write; desktop's
/// "online-only, not offline-queued" note doesn't apply here since this
/// mobile app has no offline write queue at all).
class ClientService {
  final ApiClient _client;
  ClientService(this._client);

  /// No server-side search — same client-side-filter convention as
  /// `stays_list_page.dart`'s `_visibleStays` (simpler than confirming the
  /// generic OData layer's `contains()` combining rules for this small a
  /// dataset per workplace).
  /// Sales clients only by default; the pharma POS passes [isPharma].
  Future<List<Client>> list({bool isPharma = false}) async {
    final res = await _client.get('clients?\$expand=group&\$filter=is_pharma eq $isPharma&\$orderby=name asc&\$top=1000');
    return unwrapList(res).cast<Map<String, dynamic>>().map(Client.fromJson).toList();
  }

  /// Mirrors desktop's `POST generate-code {code:'CLI', table:'clients',
  /// column:'code'}` — used to prefill a new client's code (pattern
  /// `CLI-2026-0001`); still freely editable afterward.
  Future<String?> generateCode() async {
    try {
      final res = await _client.post('generate-code', {'code': 'CLI', 'table': 'clients', 'column': 'code'}, isV8: false);
      return toStringOrNull(res is Map ? (res['code'] ?? res['value']) : null);
    } catch (_) {
      return null;
    }
  }

  Future<Client> create(Map<String, dynamic> payload) async {
    // `ApiClient.post` defaults to isV8: false (unlike put/delete, which
    // default to true) — `clients` is a plain OData entity, so this must be
    // explicit or the request silently hits `/api/clients` instead of
    // `/v1/clients` and never creates the row.
    final res = await _client.post('clients', payload, isV8: true);
    final unwrapped = (res is Map && res['value'] is Map) ? res['value'] : res;
    return Client.fromJson((unwrapped as Map).cast<String, dynamic>());
  }

  Future<void> update(int id, Map<String, dynamic> payload) async {
    await _client.put('clients', id, payload);
  }

  Future<void> delete(int id) async {
    await _client.delete('clients', id);
  }
}
