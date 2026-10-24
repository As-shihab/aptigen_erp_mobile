import '../orders/purchase_orders_page.dart';
import 'package:flutter/material.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/comparative_service.dart';
import '../../data/rfq_service.dart';

// Comparative study — desktop purchase/comparative/ComparativeStudy.tsx,
// adapted to a phone: pick a requisition (SPR), see one card per supplier
// quote across every RFQ raised for it (cheapest first, best price marked),
// then compare per product (cards with a price row per supplier, lowest
// highlighted) or as a horizontally scrolling matrix. "Create PO" awards a
// quote through the shared award flow (awardQuote.ts).

String _qty(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

enum CompareView { items, matrix }

/// Confirms, awards the quote (creates the PO etc.) behind a blocking
/// progress dialog and toasts the outcome. Returns the result on success.
Future<AwardResult?> runAwardFlow(BuildContext context, {required Rfq rfq, required RfqQuote quote, required PurchaseApprovalSettings settings}) async {
  final t = quoteTotalOf(rfq.items, quote);
  final notes = [
    'The other quotes on ${rfq.rfqNo} will be marked rejected and the RFQ will be closed as awarded.',
    if (!t.complete) 'Products this supplier did not price are left off the order.',
    if (settings.hasPoApproval) 'The new order goes into the approval chain.',
  ].join(' ');
  final ok = await confirmMarket(
    context,
    title: 'Create purchase order',
    message: 'Create a purchase order for ${quote.supplier} at ${money(t.total)}?\n\n$notes',
    confirm: 'Create purchase order',
    destructive: false,
  );
  if (!ok || !context.mounted) return null;

  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final p = MarketPalette.of(ctx);
      return PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: p.brand)),
                const SizedBox(width: 14),
                Material(
                  type: MaterialType.transparency,
                  child: Text('Creating purchase order', style: TextStyle(color: p.text, fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  try {
    final result = await RfqService().awardQuote(rfq: rfq, quote: quote, settings: settings);
    nav.pop();
    if (!context.mounted) return result;
    if (result == null) {
      marketToast(context, 'This supplier has not priced any product', error: true);
    } else {
      marketToast(context, result.submittedForApproval ? '${result.poNo} created and submitted for approval' : '${result.poNo} created');
      // Desktop jumps to the new order (/purchase?po=<id>).
      pushMotion(context, PurchaseOrderDetailPage(poId: result.poId));
    }
    return result;
  } catch (e) {
    nav.pop();
    if (context.mounted) marketToast(context, errorMessage(e, 'Failed to create purchase order'), error: true);
    return null;
  }
}

class ComparativeStudyPage extends StatefulWidget {
  /// Land on this requisition (desktop `?spr=<id>`).
  final int? sprId;
  const ComparativeStudyPage({super.key, this.sprId});

  @override
  State<ComparativeStudyPage> createState() => _ComparativeStudyPageState();
}

class _ComparativeStudyPageState extends State<ComparativeStudyPage> {
  final _service = ComparativeService();

  List<SprSummary> _sprs = [];
  PurchaseApprovalSettings _settings = const PurchaseApprovalSettings();
  bool _listLoading = true;
  String? _listError;
  int? _selectedId;

  List<Rfq> _rfqs = [];
  bool _detailLoading = false;
  String? _detailError;
  int? _rfqFilter;
  CompareView _view = CompareView.items;

  @override
  void initState() {
    super.initState();
    _loadList();
  }

  Future<void> _loadList() async {
    setState(() {
      _listLoading = _sprs.isEmpty;
      _listError = null;
    });
    try {
      final data = await _service.loadRequisitions();
      if (!mounted) return;
      final rows = data.sprs;
      int? pick = _selectedId;
      if (pick == null || !rows.any((r) => r.id == pick)) {
        if (widget.sprId != null && rows.any((r) => r.id == widget.sprId)) {
          pick = widget.sprId;
        } else {
          pick = (rows.where((r) => r.quoteCount > 0).firstOrNull ?? rows.firstOrNull)?.id;
        }
      }
      setState(() {
        _sprs = rows;
        _settings = data.settings;
        _selectedId = pick;
      });
      if (pick != null) {
        await _loadDetail(pick);
      } else {
        setState(() => _rfqs = []);
      }
    } catch (e) {
      if (mounted) setState(() => _listError = errorMessage(e, 'Failed to load requisitions'));
    } finally {
      if (mounted) setState(() => _listLoading = false);
    }
  }

  Future<void> _loadDetail(int sprId) async {
    setState(() {
      _detailLoading = true;
      _detailError = null;
    });
    try {
      final rfqs = await _service.loadRfqsForSpr(sprId);
      if (!mounted || _selectedId != sprId) return;
      setState(() {
        _rfqs = rfqs;
        if (_rfqFilter != null && !rfqs.any((r) => r.id == _rfqFilter)) _rfqFilter = null;
      });
    } catch (e) {
      if (mounted) setState(() => _detailError = errorMessage(e, 'Failed to load quotes'));
    } finally {
      if (mounted) setState(() => _detailLoading = false);
    }
  }

  Future<void> _refresh() async {
    await _loadList();
  }

  SprSummary? get _selected => _sprs.where((s) => s.id == _selectedId).firstOrNull;

  Future<void> _pickSpr() async {
    final picked = await showPickerSheet(
      context,
      title: 'Select requisition',
      selected: _selectedId,
      options: [
        for (final s in _sprs)
          PickOption(
            s.id,
            s.sprNo,
            sub: [s.warehouseName ?? 'No warehouse', '${s.quoteCount} quote${s.quoteCount == 1 ? '' : 's'}', purchaseStatusLabel(s.status)].join(' · '),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    final id = picked.id as int;
    if (id == _selectedId) return;
    setState(() {
      _selectedId = id;
      _rfqs = [];
      _rfqFilter = null;
    });
    _loadDetail(id);
  }

  Future<void> _award(QuoteCardData card) async {
    final res = await runAwardFlow(context, rfq: card.rfq, quote: card.quote, settings: _settings);
    if (res != null && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    return MotionScaffold(
      title: 'Comparative study',
      subtitle: sel == null ? 'Compare supplier quotes' : '${sel.sprNo} · ${purchaseStatusLabel(sel.status)}',
      icon: Icons.compare_arrows_rounded,
      onRefresh: _refresh,
      actions: [IconButton(tooltip: 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
      headerExtra: _listLoading || _sprs.isEmpty ? null : _SprSelector(spr: sel, onTap: _pickSpr),
      slivers: _body(sel),
    );
  }

  List<Widget> _body(SprSummary? sel) {
    if (_listLoading) return [sliverSkeleton(count: 4, height: 110)];
    if (_listError != null) {
      return [sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _listError, actionLabel: 'Retry', onAction: _loadList)];
    }
    if (_sprs.isEmpty || sel == null) {
      return [
        sliverEmpty(icon: Icons.inbox_outlined, title: 'No purchase requisitions yet', message: 'Approved requisitions sent out for quotation show up here.'),
      ];
    }
    final rfqs = _rfqFilter == null ? _rfqs : _rfqs.where((r) => r.id == _rfqFilter).toList();
    final cards = buildQuoteCards(rfqs);
    final best = bestCardQuoteId(cards);
    final rows = buildComparisonRows(rfqs, cards);
    final deadlines = _rfqs.map((r) => r.deadline).whereType<DateTime>().toList()..sort();

    final out = <Widget>[
      sliverBox(_SprSummaryCard(spr: sel, earliestDeadline: deadlines.firstOrNull, quoteCount: buildQuoteCards(_rfqs).length, rfqCount: _rfqs.length)),
    ];
    if (_detailLoading && _rfqs.isEmpty) return [...out, sliverSkeleton(count: 3, height: 120)];
    if (_detailError != null) {
      return [
        ...out,
        sliverEmpty(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load quotes',
          message: _detailError,
          actionLabel: 'Retry',
          onAction: () => _loadDetail(sel.id),
        ),
      ];
    }
    if (_rfqs.isEmpty) {
      return [...out, sliverEmpty(icon: Icons.inbox_outlined, title: 'No RFQs yet', message: 'No RFQs have been raised for this requisition yet.')];
    }
    if (_rfqs.length > 1) {
      out.add(
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<int>(
              value: _rfqFilter ?? 0,
              options: [(id: 0, label: 'All RFQs', count: _rfqs.length), for (final r in _rfqs) (id: r.id, label: r.rfqNo, count: r.quotes.length)],
              onChanged: (v) => setState(() => _rfqFilter = v == 0 ? null : v),
            ),
          ),
        ),
      );
    }
    if (cards.isEmpty) {
      return [
        ...out,
        sliverEmpty(icon: Icons.request_quote_outlined, title: 'No supplier quotes yet', message: 'Add quotes from the RFQ page to compare them here.'),
      ];
    }
    out.addAll([
      sliverBox(
        SectionHeader('Supplier quotes', subtitle: '${cards.length} quote${cards.length == 1 ? '' : 's'} · cheapest first'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 206,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => FadeSlideIn(
              index: i,
              child: QuoteCompareCard(
                card: cards[i],
                isBest: cards[i].quote.id == best,
                onAward: canAwardQuote(cards[i].rfq, cards[i].quote) ? () => _award(cards[i]) : null,
              ),
            ),
          ),
        ),
      ),
      sliverBox(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader('Item price comparison', subtitle: '${rows.length} product${rows.length == 1 ? '' : 's'}'),
            Align(
              alignment: Alignment.centerLeft,
              child: MarketSegmented<CompareView>(
                value: _view,
                options: const [(id: CompareView.items, label: 'By item', count: null), (id: CompareView.matrix, label: 'Matrix', count: null)],
                onChanged: (v) => setState(() => _view = v),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      ),
    ]);
    if (_view == CompareView.matrix) {
      out.add(
        sliverBox(
          FadeSlideIn(
            child: PriceMatrix(rows: rows, cards: cards, bestQuoteId: best),
          ),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        ),
      );
    } else {
      out.add(
        sliverStagger(
          count: rows.length,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          builder: (_, i) => ItemPriceCard(row: rows[i], cards: cards),
        ),
      );
    }
    return out;
  }
}

class _SprSelector extends StatelessWidget {
  final SprSummary? spr;
  final VoidCallback onTap;
  const _SprSelector({required this.spr, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return GlowCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const AccentIcon(Icons.assignment_outlined, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Requisition', style: TextStyle(fontSize: 11.5, color: p.label)),
                Text(
                  spr?.sprNo ?? 'Select a requisition',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
                ),
              ],
            ),
          ),
          Text(
            'Change',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.brand),
          ),
          Icon(Icons.expand_more_rounded, color: p.brand),
        ],
      ),
    );
  }
}

class _SprSummaryCard extends StatelessWidget {
  final SprSummary spr;
  final DateTime? earliestDeadline;
  final int quoteCount;
  final int rfqCount;
  const _SprSummaryCard({required this.spr, this.earliestDeadline, required this.quoteCount, required this.rfqCount});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return FadeSlideIn(
      child: GlowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    spr.sprNo,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text),
                  ),
                ),
                StatusPill(purchaseStatusLabel(spr.status), tone: _sprTone(spr.status)),
              ],
            ),
            if (spr.purpose != null && spr.purpose!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                spr.purpose!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: p.label),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (spr.warehouseName != null) StatusPill(spr.warehouseName!, tone: MarketTone.info, icon: Icons.warehouse_outlined),
                StatusPill('$rfqCount RFQ${rfqCount == 1 ? '' : 's'}', tone: MarketTone.neutral),
                StatusPill('$quoteCount quote${quoteCount == 1 ? '' : 's'}', tone: quoteCount > 0 ? MarketTone.brand : MarketTone.neutral),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              [
                'Requested ${spr.requestedDate == null ? '—' : fmtDate(spr.requestedDate)}',
                if (earliestDeadline != null) 'Quotes due by ${fmtDate(earliestDeadline)}',
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: p.label),
            ),
          ],
        ),
      ),
    );
  }
}

MarketTone _sprTone(String s) => switch (s) {
  'PENDING' => MarketTone.warn,
  'APPROVED' => MarketTone.info,
  'ORDERED' => MarketTone.ok,
  'REJECTED' => MarketTone.error,
  _ => MarketTone.neutral,
};

MarketTone quoteTone(String s) => switch (s) {
  'RECEIVED' => MarketTone.info,
  'AWARDED' => MarketTone.ok,
  'REJECTED' => MarketTone.error,
  _ => MarketTone.neutral,
};

/// Small SAP button (emphasized = solid brand, otherwise outlined).
class SmallActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool emphasized;
  final bool destructive;
  const SmallActionButton({super.key, required this.label, this.icon, this.onTap, this.emphasized = false, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final fg = emphasized ? Colors.white : (destructive ? p.error : p.brand);
    return PressScale(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: emphasized ? p.brand : p.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: emphasized ? p.brand : p.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 6)],
            Text(
              label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// One supplier quote: total, validity, coverage, status and the award action.
class QuoteCompareCard extends StatelessWidget {
  final QuoteCardData card;
  final bool isBest;
  final VoidCallback? onAward;
  final double width;
  const QuoteCompareCard({super.key, required this.card, required this.isBest, this.onAward, this.width = 240});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final q = card.quote;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isBest ? p.brand : p.line, width: isBest ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  card.supplier,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
                ),
              ),
              if (isBest) const StatusPill('Best price', tone: MarketTone.ok, icon: Icons.verified_outlined),
            ],
          ),
          const SizedBox(height: 2),
          Text(card.rfq.rfqNo, style: TextStyle(fontSize: 12, color: p.label)),
          const SizedBox(height: 8),
          CountUp(
            value: card.total,
            format: (v) => money(v),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text),
          ),
          const SizedBox(height: 6),
          Text('Valid until ${q.validUntil == null ? '—' : fmtDate(q.validUntil)}', style: TextStyle(fontSize: 11.5, color: p.label)),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${card.pricedCount} item${card.pricedCount == 1 ? '' : 's'}'),
                if (q.leadTimeDays != null) TextSpan(text: ' · ${q.leadTimeDays} day lead'),
                if (!card.complete)
                  TextSpan(
                    text: ' · incomplete',
                    style: TextStyle(color: p.warn, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            style: TextStyle(fontSize: 11.5, color: p.label),
          ),
          const Spacer(),
          Row(
            children: [
              Flexible(child: StatusPill(purchaseStatusLabel(q.status), tone: quoteTone(q.status))),
              const Spacer(),
              if (q.poNo != null)
                Flexible(
                  child: Text(
                    q.poNo!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.label),
                  ),
                )
              else if (onAward != null)
                SmallActionButton(label: 'Create PO', emphasized: isBest, onTap: onAward),
            ],
          ),
        ],
      ),
    );
  }
}

/// Per-product card: required quantity, best supplier and one price row per
/// quote with the lowest highlighted.
class ItemPriceCard extends StatelessWidget {
  final ComparisonRow row;
  final List<QuoteCardData> cards;
  const ItemPriceCard({super.key, required this.row, required this.cards});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return GlowCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AccentIcon(Icons.inventory_2_outlined, size: 36, accent: Accent.teal),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text),
                    ),
                    const SizedBox(height: 2),
                    Text('${row.code} · Required ${_qty(row.quantity)}', style: TextStyle(fontSize: 12, color: p.label)),
                  ],
                ),
              ),
            ],
          ),
          if (row.bestSupplier != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.emoji_events_outlined, size: 15, color: p.ok),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Best: ${row.bestSupplier} at ${money(row.lowest ?? 0)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.ok),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Divider(height: 1, color: p.line),
          for (var i = 0; i < cards.length; i++) _priceRow(context, i),
        ],
      ),
    );
  }

  Widget _priceRow(BuildContext context, int i) {
    final p = MarketPalette.of(context);
    final price = row.prices[i];
    final lowest = price != null && price == row.lowest && cards.length > 1;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: lowest ? p.okBg : Colors.transparent, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cards[i].supplier,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: lowest ? FontWeight.w700 : FontWeight.w500, color: lowest ? p.ok : p.text),
                ),
                Text(cards[i].rfq.rfqNo, style: TextStyle(fontSize: 11, color: p.label)),
              ],
            ),
          ),
          if (price == null)
            Text('No price', style: TextStyle(fontSize: 12.5, color: p.label))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (lowest) ...[Icon(Icons.check_circle_rounded, size: 14, color: p.ok), const SizedBox(width: 4)],
                    Text(
                      money(price),
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: lowest ? p.ok : p.text),
                    ),
                  ],
                ),
                Text('Line ${money(price * row.quantity)}', style: TextStyle(fontSize: 11, color: p.label)),
              ],
            ),
        ],
      ),
    );
  }
}

/// Side-by-side matrix: fixed product column, horizontally scrolling
/// supplier columns, totals row at the bottom.
class PriceMatrix extends StatelessWidget {
  final List<ComparisonRow> rows;
  final List<QuoteCardData> cards;
  final int? bestQuoteId;
  const PriceMatrix({super.key, required this.rows, required this.cards, this.bestQuoteId});

  static const _headH = 54.0;
  static const _rowH = 54.0;
  static const _leftW = 148.0;
  static const _colW = 128.0;

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    Widget cell(Widget child, {double h = _rowH, Color? color, bool top = true, AlignmentGeometry align = Alignment.centerRight, double w = _colW}) =>
        Container(
          width: w,
          height: h,
          alignment: align,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: color,
            border: top ? Border(top: BorderSide(color: p.line)) : null,
          ),
          child: child,
        );

    final left = Column(
      children: [
        cell(
          Text(
            'Product',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.label),
          ),
          h: _headH,
          color: p.surface,
          top: false,
          align: Alignment.centerLeft,
          w: _leftW,
        ),
        for (final r in rows)
          cell(
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.text),
                ),
                Text(
                  '${r.code} · Qty ${_qty(r.quantity)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: p.label),
                ),
              ],
            ),
            align: Alignment.centerLeft,
            w: _leftW,
            color: p.card,
          ),
        cell(
          Text(
            'Total',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text),
          ),
          color: p.surface,
          align: Alignment.centerLeft,
          w: _leftW,
        ),
      ],
    );

    final right = Row(
      children: [
        for (var c = 0; c < cards.length; c++)
          Column(
            children: [
              cell(
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      cards[c].supplier,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cards[c].quote.id == bestQuoteId ? p.brand : p.text),
                    ),
                    Text(cards[c].rfq.rfqNo, style: TextStyle(fontSize: 11, color: p.label)),
                  ],
                ),
                h: _headH,
                color: p.surface,
                top: false,
              ),
              for (final r in rows)
                () {
                  final price = r.prices[c];
                  final lowest = price != null && price == r.lowest && cards.length > 1;
                  return cell(
                    Text(
                      price == null ? '—' : money(price),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: lowest ? FontWeight.w700 : FontWeight.w500,
                        color: lowest ? p.ok : (price == null ? p.label : p.text),
                      ),
                    ),
                    color: lowest ? p.okBg : null,
                  );
                }(),
              cell(
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      money(cards[c].total),
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text),
                    ),
                    if (!cards[c].complete) Text('Incomplete', style: TextStyle(fontSize: 10.5, color: p.warn)),
                  ],
                ),
                color: p.surface,
              ),
            ],
          ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: p.line)),
            ),
            child: left,
          ),
          Expanded(
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(), child: right),
          ),
        ],
      ),
    );
  }
}
