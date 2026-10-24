import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/data/media_library_service.dart';
import '../../../../shared/models/media_library_item.dart';
import '../../../../shared/ui/motion_kit.dart';

/// Soft tinted banner for explanations ("desktop only", "read only", ...).
class NoteBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final MarketTone tone;
  const NoteBanner({super.key, this.icon = Icons.info_outline_rounded, required this.title, required this.message, this.tone = MarketTone.info});

  @override
  Widget build(BuildContext context) {
    final c = MarketPalette.of(context).tone(tone);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.fg.withValues(alpha: 0.25))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: c.fg, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.fg)),
            const SizedBox(height: 3),
            Text(message, style: TextStyle(fontSize: 12.5, height: 1.35, color: c.fg.withValues(alpha: 0.9))),
          ]),
        ),
      ]),
    );
  }
}

/// Card with an accent icon, title, subtitle and body — used for the
/// grouped preference sections.
class SettingsSection extends StatelessWidget {
  final IconData icon;
  final Accent accent;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  const SettingsSection({super.key, required this.icon, this.accent = Accent.ocean, required this.title, this.subtitle, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return GlowCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AccentIcon(icon, accent: accent, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
              if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12, color: p.label)),
            ]),
          ),
          ?trailing,
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}

/// Small stat chip (label over value) used in summary rows.
class StatChip extends StatelessWidget {
  final String label;
  final String value;
  final MarketTone tone;
  const StatChip({super.key, required this.label, required this.value, this.tone = MarketTone.neutral});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final c = p.tone(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
        const SizedBox(height: 3),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Text(value, key: ValueKey(value), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.fg)),
        ),
      ]),
    );
  }
}

/// Picks an image from the workplace media library; returns its URL.
Future<String?> pickMediaImage(BuildContext context, {String title = 'Select image'}) =>
    showMotionSheet<String>(context, (_) => _MediaPickSheet(title: title));

class _MediaPickSheet extends StatefulWidget {
  final String title;
  const _MediaPickSheet({required this.title});

  @override
  State<_MediaPickSheet> createState() => _MediaPickSheetState();
}

class _MediaPickSheetState extends State<_MediaPickSheet> {
  final _service = MediaLibraryService(ApiClient());
  List<MediaLibraryItem> _items = [];
  bool _loading = true;
  String? _error;
  String _q = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _service.loadItems(kind: 'image', search: _q, newestFirst: true, top: 60, withCount: false);
      if (mounted) setState(() => _items = res.items);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load media'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.78,
      child: Column(children: [
        const SheetGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(children: [
            Expanded(child: Text(widget.title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text))),
            IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: p.label)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TextField(
            onChanged: (v) {
              _q = v;
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), _load);
            },
            decoration: motionInput(context, hint: 'Search images', icon: Icons.search_rounded),
          ),
        ),
        Expanded(
          child: _loading
              ? GridView.count(
                  crossAxisCount: 3,
                  padding: const EdgeInsets.all(16),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: List.generate(9, (_) => const SkeletonBox(height: 100, radius: 14)),
                )
              : _error != null
                  ? MarketEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
                  : _items.isEmpty
                      ? const MarketEmpty(icon: Icons.image_not_supported_outlined, title: 'No images', message: 'Upload images from Settings, Media first.')
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10),
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final it = _items[i];
                            return FadeSlideIn(
                              index: i,
                              child: PressScale(
                                onTap: () => Navigator.pop(context, it.fileUrl.isNotEmpty ? it.fileUrl : it.previewUrl),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.network(
                                    it.previewUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(color: p.surface, child: Icon(Icons.broken_image_outlined, color: p.label)),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}

/// Day label for timeline grouping: "Today", "Yesterday" or a date.
String dayLabel(DateTime? d) {
  if (d == null) return 'Unknown date';
  final l = d.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(l.year, l.month, l.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return fmtDate(l);
}

/// "3 min ago" style relative time.
String timeAgo(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d.toLocal());
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return fmtDate(d);
}
