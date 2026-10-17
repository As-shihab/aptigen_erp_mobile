import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../data/document_models.dart';
import '../../data/document_services.dart';
import '../widgets/store_ui.dart';
import 'doc_kit.dart';

/// Read-only — Purchase Order authoring stays desktop/Purchase-module
/// territory (see plan's scope notes). Mobile only needs to browse POs and
/// drill into one to see its items, feeding MRR's "Load items from PO".
class PurchaseOrderListPage extends StatefulWidget {
  const PurchaseOrderListPage({super.key});

  @override
  State<PurchaseOrderListPage> createState() => _PurchaseOrderListPageState();
}

class _PurchaseOrderListPageState extends State<PurchaseOrderListPage> {
  final _service = PurchaseOrderService(ApiClient());

  @override
  Widget build(BuildContext context) {
    return StoreDocList<StorePurchaseOrder>(
      title: 'Purchase orders',
      icon: Icons.shopping_cart_outlined,
      load: () => _service.list(),
      describe: (po) => DocListItem(
        number: po.poNo,
        date: po.orderDate,
        meta: [po.supplierName, if (po.expectedDate != null) 'Expected ${_date(po.expectedDate)}'],
        status: po.status,
      ),
      statuses: const ['PENDING', 'APPROVED', 'SENT', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CANCELLED'],
      kpis: const [
        DocKpi(icon: Icons.local_shipping_outlined, label: 'Awaiting goods', tone: MarketTone.info, statuses: {'APPROVED', 'SENT', 'PARTIALLY_RECEIVED'}),
        DocKpi(icon: Icons.inventory_outlined, label: 'Received', tone: MarketTone.ok, statuses: {'RECEIVED'}),
      ],
      searchHint: 'Search PO number or supplier',
      emptyTitle: 'No purchase orders yet',
      emptyMessage: 'Purchase orders raised in the purchase module show up here.',
      onOpen: (po) async {
        await Navigator.of(context).push(marketRoute(PurchaseOrderDetailPage(po: po)));
        return false;
      },
    );
  }
}

String _date(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  return d == null ? '—' : docShortDate(d);
}

class PurchaseOrderDetailPage extends StatefulWidget {
  final StorePurchaseOrder po;
  const PurchaseOrderDetailPage({super.key, required this.po});

  @override
  State<PurchaseOrderDetailPage> createState() => _PurchaseOrderDetailPageState();
}

class _PurchaseOrderDetailPageState extends State<PurchaseOrderDetailPage> {
  final _service = PurchaseOrderService(ApiClient());
  bool _loading = true;
  bool _failed = false;
  List<DocumentLine> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items = await _service.loadItems(widget.po.id);
      if (!mounted) return;
      setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _qty(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final po = widget.po;
    final total = _items.fold<double>(0, (s, l) => s + l.quantity * (l.unitPrice ?? 0));

    return MarketScaffold(
      title: po.poNo,
      subtitle: 'Purchase order · read only',
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            DocSection(
              title: 'Details',
              trailing: StatusPill(storeStatusLabel(po.status), tone: docStatusTone(po.status)),
              children: [
                InfoRow('Supplier', po.supplierName ?? '—'),
                InfoRow('Order date', _date(po.orderDate)),
                InfoRow('Expected', _date(po.expectedDate)),
                if ((po.remarks ?? '').isNotEmpty) InfoRow('Remarks', po.remarks!),
                const SizedBox(height: 9),
              ],
            ),
            DocSection(
              index: 1,
              title: 'Items',
              subtitle: _loading ? null : docLineSummary(_items),
              card: false,
              children: [
                if (_loading)
                  for (var i = 0; i < 3; i++) const Padding(padding: EdgeInsets.only(bottom: 8), child: SkeletonBox(height: 58, radius: 12))
                else if (_failed)
                  MarketEmpty(icon: Icons.cloud_off_outlined, title: 'Could not load the items', actionLabel: 'Try again', onAction: _load)
                else if (_items.isEmpty)
                  const MarketEmpty(icon: Icons.inventory_2_outlined, title: 'No items on this order')
                else ...[
                  MarketCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (var i = 0; i < _items.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: p.line),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(_items[i].productName,
                                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                                const SizedBox(height: 2),
                                Text(
                                  '${_qty(_items[i].quantity)} × ${_items[i].unitPrice != null ? money(_items[i].unitPrice!) : '—'}',
                                  style: TextStyle(fontSize: 11.5, color: p.label),
                                ),
                              ]),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _items[i].unitPrice != null ? money(_items[i].quantity * _items[i].unitPrice!) : '—',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text),
                            ),
                          ]),
                        ),
                      ],
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                    child: Row(children: [
                      Expanded(child: Text('Order value', style: TextStyle(fontSize: 12.5, color: p.label))),
                      Text(money(total), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
                    ]),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
