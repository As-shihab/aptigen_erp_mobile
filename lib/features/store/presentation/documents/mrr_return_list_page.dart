import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../data/document_models.dart';
import '../../data/document_services.dart';
import '../widgets/store_ui.dart';
import 'doc_kit.dart';
import 'mrr_return_form_page.dart';

/// MRR Return list — reverses an MRR (damaged/wrong goods sent back to the
/// supplier). Doesn't post to the stock ledger — matches desktop, a
/// documented gap, not a mobile omission.
class MrrReturnListPage extends StatefulWidget {
  const MrrReturnListPage({super.key});

  @override
  State<MrrReturnListPage> createState() => _MrrReturnListPageState();
}

class _MrrReturnListPageState extends State<MrrReturnListPage> {
  late final _service = mrrReturnService(ApiClient());

  Future<bool> _openForm({StoreMrrReturn? existing}) async {
    final saved = await Navigator.of(context).push<bool>(marketRoute(MrrReturnFormPage(existing: existing)));
    return saved == true;
  }

  @override
  Widget build(BuildContext context) {
    return StoreDocList<StoreMrrReturn>(
      title: 'Return MRR',
      icon: Icons.undo_outlined,
      load: () => _service.list(),
      describe: (r) => DocListItem(
        number: r.returnNo,
        date: r.returnDate,
        meta: [r.supplierName, r.warehouseLabel],
        itemCount: r.itemCount,
        status: r.status,
      ),
      statuses: const ['PENDING', 'APPROVED', 'SHIPPED', 'REJECTED'],
      kpis: const [
        DocKpi(icon: Icons.undo_outlined, label: 'Returns', tone: MarketTone.brand),
        DocKpi(icon: Icons.hourglass_empty_outlined, label: 'Pending', tone: MarketTone.warn, statuses: {'PENDING'}),
      ],
      searchHint: 'Search number or supplier',
      emptyTitle: 'No MRR returns yet',
      emptyMessage: 'Goods sent back to a supplier show up here.',
      createLabel: 'New MRR return',
      onCreate: () => _openForm(),
      onOpen: (r) => _openForm(existing: r),
    );
  }
}
