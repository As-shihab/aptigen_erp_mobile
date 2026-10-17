import '../../../core/network/http_client.dart';
import '../../store/data/store_util.dart';

/// Register-wide POS defaults (`order_settings`, one row per workplace) —
/// mirrors desktop's PosTerminal.tsx settings dialog. Distinct from
/// `sell_settings` (module feature toggles, see sell_settings_service.dart).
class OrderSettings {
  final int? id;
  final int? defaultWarehouseId;
  final double defaultTaxRate;
  final String currencySymbolOverride;
  final String? receiptFooter;

  const OrderSettings({
    this.id,
    this.defaultWarehouseId,
    this.defaultTaxRate = 0,
    this.currencySymbolOverride = '',
    this.receiptFooter,
  });

  factory OrderSettings.fromJson(Map json) => OrderSettings(
        id: toIntOrNull(json['id']),
        defaultWarehouseId: toIntOrNull(json['default_warehouse_id']),
        defaultTaxRate: toDouble(json['default_tax_rate']),
        currencySymbolOverride: (json['currency_symbol'] ?? '').toString(),
        receiptFooter: toStringOrNull(json['receipt_footer']),
      );

  OrderSettings copyWith({int? defaultWarehouseId, bool clearWarehouse = false, double? defaultTaxRate, String? currencySymbolOverride, String? receiptFooter}) =>
      OrderSettings(
        id: id,
        defaultWarehouseId: clearWarehouse ? null : (defaultWarehouseId ?? this.defaultWarehouseId),
        defaultTaxRate: defaultTaxRate ?? this.defaultTaxRate,
        currencySymbolOverride: currencySymbolOverride ?? this.currencySymbolOverride,
        receiptFooter: receiptFooter ?? this.receiptFooter,
      );
}

class OrderSettingsService {
  final ApiClient _client;
  OrderSettingsService(this._client);

  Future<OrderSettings> load() async {
    final res = await _client.get(r'order_settings?$top=1');
    final rows = unwrapList(res);
    if (rows.isEmpty) return const OrderSettings();
    return OrderSettings.fromJson((rows.first as Map).cast<String, dynamic>());
  }

  Future<void> save(OrderSettings settings) async {
    final payload = {
      'default_warehouse_id': settings.defaultWarehouseId,
      'default_tax_rate': settings.defaultTaxRate,
      'currency_symbol': settings.currencySymbolOverride,
      'receipt_footer': settings.receiptFooter,
    };
    if (settings.id != null) {
      await _client.put('order_settings', settings.id!, payload);
    } else {
      await _client.post('order_settings', payload, isV8: true);
    }
  }
}
