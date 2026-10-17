import 'package:flutter/material.dart';
import '../widgets/market_ui.dart';
import 'banner_meta.dart';
import 'form_kit.dart';
import 'market_media.dart';

/// Banner card: preview, copy, approval + schedule state and an active switch.
class BannerCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const BannerCard({super.key, required this.row, required this.busy, required this.onToggle, required this.onEdit, required this.onDelete});

  String _s(String k) => (row[k] ?? '').toString().trim();

  ({String label, MarketTone tone, IconData icon}) get _approval => switch (_s('approval_status')) {
        'approved' => (label: 'Approved', tone: MarketTone.ok, icon: Icons.check_circle_outline),
        'rejected' => (label: 'Rejected', tone: MarketTone.error, icon: Icons.block_outlined),
        _ => (label: 'Awaiting approval', tone: MarketTone.warn, icon: Icons.schedule_outlined),
      };

  String? get _schedule {
    final s = parseDate(row['starts_at']);
    final e = parseDate(row['ends_at']);
    if (s == null && e == null) return null;
    if (s != null && e != null) return '${formatDateTime(s)} – ${formatDateTime(e)}';
    if (s != null) return 'From ${formatDateTime(s)}';
    return 'Until ${formatDateTime(e!)}';
  }

  ({String label, MarketTone tone})? get _window {
    final now = DateTime.now();
    final s = parseDate(row['starts_at']);
    final e = parseDate(row['ends_at']);
    if (e != null && e.isBefore(now)) return (label: 'Ended', tone: MarketTone.neutral);
    if (s != null && s.isAfter(now)) return (label: 'Scheduled', tone: MarketTone.info);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final placement = bannerPlacement(_s('placement'));
    final active = row['is_active'] == true;
    final appr = _approval;
    final win = _window;
    final schedule = _schedule;
    final tone = bannerTone(context, _s('tone'));

    final preview = AspectRatio(
      aspectRatio: placement.aspect,
      child: Stack(fit: StackFit.expand, children: [
        MarketNetImage(
          _s('image_url').isNotEmpty ? _s('image_url') : _s('mobile_image_url'),
          fallback: Container(
            color: tone.bg,
            padding: const EdgeInsets.all(14),
            alignment: Alignment.bottomLeft,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_s('title'),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: tone.fg)),
              if (_s('cta_label').isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: tone.fg, borderRadius: BorderRadius.circular(20)),
                  child: Text(_s('cta_label'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
        ),
        Positioned(
          left: 8,
          top: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(6)),
            child: Text(placement.label, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
          ),
        ),
        if (!active)
          Container(
            color: Colors.black.withValues(alpha: 0.45),
            alignment: Alignment.center,
            child: const Text('Turned off', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
      ]),
    );

    return MarketCard(
      onTap: onEdit,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), child: preview),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_s('title'),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text)),
                if (_s('subtitle').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(_s('subtitle'), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.label)),
                  ),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  StatusPill(appr.label, tone: appr.tone, icon: appr.icon),
                  if (win != null) StatusPill(win.label, tone: win.tone),
                  if (_s('cta_label').isNotEmpty) StatusPill(_s('cta_label'), tone: MarketTone.brand, icon: Icons.touch_app_outlined),
                ]),
              ]),
            ),
            SizedBox(
              height: 40,
              child: busy
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Switch.adaptive(value: active, onChanged: onToggle),
            ),
          ]),
        ),
        if (_s('approval_status') == 'rejected' && _s('rejection_reason').isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.errorBg, borderRadius: BorderRadius.circular(8)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.error_outline, size: 16, color: p.error),
              const SizedBox(width: 8),
              Expanded(child: Text(_s('rejection_reason'), style: TextStyle(fontSize: 12, color: p.error, height: 1.35))),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 2, 4),
          child: Row(children: [
            Icon(Icons.event_outlined, size: 15, color: p.label),
            const SizedBox(width: 6),
            Expanded(
              child: Text(schedule ?? 'Always on while active',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(Icons.more_horiz, color: p.label, size: 20),
              onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ]),
        ),
      ]),
    );
  }
}
