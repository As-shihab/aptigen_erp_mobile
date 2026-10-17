import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../data/market_seller_service.dart';
import 'listings/listing_card.dart';
import 'listings/listing_common.dart';
import 'listings/listing_detail_sheet.dart';
import 'listings/listing_form_page.dart';
import 'widgets/market_ui.dart';

/// Sell → Online → Market → Listings. Mobile port of erp/desktop's
/// pages/market/listings/ListingList.tsx: performance totals for a date
/// range, status filter, search, list / grid cards, detail sheet and the
/// listing wizard.
class MarketListingsPage extends StatefulWidget {
  const MarketListingsPage({super.key});

  @override
  State<MarketListingsPage> createState() => _MarketListingsPageState();
}

enum _Filter { all, active, draft, paused, awaiting, rejected }

const _ranges = [
  (id: '7', label: '7 days'),
  (id: '30', label: '30 days'),
  (id: '90', label: '90 days'),
  (id: 'all', label: 'All time'),
  (id: 'custom', label: 'Custom'),
];

class _MarketListingsPageState extends State<MarketListingsPage> {
  final _service = MarketSellerService();
  final _search = TextEditingController();

  List<Map<String, dynamic>> _rows = [];
  Map<int, Map<String, dynamic>> _stats = {};
  bool _loading = true;
  bool _statsLoading = false;
  String? _error;

  String _range = '30';
  DateTimeRange? _custom;
  _Filter _filter = _Filter.all;
  String _query = '';
  bool _grid = false;

  static final _ymd = DateFormat('yyyy-MM-dd');

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

  ({String from, String to})? get _resolvedRange {
    if (_range == 'all') return null;
    if (_range == 'custom') {
      final c = _custom;
      return c == null ? null : (from: _ymd.format(c.start), to: _ymd.format(c.end));
    }
    final days = int.parse(_range);
    final to = DateTime.now();
    final from = to.subtract(Duration(days: days - 1));
    return (from: _ymd.format(from), to: _ymd.format(to));
  }

  String get _rangeLabel {
    final r = _resolvedRange;
    if (r == null) return 'All time';
    final f = DateFormat('d MMM y');
    return '${f.format(DateTime.parse(r.from))} – ${f.format(DateTime.parse(r.to))}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    final statsFuture = _loadStats();
    try {
      final rows = await _service.listings();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
        if (_rows.isNotEmpty) marketToast(context, e.message, error: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load listings';
          _loading = false;
        });
      }
    }
    await statsFuture;
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final r = _resolvedRange;
      final list = await _service.listingStats(from: r?.from, to: r?.to);
      if (!mounted) return;
      setState(() => _stats = {for (final s in list) toInt(s['listing_id']): s});
    } catch (_) {
      // Stats are supplementary — the listings still work without them.
    } finally {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _setRange(String id) async {
    if (id == 'custom') {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: now,
        initialDateRange: _custom ?? DateTimeRange(start: now.subtract(const Duration(days: 29)), end: now),
        helpText: 'Select a date range',
      );
      if (picked == null || !mounted) return;
      setState(() {
        _custom = picked;
        _range = 'custom';
      });
    } else {
      setState(() => _range = id);
    }
    _loadStats();
  }

  // ── Derived ─────────────────────────────────────────────────────────

  bool _matches(Map<String, dynamic> r, _Filter f) => switch (f) {
        _Filter.all => true,
        _Filter.active => r['status'] == 'active',
        _Filter.draft => r['status'] == 'draft',
        _Filter.paused => r['status'] == 'paused',
        _Filter.awaiting => (r['approval_status'] ?? 'pending') == 'pending',
        _Filter.rejected => r['approval_status'] == 'rejected',
      };

  List<Map<String, dynamic>> get _visible {
    final q = _query.trim().toLowerCase();
    return _rows.where((r) {
      if (!_matches(r, _filter)) return false;
      if (q.isEmpty) return true;
      return '${r['title'] ?? ''}'.toLowerCase().contains(q) ||
          '${(r['product'] as Map?)?['name'] ?? ''}'.toLowerCase().contains(q) ||
          '${r['tags'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
  }

  ({double views, double unique, double clicks, double cart, double orders, double revenue}) get _totals {
    double v = 0, u = 0, c = 0, ca = 0, o = 0, rv = 0;
    for (final s in _stats.values) {
      v += toDouble(s['views']);
      u += toDouble(s['unique_views']);
      c += toDouble(s['clicks']);
      ca += toDouble(s['cart_adds']);
      o += toDouble(s['orders']);
      rv += toDouble(s['revenue']);
    }
    return (views: v, unique: u, clicks: c, cart: ca, orders: o, revenue: rv);
  }

  // ── Actions ─────────────────────────────────────────────────────────

  Future<void> _openForm([Map<String, dynamic>? listing]) async {
    String? cityHint, countryHint;
    for (final r in _rows) {
      if ('${r['city'] ?? ''}'.trim().isNotEmpty || '${r['country'] ?? ''}'.trim().isNotEmpty) {
        cityHint = '${r['city'] ?? ''}'.trim();
        countryHint = '${r['country'] ?? ''}'.trim();
        break;
      }
    }
    final res = await Navigator.of(context).push<String>(
      marketRoute(ListingFormPage(listing: listing, cityHint: cityHint, countryHint: countryHint)),
    );
    if (res == null || !mounted) return;
    if (res == 'draft') marketToast(context, listing == null ? 'Draft saved' : 'Listing saved as draft');
    if (res == 'active' && listing != null) marketToast(context, 'Listing updated — awaiting approval');
    _load();
  }

  Future<void> _openDetail(Map<String, dynamic> row) async {
    final res = await showListingDetailSheet(
      context,
      row: row,
      stats: _stats[toInt(row['id'])],
      rangeLabel: _rangeLabel,
      service: _service,
    );
    if (!mounted || res == null) return;
    if (res == ListingSheetResult.edit) {
      await _openForm(row);
    } else {
      _load();
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketScaffold(
      title: 'Listings',
      subtitle: _loading ? null : '${_rows.length} listing${_rows.length == 1 ? '' : 's'}',
      actions: [
        IconButton(
          tooltip: _grid ? 'List view' : 'Grid view',
          onPressed: () => setState(() => _grid = !_grid),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(a), child: c)),
            child: Icon(_grid ? Icons.view_agenda_outlined : Icons.grid_view_outlined, key: ValueKey(_grid), color: p.text),
          ),
        ),
        const SizedBox(width: 4),
      ],
      fab: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('New listing'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [SkeletonList(count: 6, itemHeight: 140)])
            : _error != null && _rows.isEmpty
                ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                    MarketEmpty(icon: Icons.cloud_off_outlined, title: 'Could not load listings', message: _error, actionLabel: 'Retry', onAction: _load),
                  ])
                : _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final p = MarketPalette.of(context);
    final t = _totals;
    final conv = t.unique > 0 ? t.orders / t.unique * 100 : 0.0;
    final visible = _visible;
    int count(_Filter f) => _rows.where((r) => _matches(r, f)).length;

    final kpis = [
      KpiTile(icon: Icons.visibility_outlined, label: 'Views', value: t.views, format: fmtCount, sub: '${fmtCount(t.unique)} unique', tone: MarketTone.info),
      KpiTile(icon: Icons.ads_click, label: 'Clicks', value: t.clicks, format: fmtCount, tone: MarketTone.brand),
      KpiTile(icon: Icons.add_shopping_cart, label: 'Add to cart', value: t.cart, format: fmtCount, tone: MarketTone.warn),
      KpiTile(icon: Icons.inventory_outlined, label: 'Orders', value: t.orders, format: fmtCount, tone: MarketTone.ok),
      KpiTile(icon: Icons.account_balance_wallet_outlined, label: 'Revenue', value: t.revenue, format: (v) => money(v), tone: MarketTone.ok),
      KpiTile(icon: Icons.percent, label: 'Conversion', value: conv, format: (v) => '${v.toStringAsFixed(1)}%', sub: 'orders ÷ unique views', tone: MarketTone.neutral),
    ];

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          sliver: SliverList.list(children: [
            // Range selector
            FadeSlideIn(
              child: MarketSegmented<String>(
                value: _range,
                options: [for (final r in _ranges) (id: r.id, label: r.label, count: null)],
                onChanged: _setRange,
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Text(
                  _range == 'custom' && _custom == null ? 'Showing all time until you pick a range' : 'Showing ${_resolvedRange == null ? 'all time' : _rangeLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: p.label),
                ),
              ),
              AnimatedOpacity(
                opacity: _statsLoading ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ]),
            const SizedBox(height: 10),
            // KPI strip
            LayoutBuilder(builder: (ctx, c) {
              final cols = c.maxWidth >= 720 ? 3 : 2;
              final w = (c.maxWidth - 8 * (cols - 1)) / cols;
              return Wrap(spacing: 8, runSpacing: 8, children: [
                for (var i = 0; i < kpis.length; i++) SizedBox(width: w, child: FadeSlideIn(index: i, child: kpis[i])),
              ]);
            }),
            const SizedBox(height: 16),
            // Status filter
            MarketSegmented<_Filter>(
              value: _filter,
              options: [
                (id: _Filter.all, label: 'All', count: _rows.length),
                (id: _Filter.active, label: 'Active', count: count(_Filter.active)),
                (id: _Filter.draft, label: 'Draft', count: count(_Filter.draft)),
                (id: _Filter.paused, label: 'Paused', count: count(_Filter.paused)),
                (id: _Filter.awaiting, label: 'Awaiting approval', count: count(_Filter.awaiting)),
                (id: _Filter.rejected, label: 'Rejected', count: count(_Filter.rejected)),
              ],
              onChanged: (f) => setState(() => _filter = f),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search title, product or tag',
                isDense: true,
                filled: true,
                fillColor: p.card,
                prefixIcon: Icon(Icons.search, size: 18, color: p.label),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close, size: 18, color: p.label),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
                hintStyle: TextStyle(fontSize: 13, color: p.label),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.brand, width: 1.5)),
              ),
            ),
            const SizedBox(height: 12),
          ]),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          sliver: SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
              child: KeyedSubtree(
                key: ValueKey('${_grid}_${_filter.name}'),
                child: visible.isEmpty ? _empty() : (_grid ? _gridView(visible) : _listView(visible)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty() {
    if (_rows.isEmpty) {
      return MarketEmpty(
        icon: Icons.storefront_outlined,
        title: 'No listings yet',
        message: 'Publish a product from your catalog to start selling on the market.',
        actionLabel: 'New listing',
        onAction: () => _openForm(),
      );
    }
    return MarketEmpty(
      icon: Icons.filter_alt_off_outlined,
      title: 'Nothing matches',
      message: _query.isEmpty ? 'No listings with this status.' : 'Try a different search or filter.',
    );
  }

  Widget _listView(List<Map<String, dynamic>> rows) => Column(children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            key: ValueKey(rows[i]['id']),
            padding: const EdgeInsets.only(bottom: 10),
            child: FadeSlideIn(
              index: i,
              child: ListingCard(row: rows[i], stats: _stats[toInt(rows[i]['id'])], onTap: () => _openDetail(rows[i])),
            ),
          ),
      ]);

  Widget _gridView(List<Map<String, dynamic>> rows) => LayoutBuilder(builder: (ctx, c) {
        final cols = c.maxWidth >= 600 ? 3 : 2;
        const gap = 10.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        final extent = w * 0.75 + 172;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: rows.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: gap, crossAxisSpacing: gap, mainAxisExtent: extent),
          itemBuilder: (_, i) => FadeSlideIn(
            key: ValueKey(rows[i]['id']),
            index: i,
            child: ListingCard(grid: true, row: rows[i], stats: _stats[toInt(rows[i]['id'])], onTap: () => _openDetail(rows[i])),
          ),
        );
      });
}
