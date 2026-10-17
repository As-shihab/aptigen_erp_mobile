import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../data/document_models.dart';
import '../../data/document_services.dart';
import '../widgets/store_ui.dart';
import 'doc_kit.dart';
import 'purchase_requisition_form_page.dart';

/// Store Purchase Requisition (SPR) list. `statusFilter` mirrors desktop's
/// `SprRequestPage.tsx` (this list pre-filtered to PENDING), same trick as
/// `RequisitionListPage`.
///
/// SPRs run through an approval chain (see spr_approval_service.dart): the
/// row shows its progress ("Approval 1/2") and only PENDING / REJECTED SPRs
/// can be opened for editing.
class PurchaseRequisitionListPage extends StatefulWidget {
  final String? statusFilter;
  final String title;
  const PurchaseRequisitionListPage({super.key, this.statusFilter, this.title = 'Purchase requisitions'});

  @override
  State<PurchaseRequisitionListPage> createState() => _PurchaseRequisitionListPageState();
}

class _PurchaseRequisitionListPageState extends State<PurchaseRequisitionListPage> {
  late final _service = purchaseRequisitionService(ApiClient());

  // Same expand as desktop. `approvals` only exists once the approval-chain
  // migration has run, so fall back to the plain list if it fails.
  static const _richExpand = r'warehouse,items($select=id),approvals($select=id,status)';

  Future<List<StorePurchaseRequisition>> _load() async {
    final filter = widget.statusFilter != null ? "status eq '${widget.statusFilter}'" : null;
    try {
      return await _service.list(filter: filter, expand: _richExpand);
    } catch (_) {
      return _service.list(filter: filter);
    }
  }

  Future<bool> _create() async {
    final saved = await Navigator.of(context).push<bool>(marketRoute(const PurchaseRequisitionFormPage()));
    return saved == true;
  }

  Future<bool> _open(StorePurchaseRequisition row) async {
    if (!row.isEditable) {
      marketToast(context, '${row.sprNo} is ${sprStatusLabel(row.status).toLowerCase()} and can no longer be changed');
      return false;
    }
    final saved = await Navigator.of(context).push<bool>(marketRoute(PurchaseRequisitionFormPage(existing: row)));
    return saved == true;
  }

  (String, MarketTone)? _progress(StorePurchaseRequisition r) {
    if (r.approvalSteps == 0) return null;
    final tone = r.status == 'REJECTED'
        ? MarketTone.error
        : r.approvalsDone >= r.approvalSteps
            ? MarketTone.ok
            : MarketTone.info;
    return ('Approval ${r.approvalsDone}/${r.approvalSteps}', tone);
  }

  @override
  Widget build(BuildContext context) {
    return StoreDocList<StorePurchaseRequisition>(
      title: widget.title,
      icon: Icons.request_page_outlined,
      load: _load,
      describe: (r) => DocListItem(
        number: r.sprNo,
        date: r.requestedDate,
        meta: [r.warehouseLabel, r.purpose],
        itemCount: r.itemCount,
        status: r.status,
        extraPill: _progress(r),
      ),
      statusLabel: sprStatusLabel,
      statuses: widget.statusFilter != null ? const [] : const ['PENDING', 'APPROVED', 'ORDERED', 'REJECTED'],
      kpis: const [
        DocKpi(icon: Icons.hourglass_empty_outlined, label: 'Pending approval', tone: MarketTone.warn, statuses: {'PENDING'}),
        DocKpi(icon: Icons.verified_outlined, label: 'Approved', tone: MarketTone.ok, statuses: {'APPROVED'}),
      ],
      searchHint: 'Search number, warehouse or purpose',
      emptyTitle: widget.statusFilter != null ? 'Nothing waiting' : 'No purchase requisitions yet',
      emptyMessage: 'Requests to buy stock go here, then through approval to purchasing.',
      createLabel: 'New SPR',
      onCreate: _create,
      onOpen: _open,
    );
  }
}
