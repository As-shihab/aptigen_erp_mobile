import 'package:flutter/material.dart';
import '../data/market_seller_service.dart';
import 'orders/order_common.dart';
import 'reviews/review_card.dart';
import 'widgets/market_ui.dart';

/// Reviews buyers left on this store's listings, with the seller's public
/// reply — GET /api/market/seller-reviews, POST …/:id/reply.
class MarketReviewsPage extends StatefulWidget {
  const MarketReviewsPage({super.key});

  @override
  State<MarketReviewsPage> createState() => _MarketReviewsPageState();
}

class _MarketReviewsPageState extends State<MarketReviewsPage> {
  final _service = MarketSellerService();
  final _search = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';
  String _query = '';

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

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final rows = await _service.reviews();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (_rows.isEmpty) setState(() => _error = errorText(e, 'Could not load reviews'));
      marketToast(context, errorText(e, 'Could not load reviews'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _needsReply(Map<String, dynamic> r) => str(r['seller_reply']) == null;

  List<Map<String, dynamic>> get _visible {
    final q = _query.trim().toLowerCase();
    return _rows.where((r) {
      final rating = toInt(r['rating']);
      final ok = switch (_filter) {
        'needs_reply' => _needsReply(r),
        'low' => rating <= 2,
        'high' => rating >= 4,
        _ => true,
      };
      if (!ok) return false;
      if (q.isEmpty) return true;
      return [r['listing_title'], r['reviewer'], r['order_no'], r['comment'], r['seller_reply']]
          .any((v) => (v ?? '').toString().toLowerCase().contains(q));
    }).toList();
  }

  void _onSaved(Map<String, dynamic> updated) {
    setState(() {
      _rows = [for (final r in _rows) r['id'] == updated['id'] ? updated : r];
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final needs = _rows.where(_needsReply).length;
    final visible = _visible;

    return MarketScaffold(
      title: 'Reviews',
      subtitle: _loading && _rows.isEmpty ? null : '${_rows.length} reviews · $needs need a reply',
      actions: [
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : () => _load(), icon: const Icon(Icons.refresh)),
      ],
      body: RefreshIndicator(
        onRefresh: () => _load(silent: true),
        child: _loading && _rows.isEmpty
            ? const SkeletonList(itemHeight: 130)
            : _error != null && _rows.isEmpty
                ? ListView(children: [
                    MarketEmpty(icon: Icons.cloud_off_outlined, title: 'Could not load reviews', message: _error, actionLabel: 'Try again', onAction: _load),
                  ])
                : CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        sliver: SliverList.list(children: [
                          FadeSlideIn(child: _ReviewSummary(rows: _rows)),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _search,
                            onChanged: (v) => setState(() => _query = v),
                            style: TextStyle(fontSize: 14, color: p.text),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Search listing, reviewer or comment',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear',
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () {
                                        _search.clear();
                                        setState(() => _query = '');
                                      },
                                    ),
                              filled: true,
                              fillColor: p.card,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: MarketSegmented<String>(
                              value: _filter,
                              options: [
                                (id: 'all', label: 'All', count: null),
                                (id: 'needs_reply', label: 'Needs reply', count: needs),
                                (id: 'low', label: '1–2 stars', count: null),
                                (id: 'high', label: '4–5 stars', count: null),
                              ],
                              onChanged: (v) => setState(() => _filter = v),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ]),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        sliver: SliverToBoxAdapter(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: visible.isEmpty
                                ? MarketEmpty(
                                    key: ValueKey('empty-$_filter'),
                                    icon: Icons.reviews_outlined,
                                    title: _rows.isEmpty ? 'No reviews yet' : 'No matching reviews',
                                    message: _rows.isEmpty
                                        ? 'Reviews buyers leave on your listings show up here.'
                                        : 'Try another filter or search.',
                                  )
                                : Column(
                                    key: ValueKey('list-$_filter'),
                                    children: [
                                      for (var i = 0; i < visible.length; i++)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 10),
                                          child: FadeSlideIn(
                                            key: ValueKey('rv-${visible[i]['id']}'),
                                            index: i,
                                            child: ReviewCard(
                                              key: ValueKey('card-${visible[i]['id']}'),
                                              review: visible[i],
                                              service: _service,
                                              onSaved: _onSaved,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

/// Average rating, totals, reply rate and a 5→1 distribution with bars
/// that grow in.
class _ReviewSummary extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _ReviewSummary({required this.rows});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final total = rows.length;
    final dist = List<int>.filled(6, 0);
    var sum = 0;
    var replied = 0;
    for (final r in rows) {
      final v = toInt(r['rating']).clamp(1, 5);
      dist[v]++;
      sum += v;
      if (str(r['seller_reply']) != null) replied++;
    }
    final avg = total == 0 ? 0.0 : sum / total;
    final pct = total == 0 ? 0 : (replied * 100 / total).round();
    final gold = p.dark ? const Color(0xFFFFC233) : const Color(0xFFE9A100);

    return MarketCard(
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 104,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CountUp(
              value: avg,
              format: (v) => v.toStringAsFixed(1),
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: p.text, height: 1.1),
            ),
            const SizedBox(height: 4),
            StarRow(rating: avg, size: 16),
            const SizedBox(height: 8),
            Text(total == 1 ? '1 review' : '$total reviews', style: TextStyle(fontSize: 12, color: p.label)),
            const SizedBox(height: 2),
            Text('$pct% replied', style: TextStyle(fontSize: 12, color: p.label)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(children: [
            for (var s = 5; s >= 1; s--)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 12, child: Text('$s', style: TextStyle(fontSize: 12, color: p.label))),
                  Icon(Icons.star_rounded, size: 12, color: gold),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        height: 8,
                        color: p.surface,
                        alignment: Alignment.centerLeft,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: total == 0 ? 0 : dist[s] / total),
                          duration: Duration(milliseconds: 500 + (5 - s) * 60),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, _) => FractionallySizedBox(
                            widthFactor: v.clamp(0.0, 1.0),
                            child: Container(color: s >= 4 ? p.ok : (s == 3 ? gold : p.warn)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 26,
                    child: Text('${dist[s]}', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: p.label)),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}
