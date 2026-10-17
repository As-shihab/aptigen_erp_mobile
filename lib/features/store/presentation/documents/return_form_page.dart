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

const _returnStatuses = ['PENDING', 'APPROVED', 'RECEIVED', 'REJECTED'];

/// Create/edit a Store Return — IN-posts to the ledger on the transition
/// into RECEIVED (same `originalStatus` pattern as SR's ISSUED posting).
class ReturnFormPage extends StatefulWidget {
  final StoreReturnDoc? existing;
  const ReturnFormPage({super.key, this.existing});

  @override
  State<ReturnFormPage> createState() => _ReturnFormPageState();
}

class _ReturnFormPageState extends State<ReturnFormPage> {
  final _client = ApiClient();
  late final _service = storeReturnService(_client);
  late final _srService = requisitionService(_client);
  late final _productService = StoreProductService(_client);

  bool get _isEdit => widget.existing != null;
  late final String? _originalStatus = widget.existing?.status;

  late int? _warehouseId = widget.existing?.warehouseId;
  late int? _departmentId = widget.existing?.departmentId;
  late int? _requisitionId = widget.existing?.requisitionId;
  late final _remarksController = TextEditingController(text: widget.existing?.remarks ?? '');
  late String _status = widget.existing?.status ?? 'PENDING';

  bool _loading = true;
  bool _submitting = false;
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _departments = [];
  List<StoreRequisition> _requisitions = [];
  List<StoreProduct> _products = [];
  List<DocumentLine> _lines = [];
  List<int> _originalLineIds = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final lookups = await StoreLookupService(_client).loadAll();
      final products = await _productService.list();
      final requisitions = await _srService.list(top: 200);
      List<DocumentLine> lines = [];
      if (_isEdit) lines = await _service.loadLines(widget.existing!.id);
      if (!mounted) return;
      setState(() {
        _warehouses = lookups['warehouses'] ?? [];
        _departments = lookups['departments'] ?? [];
        _requisitions = requisitions;
        _products = products;
        _lines = lines;
        _originalLineIds = lines.where((l) => l.id != null).map((l) => l.id!).toList();
      });
    } catch (_) {
      if (mounted) marketToast(context, 'Some lists could not be loaded.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
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
    final wasReceivedBefore = _isEdit && _originalStatus == 'RECEIVED';
    try {
      final headerPayload = {
        'warehouse_id': _warehouseId,
        'department_id': _departmentId,
        'requisition_id': _requisitionId,
        'status': _status,
        'remarks': _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
      };

      int headerId;
      if (_isEdit) {
        headerId = widget.existing!.id;
        await _service.updateHeader(headerId, headerPayload);
      } else {
        final created = await _service.createHeader({
          ...headerPayload,
          'return_no': 'RET-${DateTime.now().millisecondsSinceEpoch}',
          'return_date': DateTime.now().toIso8601String(),
        });
        headerId = (created['id'] as num).toInt();
      }

      await _service.saveLines(headerId, _lines, _originalLineIds);

      if (!wasReceivedBefore && _status == 'RECEIVED') {
        try {
          final locationId = await resolveWarehouseLocationId(_client, _warehouseId!);
          if (locationId != null) {
            for (final line in _lines) {
              await postStockMovement(_client, StockMovementInput(
                productId: line.productId,
                locationId: locationId,
                type: 'IN',
                quantity: line.quantity,
                referenceType: 'RETURN',
                referenceId: headerId,
              ));
            }
          }
        } catch (e) {
          if (mounted) {
            marketToast(context, e is InsufficientStockException ? e.toString() : 'Could not post stock movement.', error: true);
          }
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Could not save this return.', error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final willReceive = _status == 'RECEIVED' && _originalStatus != 'RECEIVED';
    return MarketScaffold(
      title: _isEdit ? 'Edit ${widget.existing!.returnNo}' : 'New return',
      subtitle: 'Materials coming back into a warehouse',
      bottom: DocSaveBar(
        label: _isEdit ? 'Save changes' : 'Create return',
        icon: _isEdit ? Icons.check : Icons.assignment_return_outlined,
        busy: _submitting,
        onPressed: _loading ? null : _submit,
        summary: _loading ? null : docLineSummary(_lines),
      ),
      body: _loading
          ? const DocFormSkeleton()
          : DocFormBody(children: [
              DocSection(
                title: 'Return details',
                subtitle: 'Where the materials come back to',
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
                  DocDropdown<int>(
                    label: 'Department',
                    help: 'Optional',
                    icon: Icons.apartment_outlined,
                    hint: 'No department',
                    value: _departmentId,
                    options: [for (final d in _departments) ((d['id'] as num).toInt(), (d['name'] ?? '').toString())],
                    onChanged: (v) => setState(() => _departmentId = v),
                  ),
                  DocDropdown<int>(
                    label: 'Reverses SR',
                    help: 'Optional',
                    icon: Icons.description_outlined,
                    hint: 'No requisition',
                    value: _requisitionId,
                    options: [for (final r in _requisitions) (r.id, r.srNo)],
                    onChanged: (v) => setState(() => _requisitionId = v),
                  ),
                  DocStatusPicker(
                    statuses: _returnStatuses,
                    value: _returnStatuses.contains(_status) ? _status : 'PENDING',
                    onChanged: (v) => setState(() => _status = v),
                    help: willReceive ? 'Saving as received puts these items back into stock.' : null,
                  ),
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
                    fieldsConfig: const LineFieldsConfig(showReason: true, showRemarks: true),
                  ),
                ],
              ),
            ]),
    );
  }
}
