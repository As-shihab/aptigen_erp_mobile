import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../../core/network/http_client.dart';
import '../../data/market_seller_service.dart';
import '../widgets/market_ui.dart';
import 'listing_common.dart';

/// What the detail sheet asks the list page to do once it closes.
enum ListingSheetResult { edit, changed }

/// Object-header style detail for one listing: gallery, every field, the
/// range's performance, rejection reason and Edit / Pause–Activate / Delete.
Future<ListingSheetResult?> showListingDetailSheet(
  BuildContext context, {
  required Map<String, dynamic> row,
  Map<String, dynamic>? stats,
  required String rangeLabel,
  required MarketSellerService service,
}) =>
    showMarketSheet<ListingSheetResult>(
      context,
      builder: (ctx) => _ListingDetail(row: row, stats: stats, rangeLabel: rangeLabel, service: service),
    );

class _ListingDetail extends StatefulWidget {
  final Map<String, dynamic> row;
  final Map<String, dynamic>? stats;
  final String rangeLabel;
  final MarketSellerService service;
  const _ListingDetail({required this.row, required this.stats, required this.rangeLabel, required this.service});

  @override
  State<_ListingDetail> createState() => _ListingDetailState();
}

class _ListingDetailState extends State<_ListingDetail> {
  final _page = PageController();
  int _index = 0;
  bool _busy = false;

  Map<String, dynamic> get r => widget.row;
  int get _id => toInt(r['id']);
  String? get _currency => '${r['currency'] ?? ''}'.isEmpty ? null : '${r['currency']}';

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _gallery {
    final medias = listingMedias(r);
    if (medias.isNotEmpty) return medias;
    final cover = listingCover(r);
    return cover == null ? const [] : [{'url': cover, 'type': 'image'}];
  }

  Future<void> _toggleStatus() async {
    final next = r['status'] == 'active' ? 'paused' : 'active';
    setState(() => _busy = true);
    try {
      await widget.service.saveListing({'status': next}, id: _id);
      if (!mounted) return;
      marketToast(context, next == 'active' ? 'Listing activated' : 'Listing paused');
      Navigator.pop(context, ListingSheetResult.changed);
    } on ApiException catch (e) {
      if (mounted) marketToast(context, e.message, error: true);
    } catch (_) {
      if (mounted) marketToast(context, 'Could not update the listing', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmMarket(context,
        title: 'Delete listing', message: 'Delete "${r['title'] ?? 'this listing'}"? Buyers will no longer see it. This cannot be undone.');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.service.deleteListing(_id);
      if (!mounted) return;
      marketToast(context, 'Listing deleted');
      Navigator.pop(context, ListingSheetResult.changed);
    } on ApiException catch (e) {
      if (mounted) marketToast(context, e.message, error: true);
    } catch (_) {
      if (mounted) marketToast(context, 'Could not delete the listing', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(dynamic v) {
    final d = DateTime.tryParse('${v ?? ''}');
    return d == null ? '—' : DateFormat('d MMM y, h:mm a').format(d.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final status = '${r['status'] ?? 'draft'}';
    final approval = '${r['approval_status'] ?? 'pending'}';
    final gallery = _gallery;
    final s = widget.stats;
    final tags = '${r['tags'] ?? ''}'.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    final location = [r['city'], r['country']].where((v) => v != null && '$v'.trim().isNotEmpty).join(', ');
    final canToggle = status == 'active' || status == 'paused' || status == 'draft';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(children: [
        const SizedBox(height: 8),
        Container(width: 36, height: 4, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2))),
        Expanded(
          child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
            // Gallery
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: gallery.isEmpty
                    ? const MarketNetImage(null, iconSize: 40)
                    : Stack(children: [
                        PageView.builder(
                          controller: _page,
                          itemCount: gallery.length,
                          onPageChanged: (i) => setState(() => _index = i),
                          itemBuilder: (_, i) {
                            final m = gallery[i];
                            if (isVideoMedia(m)) {
                              return Container(
                                color: p.surface,
                                alignment: Alignment.center,
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.play_circle_outline, size: 44, color: p.label),
                                  const SizedBox(height: 6),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24),
                                    child: Text('${m['name'] ?? 'Video'}',
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
                                  ),
                                ]),
                              );
                            }
                            return MarketNetImage('${m['url'] ?? ''}', iconSize: 40);
                          },
                        ),
                        if (gallery.length > 1)
                          Positioned(
                            bottom: 8,
                            left: 0,
                            right: 0,
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              for (var i = 0; i < gallery.length && i < 12; i++)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                                  width: i == _index ? 16 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: i == _index ? p.brand : p.card.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                            ]),
                          ),
                      ]),
              ),
            ),
            const SizedBox(height: 14),

            // Object header
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatusPill(listingStatusLabels[status] ?? sentenceCase(status), tone: listingStatusTone(status)),
              StatusPill(approvalLabels[approval] ?? sentenceCase(approval),
                  tone: approvalTone(approval), icon: listingProcessing(r) ? Icons.sync : null),
              if (r['is_featured'] == true) const StatusPill('Featured', tone: MarketTone.warn, icon: Icons.star_rounded),
            ]),
            const SizedBox(height: 8),
            Text('${r['title'] ?? 'Untitled listing'}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text, height: 1.25)),
            if ((r['product'] as Map?)?['name'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('${(r['product'] as Map)['name']}', style: TextStyle(fontSize: 12.5, color: p.label)),
              ),
            const SizedBox(height: 8),
            Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 8, children: [
              Text(money(toDouble(r['price']), currency: _currency), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text)),
              if (r['compare_price'] != null && toDouble(r['compare_price']) > toDouble(r['price']))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(money(toDouble(r['compare_price']), currency: _currency),
                      style: TextStyle(fontSize: 13, color: p.label, decoration: TextDecoration.lineThrough)),
                ),
            ]),

            if (approval == 'rejected') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.errorBg, borderRadius: BorderRadius.circular(10)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline, size: 18, color: p.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Rejected by the platform', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.error)),
                      const SizedBox(height: 2),
                      Text(
                        '${r['rejection_reason'] ?? ''}'.trim().isEmpty ? 'No reason was given. Edit the listing and publish again.' : '${r['rejection_reason']}',
                        style: TextStyle(fontSize: 12.5, color: p.text, height: 1.35),
                      ),
                    ]),
                  ),
                ]),
              ),
            ] else if (approval == 'pending') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.warnBg, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Icon(Icons.hourglass_top_rounded, size: 18, color: p.warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Awaiting platform approval. It appears on the market once approved and active.',
                        style: TextStyle(fontSize: 12.5, color: p.text, height: 1.35)),
                  ),
                ]),
              ),
            ],

            // Performance
            SectionHeader('Performance', subtitle: widget.rangeLabel),
            MarketCard(
              padding: const EdgeInsets.all(12),
              child: s == null
                  ? Text('No activity in this range yet.', style: TextStyle(fontSize: 12.5, color: p.label))
                  : Column(children: [
                      InfoRow('Views', '${fmtCount(toDouble(s['views']))} · ${fmtCount(toDouble(s['unique_views']))} unique'),
                      InfoRow('Clicks', fmtCount(toDouble(s['clicks']))),
                      InfoRow('Saves', fmtCount(toDouble(s['saves']))),
                      InfoRow('Add to cart', fmtCount(toDouble(s['cart_adds']))),
                      InfoRow('Orders', fmtCount(toDouble(s['orders']))),
                      InfoRow('Units sold', fmtCount(toDouble(s['units_sold']))),
                      InfoRow('Revenue', money(toDouble(s['revenue']), currency: _currency), emphasize: true),
                      InfoRow('Conversion', '${conversionOf(s).toStringAsFixed(1)}%'),
                    ]),
            ),

            // Fields
            const SectionHeader('Details'),
            MarketCard(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                InfoRow('Category', '${(r['category'] as Map?)?['name'] ?? '—'}'),
                InfoRow('Condition', conditionLabels[r['condition']] ?? '${r['condition'] ?? '—'}'),
                InfoRow('Listing type', listingTypeLabels[r['listing_type']] ?? '${r['listing_type'] ?? '—'}'),
                InfoRow('Currency', '${r['currency'] ?? '—'}'),
                InfoRow('Stock', '${toInt(r['quantity'])}'),
                InfoRow('Min order', '${r['min_order'] ?? 1}'),
                InfoRow('Max order', r['max_order'] == null ? 'No limit' : '${r['max_order']}'),
                InfoRow('Location', location.isEmpty ? '—' : location),
                InfoRow('Expires', r['expires_at'] == null ? 'Never' : _date(r['expires_at'])),
                InfoRow('Media', '${listingMedias(r).length} files · ${listingVideoCount(r)} video'),
                InfoRow('Created', _date(r['created_at'])),
                InfoRow('Updated', _date(r['updated_at'])),
              ]),
            ),
            if ('${r['description'] ?? ''}'.trim().isNotEmpty) ...[
              const SectionHeader('Description'),
              Text('${r['description']}', style: TextStyle(fontSize: 13, color: p.text, height: 1.45)),
            ],
            if (tags.isNotEmpty) ...[
              const SectionHeader('Tags'),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final t in tags) StatusPill(t, tone: MarketTone.info)]),
            ],
          ]),
        ),

        // Actions
        Container(
          decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SafeArea(
            top: false,
            child: Row(children: [
              IconButton(
                tooltip: 'Delete',
                onPressed: _busy ? null : _delete,
                icon: Icon(Icons.delete_outline, color: p.error),
              ),
              const SizedBox(width: 4),
              if (canToggle)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _toggleStatus,
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(status == 'active' ? Icons.pause_circle_outline : Icons.play_circle_outline, size: 18),
                    label: Text(status == 'active' ? 'Pause' : 'Activate', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              if (canToggle) const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => Navigator.pop(context, ListingSheetResult.edit),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
