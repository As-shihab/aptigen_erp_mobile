import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../../core/config/app_config.dart';
import '../widgets/market_ui.dart';

// Shared helpers for the flash sale and promotion screens: media URLs,
// thumbnails, date formatting, countdowns, a date-time field and the
// searchable listing multi-pick sheet. Mirrors erp/desktop's
// pages/market/_marketUtils.ts.

/// API media paths can be relative (`/public/uploads/x.jpg`) — same rule as
/// the rest of the app (desktop's LazyImage.tsx `resolveMediaUrl`).
String? resolveMarketMedia(dynamic raw) {
  final url = raw?.toString() ?? '';
  if (url.isEmpty) return null;
  if (url.startsWith('http') || url.startsWith('data:')) return url;
  return '${AppConfig.apiBase}${url.startsWith('/') ? '' : '/'}$url';
}

/// Best thumbnail for a market listing row (thumbnail_url, else first image media).
String? listingThumb(Map<String, dynamic>? l) {
  if (l == null) return null;
  final direct = resolveMarketMedia(l['thumbnail_url']);
  if (direct != null) return direct;
  final medias = l['medias'];
  if (medias is List) {
    for (final m in medias) {
      if (m is Map && (m['type'] ?? 'image') != 'video') {
        final u = resolveMarketMedia(m['url'] ?? m['file_url']);
        if (u != null) return u;
      }
    }
  }
  return null;
}

String _ampm(String s) => s.replaceAll('AM', 'am').replaceAll('PM', 'pm');

DateTime? parseDate(dynamic iso) {
  if (iso == null || '$iso'.isEmpty) return null;
  return DateTime.tryParse('$iso')?.toLocal();
}

String fmtDateTime(DateTime? d) => d == null ? '—' : _ampm(DateFormat('d MMM yyyy, h:mm a').format(d));
String fmtDate(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy').format(d);
String _short(DateTime d) => _ampm(DateFormat('d MMM, h:mm a').format(d));

/// "12 Oct, 9:00 am – 14 Oct, 9:00 pm"; open ends read "From …" / "Until …".
String fmtWindow(DateTime? start, DateTime? end) {
  if (start == null && end == null) return 'Always';
  if (start != null && end != null) return '${_short(start)} – ${_short(end)}';
  if (start != null) return 'From ${_short(start)}';
  return 'Until ${_short(end!)}';
}

/// "02:14:09", or "2d 04:10:05" beyond a day.
String countdown(DateTime target, DateTime now) {
  var s = target.difference(now).inSeconds;
  if (s < 0) s = 0;
  final d = s ~/ 86400;
  final h = (s % 86400) ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  final clock = '${two(h)}:${two(m)}:${two(sec)}';
  return d > 0 ? '${d}d $clock' : clock;
}

/// "12.5" / "10" without trailing zeros.
String plainNum(num v) {
  final f = NumberFormat('#,##0.##');
  return f.format(v);
}

/// One combined date + time picker.
Future<DateTime?> pickDateTime(BuildContext context, {DateTime? initial}) async {
  final now = DateTime.now();
  final base = initial ?? DateTime(now.year, now.month, now.day, now.hour + 1);
  final date = await showDatePicker(
    context: context,
    initialDate: base,
    firstDate: DateTime(now.year - 2),
    lastDate: DateTime(now.year + 5),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// Tappable date-time field in the same outline style as the text fields.
class DateTimeField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool clearable;
  final String? errorText;
  const DateTimeField({super.key, required this.label, required this.value, required this.onChanged, this.clearable = false, this.errorText});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked = await pickDateTime(context, initial: value);
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          prefixIcon: const Icon(Icons.event_outlined, size: 20),
          suffixIcon: clearable && value != null
              ? IconButton(icon: const Icon(Icons.close, size: 18), tooltip: 'Clear', onPressed: () => onChanged(null))
              : null,
        ),
        child: Text(value == null ? '' : fmtDateTime(value),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.text)),
      ),
    );
  }
}

/// Square listing thumbnail with a neutral placeholder.
class MarketThumb extends StatelessWidget {
  final String? url;
  final double size;
  const MarketThumb({super.key, this.url, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    Widget placeholder() => Container(
          width: size,
          height: size,
          color: p.surface,
          child: Icon(Icons.image_not_supported_outlined, size: size * 0.4, color: p.label),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url == null
          ? placeholder()
          : CachedNetworkImage(
              imageUrl: url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder(),
              errorWidget: (_, _, _) => placeholder(),
            ),
    );
  }
}

/// Thin animated progress bar (0..1).
class MarketProgress extends StatelessWidget {
  final double value;
  final MarketTone tone;
  final double height;
  const MarketProgress({super.key, required this.value, this.tone = MarketTone.brand, this.height = 5});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final c = p.tone(tone);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: height, backgroundColor: p.surface, color: c.fg),
      ),
    );
  }
}

/// Searchable multi-pick sheet of the seller's listings. [selected] is the
/// starting selection; [locked] ids show as checked and can't be changed.
/// Resolves to the full selection, or null when dismissed.
Future<Set<int>?> pickListingsSheet(
  BuildContext context, {
  required List<Map<String, dynamic>> listings,
  Set<int> selected = const {},
  Set<int> locked = const {},
  String title = 'Choose listings',
  String confirmLabel = 'Done',
}) {
  return showMarketSheet<Set<int>>(context, builder: (ctx) => _ListingPicker(
        listings: listings,
        selected: {...selected, ...locked},
        locked: locked,
        title: title,
        confirmLabel: confirmLabel,
      ));
}

class _ListingPicker extends StatefulWidget {
  final List<Map<String, dynamic>> listings;
  final Set<int> selected;
  final Set<int> locked;
  final String title;
  final String confirmLabel;
  const _ListingPicker({required this.listings, required this.selected, required this.locked, required this.title, required this.confirmLabel});

  @override
  State<_ListingPicker> createState() => _ListingPickerState();
}

class _ListingPickerState extends State<_ListingPicker> {
  late final Set<int> _sel = {...widget.selected};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.listings
        : widget.listings.where((l) => '${l['title'] ?? ''}'.toLowerCase().contains(q)).toList();
    final picked = _sel.difference(widget.locked).length;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.82,
      child: Column(children: [
        const SizedBox(height: 8),
        Container(width: 36, height: 4, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(children: [
            Expanded(child: Text(widget.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text))),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(hintText: 'Search listings', prefixIcon: Icon(Icons.search), isDense: true),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? MarketEmpty(
                  icon: Icons.storefront_outlined,
                  title: widget.listings.isEmpty ? 'No listings yet' : 'No matches',
                  message: widget.listings.isEmpty ? 'Create a listing first, then add it here.' : 'Try another search.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: p.line, indent: 64),
                  itemBuilder: (_, i) {
                    final l = list[i];
                    final id = toInt(l['id']);
                    final isLocked = widget.locked.contains(id);
                    final on = _sel.contains(id);
                    final status = '${l['status'] ?? ''}';
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      enabled: !isLocked,
                      onTap: () => setState(() => on ? _sel.remove(id) : _sel.add(id)),
                      leading: MarketThumb(url: listingThumb(l), size: 44),
                      title: Text('${l['title'] ?? 'Listing #$id'}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                      subtitle: Text(
                        [money(toDouble(l['price'])), if (status.isNotEmpty) _sentence(status), if (isLocked) 'Already added'].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.label),
                      ),
                      trailing: Checkbox(value: on, onChanged: isLocked ? null : (v) => setState(() => v == true ? _sel.add(id) : _sel.remove(id))),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _sel),
                child: Text(picked > 0 ? '${widget.confirmLabel} ($picked)' : widget.confirmLabel),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

String _sentence(String s) {
  final t = s.replaceAll('_', ' ').trim();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1).toLowerCase();
}

/// Small labelled stat used in cards and detail sheets.
class MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const MiniStat(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
      const SizedBox(height: 1),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.label)),
    ]);
  }
}
