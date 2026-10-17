import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../data/sales_order_model.dart';
import '../data/sales_order_service.dart';
import 'pos/pos_terminal_page.dart';
import 'widgets/sell_ui.dart';

/// PARKED sales — mirrors desktop's HeldBillList.tsx. "Resume" is just a
/// navigation shortcut to POS Terminal, same as desktop (its own held-bill
/// picker inside POS is where the actual cart hand-off happens — this list
/// doesn't hand off any state itself, matching the real desktop behavior
/// rather than over-engineering a deep link desktop itself doesn't have).
/// "Cancel" is a raw status PUT — a parked sale never touched stock/ledger,
/// so there's nothing to reverse.
class HeldBillsListPage extends StatefulWidget {
  final bool isPharma;
  const HeldBillsListPage({super.key, this.isPharma = false});

  @override
  State<HeldBillsListPage> createState() => _HeldBillsListPageState();
}

class _HeldBillsListPageState extends State<HeldBillsListPage> {
  late final _service = SalesOrderService(ApiClient());
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<SalesOrder> _rows = [];
  final Set<int> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.list(statusFilter: 'PARKED', isPharma: widget.isPharma);
      if (!mounted) return;
      setState(() => _rows = result);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load held bills.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _resume() {
    Navigator.of(context).push(marketRoute(PosTerminalPage(isPharma: widget.isPharma)));
  }

  Future<void> _cancel(SalesOrder sale) async {
    final confirmed = await confirmMarket(
      context,
      title: 'Cancel held bill',
      message: 'Cancel "${sale.displayNo}"? This can\'t be undone.',
      confirm: 'Cancel bill',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busyIds.add(sale.id));
    try {
      await _service.cancelHeldBill(sale.id);
      if (!mounted) return;
      setState(() => _rows.removeWhere((r) => r.id == sale.id));
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Could not cancel this bill.', error: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(sale.id));
    }
  }

  List<SalesOrder> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows
        .where((o) =>
            o.displayNo.toLowerCase().contains(q) ||
            (o.clientName ?? 'walk-in').toLowerCase().contains(q) ||
            (o.clientPhone ?? '').contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final visible = _visible;
    final value = visible.fold<double>(0, (s, o) => s + o.total);

    return MarketScaffold(
      title: widget.isPharma ? 'Pharma held bills' : 'Held bills',
      subtitle: _loading && _rows.isEmpty ? 'Loading…' : '${visible.length} of ${_rows.length}',
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(children: [
                Row(children: [
                  Expanded(child: KpiTile(icon: Icons.pause_circle_outline, label: 'Held bills', value: visible.length, tone: MarketTone.warn)),
                  const SizedBox(width: 10),
                  Expanded(child: KpiTile(icon: Icons.account_balance_wallet_outlined, label: 'Value', value: value, format: (v) => money(v), tone: MarketTone.info)),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search number, client or phone',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    fillColor: p.card,
                    suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
                  ),
                ),
              ]),
            ),
          ),
          ..._listSlivers(p, visible),
        ]),
      ),
    );
  }

  List<Widget> _listSlivers(MarketPalette p, List<SalesOrder> visible) {
    if (_loading && _rows.isEmpty) {
      return const [SliverFillRemaining(hasScrollBody: false, child: SkeletonList(count: 5, itemHeight: 96))];
    }
    if (_error != null) {
      return [SliverFillRemaining(hasScrollBody: false, child: MarketEmpty(icon: Icons.cloud_off_outlined, title: _error!, actionLabel: 'Try again', onAction: _load))];
    }
    if (visible.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: MarketEmpty(
            icon: Icons.pause_circle_outline,
            title: _rows.isEmpty ? 'No held bills' : 'Nothing matches',
            message: _rows.isEmpty ? 'Bills you hold in the POS wait here until you resume them.' : 'Try another search.',
            actionLabel: _rows.isEmpty ? 'Open POS' : null,
            onAction: _rows.isEmpty ? _resume : null,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        sliver: SliverList.separated(
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) => FadeSlideIn(index: i, child: _row(p, visible[i])),
        ),
      ),
    ];
  }

  Widget _row(MarketPalette p, SalesOrder o) {
    final busy = _busyIds.contains(o.id);
    final c = p.tone(MarketTone.warn);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: busy ? 0.5 : 1,
      child: MarketCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.pause_rounded, size: 20, color: c.fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.clientName ?? 'Walk-in', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                const SizedBox(height: 2),
                Text(
                  [o.displayNo, if ((o.clientPhone ?? '').isNotEmpty) o.clientPhone!].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: p.label),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Text(money(o.total), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
          ]),
          const SizedBox(height: 8),
          Divider(height: 1, color: p.line),
          Row(children: [
            Icon(Icons.schedule, size: 14, color: p.label),
            const SizedBox(width: 5),
            Expanded(
              child: Text('Held since ${dateTimeLabel(o.updatedAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
            ),
            TextButton(
              onPressed: busy ? null : () => _cancel(o),
              style: TextButton.styleFrom(foregroundColor: p.error, visualDensity: VisualDensity.compact),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: busy ? null : _resume,
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Resume'),
            ),
          ]),
        ]),
      ),
    );
  }
}
