import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import '../../../../core/config/app_config.dart';
import '../../../../shared/ui/motion_kit.dart';

// Shared bits for job postings + applications: candidate pipeline stages,
// media url resolution and an in-app opener for resume files (images in a
// zoomable viewer, PDFs through the system print / share preview).

const resumeStages = ['applied', 'shortlisted', 'interviewed', 'offered', 'hired', 'rejected'];

/// Forward pipeline order (rejected is a side exit).
const pipelineStages = ['applied', 'shortlisted', 'interviewed', 'offered', 'hired'];

Color stageColor(String s) => switch (s) {
      'applied' => const Color(0xFF5B738B),
      'shortlisted' => const Color(0xFF168EFF),
      'interviewed' => const Color(0xFF5D36FF),
      'offered' => const Color(0xFFE76500),
      'hired' => const Color(0xFF30914C),
      'rejected' => const Color(0xFFD20A0A),
      _ => const Color(0xFF8396A8),
    };

MarketTone stageTone(String s) => switch (s) {
      'shortlisted' || 'interviewed' => MarketTone.info,
      'offered' => MarketTone.warn,
      'hired' => MarketTone.ok,
      'rejected' => MarketTone.error,
      _ => MarketTone.neutral,
    };

IconData stageIcon(String s) => switch (s) {
      'applied' => Icons.inbox_rounded,
      'shortlisted' => Icons.playlist_add_check_rounded,
      'interviewed' => Icons.record_voice_over_rounded,
      'offered' => Icons.local_offer_rounded,
      'hired' => Icons.verified_rounded,
      'rejected' => Icons.block_rounded,
      _ => Icons.circle_outlined,
    };

/// Relative "/uploads/…" paths → absolute (desktop's resolveMediaUrl).
String mediaUrl(String url) {
  if (url.isEmpty) return url;
  if (url.startsWith('http') || url.startsWith('data:')) return url;
  return '${AppConfig.apiBase}${url.startsWith('/') ? '' : '/'}$url';
}

final _imageExt = RegExp(r'\.(png|jpe?g|gif|webp|bmp|heic|avif)(\?|#|$)', caseSensitive: false);

/// Opens a resume / document link inside the app.
Future<void> openResumeFile(BuildContext context, String raw, {String name = 'resume'}) async {
  final url = mediaUrl(raw.trim());
  if (url.isEmpty) {
    marketToast(context, 'No CV on file for this applicant', error: true);
    return;
  }
  final key = await showActionSheet(context, title: 'Resume file', actions: [
    (key: 'open', label: _imageExt.hasMatch(url) ? 'View image' : 'Open document', icon: Icons.open_in_new_rounded, destructive: false),
    (key: 'copy', label: 'Copy link', icon: Icons.link_rounded, destructive: false),
  ]);
  if (key == null || !context.mounted) return;
  if (key == 'copy') {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) marketToast(context, 'Link copied');
    return;
  }
  if (_imageExt.hasMatch(url)) {
    pushMotion(context, _ImageViewer(url: url, title: name));
    return;
  }
  marketToast(context, 'Opening document');
  try {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (res.statusCode >= 400) throw Exception('HTTP ${res.statusCode}');
    final bytes = res.bodyBytes;
    final isPdf = bytes.length > 4 && String.fromCharCodes(bytes.take(4)) == '%PDF';
    if (!context.mounted) return;
    if (isPdf) {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
    } else if ((res.headers['content-type'] ?? '').startsWith('image/')) {
      pushMotion(context, _ImageViewer(url: url, title: name));
    } else {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) marketToast(context, 'This file type cannot be previewed here. Link copied.');
    }
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) marketToast(context, 'Could not open the file. Link copied instead.', error: true);
  }
}

class _ImageViewer extends StatelessWidget {
  final String url;
  final String title;
  const _ImageViewer({required this.url, required this.title});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title)),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.network(
              url,
              loadingBuilder: (_, child, prog) => prog == null ? child : const CircularProgressIndicator(color: Colors.white),
              errorBuilder: (_, _, _) => const Text('Could not load image', style: TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      );
}

/// Thin stacked bar showing how many applications sit in each stage.
class PipelineBar extends StatelessWidget {
  final Map<String, int> counts;
  final double height;
  const PipelineBar({super.key, required this.counts, this.height = 8});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return Container(height: height, decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(height)));
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (_, t, _) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: Row(children: [
            for (final s in resumeStages)
              if ((counts[s] ?? 0) > 0) Expanded(flex: ((counts[s]! * 1000 * t).round()).clamp(1, 1 << 30), child: Container(color: stageColor(s))),
            if (t < 1) Expanded(flex: ((1 - t) * total * 1000).round().clamp(1, 1 << 30), child: Container(color: p.surface)),
          ]),
        ),
      ),
    );
  }
}
