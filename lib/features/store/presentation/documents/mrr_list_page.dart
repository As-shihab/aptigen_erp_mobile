import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../data/document_models.dart';
import '../../data/document_services.dart';
import '../mrr_scanner_page.dart';
import '../widgets/store_ui.dart';
import 'doc_kit.dart';
import 'mrr_form_page.dart';

/// One list page serves all three MRR types (LOCAL/IMPORTED/REPAIR) via the
/// `type` filter — mirrors desktop's 3 separate routes/nav items that all
/// share `StoreMrrsView.tsx`. Real CRUD now (create/edit push the full
/// form) — the old `MrrListPage`/`store_mrr_service.dart` only listed
/// headers and relayed scans to desktop; this replaces both.
class MrrListPage extends StatefulWidget {
  final String type; // LOCAL | IMPORTED | REPAIR
  const MrrListPage({super.key, required this.type});

  @override
  State<MrrListPage> createState() => _MrrListPageState();
}

class _MrrListPageState extends State<MrrListPage> {
  late final _service = mrrService(ApiClient());

  String get _title => switch (widget.type) {
        'IMPORTED' => 'Imported MRR',
        'REPAIR' => 'Repair MRR',
        _ => 'Local MRR',
      };

  IconData get _icon => switch (widget.type) {
        'IMPORTED' => Icons.flight_land_outlined,
        'REPAIR' => Icons.build_outlined,
        _ => Icons.move_to_inbox_outlined,
      };

  Future<bool> _openForm({StoreMrr? existing}) async {
    final saved = await Navigator.of(context).push<bool>(marketRoute(MrrFormPage(type: widget.type, existing: existing)));
    return saved == true;
  }

  Future<void> _openRemoteScan(StoreMrr mrr) async {
    await Navigator.of(context).push(marketRoute(MrrScannerPage(mrrId: mrr.id, mrrNo: mrr.mrrNo)));
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return StoreDocList<StoreMrr>(
      title: _title,
      icon: _icon,
      load: () => _service.list(filter: "type eq '${widget.type}'"),
      describe: (m) => DocListItem(
        number: m.mrrNo,
        date: m.receivedDate,
        meta: [m.supplierName, m.warehouseLabel, m.referenceNo],
        itemCount: m.itemCount,
        status: m.status,
      ),
      statuses: const ['PARTIAL', 'COMPLETED', 'HOLD'],
      kpis: const [
        DocKpi(icon: Icons.move_to_inbox_outlined, label: 'Receipts', tone: MarketTone.brand),
        DocKpi(icon: Icons.pending_actions_outlined, label: 'Partial or on hold', tone: MarketTone.warn, statuses: {'PARTIAL', 'HOLD'}),
      ],
      searchHint: 'Search number, supplier or reference',
      emptyTitle: 'No receipts yet',
      emptyMessage: 'Goods you receive into a warehouse show up here.',
      createLabel: 'New receipt',
      onCreate: () => _openForm(),
      onOpen: (m) => _openForm(existing: m),
      trailing: (m) => IconButton(
        icon: Icon(Icons.qr_code_scanner, color: p.brand),
        tooltip: 'Remote scan (desktop)',
        onPressed: () => _openRemoteScan(m),
      ),
    );
  }
}
