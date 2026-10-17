import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../../core/config/app_config.dart';
import '../../data/market_seller_service.dart';
import '../orders/order_common.dart';
import '../widgets/market_ui.dart';

// The API returns media as relative paths — same per-file convention as
// notification_model.dart / stay_model.dart (desktop's LazyImage
// `resolveMediaUrl`).
String? resolveMediaUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http') || url.startsWith('data:')) return url;
  return '${AppConfig.apiBase}${url.startsWith('/') ? '' : '/'}$url';
}

/// Five stars, filled up to [rating].
class StarRow extends StatelessWidget {
  final double rating;
  final double size;
  const StarRow({super.key, required this.rating, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final gold = p.dark ? const Color(0xFFFFC233) : const Color(0xFFE9A100);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 5; i++)
        Icon(
          rating >= i ? Icons.star_rounded : (rating >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
          size: size,
          color: rating >= i - 0.5 ? gold : p.label.withValues(alpha: 0.6),
        ),
    ]);
  }
}

/// One review with the listing, rating, comment and an inline reply editor.
class ReviewCard extends StatefulWidget {
  final Map<String, dynamic> review;
  final MarketSellerService service;
  final ValueChanged<Map<String, dynamic>> onSaved;
  const ReviewCard({super.key, required this.review, required this.service, required this.onSaved});

  @override
  State<ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<ReviewCard> {
  final _draft = TextEditingController();
  bool _editing = false;
  bool _saving = false;
  bool _flash = false;

  Map<String, dynamic> get r => widget.review;
  String? get _reply => str(r['seller_reply']);

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _send(String reply) async {
    setState(() => _saving = true);
    try {
      final res = await widget.service.replyToReview(toInt(r['id']), reply);
      if (!mounted) return;
      widget.onSaved({
        ...r,
        'seller_reply': res.containsKey('seller_reply') ? res['seller_reply'] : (reply.isEmpty ? null : reply),
        'seller_replied_at': res['seller_replied_at'] ?? (reply.isEmpty ? null : DateTime.now().toIso8601String()),
      });
      setState(() {
        _editing = false;
        _flash = reply.isNotEmpty;
      });
      marketToast(context, reply.isEmpty ? 'Reply removed' : 'Reply saved');
      if (_flash) {
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) setState(() => _flash = false);
        });
      }
    } catch (e) {
      if (mounted) marketToast(context, errorText(e, 'Could not save the reply'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final ok = await confirmMarket(context, title: 'Remove reply', message: 'Remove your public reply to this review?', confirm: 'Remove');
    if (ok && mounted) _send('');
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final thumb = resolveMediaUrl(str(r['listing_thumbnail']));
    final comment = str(r['comment']);
    final orderNo = str(r['order_no']);
    final reply = _reply;
    final meta = [str(r['reviewer']) ?? 'Anonymous buyer', if (orderNo != null) 'Order $orderNo', fmtDate(r['created_at'])].join(' · ');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _flash ? p.okBg : p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _flash ? p.ok.withValues(alpha: 0.5) : p.line),
      ),
      padding: const EdgeInsets.all(14),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: thumb == null
                    ? _thumbPlaceholder(p)
                    : CachedNetworkImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: p.surface),
                        errorWidget: (_, _, _) => _thumbPlaceholder(p),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str(r['listing_title']) ?? 'Listing #${r['listing_id']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
                const SizedBox(height: 3),
                StarRow(rating: toDouble(r['rating'])),
                const SizedBox(height: 3),
                Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
              ]),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: reply == null
                  ? const Padding(padding: EdgeInsets.only(left: 8), child: StatusPill('Needs reply', tone: MarketTone.warn))
                  : const SizedBox.shrink(),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            comment ?? 'No written comment.',
            style: TextStyle(fontSize: 13.5, color: comment == null ? p.label : p.text, fontStyle: comment == null ? FontStyle.italic : null, height: 1.4),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _editing ? _editor(p) : (reply != null ? _replyBox(p, reply) : _replyButton()),
          ),
        ]),
      ),
    );
  }

  Widget _thumbPlaceholder(MarketPalette p) =>
      Container(color: p.surface, child: Icon(Icons.image_not_supported_outlined, size: 18, color: p.label));

  Widget _replyButton() => Align(
        key: const ValueKey('btn'),
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () {
            _draft.text = '';
            setState(() => _editing = true);
          },
          icon: const Icon(Icons.reply, size: 18),
          label: const Text('Reply'),
        ),
      );

  Widget _replyBox(MarketPalette p, String reply) {
    final at = r['seller_replied_at'];
    return Container(
      key: const ValueKey('reply'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: p.brand, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(at == null ? 'Your reply' : 'Your reply · ${fmtDate(at)}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text)),
          ),
          IconButton(
            tooltip: 'Edit reply',
            visualDensity: VisualDensity.compact,
            onPressed: _saving
                ? null
                : () {
                    _draft.text = reply;
                    setState(() => _editing = true);
                  },
            icon: Icon(Icons.edit_outlined, size: 18, color: p.label),
          ),
          IconButton(
            tooltip: 'Remove reply',
            visualDensity: VisualDensity.compact,
            onPressed: _saving ? null : _remove,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.delete_outline, size: 18, color: p.error),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(reply, style: TextStyle(fontSize: 13, color: p.text, height: 1.4)),
        ),
      ]),
    );
  }

  Widget _editor(MarketPalette p) => Column(
        key: const ValueKey('editor'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _draft,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            maxLength: 1000,
            enabled: !_saving,
            onChanged: (_) => setState(() {}),
            style: TextStyle(fontSize: 13.5, color: p.text),
            decoration: InputDecoration(
              hintText: 'Write a public reply',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: _saving ? null : () => setState(() => _editing = false), child: const Text('Cancel')),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: _saving || _draft.text.trim().isEmpty ? null : () => _send(_draft.text.trim()),
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save reply'),
            ),
          ]),
        ],
      );
}
