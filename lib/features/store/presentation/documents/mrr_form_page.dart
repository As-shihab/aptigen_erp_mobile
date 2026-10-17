import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../sell/market/presentation/banners/form_kit.dart' show FieldBlock, MarketTextField;
import '../../data/document_models.dart';
import '../../data/document_services.dart';
import '../../data/stock_ledger_helper.dart';
import '../../data/store_lookup_service.dart';
import '../../data/store_product_model.dart';
import '../../data/store_product_service.dart';
import '../widgets/line_items_editor.dart';
import '../widgets/store_ui.dart';
import 'doc_kit.dart';

const _mrrStatuses = ['PARTIAL', 'COMPLETED', 'HOLD'];

/// Create/edit one MRR (Local/Imported/Repair share this form, `type` fixed
/// per the list page that pushed it — never a picker here, matches desktop's
/// 3-routes-one-component split). PO linkage + "Load items from PO" only for
/// LOCAL/IMPORTED (REPAIR never has a PO, mirrors desktop). Ledger IN-posting
/// + PO status sync only fire on a fresh create (`wasCreate`), matching
/// desktop's documented create-only scope.
class MrrFormPage extends StatefulWidget {
  final String type;
  final StoreMrr? existing;
  const MrrFormPage({super.key, required this.type, this.existing});

  @override
  State<MrrFormPage> createState() => _MrrFormPageState();
}

class _MrrFormPageState extends State<MrrFormPage> {
  final _client = ApiClient();
  late final _service = mrrService(_client);
  late final _poService = PurchaseOrderService(_client);
  late final _productService = StoreProductService(_client);

  bool get _isEdit => widget.existing != null;
  String get _referenceLabel => switch (widget.type) {
        'IMPORTED' => 'LC / BL / import permit no.',
        'REPAIR' => 'Repair job / order no.',
        _ => 'PO / invoice no.',
      };
  String get _supplierLabel => widget.type == 'REPAIR' ? 'Repair vendor' : 'Supplier name';
  String get _typeLabel => switch (widget.type) {
        'IMPORTED' => 'Imported receipt',
        'REPAIR' => 'Repair receipt',
        _ => 'Local receipt',
      };

  late int? _warehouseId = widget.existing?.warehouseId;
  late int? _purchaseOrderId = widget.existing?.purchaseOrderId;
  late final _referenceNoController = TextEditingController(text: widget.existing?.referenceNo ?? '');
  late final _supplierController = TextEditingController(text: widget.existing?.supplierName ?? '');
  late final _remarksController = TextEditingController(text: widget.existing?.remarks ?? '');
  late String _status = widget.existing?.status ?? 'PARTIAL';

  bool _loading = true;
  bool _submitting = false;
  bool _loadingPoItems = false;
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _batchRows = [];
  List<StorePurchaseOrder> _pos = [];
  List<StoreProduct> _products = [];
  List<StorePackaging> _packagings = [];
  List<DocumentLine> _lines = [];
  List<int> _originalLineIds = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _referenceNoController.dispose();
    _supplierController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final lookups = await StoreLookupService(_client).loadAll();
      final products = await _productService.list();
      final packagings = await _productService.listPackagings();
      final pos = widget.type == 'REPAIR' ? <StorePurchaseOrder>[] : await _poService.list(filter: "status ne 'RECEIVED' and status ne 'CANCELLED'");
      List<DocumentLine> lines = [];
      if (_isEdit) {
        lines = await _service.loadLines(widget.existing!.id);
      }
      if (!mounted) return;
      setState(() {
        _warehouses = lookups['warehouses'] ?? [];
        _batchRows = lookups['batches'] ?? [];
        _products = products;
        _packagings = packagings;
        _pos = pos;
        _lines = lines;
        _originalLineIds = lines.where((l) => l.id != null).map((l) => l.id!).toList();
      });
    } catch (_) {
      // form still usable, just without lookups
      if (mounted) marketToast(context, 'Some lists could not be loaded.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadItemsFromPo() async {
    if (_purchaseOrderId == null) return;
    if (_lines.isNotEmpty) {
      final confirmed = await confirmMarket(
        context,
        title: 'Replace current lines?',
        message: 'This overwrites the items currently on this receipt with the PO\'s ordered items.',
        confirm: 'Replace',
        destructive: false,
      );
      if (!confirmed) return;
    }
    setState(() => _loadingPoItems = true);
    try {
      final poItems = await _poService.loadItems(_purchaseOrderId!);
      if (!mounted) return;
      setState(() => _lines = poItems.map((i) => DocumentLine(productId: i.productId, productName: i.productName, quantity: i.quantity, unitPrice: i.unitPrice)).toList());
    } catch (_) {
      if (mounted) marketToast(context, 'Could not load the PO items.', error: true);
    } finally {
      if (mounted) setState(() => _loadingPoItems = false);
    }
  }

  Future<void> _submit() async {
    if (_warehouseId == null) {
      marketToast(context, 'Please select a warehouse.', error: true);
      return;
    }
    if (_lines.isEmpty) {
      marketToast(context, 'Add at least one item.', error: true);
      return;
    }
    setState(() => _submitting = true);
    final wasCreate = !_isEdit;
    try {
      final headerPayload = {
        'warehouse_id': _warehouseId,
        'purchase_order_id': _purchaseOrderId,
        'type': widget.type,
        'mode': _purchaseOrderId != null ? 'po_mode' : 'direct_mode',
        'status': _status,
        'reference_no': _referenceNoController.text.trim().isEmpty ? null : _referenceNoController.text.trim(),
        'supplier_name': _supplierController.text.trim().isEmpty ? null : _supplierController.text.trim(),
        'remarks': _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
      };

      int headerId;
      if (_isEdit) {
        headerId = widget.existing!.id;
        await _service.updateHeader(headerId, headerPayload);
      } else {
        final created = await _service.createHeader({
          ...headerPayload,
          'mrr_no': 'MRR-${DateTime.now().millisecondsSinceEpoch}',
          'received_date': DateTime.now().toIso8601String(),
        });
        headerId = (created['id'] as num).toInt();
      }

      await _service.saveLines(headerId, _lines, _originalLineIds);

      if (wasCreate) {
        final locationId = await resolveWarehouseLocationId(_client, _warehouseId!);
        if (locationId != null) {
          for (final line in _lines) {
            await postStockMovement(_client, StockMovementInput(
              productId: line.productId,
              locationId: locationId,
              batchId: line.batchId,
              type: 'IN',
              quantity: line.quantity,
              referenceType: 'MRR',
              referenceId: headerId,
            ));
          }
        }
        if (_purchaseOrderId != null) {
          await _poService.syncStatusAfterReceipt(_purchaseOrderId!);
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      marketToast(context, e is InsufficientStockException ? e.toString() : 'Could not save this receipt.', error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketScaffold(
      title: _isEdit ? 'Edit ${widget.existing!.mrrNo}' : 'New receipt',
      subtitle: _typeLabel,
      bottom: DocSaveBar(
        label: _isEdit ? 'Save changes' : 'Receive',
        icon: _isEdit ? Icons.check : Icons.move_to_inbox_outlined,
        busy: _submitting,
        onPressed: _loading ? null : _submit,
        summary: _loading ? null : docLineSummary(_lines),
      ),
      body: _loading
          ? const DocFormSkeleton()
          : DocFormBody(children: [
              DocSection(
                title: 'Receipt details',
                subtitle: 'Where the goods arrive and who sent them',
                children: [
                  DocDropdown<int>(
                    label: 'Warehouse',
                    required: true,
                    icon: Icons.warehouse_outlined,
                    hint: 'Choose a warehouse',
                    value: _warehouseId,
                    options: [for (final w in _warehouses) ((w['id'] as num).toInt(), (w['name'] ?? '').toString())],
                    onChanged: (v) => setState(() => _warehouseId = v),
                  ),
                  if (widget.type != 'REPAIR') ...[
                    DocDropdown<int>(
                      label: 'Linked purchase order',
                      help: 'Optional',
                      icon: Icons.shopping_cart_outlined,
                      hint: 'No purchase order',
                      value: _purchaseOrderId,
                      options: [for (final po in _pos) (po.id, '${po.poNo} · ${storeStatusLabel(po.status)}')],
                      onChanged: (v) => setState(() => _purchaseOrderId = v),
                    ),
                    if (_purchaseOrderId != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: p.brand,
                              side: BorderSide(color: p.line),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _loadingPoItems ? null : _loadItemsFromPo,
                            icon: _loadingPoItems
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.download_outlined, size: 18),
                            label: const Text('Load items from PO'),
                          ),
                        ),
                      ),
                  ],
                  FieldBlock(
                    label: _referenceLabel,
                    child: MarketTextField(controller: _referenceNoController, hint: 'Reference', icon: Icons.tag, capitalization: TextCapitalization.characters),
                  ),
                  FieldBlock(
                    label: _supplierLabel,
                    child: MarketTextField(controller: _supplierController, hint: 'Name', icon: Icons.storefront_outlined, capitalization: TextCapitalization.words),
                  ),
                  DocStatusPicker(statuses: _mrrStatuses, value: _mrrStatuses.contains(_status) ? _status : 'PARTIAL', onChanged: (v) => setState(() => _status = v)),
                  FieldBlock(label: 'Remarks', child: MarketTextField(controller: _remarksController, hint: 'Optional notes', maxLines: 3)),
                ],
              ),
              DocSection(
                index: 1,
                title: 'Items',
                subtitle: docLineSummary(_lines),
                card: false,
                children: [
                  LineItemsEditor(
                    lines: _lines,
                    onChanged: (lines) => setState(() => _lines = lines),
                    products: _products,
                    packagings: _packagings,
                    batchRows: _batchRows,
                    fieldsConfig: const LineFieldsConfig(showUnitPrice: true, showBatch: true, showRemarks: true),
                  ),
                ],
              ),
            ]),
    );
  }
}
