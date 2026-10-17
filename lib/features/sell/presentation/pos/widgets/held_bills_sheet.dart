import 'package:flutter/material.dart';
import '../../../../../core/network/http_client.dart';
import '../../../../../core/utils/currency.dart';
import '../../../data/sales_order_model.dart';
import '../../../data/sales_order_service.dart';
import '../../widgets/sell_ui.dart' show MarketPalette, MarketCard, MarketEmpty, SkeletonList, FadeSlideIn, showMarketSheet;

/// Picks a PARKED sale to resume into a brand-new cart tab — the actual
/// cart-hydration logic lives in `PosTerminalPage._resumeHeldSale` (this
/// sheet just lists and returns the chosen `SalesOrder`), mirroring
/// desktop's `resumeHeldSale` (PosTerminal.tsx).
Future<SalesOrder?> showHeldBillsSheet(BuildContext context, {bool isPharma = false}) {
  return showMarketSheet<SalesOrder>(
    context,
    builder: (_) => _HeldBillsSheet(isPharma: isPharma),
  );
}

class _HeldBillsSheet extends StatefulWidget {
  final bool isPharma;
  const _HeldBillsSheet({this.isPharma = false});

  @override
  State<_HeldBillsSheet> createState() => _HeldBillsSheetState();
}

class _HeldBillsSheetState extends State<_HeldBillsSheet> {
  late final _service = SalesOrderService(ApiClient());
  bool _loading = true;
  List<SalesOrder> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await _service.list(statusFilter: 'PARKED', expandItems: true, isPharma: widget.isPharma);
      if (!mounted) return;
      setState(() => _rows = result);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        final p = MarketPalette.of(context);
        return Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: p.warnBg, borderRadius: BorderRadius.circular(9)),
                    child: Icon(Icons.pause_circle_outline, size: 18, color: p.warn),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Held sales', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: p.text)),
                        const SizedBox(height: 2),
                        Text(
                          _loading ? 'Loading…' : '${_rows.length} parked sale${_rows.length == 1 ? '' : 's'} · tap one to resume',
                          style: TextStyle(fontSize: 12, color: p.label),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const SkeletonList(count: 5, itemHeight: 64)
                  : _rows.isEmpty
                      ? ListView(
                          controller: scrollController,
                          children: const [
                            MarketEmpty(icon: Icons.pause_circle_outline, title: 'No held bills', message: 'Parked sales show up here so you can resume them later.'),
                          ],
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final row = _rows[index];
                            return FadeSlideIn(
                              index: index,
                              child: MarketCard(
                                onTap: () => Navigator.of(context).pop(row),
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(9)),
                                      child: Icon(Icons.receipt_long_outlined, size: 18, color: p.label),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(row.displayNo, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: p.text)),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${row.clientName ?? 'Walk-in'} · ${row.items.length} item${row.items.length == 1 ? '' : 's'}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 12, color: p.label),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(formatMoney(row.total), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: p.text)),
                                        const SizedBox(height: 2),
                                        Text('Resume', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.brand)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}
