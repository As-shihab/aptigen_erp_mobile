import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../../../shared/ui/motion_wizard.dart';
import '../../data/comparative_service.dart';
import '../../data/rfq_service.dart';
import '../comparative/comparative_study_page.dart';

// Requests for quotation — desktop purchase/rfq/PurchaseRfqs.tsx +
// RfqQuotesDialog.tsx. List grouped by requisition (status chips, search),
// a detail page with lines, supplier quotes, a price comparison and the
// award (create PO) action, and step wizards for the RFQ and each quote.

String _qty(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

MarketTone _rfqTone(String s) => switch (s) {
      'DRAFT' => MarketTone.neutral,
      'SENT' => MarketTone.info,
      'CLOSED' => MarketTone.warn,
      'AWARDED' => MarketTone.ok,
      'CANCELLED' => MarketTone.error,
      _ => MarketTone.neutral,
    };

String _deadlineText(DateTime? d) {
  if (d == null) return 'No deadline';
  final today = DateUtils.dateOnly(DateTime.now());
  final days = DateUtils.dateOnly(d.toLocal()).difference(today).inDays;
  if (days < 0) return 'Due ${fmtDate(d)} · overdue';
  if (days == 0) return 'Due today';
  return 'Due ${fmtDate(d)} · in $days day${days == 1 ? '' : 's'}';
}

Future<bool> _deleteRfq(BuildContext context, Rfq r) async {
  final ok = await confirmMarket(
    context,
    title: 'Delete RFQ?',
    message: 'Delete RFQ "${r.rfqNo}"? Its lines and ${r.quotes.length} supplier quote(s) will be removed too.',
  );
  if (!ok) return false;
  try {
    await RfqService().deleteRfq(r.id);
    if (context.mounted) marketToast(context, 'Request for quotation deleted');
    return true;
  } catch (e) {
    if (context.mounted) marketToast(context, errorMessage(e, 'Could not delete'), error: true);
    return false;
  }
}

// ── List ────────────────────────────────────────────────────────────────

class _Group {
  final String key;
  final int? sprId;
  final String? sprNo;
  final String? sprStatus;
  final String? warehouse;
  final List<Rfq> rfqs = [];
  _Group(this.key, this.sprId, this.sprNo, this.sprStatus, this.warehouse);

  List<({Rfq r, RfqQuote q, QuoteTotal t})> get allQuotes => [
        for (final r in rfqs)
          for (final q in r.quotes) (r: r, q: q, t: quoteTotalOf(r.items, q)),
      ];
}

class RfqsPage extends StatefulWidget {
  const RfqsPage({super.key});

  @override
  State<RfqsPage> createState() => _RfqsPageState();
}

class _RfqsPageState extends State<RfqsPage> {
  final _service = RfqService();
  List<Rfq> _rows = [];
  bool _loading = true;
  String? _error;
  String _q = '';
  String _status = 'ALL';
  final Set<String> _collapsed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    try {
      final rows = await _service.loadList();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Failed to load requests for quotation'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _matches(Rfq r) {
    if (_status != 'ALL' && r.status != _status) return false;
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [r.rfqNo, r.title, r.sprNo, r.warehouseName, r.clientName, ...r.quotes.map((x) => x.supplierName)].any((v) => (v ?? '').toLowerCase().contains(q));
  }

  /// One group per requisition, RFQs without one last.
  List<_Group> get _groups {
    final map = <String, _Group>{};
    for (final r in _rows.where(_matches)) {
      final key = r.sprId != null ? 'spr-${r.sprId}' : 'none';
      map.putIfAbsent(key, () => _Group(key, r.sprId, r.sprNo, r.sprStatus, r.warehouseName)).rfqs.add(r);
    }
    final list = map.values.toList();
    return [...list.where((g) => g.key != 'none'), ...list.where((g) => g.key == 'none')];
  }

  Future<void> _openCreate() async {
    final saved = await pushMotion<bool>(context, const RfqFormPage());
    if (saved == true) _load();
  }

  Future<void> _openEdit(Rfq r) async {
    final saved = await pushMotion<bool>(context, RfqFormPage(existing: r));
    if (saved == true) _load();
  }

  void _openDetail(Rfq r) => pushMotion(context, RfqDetailPage(rfqId: r.id, initial: r)).then((_) => _load());

  Future<void> _more(Rfq r) async {
    final key = await showActionSheet(context, title: r.rfqNo, actions: [
      (key: 'open', label: 'Open', icon: Icons.open_in_new_rounded, destructive: false),
      (key: 'quotes', label: r.quotes.isEmpty ? 'Add quote' : 'Quotes', icon: Icons.request_quote_outlined, destructive: false),
      (key: 'edit', label: 'Edit', icon: Icons.edit_outlined, destructive: false),
      if (r.sprId != null && r.quotes.isNotEmpty) (key: 'compare', label: 'Comparative study', icon: Icons.compare_arrows_rounded, destructive: false),
      (key: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (key == null || !mounted) return;
    switch (key) {
      case 'open':
      case 'quotes':
        _openDetail(r);
      case 'edit':
        _openEdit(r);
      case 'compare':
        pushMotion(context, ComparativeStudyPage(sprId: r.sprId)).then((_) => _load());
      case 'delete':
        if (await _deleteRfq(context, r)) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    final quoteCount = _rows.fold<int>(0, (n, r) => n + r.quotes.length);
    final awaiting = _rows.where((r) => r.quotes.isEmpty && r.status != 'CANCELLED').length;
    final awarded = _rows.where((r) => r.isAwarded).length;
    final entries = <Object>[];
    for (final g in groups) {
      entries.add(g);
      if (!_collapsed.contains(g.key)) entries.addAll(g.rfqs);
    }

    return MotionScaffold(
      title: 'Requests for quotation',
      subtitle: '${_rows.length} RFQ${_rows.length == 1 ? '' : 's'} · $quoteCount quote${quoteCount == 1 ? '' : 's'}',
      icon: Icons.request_quote_outlined,
      onRefresh: _load,
      onFab: _openCreate,
      fabLabel: 'New RFQ',
      actions: [
        IconButton(
          tooltip: 'Comparative study',
          icon: const Icon(Icons.compare_arrows_rounded),
          onPressed: () => pushMotion(context, const ComparativeStudyPage()).then((_) => _load()),
        ),
      ],
      headerExtra: HeaderSearch(hint: 'Search RFQ, requisition, supplier', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        if (!_loading && _error == null && _rows.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.only(top: 14),
            sliver: SliverToBoxAdapter(
              child: KpiStrip(height: 108, children: [
                GradientKpi(icon: Icons.request_quote_outlined, label: 'RFQs', value: _rows.length),
                GradientKpi(icon: Icons.hourglass_empty_rounded, label: 'Awaiting quotes', value: awaiting, accent: Accent.amber),
                GradientKpi(icon: Icons.inbox_outlined, label: 'Quotes received', value: quoteCount, accent: Accent.teal),
                GradientKpi(icon: Icons.verified_outlined, label: 'Awarded', value: awarded, accent: Accent.emerald),
              ]),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _status,
              options: [
                (id: 'ALL', label: 'All', count: _rows.length),
                for (final s in rfqStatuses) (id: s, label: rfqStatusLabel[s]!, count: _rows.where((r) => r.status == s).length),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton()
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (groups.isEmpty)
          sliverEmpty(
            icon: Icons.find_in_page_outlined,
            title: _rows.isEmpty ? 'No requests for quotation yet' : 'Nothing matches this search',
            message: 'Create one from an approved purchase requisition.',
            actionLabel: _rows.isEmpty ? 'New RFQ' : null,
            onAction: _rows.isEmpty ? _openCreate : null,
          )
        else
          sliverStagger(
            count: entries.length,
            gap: 8,
            builder: (_, i) {
              final e = entries[i];
              if (e is _Group) {
                return _GroupHeader(
                  group: e,
                  collapsed: _collapsed.contains(e.key),
                  onToggle: () => setState(() => _collapsed.contains(e.key) ? _collapsed.remove(e.key) : _collapsed.add(e.key)),
                  onCompare: e.sprId == null ? null : () => pushMotion(context, ComparativeStudyPage(sprId: e.sprId)).then((_) => _load()),
                );
              }
              final r = e as Rfq;
              final best = bestQuoteIdOf(r.items, r.quotes);
              final awardedQ = r.quotes.where((q) => q.status == 'AWARDED').firstOrNull;
              final bestQ = r.quotes.where((q) => q.id == best).firstOrNull;
              final priceLine = awardedQ != null
                  ? 'Awarded ${awardedQ.supplier} · ${money(quoteTotalOf(r.items, awardedQ).total)}'
                  : bestQ != null
                      ? 'Lowest ${bestQ.supplier} · ${money(quoteTotalOf(r.items, bestQ).total)}'
                      : null;
              return Padding(
                padding: const EdgeInsets.only(left: 10),
                child: MotionTile(
                  key: ValueKey('rfq-${r.id}'),
                  leading: AccentIcon(Icons.description_outlined, accent: r.isAwarded ? Accent.emerald : Accent.ocean, size: 40),
                  title: r.title == null ? r.rfqNo : '${r.rfqNo} · ${r.title}',
                  subtitle: [
                    '${r.items.length} product${r.items.length == 1 ? '' : 's'}',
                    r.quotes.isEmpty ? 'No quotes yet' : '${r.quotes.length} quote${r.quotes.length == 1 ? '' : 's'}',
                    ?priceLine,
                  ].join(' · '),
                  meta: [_deadlineText(r.deadline), if (r.clientName != null) 'For ${r.clientName}'].join(' · '),
                  trailing: StatusPill(r.statusText, tone: _rfqTone(r.status)),
                  onTap: () => _openDetail(r),
                  onLongPress: () => _more(r),
                  onDelete: () async {
                    final ok = await _deleteRfq(context, r);
                    if (ok) _load();
                    return ok;
                  },
                ),
              );
            },
          ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final _Group group;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onCompare;
  const _GroupHeader({required this.group, required this.collapsed, required this.onToggle, this.onCompare});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final all = group.allQuotes;
    final competing = all.where((x) => x.t.complete && x.q.status != 'REJECTED').map((x) => x.t.total).toList();
    final lowest = competing.isEmpty ? null : competing.reduce((a, b) => a < b ? a : b);
    final awarded = all.where((x) => x.q.status == 'AWARDED').firstOrNull;
    final ({String label, MarketTone tone}) pill = group.sprStatus == 'ORDERED' || awarded != null
        ? (label: 'Ordered', tone: MarketTone.ok)
        : all.isNotEmpty
            ? (label: 'Comparing', tone: MarketTone.info)
            : (label: 'Awaiting quotes', tone: MarketTone.warn);
    final price = awarded != null ? 'awarded ${money(awarded.t.total)}' : (lowest != null ? 'lowest ${money(lowest)}' : null);
    return PressScale(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
        child: Row(children: [
          AnimatedRotation(
            turns: collapsed ? -0.25 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.expand_more_rounded, color: p.label, size: 20),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: group.sprNo ?? (group.sprId == null ? 'Not linked to a requisition' : 'SPR #${group.sprId}')),
                  if (group.warehouse != null) TextSpan(text: ' · ${group.warehouse}', style: TextStyle(fontWeight: FontWeight.w400, color: p.label)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text),
              ),
              Text(
                ['${all.length} quote${all.length == 1 ? '' : 's'}', ?price].join(' · '),
                style: TextStyle(fontSize: 12, color: p.label),
              ),
            ]),
          ),
          StatusPill(pill.label, tone: pill.tone),
          if (onCompare != null && all.isNotEmpty)
            IconButton(tooltip: 'Comparative study', visualDensity: VisualDensity.compact, onPressed: onCompare, icon: Icon(Icons.compare_arrows_rounded, color: p.brand, size: 20))
          else
            const SizedBox(width: 8),
        ]),
      ),
    );
  }
}

// ── Detail ──────────────────────────────────────────────────────────────

class RfqDetailPage extends StatefulWidget {
  final int rfqId;
  final Rfq? initial;
  const RfqDetailPage({super.key, required this.rfqId, this.initial});

  @override
  State<RfqDetailPage> createState() => _RfqDetailPageState();
}

class _RfqDetailPageState extends State<RfqDetailPage> {
  final _service = RfqService();
  Rfq? _rfq;
  List<Map<String, dynamic>> _suppliers = [];
  PurchaseApprovalSettings _settings = const PurchaseApprovalSettings();
  bool _loading = true;
  String? _error;
  CompareView _view = CompareView.items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rfq == null;
      _error = null;
    });
    try {
      final b = await _service.loadDetail(widget.rfqId);
      if (!mounted) return;
      setState(() {
        _rfq = b.rfq;
        _suppliers = b.suppliers;
        _settings = b.settings;
        if (b.rfq == null) _error = 'This RFQ no longer exists';
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Failed to load quotes'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openQuote([RfqQuote? q]) async {
    final rfq = _rfq;
    if (rfq == null) return;
    final saved = await pushMotion<bool>(context, QuoteFormPage(rfq: rfq, suppliers: _suppliers, existing: q));
    if (saved == true) _load();
  }

  Future<void> _deleteQuote(RfqQuote q) async {
    final ok = await confirmMarket(context, title: 'Delete quote?', message: 'Delete the quote from "${q.supplierName ?? 'this supplier'}"?');
    if (!ok) return;
    try {
      await _service.deleteQuote(q.id);
      if (mounted) marketToast(context, 'Quote deleted');
      _load();
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete quote'), error: true);
    }
  }

  Future<void> _award(RfqQuote q) async {
    final rfq = _rfq;
    if (rfq == null) return;
    final res = await runAwardFlow(context, rfq: rfq, quote: q, settings: _settings);
    if (res != null && mounted) _load();
  }

  Future<void> _edit() async {
    final rfq = _rfq;
    if (rfq == null) return;
    final saved = await pushMotion<bool>(context, RfqFormPage(existing: rfq));
    if (saved == true) _load();
  }

  Future<void> _more() async {
    final rfq = _rfq;
    if (rfq == null) return;
    final key = await showActionSheet(context, title: rfq.rfqNo, actions: [
      (key: 'edit', label: 'Edit RFQ', icon: Icons.edit_outlined, destructive: false),
      if (rfq.sprId != null && rfq.quotes.isNotEmpty) (key: 'compare', label: 'Comparative study', icon: Icons.compare_arrows_rounded, destructive: false),
      (key: 'delete', label: 'Delete RFQ', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (key == null || !mounted) return;
    if (key == 'edit') return _edit();
    if (key == 'compare') {
      pushMotion(context, ComparativeStudyPage(sprId: rfq.sprId)).then((_) => _load());
      return;
    }
    if (key == 'delete' && await _deleteRfq(context, rfq) && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final rfq = _rfq;
    final canAddQuote = rfq != null && !rfq.isAwarded && rfq.items.isNotEmpty;
    return MotionScaffold(
      title: rfq?.rfqNo ?? widget.initial?.rfqNo ?? 'Request for quotation',
      subtitle: rfq == null ? null : '${rfq.statusText} · ${rfq.quotes.length} quote${rfq.quotes.length == 1 ? '' : 's'} · ${rfq.items.length} product${rfq.items.length == 1 ? '' : 's'}',
      onRefresh: _load,
      onFab: canAddQuote ? () => _openQuote() : null,
      fabLabel: 'Add quote',
      actions: rfq == null
          ? null
          : [
              IconButton(tooltip: 'Edit', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
              IconButton(tooltip: 'More', onPressed: _more, icon: const Icon(Icons.more_vert_rounded)),
            ],
      slivers: _body(rfq),
    );
  }

  List<Widget> _body(Rfq? rfq) {
    if (_loading) return [sliverSkeleton(count: 5, height: 96)];
    if (_error != null || rfq == null) {
      return [sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)];
    }
    final p = MarketPalette.of(context);
    final best = bestQuoteIdOf(rfq.items, rfq.quotes);
    final bestQ = rfq.quotes.where((q) => q.id == best).firstOrNull;
    final cards = buildQuoteCards([rfq]);
    final rows = buildComparisonRows([rfq], cards);

    return [
      sliverBox(FadeSlideIn(child: _HeaderCard(rfq: rfq))),
      SliverPadding(
        padding: const EdgeInsets.only(top: 14),
        sliver: SliverToBoxAdapter(
          child: KpiStrip(height: 108, children: [
            GradientKpi(icon: Icons.inventory_2_outlined, label: 'Products', value: rfq.items.length, accent: Accent.teal),
            GradientKpi(icon: Icons.request_quote_outlined, label: 'Quotes', value: rfq.quotes.length),
            GradientKpi(
              icon: Icons.savings_outlined,
              label: bestQ == null ? 'Best total' : 'Best · ${bestQ.supplier}',
              value: bestQ == null ? 0 : quoteTotalOf(rfq.items, bestQ).total,
              format: (v) => money(v),
              accent: Accent.emerald,
            ),
          ]),
        ),
      ),
      if (rfq.sprId != null && rfq.quotes.isNotEmpty)
        sliverBox(
          GlowCard(
            onTap: () => pushMotion(context, ComparativeStudyPage(sprId: rfq.sprId)).then((_) => _load()),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              const AccentIcon(Icons.compare_arrows_rounded, size: 36, accent: Accent.violet),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Compare quotes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                  Text('Comparative study for ${rfq.sprNo ?? 'this requisition'}', style: TextStyle(fontSize: 12, color: p.label)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: p.label),
            ]),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        ),
      // Requested products
      sliverBox(SectionHeader('Requested products', subtitle: '${rfq.items.length} line${rfq.items.length == 1 ? '' : 's'}'), padding: const EdgeInsets.fromLTRB(16, 4, 16, 0)),
      if (rfq.items.isEmpty)
        sliverBox(_Note('This RFQ has no product lines yet. Edit it to add the products you want quoted.'), padding: const EdgeInsets.fromLTRB(16, 0, 16, 0))
      else
        sliverStagger(
          count: rfq.items.length,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          gap: 8,
          builder: (_, i) {
            final item = rfq.items[i];
            final low = lowestPriceFor(item.id, rfq.quotes);
            return MotionTile(
              leading: const AccentIcon(Icons.inventory_2_outlined, accent: Accent.teal, size: 38),
              title: item.productName,
              subtitle: '${item.code} · Qty ${_qty(item.quantity)}',
              meta: item.remarks,
              trailing: low == null ? null : StatusPill('Low ${money(low)}', tone: MarketTone.ok),
            );
          },
        ),
      // Supplier quotes
      sliverBox(
        SectionHeader('Supplier quotes', subtitle: rfq.isAwarded ? 'Awarded · quotes are locked' : '${rfq.quotes.length} received'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      ),
      if (rfq.quotes.isEmpty)
        sliverBox(
          _Note(rfq.items.isEmpty ? 'Add product lines first, then record each supplier\'s prices here.' : 'No quotes yet. Add each supplier\'s prices as they come in, then compare them here.'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        )
      else
        sliverStagger(
          count: rfq.quotes.length,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          builder: (_, i) {
            final q = rfq.quotes[i];
            return _QuoteCard(
              rfq: rfq,
              quote: q,
              isBest: q.id == best,
              onEdit: rfq.isAwarded ? null : () => _openQuote(q),
              onDelete: rfq.isAwarded ? null : () => _deleteQuote(q),
              onAward: canAwardQuote(rfq, q) ? () => _award(q) : null,
            );
          },
        ),
      // Price comparison
      if (rfq.items.isNotEmpty && rfq.quotes.isNotEmpty) ...[
        sliverBox(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader('Price comparison', subtitle: rfq.quotes.length > 1 ? 'Lowest price per product highlighted' : null),
            Align(
              alignment: Alignment.centerLeft,
              child: MarketSegmented<CompareView>(
                value: _view,
                options: const [(id: CompareView.items, label: 'By item', count: null), (id: CompareView.matrix, label: 'Matrix', count: null)],
                onChanged: (v) => setState(() => _view = v),
              ),
            ),
            const SizedBox(height: 12),
          ]),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        ),
        if (_view == CompareView.matrix)
          sliverBox(FadeSlideIn(child: PriceMatrix(rows: rows, cards: cards, bestQuoteId: best)), padding: const EdgeInsets.fromLTRB(16, 0, 16, 0))
        else
          sliverStagger(count: rows.length, padding: const EdgeInsets.fromLTRB(16, 0, 16, 0), builder: (_, i) => ItemPriceCard(row: rows[i], cards: cards)),
      ],
    ];
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, size: 18, color: p.label),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: p.label, height: 1.35))),
      ]),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Rfq rfq;
  const _HeaderCard({required this.rfq});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return GlowCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const AccentIcon(Icons.description_outlined, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rfq.rfqNo, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
              if (rfq.title != null) Text(rfq.title!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.label)),
            ]),
          ),
          StatusPill(rfq.statusText, tone: _rfqTone(rfq.status)),
        ]),
        const SizedBox(height: 10),
        Divider(height: 1, color: p.line),
        const SizedBox(height: 6),
        InfoRow('Requisition', [rfq.sprNo ?? '—', if (rfq.sprStatus != null) purchaseStatusLabel(rfq.sprStatus)].join(' · ')),
        if (rfq.warehouseName != null) InfoRow('Warehouse', rfq.warehouseName!),
        InfoRow('Client', rfq.clientName ?? '—'),
        InfoRow('RFQ date', rfq.rfqDate == null ? '—' : fmtDate(rfq.rfqDate)),
        InfoRow('Quote deadline', _deadlineText(rfq.deadline)),
        if (rfq.remarks != null) ...[
          const SizedBox(height: 6),
          Text('Remarks', style: TextStyle(fontSize: 12.5, color: p.label)),
          const SizedBox(height: 2),
          Text(rfq.remarks!, style: TextStyle(fontSize: 13, color: p.text, height: 1.35)),
        ],
      ]),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  final Rfq rfq;
  final RfqQuote quote;
  final bool isBest;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onAward;
  const _QuoteCard({required this.rfq, required this.quote, required this.isBest, this.onEdit, this.onDelete, this.onAward});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final t = quoteTotalOf(rfq.items, quote);
    final status = quote.status == 'RECEIVED' && isBest ? 'Best total' : quote.statusText;
    final tone = quote.status == 'RECEIVED' && isBest ? MarketTone.info : quoteTone(quote.status);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isBest && quote.status != 'REJECTED' ? p.brand : p.line, width: isBest && quote.status != 'REJECTED' ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          InitialsAvatar(quote.supplier, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(quote.supplier, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
              Text(
                ['Quoted ${quote.quoteDate == null ? '—' : fmtDate(quote.quoteDate)}', '${t.priced}/${rfq.items.length} priced'].join(' · '),
                style: TextStyle(fontSize: 11.5, color: p.label),
              ),
            ]),
          ),
          StatusPill(status, tone: tone),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: CountUp(value: t.total, format: (v) => money(v), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: p.text)),
          ),
          if (!t.complete) StatusPill('Incomplete', tone: MarketTone.warn),
        ]),
        const SizedBox(height: 4),
        Text(
          '${quote.leadTimeDays != null ? '${quote.leadTimeDays} day(s) lead time' : 'No lead time'} · valid until ${quote.validUntil == null ? '—' : fmtDate(quote.validUntil)}',
          style: TextStyle(fontSize: 12, color: p.label),
        ),
        if (quote.remarks != null) ...[
          const SizedBox(height: 4),
          Text(quote.remarks!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.text)),
        ],
        if (onEdit != null || onDelete != null || onAward != null) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (onAward != null) SmallActionButton(label: 'Create PO', icon: Icons.shopping_cart_checkout_rounded, emphasized: true, onTap: onAward),
            if (onEdit != null) SmallActionButton(label: 'Edit', icon: Icons.edit_outlined, onTap: onEdit),
            if (onDelete != null) SmallActionButton(label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true, onTap: onDelete),
          ]),
        ],
      ]),
    );
  }
}

// ── RFQ create / edit wizard ────────────────────────────────────────────

class _LineCtl {
  final RfqLineDraft d;
  final TextEditingController qty;
  final TextEditingController remarks;
  _LineCtl(this.d)
      : qty = TextEditingController(text: d.quantity),
        remarks = TextEditingController(text: d.remarks);
  void dispose() {
    qty.dispose();
    remarks.dispose();
  }
}

class RfqFormPage extends StatefulWidget {
  final Rfq? existing;

  /// Opens a new RFQ already linked to this approved SPR with its lines
  /// (desktop `?spr=<id>` from Purchase requisitions → "Create RFQ").
  final int? presetSprId;
  const RfqFormPage({super.key, this.existing, this.presetSprId});

  @override
  State<RfqFormPage> createState() => _RfqFormPageState();
}

class _RfqFormPageState extends State<RfqFormPage> {
  final _service = RfqService();
  final _rfqNo = TextEditingController();
  final _title = TextEditingController();
  final _remarks = TextEditingController();
  String _status = 'DRAFT';
  int? _sprId;
  String? _sprName;
  int? _clientId;
  DateTime? _deadline;
  final List<_LineCtl> _lines = [];
  List<int> _originalLineIds = [];
  RfqLookups _lookups = const RfqLookups();
  bool _loading = true;
  String? _error;
  bool _generating = false;
  bool _loadingSprLines = false;
  bool _dirty = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _rfqNo.text = e.rfqNo;
      _title.text = e.title ?? '';
      _remarks.text = e.remarks ?? '';
      _status = e.status;
      _sprId = e.sprId;
      _sprName = e.sprNo;
      _clientId = e.clientId;
      _deadline = e.deadline;
    }
    _init();
  }

  @override
  void dispose() {
    _rfqNo.dispose();
    _title.dispose();
    _remarks.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _setLines(List<RfqLineDraft> drafts) {
    for (final l in _lines) {
      l.dispose();
    }
    _lines
      ..clear()
      ..addAll((drafts.isEmpty ? [RfqLineDraft()] : drafts).map(_LineCtl.new));
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lookups = await _service.loadLookups();
      List<RfqLineDraft> lines = [];
      if (_isEdit) {
        lines = await _service.loadRfqLines(widget.existing!.id);
        _originalLineIds = lines.map((l) => l.id).whereType<int>().toList();
      }
      if (!mounted) return;
      setState(() {
        _lookups = lookups;
        _setLines(lines);
      });
      if (!_isEdit) {
        final preset = widget.presetSprId;
        if (preset != null) {
          final match = lookups.requisitions.where((r) => r['id'] == preset).firstOrNull;
          if (match == null) {
            marketToast(context, 'That requisition is not approved for quotation', error: true);
          } else {
            final name = str(match['spr_no']);
            setState(() {
              _sprId = preset;
              _sprName = name;
              _title.text = 'Quotation for $name';
            });
            _pullSprLines(preset, force: true);
          }
        }
        _generateNo();
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load form data'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generateNo() async {
    setState(() => _generating = true);
    final code = await _service.generateCode('RFQ', 'purchase_rfqs');
    if (!mounted) return;
    setState(() {
      _generating = false;
      if (code != null) _rfqNo.text = code;
    });
  }

  Future<void> _pullSprLines(int sprId, {bool force = false}) async {
    if (!force && _lines.any((l) => l.d.productId != null)) return;
    setState(() => _loadingSprLines = true);
    try {
      final lines = await _service.loadRequisitionLines(sprId);
      if (mounted && lines.isNotEmpty) setState(() => _setLines(lines));
    } catch (_) {
      // best effort — lines can still be added by hand
    } finally {
      if (mounted) setState(() => _loadingSprLines = false);
    }
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  List<RfqLineDraft> get _validLines {
    for (final l in _lines) {
      l.d.quantity = l.qty.text;
      l.d.remarks = l.remarks.text;
    }
    return _lines.map((l) => l.d).where((d) => d.isValid).toList();
  }

  Future<bool> _save() async {
    final lines = _validLines;
    try {
      await _service.saveRfq(
        editingId: widget.existing?.id,
        header: {
          'rfq_no': _rfqNo.text.trim(),
          'title': _title.text.trim().isEmpty ? null : _title.text.trim(),
          'status': _status,
          'purchase_requisition_id': _sprId,
          'client_id': _clientId,
          'deadline_date': isoDateOnly(_deadline),
          'remarks': _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
        },
        lines: lines,
        originalLineIds: _originalLineIds,
      );
      if (!mounted) return true;
      marketToast(context, _isEdit ? 'Request for quotation updated' : 'Request for quotation created');
      Navigator.of(context).pop(true);
      return true;
    } catch (e) {
      if (!mounted) return false;
      final msg = e is ApiException && e.message.contains('rfq_no') && e.message.contains('Unique constraint')
          ? 'That RFQ no is already in use for this workplace, use a different number'
          : errorMessage(e, 'Failed to save request for quotation');
      marketToast(context, msg, error: true);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    if (_loading || _error != null) {
      return Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          backgroundColor: p.card,
          foregroundColor: p.text,
          surfaceTintColor: Colors.transparent,
          shape: Border(bottom: BorderSide(color: p.line)),
          title: Text(_isEdit ? 'Edit request for quotation' : 'New request for quotation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
        ),
        body: _error != null
            ? MarketEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _init)
            : ListView(padding: const EdgeInsets.all(16), children: [
                for (var i = 0; i < 4; i++) ...[const SkeletonBox(height: 64, radius: 12), const SizedBox(height: 12)],
              ]),
      );
    }
    return MotionWizardPage(
      title: _isEdit ? 'Edit request for quotation' : 'New request for quotation',
      submitLabel: _isEdit ? 'Save changes' : 'Create RFQ',
      isDirty: () => _dirty,
      onSubmit: _save,
      steps: [
        WizardStep(
          title: 'Basics',
          icon: Icons.description_outlined,
          caption: 'Number, title, status and client',
          validate: () => _rfqNo.text.trim().isEmpty ? 'RFQ no is required' : null,
          builder: (_) => _basics(),
        ),
        WizardStep(
          title: 'Items',
          icon: Icons.inventory_2_outlined,
          caption: 'Requisition and the products to be quoted',
          validate: () {
            if (_sprId == null) return 'Pick the approved purchase requisition this RFQ is for';
            if (_validLines.isEmpty) return 'Add at least one product line with a quantity';
            return null;
          },
          builder: (_) => _items(),
        ),
        WizardStep(title: 'Terms', icon: Icons.event_note_outlined, caption: 'Quote deadline and remarks for suppliers', builder: (_) => _terms()),
        WizardStep(title: 'Review', icon: Icons.fact_check_outlined, caption: 'Check everything before saving', builder: (_) => _review()),
      ],
    );
  }

  Widget _basics() {
    final p = MarketPalette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FormLabel(
        label: 'RFQ no',
        required: true,
        child: TextField(
          controller: _rfqNo,
          enabled: !_generating,
          onChanged: (_) => _touch(),
          decoration: motionInput(
            context,
            hint: _generating ? 'Generating…' : 'e.g. RFQ-2026-0001',
            icon: Icons.tag_rounded,
            suffix: _generating
                ? Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.brand)))
                : (_isEdit ? null : IconButton(tooltip: 'Generate', icon: Icon(Icons.autorenew_rounded, color: p.label, size: 20), onPressed: _generateNo)),
          ),
        ),
      ),
      FormLabel(
        label: 'Title',
        child: TextField(controller: _title, onChanged: (_) => _touch(), decoration: motionInput(context, hint: 'Optional', icon: Icons.title_rounded)),
      ),
      FormLabel(
        label: 'Status',
        required: true,
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in rfqStatuses)
            ChoiceChip(
              label: Text(rfqStatusLabel[s]!),
              selected: _status == s,
              onSelected: (_) => setState(() {
                _status = s;
                _dirty = true;
              }),
            ),
        ]),
      ),
      FormLabel(
        label: 'Client',
        help: 'Optional — who this purchase is for',
        child: PickerField(
          value: _clientId,
          hint: 'Select client',
          icon: Icons.person_outline_rounded,
          options: [for (final c in _lookups.clients) PickOption(c['id'], str(c['name']))],
          onChanged: (v) => setState(() {
            _clientId = v as int?;
            _dirty = true;
          }),
        ),
      ),
    ]);
  }

  Widget _items() {
    final p = MarketPalette.of(context);
    final sprOptions = [
      for (final r in _lookups.requisitions) PickOption(r['id'], str(r['spr_no'])),
      // Keep an already linked (e.g. now ordered) SPR selectable when editing.
      if (_sprId != null && !_lookups.requisitions.any((r) => r['id'] == _sprId)) PickOption(_sprId!, _sprName ?? 'SPR #$_sprId'),
    ];
    final productOptions = [for (final pr in _lookups.products) PickOption(pr['id'], str(pr['name']), sub: pr['sku'] == null ? null : str(pr['sku']))];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FormLabel(
        label: 'Purchase requisition',
        required: true,
        help: 'Only approved requisitions can go out for quotation',
        child: PickerField(
          value: _sprId,
          hint: 'Approved requisition',
          icon: Icons.assignment_outlined,
          options: sprOptions,
          onChanged: (v) {
            final id = v as int?;
            setState(() {
              _sprId = id;
              _sprName = id == null ? null : sprOptions.where((o) => o.id == id).firstOrNull?.label;
              _dirty = true;
            });
            if (id != null) _pullSprLines(id);
          },
        ),
      ),
      if (_sprId != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _loadingSprLines ? null : () => _pullSprLines(_sprId!, force: true),
            icon: _loadingSprLines
                ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: p.brand))
                : const Icon(Icons.download_rounded, size: 18),
            label: const Text('Copy lines from requisition'),
          ),
        ),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(child: Text('Requested products', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text))),
        TextButton.icon(
          onPressed: () => setState(() {
            _lines.add(_LineCtl(RfqLineDraft()));
            _dirty = true;
          }),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add line'),
        ),
      ]),
      const SizedBox(height: 6),
      for (var i = 0; i < _lines.length; i++)
        FadeSlideIn(
          key: ObjectKey(_lines[i]),
          index: i,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text('Line ${i + 1}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.label)),
                const Spacer(),
                IconButton(
                  tooltip: 'Remove line',
                  visualDensity: VisualDensity.compact,
                  onPressed: _lines.length == 1
                      ? null
                      : () => setState(() {
                            _lines.removeAt(i).dispose();
                            _dirty = true;
                          }),
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: _lines.length == 1 ? p.line : p.error),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  PickerField(
                    value: _lines[i].d.productId,
                    hint: 'Select product',
                    icon: Icons.inventory_2_outlined,
                    allowClear: false,
                    options: productOptions,
                    onChanged: (v) => setState(() {
                      _lines[i].d.productId = v as int?;
                      _lines[i].d.productName = productOptions.where((o) => o.id == v).firstOrNull?.label ?? '';
                      _dirty = true;
                    }),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    SizedBox(
                      width: 104,
                      child: TextField(
                        controller: _lines[i].qty,
                        onChanged: (_) => _touch(),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: motionInput(context, hint: 'Qty'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(controller: _lines[i].remarks, onChanged: (_) => _touch(), decoration: motionInput(context, hint: 'Remarks, e.g. spec')),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
    ]);
  }

  Widget _terms() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FormLabel(
          label: 'Quote deadline',
          help: 'Last day suppliers can send their quotes',
          child: DatePickField(
            value: _deadline,
            hint: 'Pick a date',
            onChanged: (d) => setState(() {
              _deadline = d;
              _dirty = true;
            }),
          ),
        ),
        FormLabel(
          label: 'Remarks',
          child: TextField(controller: _remarks, onChanged: (_) => _touch(), minLines: 3, maxLines: 6, decoration: motionInput(context, hint: 'Optional, e.g. delivery terms')),
        ),
      ]);

  Widget _review() {
    final p = MarketPalette.of(context);
    final lines = _validLines;
    final client = _lookups.clients.where((c) => c['id'] == _clientId).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      reviewGrid([
        ('RFQ no', _rfqNo.text.trim()),
        ('Status', rfqStatusLabel[_status] ?? _status),
        ('Title', _title.text.trim()),
        ('Client', client == null ? '' : str(client['name'])),
        ('Requisition', _sprName ?? ''),
        ('Quote deadline', _deadline == null ? '' : fmtDate(_deadline)),
      ]),
      if (_remarks.text.trim().isNotEmpty) ...[
        const SizedBox(height: 10),
        ReviewTile('Remarks', _remarks.text.trim()),
      ],
      const SizedBox(height: 16),
      Text('${lines.length} product line${lines.length == 1 ? '' : 's'}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
      const SizedBox(height: 8),
      for (var i = 0; i < lines.length; i++)
        FadeSlideIn(
          index: i,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(lines[i].productName.isEmpty ? 'Product #${lines[i].productId}' : lines[i].productName,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                  if (lines[i].remarks.trim().isNotEmpty) Text(lines[i].remarks.trim(), style: TextStyle(fontSize: 12, color: p.label)),
                ]),
              ),
              Text('× ${lines[i].quantity.trim()}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
            ]),
          ),
        ),
    ]);
  }
}

// ── Quote create / edit wizard ──────────────────────────────────────────

class QuoteFormPage extends StatefulWidget {
  final Rfq rfq;
  final List<Map<String, dynamic>> suppliers;
  final RfqQuote? existing;
  const QuoteFormPage({super.key, required this.rfq, required this.suppliers, this.existing});

  @override
  State<QuoteFormPage> createState() => _QuoteFormPageState();
}

class _QuoteFormPageState extends State<QuoteFormPage> {
  final _service = RfqService();
  final _supplierName = TextEditingController();
  final _leadTime = TextEditingController();
  final _remarks = TextEditingController();
  final Map<int, TextEditingController> _prices = {};
  int? _supplierId;
  DateTime? _validUntil;
  bool _dirty = false;

  Rfq get rfq => widget.rfq;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _supplierId = e.supplierId;
      _supplierName.text = e.supplierName ?? '';
      _leadTime.text = e.leadTimeDays?.toString() ?? '';
      _remarks.text = e.remarks ?? '';
      _validUntil = e.validUntil;
    }
    for (final item in rfq.items) {
      final price = e == null ? null : quotePriceOf(e, item.id);
      _prices[item.id] = TextEditingController(text: price == null ? '' : (price == price.roundToDouble() ? price.toInt().toString() : price.toString()));
    }
  }

  @override
  void dispose() {
    _supplierName.dispose();
    _leadTime.dispose();
    _remarks.dispose();
    for (final c in _prices.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  double? _priceOf(int itemId) {
    final raw = _prices[itemId]?.text.trim() ?? '';
    if (raw.isEmpty) return null;
    final v = double.tryParse(raw);
    return v != null && v.isFinite ? v : null;
  }

  ({double total, int priced}) get _running {
    var total = 0.0;
    var priced = 0;
    for (final item in rfq.items) {
      final pr = _priceOf(item.id);
      if (pr == null) continue;
      priced++;
      total += pr * item.quantity;
    }
    return (total: total, priced: priced);
  }

  Future<bool> _save() async {
    try {
      final lead = _leadTime.text.trim();
      await _service.saveQuote(
        rfq: rfq,
        editing: widget.existing,
        supplierId: _supplierId,
        supplierName: _supplierName.text,
        validUntil: _validUntil,
        leadTimeDays: lead.isEmpty ? null : ((double.tryParse(lead) ?? 0).round().clamp(0, 1 << 31)),
        remarks: _remarks.text,
        prices: {for (final e in _prices.entries) e.key: e.value.text},
      );
      if (!mounted) return true;
      marketToast(context, widget.existing != null ? 'Quote updated' : 'Quote added');
      Navigator.of(context).pop(true);
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Failed to save quote'), error: true);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MotionWizardPage(
      title: widget.existing != null ? 'Edit quote' : 'New quote',
      subtitle: null,
      submitLabel: 'Save quote',
      isDirty: () => _dirty,
      onSubmit: _save,
      steps: [
        WizardStep(
          title: 'Supplier',
          icon: Icons.storefront_outlined,
          caption: 'Who sent this quote for ${rfq.rfqNo}',
          validate: () => _supplierName.text.trim().isEmpty ? 'Pick the supplier who sent this quote' : null,
          builder: (_) => _supplierStep(),
        ),
        WizardStep(
          title: 'Prices',
          icon: Icons.sell_outlined,
          caption: 'Unit price per product, leave blank if not quoted',
          validate: () => _running.priced == 0 ? 'Enter a price for at least one product' : null,
          builder: (_) => _pricesStep(),
        ),
        WizardStep(title: 'Review', icon: Icons.fact_check_outlined, caption: 'Check the quote before saving', builder: (_) => _reviewStep()),
      ],
    );
  }

  Widget _supplierStep() {
    final options = [for (final s in widget.suppliers) PickOption(s['id'], str(s['supplier_name']))];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FormLabel(
        label: 'Supplier',
        required: true,
        child: PickerField(
          value: _supplierId,
          hint: 'Select supplier',
          icon: Icons.storefront_outlined,
          options: options,
          onChanged: (v) => setState(() {
            _supplierId = v as int?;
            final label = options.where((o) => o.id == v).firstOrNull?.label;
            if (label != null) _supplierName.text = label;
            _dirty = true;
          }),
        ),
      ),
      FormLabel(
        label: 'Supplier name',
        help: 'Filled from the list, or type a supplier that is not saved yet',
        child: TextField(
          controller: _supplierName,
          decoration: motionInput(context, hint: 'Supplier name', icon: Icons.badge_outlined),
          onChanged: (v) {
            final match = options.where((o) => o.label == v.trim()).firstOrNull;
            setState(() {
              _supplierId = match?.id as int?;
              _dirty = true;
            });
          },
        ),
      ),
      FormLabel(
        label: 'Valid until',
        child: DatePickField(
          value: _validUntil,
          onChanged: (d) => setState(() {
            _validUntil = d;
            _dirty = true;
          }),
        ),
      ),
      FormLabel(
        label: 'Lead time (days)',
        child: TextField(controller: _leadTime, onChanged: (_) => _touch(), keyboardType: TextInputType.number, decoration: motionInput(context, hint: 'Optional', icon: Icons.local_shipping_outlined)),
      ),
      FormLabel(
        label: 'Remarks',
        child: TextField(controller: _remarks, onChanged: (_) => _touch(), minLines: 2, maxLines: 5, decoration: motionInput(context, hint: 'Optional, e.g. payment terms')),
      ),
    ]);
  }

  Widget _pricesStep() {
    final p = MarketPalette.of(context);
    final run = _running;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < rfq.items.length; i++)
        () {
          final item = rfq.items[i];
          final pr = _priceOf(item.id);
          return FadeSlideIn(
            index: i,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.productName, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                    const SizedBox(height: 2),
                    Text('× ${_qty(item.quantity)}${pr == null ? '' : ' · line ${money(pr * item.quantity)}'}', style: TextStyle(fontSize: 12, color: p.label)),
                  ]),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _prices[item.id],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    onChanged: (_) => setState(() => _dirty = true),
                    decoration: motionInput(context, hint: 'Not quoted'),
                  ),
                ),
              ]),
            ),
          );
        }(),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Quote total', style: TextStyle(fontSize: 12.5, color: p.label)),
              Text('${run.priced} of ${rfq.items.length} priced', style: TextStyle(fontSize: 11.5, color: run.priced == rfq.items.length ? p.ok : p.warn)),
            ]),
          ),
          CountUp(value: run.total, format: (v) => money(v), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
        ]),
      ),
    ]);
  }

  Widget _reviewStep() {
    final p = MarketPalette.of(context);
    final run = _running;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      reviewGrid([
        ('Supplier', _supplierName.text.trim()),
        ('RFQ', rfq.rfqNo),
        ('Valid until', _validUntil == null ? '' : fmtDate(_validUntil)),
        ('Lead time', _leadTime.text.trim().isEmpty ? '' : '${_leadTime.text.trim()} day(s)'),
        ('Priced', '${run.priced} of ${rfq.items.length}'),
        ('Total', money(run.total)),
      ]),
      if (_remarks.text.trim().isNotEmpty) ...[const SizedBox(height: 10), ReviewTile('Remarks', _remarks.text.trim())],
      if (run.priced < rfq.items.length) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.warnBg, borderRadius: BorderRadius.circular(10)),
          child: Text('Some products are not priced. This quote will show as incomplete and won\'t compete for best total.',
              style: TextStyle(fontSize: 12.5, color: p.warn)),
        ),
      ],
    ]);
  }
}
