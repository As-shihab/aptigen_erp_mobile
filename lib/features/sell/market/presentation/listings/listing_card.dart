import 'package:flutter/material.dart';
import '../widgets/market_ui.dart';
import 'listing_common.dart';

/// One listing, as a list row ([grid] false) or a grid tile ([grid] true).
/// Mirrors desktop ListingList.tsx `renderListingCard`.
class ListingCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final Map<String, dynamic>? stats;
  final bool grid;
  final VoidCallback? onTap;
  const ListingCard({super.key, required this.row, this.stats, this.grid = false, this.onTap});

  @override
  Widget build(BuildContext context) => grid ? _grid(context) : _list(context);

  String? get _currency => (row['currency'] ?? '').toString().isEmpty ? null : row['currency'].toString();

  bool get _hasCompare => row['compare_price'] != null && toDouble(row['compare_price']) > toDouble(row['price']);

  String get _meta {
    final parts = <String>[
      conditionLabels[row['condition']] ?? '${row['condition'] ?? ''}',
      listingTypeLabels[row['listing_type']] ?? '${row['listing_type'] ?? ''}',
      if (row['quantity'] != null) 'Stock ${toInt(row['quantity'])}',
    ].where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  List<Widget> _pills() {
    final status = '${row['status'] ?? 'draft'}';
    final approval = '${row['approval_status'] ?? 'pending'}';
    return [
      StatusPill(listingStatusLabels[status] ?? sentenceCase(status), tone: listingStatusTone(status)),
      if (approval != 'approved')
        StatusPill(approvalLabels[approval] ?? sentenceCase(approval),
            tone: approvalTone(approval), icon: listingProcessing(row) ? Icons.sync : null),
    ];
  }

  Widget _cover(BuildContext context, {required BorderRadius radius}) {
    final p = MarketPalette.of(context);
    final videos = listingVideoCount(row);
    final featured = row['is_featured'] == true;
    return ClipRRect(
      borderRadius: radius,
      child: Stack(fit: StackFit.expand, children: [
        MarketNetImage(listingCover(row)),
        if (featured || videos > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (featured)
                _badge(p, Icon(Icons.star_rounded, size: 14, color: p.warn)),
              if (featured && videos > 0) const SizedBox(width: 4),
              if (videos > 0)
                _badge(
                    p,
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.videocam_outlined, size: 13, color: p.text),
                      const SizedBox(width: 3),
                      Text('$videos', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: p.text)),
                    ])),
            ]),
          ),
      ]),
    );
  }

  Widget _badge(MarketPalette p, Widget child) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: p.card.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(6)),
        child: child,
      );

  Widget _price(MarketPalette p, {double size = 15}) => Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Flexible(
          child: Text(money(toDouble(row['price']), currency: _currency),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: p.text)),
        ),
        if (_hasCompare) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(money(toDouble(row['compare_price']), currency: _currency),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: p.label, decoration: TextDecoration.lineThrough)),
          ),
        ],
      ]);

  Widget _miniStats(MarketPalette p) {
    final s = stats;
    Widget cell(String label, String key) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(6)),
            child: Column(children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: p.label)),
              const SizedBox(height: 1),
              Text(s == null ? '—' : fmtCount(toDouble(s[key])),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text)),
            ]),
          ),
        );
    return Row(children: [
      cell('Views', 'views'),
      const SizedBox(width: 5),
      cell('Clicks', 'clicks'),
      const SizedBox(width: 5),
      cell('Orders', 'orders'),
    ]);
  }

  String get _title => '${row['title'] ?? ''}'.trim().isEmpty ? 'Untitled listing' : '${row['title']}';
  String? get _product => (row['product'] as Map?)?['name']?.toString();

  Widget _list(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 84, height: 84, child: _cover(context, radius: BorderRadius.circular(8))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 4, runSpacing: 4, children: _pills()),
              const SizedBox(height: 6),
              Text(_title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text, height: 1.25)),
              if (_product != null && _product!.isNotEmpty)
                Text(_product!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
              const SizedBox(height: 4),
              _price(p),
              Text(_meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.label)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        _miniStats(p),
      ]),
    );
  }

  Widget _grid(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(fit: StackFit.expand, children: [
            _cover(context, radius: const BorderRadius.vertical(top: Radius.circular(11))),
            Positioned(left: 6, top: 6, right: 40, child: Wrap(spacing: 4, runSpacing: 4, children: _pills())),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text, height: 1.25)),
              if (_product != null && _product!.isNotEmpty)
                Text(_product!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.label)),
              const Spacer(),
              _price(p, size: 13.5),
              Text(_meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: p.label)),
              const SizedBox(height: 6),
              _miniStats(p),
            ]),
          ),
        ),
      ]),
    );
  }
}
