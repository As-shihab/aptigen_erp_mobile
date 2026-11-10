import '../../../../core/network/http_client.dart';
import '../../../../core/storage/app_storage.dart';

/// Seller-side online market — same endpoints as erp/desktop's
/// Sell → Online → Market pages. OData resources (`/v1/…`, workplace-scoped
/// by the backend) use the exact Prisma model name; custom routes live under
/// `/api/market/…`.
///
/// Every method returns plain decoded JSON (maps / lists of maps); pages
/// parse what they need. Errors surface as [ApiException] with the server's
/// message (e.g. "The sale price must be below its price").
class MarketSellerService {
  MarketSellerService([ApiClient? client]) : _http = client ?? ApiClient();
  final ApiClient _http;

  // ── Helpers ───────────────────────────────────────────────────────────

  /// OData list / custom list → rows.
  static List<Map<String, dynamic>> rows(dynamic res) {
    final list = res is List ? res : (res is Map ? (res['value'] ?? res['data'] ?? const []) : const []);
    return list is List ? list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];
  }

  /// OData single-row responses are wrapped as `{ value: <row> }`.
  static Map<String, dynamic> row(dynamic res) {
    final v = res is Map && res['value'] is Map ? res['value'] : res;
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  static String _enc(String q) => Uri.encodeQueryComponent(q).replaceAll('+', '%20');

  // ── Listings (OData market_listings) ──────────────────────────────────

  Future<List<Map<String, dynamic>>> listings({String? filter, int top = 200}) async {
    final q = [
      r'$expand=medias,variants,category($select=id,name),product($select=id,name,stock_qty,track_stock,allow_backorder)',
      r'$orderby=id desc',
      '\$top=$top',
      if (filter != null && filter.isNotEmpty) '\$filter=${_enc(filter)}',
    ].join('&');
    return rows(await _http.get('market_listings?$q'));
  }

  Future<Map<String, dynamic>> saveListing(Map<String, dynamic> payload, {int? id}) async {
    if (id != null) return row(await _http.put('market_listings', id, payload));
    final user = await AppStorage.getUser();
    final sellerId = user?['id'];
    return row(await _http.post('market_listings', {...payload, 'seller_id': ?sellerId}, isV8: true));
  }

  Future<void> deleteListing(int id) => _http.delete('market_listings', id);

  /// Per-listing performance; [from]/[to] are YYYY-MM-DD (omit = all time).
  /// → [{ listing_id, views, unique_views, clicks, saves, cart_adds, orders, units_sold, revenue }]
  Future<List<Map<String, dynamic>>> listingStats({String? from, String? to}) async {
    final qs = (from != null && to != null) ? '?from=$from&to=$to' : '';
    return rows(await _http.get('market/listing-stats$qs', isV8: false));
  }

  /// Lookups for the listing form: products (non-pharma), the store's
  /// creator profile, market categories — one $batch round trip.
  Future<({List<Map<String, dynamic>> products, List<Map<String, dynamic>> profiles, List<Map<String, dynamic>> categories})>
      listingLookups() async {
    final res = await _http.batch([
      BatchRequest(
        id: '1',
        method: 'GET',
        url: r'store_products?$select=id,name,sku,price,thumbnail_url,stock_qty,category_id,is_pharma'
            r'&$expand=category($select=id,name,is_pharma)&$filter=is_active eq true and is_pharma eq false&$top=200',
      ),
      BatchRequest(id: '2', method: 'GET', url: r'creator_profiles?$orderby=id asc&$top=1'),
      BatchRequest(id: '3', method: 'GET', url: r'market_categories?$select=id,name,slug,icon&$filter=is_active eq true&$orderby=name asc&$top=200'),
    ]);
    List<Map<String, dynamic>> part(String id) => rows(unwrapBatchBody(res, id));
    final products = part('1').where((p) => p['is_pharma'] != true && (p['category'] as Map?)?['is_pharma'] != true).toList();
    return (products: products, profiles: part('2'), categories: part('3'));
  }

  // ── Website orders ────────────────────────────────────────────────────

  /// Orders containing this store's items, with buyer + delivery details
  /// and only this store's lines. status: pending|paid|packaged|delivered|cancelled
  Future<List<Map<String, dynamic>>> sellerOrders({String? status}) async =>
      rows(await _http.get('market/seller-orders${status == null ? '' : '?status=$status'}', isV8: false));

  /// pending → paid (accept) → packaged → delivered; or cancelled.
  /// Only single-store orders are writable through OData (desktop parity).
  Future<void> setOrderStatus(int orderId, String status) => _http.put('market_orders', orderId, {'status': status});

  // ── Flash sales (custom) ──────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> flashSales() async => rows(await _http.get('market/flash-sales', isV8: false));

  /// body: { name, description?, starts_at (ISO), ends_at (ISO), is_active,
  ///         items: [{ listing_id, sale_price, stock_limit?, per_order_limit? }] }
  Future<void> saveFlashSale(Map<String, dynamic> body, {int? id}) async {
    if (id != null) {
      await _http.put('market/flash-sales', id, body, isV8: false);
    } else {
      await _http.post('market/flash-sales', body);
    }
  }

  Future<void> deleteFlashSale(int id) => _http.delete('market/flash-sales', id, isV8: false);

  // ── Promotions (OData market_promotions) ──────────────────────────────

  Future<List<Map<String, dynamic>>> promotions() async =>
      rows(await _http.get(r'market_promotions?$orderby=id desc&$top=200'));

  /// listing_ids is a JSON array string, e.g. "[1,5]"; code null = automatic.
  Future<void> savePromotion(Map<String, dynamic> body, {int? id}) async {
    if (id != null) {
      await _http.put('market_promotions', id, body);
    } else {
      await _http.post('market_promotions', body, isV8: true);
    }
  }

  Future<void> deletePromotion(int id) => _http.delete('market_promotions', id);

  Future<List<Map<String, dynamic>>> redemptions(int promotionId) async => rows(await _http.get(
      'market_promotion_redemptions?\$filter=${_enc('promotion_id eq $promotionId')}&\$expand=order(\$select=order_no)&\$orderby=id desc&\$top=200'));

  // ── Reviews (custom) ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> reviews() async => rows(await _http.get('market/seller-reviews', isV8: false));

  /// Empty reply removes it.
  Future<Map<String, dynamic>> replyToReview(int id, String reply) async =>
      row(await _http.post('market/seller-reviews/$id/reply', {'reply': reply}));

  // ── Refunds (custom) ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> refunds({String? status}) async =>
      rows(await _http.get('market/seller-refunds${status == null ? '' : '?status=$status'}', isV8: false));

  /// status: approved|rejected|refunded (allowed transitions only);
  /// method: original|cash|mobile|bank; restock only with refunded.
  Future<void> resolveRefund(int id, {required String status, String? sellerNote, String? method, bool restock = false}) =>
      _http.patch('market/seller-refunds', id, {
        'status': status,
        'seller_note': ?sellerNote,
        'method': ?method,
        if (status == 'refunded') 'restock': restock,
      });

  // ── Payment gateways (OData market_payment_gateways) ──────────────────

  Future<List<Map<String, dynamic>>> gateways() async =>
      rows(await _http.get(r'market_payment_gateways?$orderby=sort_order asc&$top=200'));

  Future<void> saveGateway(Map<String, dynamic> body, {int? id}) async {
    if (id != null) {
      await _http.put('market_payment_gateways', id, body);
    } else {
      await _http.post('market_payment_gateways', body, isV8: true);
    }
  }

  Future<void> deleteGateway(int id) => _http.delete('market_payment_gateways', id);

  // ── Banners (OData market_banners) ────────────────────────────────────

  Future<List<Map<String, dynamic>>> banners() async =>
      rows(await _http.get(r'market_banners?$orderby=sort_order asc&$top=200'));

  /// placement: hero | promo_card | strip. approval_status is set by the
  /// platform, never by the seller.
  Future<void> saveBanner(Map<String, dynamic> body, {int? id}) async {
    if (id != null) {
      await _http.put('market_banners', id, body);
    } else {
      await _http.post('market_banners', body, isV8: true);
    }
  }

  Future<void> deleteBanner(int id) => _http.delete('market_banners', id);

  // ── Storefront (OData creator_profiles — one per workplace) ───────────

  /// The store's profile, creating an empty one the first time (desktop's
  /// Banners page does the same).
  Future<Map<String, dynamic>?> storefront({bool create = false}) async {
    final list = rows(await _http.get(r'creator_profiles?$top=1'));
    if (list.isNotEmpty) return list.first;
    if (!create) return null;
    await _http.post('creator_profiles', {}, isV8: true);
    final again = rows(await _http.get(r'creator_profiles?$top=1'));
    return again.isEmpty ? null : again.first;
  }

  Future<void> saveStorefront(int id, Map<String, dynamic> body) => _http.put('creator_profiles', id, body);

  // ── Media ─────────────────────────────────────────────────────────────

  int? _marketCategoryId;

  /// Uploads a photo or video to the media library (POST /api/media/upload,
  /// public, into a "Market" media category created on first use) and
  /// returns `{ url, type: 'image'|'video', name }` for listing medias /
  /// banner images. Videos skip sharp compression.
  Future<Map<String, dynamic>> uploadMedia(List<int> bytes, String filename) async {
    _marketCategoryId ??= await _ensureMarketCategory();
    final isVideo = RegExp(r'\.(mp4|webm|mov|m4v|mkv)$', caseSensitive: false).hasMatch(filename);
    final res = await _http.uploadFile(
      'media/upload',
      bytes: bytes,
      filename: filename,
      fields: {'category_id': '$_marketCategoryId', 'visibility': 'public'},
      useSharp: !isVideo,
    );
    final saved = res is Map && res['savedMedia'] is List && (res['savedMedia'] as List).isNotEmpty
        ? Map<String, dynamic>.from((res['savedMedia'] as List).first as Map)
        : <String, dynamic>{};
    final url = (saved['fileUrl'] ?? saved['file_url'] ?? '').toString();
    if (url.isEmpty) throw ApiException(500, 'Upload failed');
    return {'url': url, 'type': isVideo ? 'video' : 'image', 'name': filename};
  }

  Future<int> _ensureMarketCategory() async {
    final cats = rows(await _http.get('media_categories'));
    for (final c in cats) {
      if ((c['name'] ?? '').toString().trim().toLowerCase() == 'market') return (c['id'] as num).toInt();
    }
    final created = row(await _http.post('media_categories', {'name': 'Market'}, isV8: true));
    final id = created['id'];
    if (id is num) return id.toInt();
    if (cats.isNotEmpty) return (cats.first['id'] as num).toInt();
    throw ApiException(500, 'Could not create a media category');
  }

  ApiClient get http => _http;
}
