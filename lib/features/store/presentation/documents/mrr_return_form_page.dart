import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../sell/market/presentation/banners/form_kit.dart' show FieldBlock, MarketTextField;
import '../../data/document_models.dart';
import '../../data/document_services.dart';
import '../../data/store_lookup_service.dart';
import '../../data/store_product_model.dart';
import '../../data/store_product_service.dart';
import '../widgets/line_items_editor.dart';
import '../widgets/store_ui.dart';
import 'doc_kit.dart';

const _mrrReturnStatuses = ['PENDING', 'APPROVED', 'SHIPPED', 'REJECTED'];

/// Create/edit an MRR Return. Intentionally does not post to the stock
/// ledger — matches desktop's documented gap (the OUT-to-supplier posting
/// for this document was never built there either).
class MrrReturnFormPage extends StatefulWidget {
  final StoreMrrReturn? existing;
  const MrrReturnFormPage({super.key, this.existing});

  @override
  State<MrrReturnFormPage> createState() => _MrrReturnFormPageState();
}

class _MrrReturnFormPageState extends State<MrrReturnFormPage> {
  final _client = ApiClient();
  late final _service = mrrReturnService(_client);
  late final _mrrService = mrrService(_client);
  late final _productService = StoreProductService(_client);

  bool get _isEdit => widget.existing != null;

  late int? _warehouseId = widget.existing?.warehouseId;
  late int? _mrrId = widget.existing?.mrrId;
  late final _supplierController = TextEditingController(text: widget.existing?.supplierName ?? '');
  late final _remarksController = TextEditingController(text: widget.existing?.remarks ?? '');
  late String _status = widget.existing?.status ?? 'PENDING';

  bool _loading = true;
  bool _submitting = false;
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _batchRows = [];
  List<StoreMrr> _mrrs = [];
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
    _supplierController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final lookups = await StoreLookupService(_client).loadAll();
      final products = await _productService.list();
      final mrrs = await _mrrService.list(top: 200);
      List<DocumentLine> lines = [];
      if (_isEdit) lines = await _service.loadLines(widget.existing!.id);
      if (!mounted) return;
      setState(() {
        _warehouses = lookups['warehouses'] ?? [];
        _batchRows = lookups['batches'] ?? [];
        _mrrs = mrrs;
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
    try {
      final headerPayload = {
        'warehouse_id': _warehouseId,
        'mrr_id': _mrrId,
        'supplier_name': _supplierController.text.trim().isEmpty ? null : _supplierController.text.trim(),
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
          'return_no': 'MRT-${DateTime.now().millisecondsSinceEpoch}',
          'return_date': DateTime.now().toIso8601String(),
        });
        headerId = (created['id'] as num).toInt();
      }

      await _service.saveLines(headerId, _lines, _originalLineIds);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Could not save this MRR return.', error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MarketScaffold(
      title: _isEdit ? 'Edit ${widget.existing!.returnNo}' : 'New MRR return',
      subtitle: 'Goods sent back to the supplier',
      bottom: DocSaveBar(
        label: _isEdit ? 'Save changes' : 'Create return',
        icon: _isEdit ? Icons.check : Icons.undo_outlined,
        busy: _submitting,
        onPressed: _loading ? null : _submit,
        summary: _loading ? null : docLineSummary(_lines),
      ),
      body: _loading
          ? const DocFormSkeleton()
          : DocFormBody(children: [
              DocSection(
                title: 'Return details',
                subtitle: 'Which receipt this reverses and where the goods leave from',
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
                    label: 'Reverses MRR',
                    help: 'Optional',
                    icon: Icons.move_to_inbox_outlined,
                    hint: 'No receipt',
                    value: _mrrId,
                    options: [for (final m in _mrrs) (m.id, m.mrrNo)],
                    onChanged: (v) => setState(() => _mrrId = v),
                  ),
                  FieldBlock(
                    label: 'Supplier name',
                    child: MarketTextField(controller: _supplierController, hint: 'Name', icon: Icons.storefront_outlined, capitalization: TextCapitalization.words),
                  ),
                  DocStatusPicker(
                    statuses: _mrrReturnStatuses,
                    value: _mrrReturnStatuses.contains(_status) ? _status : 'PENDING',
                    onChanged: (v) => setState(() => _status = v),
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
                    batchRows: _batchRows,
                    fieldsConfig: const LineFieldsConfig(showUnitPrice: true, showBatch: true, showReason: true),
                  ),
                ],
              ),
            ]),
    );
  }
}
