import 'package:flutter/material.dart';
import '../widgets/market_ui.dart';
import 'flash_sale_widgets.dart';

/// State → pill label / tone (desktop STATE_META).
({String label, MarketTone tone, IconData icon}) flashStateMeta(String state) => switch (state) {
      'live' => (label: 'Live', tone: MarketTone.ok, icon: Icons.bolt),
      'scheduled' => (label: 'Scheduled', tone: MarketTone.info, icon: Icons.schedule),
      'paused' => (label: 'Paused', tone: MarketTone.warn, icon: Icons.pause_circle_outline),
      _ => (label: 'Ended', tone: MarketTone.neutral, icon: Icons.history),
    };

/// One flash sale: state, live countdown (driven by the page's shared
/// [clock]), window, totals and the first three items.
class FlashSaleCard extends StatelessWidget {
  final Map<String, dynamic> sale;
  final ValueNotifier<DateTime> clock;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const FlashSaleCard({super.key, required this.sale, required this.clock, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final state = '${sale['state'] ?? 'ended'}';
    final meta = flashStateMeta(state);
    final starts = parseDate(sale['starts_at']);
    final ends = parseDate(sale['ends_at']);
    final items = (sale['items'] is List ? sale['items'] as List : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

    return MarketCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${sale['name'] ?? 'Flash sale'}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                StatusPill(meta.label, tone: meta.tone, icon: meta.icon),
                _Countdown(state: state, starts: starts, ends: ends, clock: clock),
              ]),
            ]),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: p.label, size: 20),
            onSelected: (v) => v == 'edit' ? onTap() : onDelete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 8, top: 8),
          child: Row(children: [
            Icon(Icons.date_range_outlined, size: 14, color: p.label),
            const SizedBox(width: 6),
            Expanded(
              child: Text(fmtWindow(starts, ends), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Expanded(child: MiniStat('Items', '${items.length}')),
              Expanded(child: MiniStat('Units sold', plainNum(toDouble(sale['units_sold'])))),
              Expanded(flex: 2, child: MiniStat('Revenue', money(toDouble(sale['revenue'])))),
            ]),
          ),
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final it in items.take(3)) Padding(padding: const EdgeInsets.only(top: 8, right: 8), child: _ItemLine(item: it)),
          if (items.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('+${items.length - 3} more', style: TextStyle(fontSize: 12, color: p.brand, fontWeight: FontWeight.w600)),
            ),
        ],
      ]),
    );
  }
}

class _Countdown extends StatelessWidget {
  final String state;
  final DateTime? starts;
  final DateTime? ends;
  final ValueNotifier<DateTime> clock;
  const _Countdown({required this.state, required this.starts, required this.ends, required this.clock});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final style = TextStyle(fontSize: 12, color: p.label, fontFeatures: const [FontFeature.tabularFigures()]);
    if (state == 'ended') return Text(ends == null ? 'Ended' : 'Ended ${fmtDate(ends)}', style: style);
    if (state == 'paused') return Text('Turned off', style: style);
    final target = state == 'live' ? ends : starts;
    if (target == null) return const SizedBox.shrink();
    return ValueListenableBuilder<DateTime>(
      valueListenable: clock,
      builder: (_, now, _) => Text(
        '${state == 'live' ? 'Ends in' : 'Starts in'} ${countdown(target, now)}',
        style: style.copyWith(color: state == 'live' ? p.ok : p.info, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ItemLine extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ItemLine({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final l = item['listing'] is Map ? Map<String, dynamic>.from(item['listing'] as Map) : null;
    final list = toDouble(l?['price']);
    final sale = toDouble(item['sale_price']);
    final off = list > 0 && sale < list ? ((1 - sale / list) * 100).round() : 0;
    final sold = toInt(item['sold_count']);
    final limit = item['stock_limit'] == null ? null : toInt(item['stock_limit']);
    return Row(children: [
      MarketThumb(url: listingThumb(l), size: 40),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${l?['title'] ?? 'Listing #${item['listing_id']}'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
            ),
            if (off > 0) ...[const SizedBox(width: 6), StatusPill('$off% off', tone: MarketTone.error)],
          ]),
          const SizedBox(height: 3),
          Row(children: [
            Flexible(
              child: Text(money(sale), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text)),
            ),
            if (list > sale) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(money(list),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: p.label, decoration: TextDecoration.lineThrough)),
              ),
            ],
            const SizedBox(width: 8),
            Text(limit == null ? '$sold sold' : '$sold / $limit', style: TextStyle(fontSize: 11.5, color: p.label)),
          ]),
          if (limit != null && limit > 0) ...[
            const SizedBox(height: 5),
            MarketProgress(value: sold / limit, tone: sold >= limit ? MarketTone.warn : MarketTone.ok, height: 4),
          ],
        ]),
      ),
    ]);
  }
}
