import 'store_util.dart';

/// Mirrors the fields of `store_products` (cloud/prisma/schema/store.prisma)
/// actually used on mobile — catalog browsing, the POS-friendly product
/// picker, and quick low-stock restock. Skips desktop-only SEO/physical-dims
/// fields not needed here.
class StoreProduct {
  final int id;
  final String name;
  final String? sku;
  final String? barcode;
  final String? shortDesc;
  final int? categoryId;
  final int? subCategoryId;
  final int? uomId;
  final double price;
  final double? comparePrice;
  final double? costPrice;
  final double stockQty;
  final double lowStockAt;
  final bool trackStock;
  final bool isActive;
  final bool isFeatured;
  final String? thumbnailUrl;

  const StoreProduct({
    required this.id,
    required this.name,
    this.sku,
    this.barcode,
    this.shortDesc,
    this.categoryId,
    this.subCategoryId,
    this.uomId,
    required this.price,
    this.comparePrice,
    this.costPrice,
    required this.stockQty,
    required this.lowStockAt,
    required this.trackStock,
    required this.isActive,
    required this.isFeatured,
    this.thumbnailUrl,
  });

  bool get isLowStock => trackStock && stockQty <= lowStockAt;

  StoreProduct copyWith({double? stockQty}) => StoreProduct(
        id: id,
        name: name,
        sku: sku,
        barcode: barcode,
        shortDesc: shortDesc,
        categoryId: categoryId,
        subCategoryId: subCategoryId,
        uomId: uomId,
        price: price,
        comparePrice: comparePrice,
        costPrice: costPrice,
        stockQty: stockQty ?? this.stockQty,
        lowStockAt: lowStockAt,
        trackStock: trackStock,
        isActive: isActive,
        isFeatured: isFeatured,
        thumbnailUrl: thumbnailUrl,
      );

  factory StoreProduct.fromJson(Map json) => StoreProduct(
        id: toNum(json['id']),
        name: (json['name'] ?? '').toString(),
        sku: toStringOrNull(json['sku']),
        barcode: toStringOrNull(json['barcode']),
        shortDesc: toStringOrNull(json['short_desc']),
        categoryId: toIntOrNull(json['category_id']),
        subCategoryId: toIntOrNull(json['sub_category_id']),
        uomId: toIntOrNull(json['uom_id']),
        price: toDouble(json['price']),
        comparePrice: toDoubleOrNull(json['compare_price']),
        costPrice: toDoubleOrNull(json['cost_price']),
        stockQty: toDouble(json['stock_qty']),
        lowStockAt: toDouble(json['low_stock_at']),
        trackStock: toBool(json['track_stock'], fallback: true),
        isActive: toBool(json['is_active'], fallback: true),
        isFeatured: toBool(json['is_featured']),
        thumbnailUrl: toStringOrNull(json['thumbnail_url']),
      );
}

/// A `store_product_packagings` row — an alternate sellable/receivable unit
/// with its own barcode (e.g. a carton), used by the barcode-scan resolver
/// in `LineItemsEditor` alongside the base product barcode.
class StorePackaging {
  final int id;
  final int productId;
  final String name;
  final String? barcode;
  final double unitQty;

  const StorePackaging({required this.id, required this.productId, required this.name, this.barcode, required this.unitQty});

  factory StorePackaging.fromJson(Map json) => StorePackaging(
        id: toNum(json['id']),
        productId: toNum(json['product_id']),
        name: (json['name'] ?? '').toString(),
        barcode: toStringOrNull(json['barcode']),
        unitQty: toDouble(json['unit_qty']) == 0 ? 1 : toDouble(json['unit_qty']),
      );
}
