import 'package:flutter/material.dart';
import '../flash_sales/flash_sale_widgets.dart';
import '../widgets/market_ui.dart';
import 'promotion_utils.dart';

/// Monospace code chip, or "Automatic" for code-less promotions.
class PromoCodeChip extends StatelessWidget {
  final Map<String, dynamic> promotion;
  const PromoCodeChip(this.promotion, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final code = '${promotion['code'] ?? ''}'.trim();
    if (code.isEmpty) return StatusPill('Automatic', tone: MarketTone.brand, icon: Icons.auto_awesome_outlined);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(6), border: Border.all(color: p.line)),
      child: Text(code,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w700, color: p.text)),
    );
  }
}

class PromotionCard extends StatelessWidget {
  final Map<String, dynamic> promotion;
  final bool toggling;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  const PromotionCard({super.key, required this.promotion, required this.onTap, required this.onToggle, this.toggling = false});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final pr = promotion;
    final status = promotionStatus(pr, DateTime.now());
    final used = toInt(pr['used_count']);
    final limit = pr['usage_limit'] == null ? null : toInt(pr['usage_limit']);
    final minOrder = toDouble(pr['min_order']);

    return MarketCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${pr['name'] ?? 'Promotion'}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                PromoCodeChip(pr),
                StatusPill(status.label, tone: status.tone),
              ]),
            ]),
          ),
          SizedBox(
            height: 32,
            child: FittedBox(
              child: Switch(value: pr['is_active'] == true, onChanged: toggling ? null : onToggle),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Row(children: [
            Icon(Icons.sell_outlined, size: 16, color: p.brand),
            const SizedBox(width: 6),
            Expanded(
              child: Text(discountLabel(pr),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.brand)),
            ),
            if (minOrder > 0)
              Flexible(
                child: Text('Min order ${money(minOrder)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: p.label)),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Row(children: [
            Text('Used', style: TextStyle(fontSize: 12, color: p.label)),
            const Spacer(),
            Text(limit == null ? '$used' : '$used / $limit',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
        if (limit != null && limit > 0) ...[
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: MarketProgress(value: used / limit, tone: used >= limit ? MarketTone.warn : MarketTone.brand, height: 4),
          ),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.date_range_outlined, size: 14, color: p.label),
          const SizedBox(width: 6),
          Expanded(
            child: Text(fmtWindow(parseDate(pr['starts_at']), parseDate(pr['ends_at'])),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
          ),
        ]),
      ]),
    );
  }
}
