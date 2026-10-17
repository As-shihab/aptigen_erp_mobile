import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../data/document_models.dart';
import '../../data/document_services.dart';
import '../widgets/store_ui.dart';
import 'doc_kit.dart';
import 'return_form_page.dart';

/// Store Return list — reverses a Store Requisition (department/production
/// sends unused/excess materials back into a warehouse).
class ReturnListPage extends StatefulWidget {
  const ReturnListPage({super.key});

  @override
  State<ReturnListPage> createState() => _ReturnListPageState();
}

class _ReturnListPageState extends State<ReturnListPage> {
  late final _service = storeReturnService(ApiClient());

  Future<bool> _openForm({StoreReturnDoc? existing}) async {
    final saved = await Navigator.of(context).push<bool>(marketRoute(ReturnFormPage(existing: existing)));
    return saved == true;
  }

  @override
  Widget build(BuildContext context) {
    return StoreDocList<StoreReturnDoc>(
      title: 'Returns',
      icon: Icons.assignment_return_outlined,
      load: () => _service.list(),
      describe: (r) => DocListItem(
        number: r.returnNo,
        date: r.returnDate,
        meta: [r.warehouseLabel],
        itemCount: r.itemCount,
        status: r.status,
      ),
      statuses: const ['PENDING', 'APPROVED', 'RECEIVED', 'REJECTED'],
      kpis: const [
        DocKpi(icon: Icons.assignment_return_outlined, label: 'Returns', tone: MarketTone.brand),
        DocKpi(icon: Icons.hourglass_empty_outlined, label: 'Pending', tone: MarketTone.warn, statuses: {'PENDING'}),
      ],
      searchHint: 'Search number or warehouse',
      emptyTitle: 'No returns yet',
      emptyMessage: 'Materials sent back into a warehouse show up here.',
      createLabel: 'New return',
      onCreate: () => _openForm(),
      onOpen: (r) => _openForm(existing: r),
    );
  }
}
