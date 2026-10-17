import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../data/document_models.dart';
import '../../data/document_services.dart';
import '../widgets/store_ui.dart';
import 'doc_kit.dart';
import 'requisition_form_page.dart';

/// Store Requisition (SR) list. `statusFilter` (e.g. 'PENDING') turns this
/// into the "SR Request" work-queue view — mirrors desktop's
/// `SrRequestPage.tsx`, which is just `StoreRequisitions` pre-filtered, not a
/// separate component.
class RequisitionListPage extends StatefulWidget {
  final String? statusFilter;
  final String title;
  const RequisitionListPage({super.key, this.statusFilter, this.title = 'Store requisitions'});

  @override
  State<RequisitionListPage> createState() => _RequisitionListPageState();
}

class _RequisitionListPageState extends State<RequisitionListPage> {
  late final _service = requisitionService(ApiClient());

  Future<bool> _openForm({StoreRequisition? existing}) async {
    final saved = await Navigator.of(context).push<bool>(marketRoute(RequisitionFormPage(existing: existing)));
    return saved == true;
  }

  @override
  Widget build(BuildContext context) {
    return StoreDocList<StoreRequisition>(
      title: widget.title,
      icon: Icons.description_outlined,
      load: () => _service.list(filter: widget.statusFilter != null ? "status eq '${widget.statusFilter}'" : null),
      describe: (r) => DocListItem(
        number: r.srNo,
        date: r.requestedDate,
        meta: [r.warehouseLabel, r.purpose],
        itemCount: r.itemCount,
        status: r.status,
      ),
      // Pinned to one status → no filter needed.
      statuses: widget.statusFilter != null ? const [] : const ['PENDING', 'APPROVED', 'ISSUED', 'REJECTED'],
      kpis: const [
        DocKpi(icon: Icons.hourglass_empty_outlined, label: 'Pending', tone: MarketTone.warn, statuses: {'PENDING'}),
        DocKpi(icon: Icons.outbox_outlined, label: 'Issued', tone: MarketTone.ok, statuses: {'ISSUED'}),
      ],
      searchHint: 'Search number, warehouse or purpose',
      emptyTitle: widget.statusFilter != null ? 'Nothing waiting' : 'No requisitions yet',
      emptyMessage: 'Internal requests to issue stock from a warehouse show up here.',
      createLabel: 'New requisition',
      onCreate: () => _openForm(),
      onOpen: (r) => _openForm(existing: r),
    );
  }
}
