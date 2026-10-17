import 'package:flutter/material.dart';
import '../../../../core/utils/currency.dart';
import '../../data/store_lookup_service.dart';
import '../../data/store_util.dart';
import '../widgets/field_spec.dart';

/// Config objects for the 9 flat lookup entities — each just describes its
/// fields/labels, the actual list/form UI comes from `SimpleEntityListPage`/
/// `SimpleEntityFormPage` (`field_spec.dart`). `lookups` is the map returned
/// by `StoreLookupService.loadAll()`.

SimpleCrudConfig categoriesConfig() => SimpleCrudConfig(
      title: 'Categories',
      endpoint: 'store_product_categories',
      icon: Icons.category_outlined,
      rowTitle: (r) => (r['name'] ?? '').toString(),
      rowSubtitle: (r) => r['description']?.toString(),
      fields: const [
        FieldSpec(key: 'name', label: 'Name', kind: FieldKind.text, required: true),
        FieldSpec(key: 'slug', label: 'Slug', kind: FieldKind.text, hint: 'Optional — url-friendly id'),
        FieldSpec(key: 'description', label: 'Description', kind: FieldKind.multiline),
        FieldSpec(key: 'position', label: 'Sort position', kind: FieldKind.number, defaultValue: 0),
        FieldSpec(key: 'is_active', label: 'Active', kind: FieldKind.boolSwitch, defaultValue: true),
      ],
    );

SimpleCrudConfig subCategoriesConfig(Map<String, List<Map<String, dynamic>>> lookups) => SimpleCrudConfig(
      title: 'Sub-categories',
      endpoint: 'store_product_sub_categories',
      icon: Icons.category_outlined,
      rowTitle: (r) => (r['name'] ?? '').toString(),
      rowSubtitle: (r) => r['description']?.toString(),
      fields: [
        FieldSpec(
          key: 'category_id',
          label: 'Category',
          kind: FieldKind.dropdown,
          required: true,
          options: (_) => toOptions(lookups['categories'] ?? const []),
        ),
        const FieldSpec(key: 'name', label: 'Name', kind: FieldKind.text, required: true),
        const FieldSpec(key: 'slug', label: 'Slug', kind: FieldKind.text),
        const FieldSpec(key: 'description', label: 'Description', kind: FieldKind.multiline),
        const FieldSpec(key: 'position', label: 'Sort position', kind: FieldKind.number, defaultValue: 0),
        const FieldSpec(key: 'is_active', label: 'Active', kind: FieldKind.boolSwitch, defaultValue: true),
      ],
    );

SimpleCrudConfig uomsConfig() => SimpleCrudConfig(
      title: 'Units of measure',
      endpoint: 'store_uoms',
      icon: Icons.straighten_outlined,
      rowTitle: (r) => (r['name'] ?? '').toString(),
      rowSubtitle: (r) => r['code']?.toString(),
      fields: const [
        FieldSpec(key: 'name', label: 'Name', kind: FieldKind.text, required: true),
        FieldSpec(key: 'code', label: 'Code', kind: FieldKind.text, required: true),
        FieldSpec(key: 'symbol', label: 'Symbol', kind: FieldKind.text),
        FieldSpec(key: 'is_active', label: 'Active', kind: FieldKind.boolSwitch, defaultValue: true),
      ],
    );

SimpleCrudConfig packagingsConfig(Map<String, List<Map<String, dynamic>>> lookups) => SimpleCrudConfig(
      title: 'Packaging / barcodes',
      endpoint: 'store_product_packagings',
      icon: Icons.qr_code_2_outlined,
      rowTitle: (r) => (r['name'] ?? '').toString(),
      rowSubtitle: (r) => r['barcode']?.toString(),
      showBarcode: true,
      barcodeValue: (r) => r['barcode']?.toString(),
      barcodeInfo: (r) {
        final info = <String, String>{};
        final productId = toIntOrNull(r['product_id']);
        final product = (lookups['products'] ?? const []).where((p) => toIntOrNull(p['id']) == productId);
        if (product.isNotEmpty) {
          final name = (product.first['name'] ?? '').toString();
          if (name.isNotEmpty) info['Product'] = name;
        }

        final price = toDoubleOrNull(r['price']) ?? toDoubleOrNull(r['cost_price']);
        if (price != null) info['Price'] = formatMoneyAscii(price);

        final qty = toDoubleOrNull(r['unit_qty']);
        if (qty != null) {
          final uomId = toIntOrNull(r['uom_id']);
          final uom = (lookups['uoms'] ?? const []).where((u) => toIntOrNull(u['id']) == uomId);
          final uomLabel = uom.isNotEmpty ? (uom.first['code'] ?? uom.first['name'] ?? '').toString() : '';
          final qtyLabel = qty == qty.roundToDouble() ? qty.toStringAsFixed(0) : qty.toString();
          info['Qty'] = uomLabel.isEmpty ? qtyLabel : '$qtyLabel $uomLabel';
        }
        return info;
      },
      fields: [
        FieldSpec(
          key: 'product_id',
          label: 'Product',
          kind: FieldKind.dropdown,
          required: true,
          options: (_) => toOptions(lookups['products'] ?? const []),
        ),
        const FieldSpec(key: 'name', label: 'Packaging name', kind: FieldKind.text, required: true, hint: 'e.g. Box of 12'),
        const FieldSpec(key: 'barcode', label: 'Barcode', kind: FieldKind.text),
        FieldSpec(
          key: 'uom_id',
          label: 'Unit of measure',
          kind: FieldKind.dropdown,
          options: (_) => toOptions(lookups['uoms'] ?? const []),
        ),
        const FieldSpec(key: 'unit_qty', label: 'Unit quantity', kind: FieldKind.decimal, defaultValue: 1),
        const FieldSpec(key: 'price', label: 'Price override', kind: FieldKind.decimal),
        const FieldSpec(key: 'cost_price', label: 'Cost price override', kind: FieldKind.decimal),
        const FieldSpec(key: 'is_active', label: 'Active', kind: FieldKind.boolSwitch, defaultValue: true),
      ],
    );

SimpleCrudConfig batchesConfig(Map<String, List<Map<String, dynamic>>> lookups) => SimpleCrudConfig(
      title: 'Product batches',
      endpoint: 'store_product_batches',
      icon: Icons.inventory_2_outlined,
      rowTitle: (r) => (r['batch_no'] ?? '').toString(),
      rowSubtitle: (r) => 'Qty ${r['quantity'] ?? 0} — ${r['status'] ?? ''}',
      fields: [
        FieldSpec(
          key: 'product_id',
          label: 'Product',
          kind: FieldKind.dropdown,
          required: true,
          options: (_) => toOptions(lookups['products'] ?? const []),
        ),
        const FieldSpec(key: 'batch_no', label: 'Batch no.', kind: FieldKind.text, required: true),
        const FieldSpec(key: 'manufacture_date', label: 'Manufacture date', kind: FieldKind.date),
        const FieldSpec(key: 'expiry_date', label: 'Expiry date', kind: FieldKind.date),
        const FieldSpec(key: 'quantity', label: 'Quantity', kind: FieldKind.number, defaultValue: 0),
        const FieldSpec(key: 'status', label: 'Status', kind: FieldKind.choice, choices: ['ACTIVE', 'EXPIRED', 'CLOSED'], defaultValue: 'ACTIVE'),
      ],
    );

const _warehouseTypes = ['MAIN_STORE', 'RAW_MATERIAL_STORE', 'FINISHED_GOODS_STORE', 'OUTLET_STORE', 'TRANSIT_STORE', 'DAMAGE_STORE'];

SimpleCrudConfig warehousesConfig() => SimpleCrudConfig(
      title: 'Warehouses',
      endpoint: 'store_warehouses',
      icon: Icons.warehouse_outlined,
      rowTitle: (r) => (r['name'] ?? '').toString(),
      rowSubtitle: (r) => '${r['code'] ?? ''} · ${r['type'] ?? ''}',
      fields: const [
        FieldSpec(key: 'code', label: 'Code', kind: FieldKind.text, required: true),
        FieldSpec(key: 'name', label: 'Name', kind: FieldKind.text, required: true),
        FieldSpec(key: 'type', label: 'Type', kind: FieldKind.choice, choices: _warehouseTypes, defaultValue: 'MAIN_STORE'),
        FieldSpec(key: 'is_active', label: 'Active', kind: FieldKind.boolSwitch, defaultValue: true),
      ],
    );

SimpleCrudConfig corridorsConfig(Map<String, List<Map<String, dynamic>>> lookups) => SimpleCrudConfig(
      title: 'Corridors',
      endpoint: 'store_warehouse_corridors',
      icon: Icons.turn_slight_right_outlined,
      rowTitle: (r) => (r['name'] ?? r['code'] ?? '').toString(),
      rowSubtitle: (r) => r['code']?.toString(),
      fields: [
        FieldSpec(
          key: 'warehouse_id',
          label: 'Warehouse',
          kind: FieldKind.dropdown,
          required: true,
          options: (_) => toOptions(lookups['warehouses'] ?? const []),
        ),
        const FieldSpec(key: 'code', label: 'Code', kind: FieldKind.text, required: true),
        const FieldSpec(key: 'name', label: 'Name', kind: FieldKind.text),
        const FieldSpec(key: 'is_active', label: 'Active', kind: FieldKind.boolSwitch, defaultValue: true),
      ],
    );

SimpleCrudConfig racksConfig(Map<String, List<Map<String, dynamic>>> lookups) => SimpleCrudConfig(
      title: 'Racks',
      endpoint: 'store_warehouse_racks',
      icon: Icons.grid_view_outlined,
      rowTitle: (r) => (r['name'] ?? r['code'] ?? '').toString(),
      rowSubtitle: (r) => r['code']?.toString(),
      fields: [
        FieldSpec(
          key: 'corridor_id',
          label: 'Corridor',
          kind: FieldKind.dropdown,
          required: true,
          options: (_) => toCodeOptions(lookups['corridors'] ?? const []),
        ),
        const FieldSpec(key: 'code', label: 'Code', kind: FieldKind.text, required: true),
        const FieldSpec(key: 'name', label: 'Name', kind: FieldKind.text),
        const FieldSpec(key: 'is_active', label: 'Active', kind: FieldKind.boolSwitch, defaultValue: true),
      ],
    );

SimpleCrudConfig binsConfig(Map<String, List<Map<String, dynamic>>> lookups) => SimpleCrudConfig(
      title: 'Bins',
      endpoint: 'store_warehouse_bins',
      icon: Icons.inbox_outlined,
      rowTitle: (r) => (r['name'] ?? r['code'] ?? '').toString(),
      rowSubtitle: (r) => r['code']?.toString(),
      fields: [
        FieldSpec(
          key: 'rack_id',
          label: 'Rack',
          kind: FieldKind.dropdown,
          required: true,
          options: (_) => toCodeOptions(lookups['racks'] ?? const []),
        ),
        const FieldSpec(key: 'code', label: 'Code', kind: FieldKind.text, required: true),
        const FieldSpec(key: 'name', label: 'Name', kind: FieldKind.text),
        const FieldSpec(key: 'is_active', label: 'Active', kind: FieldKind.boolSwitch, defaultValue: true),
      ],
    );
