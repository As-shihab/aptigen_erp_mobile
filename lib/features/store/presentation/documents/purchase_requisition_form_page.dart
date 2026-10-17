import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../sell/market/presentation/banners/form_kit.dart' show FieldBlock, MarketTextField;
import '../../data/document_models.dart';
import '../../data/document_services.dart';
import '../../data/spr_approval_service.dart';
import '../../data/store_lookup_service.dart';
import '../../data/store_product_model.dart';
import '../../data/store_product_service.dart';
import '../../data/store_settings_service.dart';
import '../widgets/line_items_editor.dart';
import '../widgets/store_ui.dart';
import 'doc_kit.dart';

/// Create/edit a Store Purchase Requisition — pre-purchase, never posts to
/// the stock ledger (matches desktop: SPR precedes a PO/MRR, no stock moves
/// yet at this stage).
///
/// The store only *sends* an SPR: its status isn't picked here. Every save
/// sends it (back) as PENDING and, when `store_settings.has_spr_approval` is
/// on, (re)starts the approval chain (spr_approval_service.dart). Approvers
/// — or purchasing, when there's no chain — decide; once approved or ordered
/// the SPR is locked (mirrors desktop's StorePurchaseRequisitions.tsx).
class PurchaseRequisitionFormPage extends StatefulWidget {
  final StorePurchaseRequisition? existing;
  const PurchaseRequisitionFormPage({super.key, this.existing});

  @override
  State<PurchaseRequisitionFormPage> createState() => _PurchaseRequisitionFormPageState();
}

class _PurchaseRequisitionFormPageState extends State<PurchaseRequisitionFormPage> {
  final _client = ApiClient();
  late final _service = purchaseRequisitionService(_client);
  late final _productService = StoreProductService(_client);

  bool get _isEdit => widget.existing != null;
  bool get _locked => _isEdit && !widget.existing!.isEditable;

  late int? _warehouseId = widget.existing?.warehouseId;
  late final _purposeController = TextEditingController(text: widget.existing?.purpose ?? '');
  late final _remarksController = TextEditingController(text: widget.existing?.remarks ?? '');

  bool _loading = true;
  bool _submitting = false;
  bool _deleting = false;
  List<Map<String, dynamic>> _warehouses = [];
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
    _purposeController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final lookups = await StoreLookupService(_client).loadAll();
      final products = await _productService.list();
      List<DocumentLine> lines = [];
      if (_isEdit) lines = await _service.loadLines(widget.existing!.id);
      if (!mounted) return;
      setState(() {
        _warehouses = lookups['warehouses'] ?? [];
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

  void _toastLocked() {
    final spr = widget.existing!;
    marketToast(context, '${spr.sprNo} is ${sprStatusLabel(spr.status).toLowerCase()} and can no longer be changed');
  }

  /// (Re)starts the approval chain when it's switched on. Returns the number
  /// of steps created; 0 on no chain, no approvers, or any failure (e.g. the
  /// approval tables aren't migrated yet) — the SPR is saved either way and
  /// simply waits for purchasing.
  Future<int> _startApproval(int sprId) async {
    try {
      final settings = await StoreSettingsService(_client).load();
      if (!settings.hasSprApproval) return 0;
      return await SprApprovalService(_client).start(sprId, settings.sprApproverTypeId);
    } catch (_) {
      return 0;
    }
  }

  Future<void> _submit() async {
    if (_locked) return _toastLocked();
    if (_lines.isEmpty) {
      marketToast(context, 'Add at least one item.', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final headerPayload = {
        'warehouse_id': _warehouseId,
        'purpose': _purposeController.text.trim().isEmpty ? null : _purposeController.text.trim(),
        // Every save (new, edited while pending, or a rejected one resent)
        // goes (back) for approval.
        'status': 'PENDING',
        'remarks': _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
      };

      int headerId;
      String sprNo;
      if (_isEdit) {
        headerId = widget.existing!.id;
        sprNo = widget.existing!.sprNo;
        await _service.updateHeader(headerId, headerPayload);
      } else {
        sprNo = 'SPR-${DateTime.now().millisecondsSinceEpoch}';
        final created = await _service.createHeader({
          ...headerPayload,
          'spr_no': sprNo,
          'requested_date': DateTime.now().toIso8601String(),
        });
        headerId = (created['id'] as num).toInt();
        sprNo = (created['spr_no'] ?? sprNo).toString();
      }

      await _service.saveLines(headerId, _lines, _originalLineIds);

      final steps = await _startApproval(headerId);

      if (!mounted) return;
      marketToast(context, steps > 0 ? '$sprNo sent for approval ($steps step${steps == 1 ? '' : 's'})' : '$sprNo sent to purchasing for approval');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Could not save this purchase requisition.', error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _delete() async {
    final spr = widget.existing!;
    if (_locked) {
      marketToast(context, '${spr.sprNo} is already ${sprStatusLabel(spr.status).toLowerCase()} and can\'t be deleted');
      return;
    }
    final ok = await confirmMarket(
      context,
      title: 'Delete ${spr.sprNo}?',
      message: 'Its ${_lines.length} item line${_lines.length == 1 ? '' : 's'} will be removed too.',
    );
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    try {
      await _service.deleteHeader(spr.id);
      if (!mounted) return;
      marketToast(context, 'Purchase requisition deleted');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) marketToast(context, 'Could not delete this purchase requisition.', error: true);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _statusField() {
    final spr = widget.existing;
    if (spr == null) {
      return const DocReadOnlyField(
        label: 'Status',
        value: 'Sent for approval on save',
        icon: Icons.send_outlined,
        help: 'Approvers, or purchasing when no approval chain is set up, decide.',
      );
    }
    return DocReadOnlyField(
      label: 'Status',
      value: sprStatusLabel(spr.status),
      icon: Icons.verified_outlined,
      tone: storeStatusTone(spr.status),
      help: spr.status == 'REJECTED'
          ? 'Saving sends it for approval again.'
          : spr.approvalSteps > 0
              ? 'Approval ${spr.approvalsDone} of ${spr.approvalSteps} done. Saving restarts the approval.'
              : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketScaffold(
      title: _isEdit ? 'Edit ${widget.existing!.sprNo}' : 'New purchase requisition',
      subtitle: 'Request to buy stock, sent for approval',
      actions: [
        if (_isEdit && !_locked)
          IconButton(
            tooltip: 'Delete',
            onPressed: _deleting || _submitting ? null : _delete,
            icon: _deleting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.delete_outline, color: p.error),
          ),
      ],
      bottom: DocSaveBar(
        label: _isEdit ? 'Save and send' : 'Send for approval',
        icon: Icons.send_outlined,
        busy: _submitting,
        onPressed: _loading || _deleting ? null : (_locked ? _toastLocked : _submit),
        summary: _loading ? null : docLineSummary(_lines),
      ),
      body: _loading
          ? const DocFormSkeleton()
          : DocFormBody(children: [
              if (_locked)
                DocNotice(
                  icon: Icons.lock_outline,
                  tone: MarketTone.warn,
                  message: '${widget.existing!.sprNo} is ${sprStatusLabel(widget.existing!.status).toLowerCase()} and can no longer be changed.',
                ),
              DocSection(
                title: 'Requisition details',
                subtitle: 'What purchasing should buy and why',
                children: [
                  DocDropdown<int>(
                    label: 'Warehouse',
                    help: 'Optional',
                    icon: Icons.warehouse_outlined,
                    hint: 'No warehouse',
                    value: _warehouseId,
                    options: [for (final w in _warehouses) ((w['id'] as num).toInt(), (w['name'] ?? '').toString())],
                    onChanged: (v) => setState(() => _warehouseId = v),
                  ),
                  FieldBlock(label: 'Purpose', child: MarketTextField(controller: _purposeController, hint: 'What it\'s for', icon: Icons.flag_outlined)),
                  _statusField(),
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
                    fieldsConfig: const LineFieldsConfig(showEstimatedPrice: true, showRemarks: true),
                  ),
                ],
              ),
            ]),
    );
  }
}
