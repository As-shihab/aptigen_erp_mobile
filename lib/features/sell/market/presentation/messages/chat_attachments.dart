import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/market_messages_service.dart';
import '../banners/market_media.dart';
import '../widgets/market_ui.dart';

// Chat attachments: the composer's tray of picked files, the attachment
// block inside a message (image grid, video tiles, file cards) and the
// full-screen image viewer.

/// "820 KB", "1.4 MB".
String formatFileSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
}

/// Icon + accent for a file card, by extension.
(IconData, Color) _fileVisual(String name, MarketPalette p) {
  switch (fileExtension(name)) {
    case 'pdf':
      return (Icons.picture_as_pdf_outlined, p.error);
    case 'doc':
    case 'docx':
    case 'txt':
      return (Icons.description_outlined, p.info);
    case 'xls':
    case 'xlsx':
    case 'csv':
      return (Icons.table_chart_outlined, p.ok);
    case 'ppt':
    case 'pptx':
      return (Icons.slideshow_outlined, p.warn);
    case 'zip':
    case 'rar':
      return (Icons.folder_zip_outlined, p.neutral);
    default:
      return (Icons.insert_drive_file_outlined, p.neutral);
  }
}

/// "PDF · 1.2 MB".
String _fileMeta(String name, int size) {
  final ext = fileExtension(name).toUpperCase();
  final s = formatFileSize(size);
  return [if (ext.isNotEmpty) ext, if (s.isNotEmpty) s].join(' · ');
}

/// Opens an uploaded attachment in the system's viewer / browser.
Future<void> openAttachmentExternally(BuildContext context, MarketAttachment a) async {
  final url = marketMediaUrl(a.url);
  final uri = url == null ? null : Uri.tryParse(url);
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context.mounted) marketToast(context, 'Could not open this file', error: true);
}

bool _looksLikeVideoUrl(String? url) {
  if (url == null) return false;
  final clean = url.split('?').first;
  return const {'mp4', 'mov', 'webm', 'm4v', '3gp', 'mkv', 'avi'}.contains(fileExtension(clean));
}

/// Thumbnail for an image (local or remote) or a video's server preview.
class _AttachmentThumb extends StatelessWidget {
  final MarketAttachment attachment;
  const _AttachmentThumb(this.attachment);

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final a = attachment;
    final videoFallback = Container(color: p.dark ? const Color(0xFF0B0F13) : const Color(0xFF1D2D3E));
    if (a.localPath != null) {
      if (a.isVideo) return videoFallback;
      return Image.file(
        File(a.localPath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 600,
        errorBuilder: (_, _, _) => Container(color: p.surface, child: Icon(Icons.broken_image_outlined, color: p.label)),
      );
    }
    if (a.isVideo) {
      final preview = a.previewUrl;
      if (preview == null || preview == a.url || _looksLikeVideoUrl(preview)) return videoFallback;
      return MarketNetImage(preview, fallback: videoFallback);
    }
    return MarketNetImage(a.previewUrl ?? a.url);
  }
}

// ── Composer tray ────────────────────────────────────────────────────────

/// Horizontal strip of picked files with a remove button on each.
class ChatAttachmentTray extends StatelessWidget {
  final List<MarketOutgoingFile> files;
  final ValueChanged<int> onRemove;
  const ChatAttachmentTray({super.key, required this.files, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: files.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = files[i];
          final Widget tile;
          if (f.kind == 'image') {
            tile = ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(width: 64, height: 64, child: _AttachmentThumb(f.toAttachment())),
            );
          } else {
            final (icon, accent) = f.kind == 'video' ? (Icons.play_circle_outline, p.brand) : _fileVisual(f.name, p);
            tile = Container(
              width: 168,
              height: 64,
              padding: const EdgeInsets.fromLTRB(10, 8, 26, 8),
              decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Icon(icon, size: 26, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.text)),
                    const SizedBox(height: 2),
                    Text(formatFileSize(f.size), style: TextStyle(fontSize: 11, color: p.label)),
                  ]),
                ),
              ]),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Stack(clipBehavior: Clip.none, children: [
              tile,
              Positioned(
                top: -4,
                right: -4,
                child: Material(
                  color: p.text,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onRemove(i),
                    child: Padding(padding: const EdgeInsets.all(3), child: Icon(Icons.close, size: 14, color: p.card)),
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}

// ── Message attachments ──────────────────────────────────────────────────

/// Images (grid), videos (tiles) and documents (cards) of one message.
/// While [pending], media shows a progress ring and nothing opens.
class ChatMessageAttachments extends StatelessWidget {
  final List<MarketAttachment> attachments;
  final bool pending;
  final double progress;
  final double maxWidth;
  const ChatMessageAttachments({super.key, required this.attachments, required this.maxWidth, this.pending = false, this.progress = 0});

  @override
  Widget build(BuildContext context) {
    final images = attachments.where((a) => a.isImage).toList();
    final videos = attachments.where((a) => a.isVideo).toList();
    final docs = attachments.where((a) => !a.isImage && !a.isVideo).toList();
    final width = maxWidth.clamp(160.0, 260.0);
    final children = <Widget>[
      if (images.isNotEmpty) _ImageGrid(images: images, width: width, pending: pending, progress: progress),
      for (final v in videos) _VideoTile(video: v, width: width, pending: pending, progress: progress),
      for (final d in docs) _FileCard(file: d, width: width, pending: pending, progress: progress),
    ];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < children.length; i++) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 4), child: children[i]),
    ]);
  }
}

class _UploadOverlay extends StatelessWidget {
  final double progress;
  const _UploadOverlay(this.progress);

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black.withValues(alpha: 0.35),
        alignment: Alignment.center,
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            value: progress > 0 && progress < 1 ? progress : null,
            color: Colors.white,
            backgroundColor: Colors.white24,
          ),
        ),
      );
}

class _ImageGrid extends StatelessWidget {
  final List<MarketAttachment> images;
  final double width;
  final bool pending;
  final double progress;
  const _ImageGrid({required this.images, required this.width, required this.pending, required this.progress});

  void _open(BuildContext context, int index) {
    if (pending || images.any((a) => a.localPath != null)) return;
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => ChatMediaViewer(images: images, initialIndex: index)));
  }

  Widget _cell(BuildContext context, int index, {int more = 0}) {
    return GestureDetector(
      onTap: () => _open(context, index),
      child: Stack(fit: StackFit.expand, children: [
        _AttachmentThumb(images[index]),
        if (more > 0)
          Container(
            color: Colors.black.withValues(alpha: 0.5),
            alignment: Alignment.center,
            child: Text('+$more', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final n = images.length;
    const gap = 3.0;
    Widget grid;
    if (n == 1) {
      grid = SizedBox(width: width, height: width * 0.75, child: _cell(context, 0));
    } else {
      final shown = n > 4 ? 4 : n;
      final cell = (width - gap) / 2;
      grid = SizedBox(
        width: width,
        child: Wrap(spacing: gap, runSpacing: gap, children: [
          for (var i = 0; i < shown; i++)
            SizedBox(
              // An odd last image spans the full width.
              width: shown == 3 && i == 2 ? width : cell,
              height: cell,
              child: _cell(context, i, more: i == 3 && n > 4 ? n - 4 : 0),
            ),
        ]),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(border: Border.all(color: p.line), borderRadius: BorderRadius.circular(14)),
        child: Stack(children: [
          grid,
          if (pending) Positioned.fill(child: _UploadOverlay(progress)),
        ]),
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  final MarketAttachment video;
  final double width;
  final bool pending;
  final double progress;
  const _VideoTile({required this.video, required this.width, required this.pending, required this.progress});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final meta = formatFileSize(video.size);
    return GestureDetector(
      onTap: pending || video.localPath != null ? null : () => openAttachmentExternally(context, video),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: width,
          height: width * 9 / 16,
          child: Stack(fit: StackFit.expand, children: [
            _AttachmentThumb(video),
            if (pending)
              _UploadOverlay(progress)
            else
              Center(
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, size: 30, color: Colors.white),
                ),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Row(children: [
                const Icon(Icons.videocam_outlined, size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(video.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600)),
                ),
                if (meta.isNotEmpty) Text(meta, style: const TextStyle(fontSize: 11, color: Colors.white70)),
              ]),
            ),
            DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: p.line), borderRadius: BorderRadius.circular(14)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final MarketAttachment file;
  final double width;
  final bool pending;
  final double progress;
  const _FileCard({required this.file, required this.width, required this.pending, required this.progress});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final (icon, accent) = _fileVisual(file.name, p);
    final meta = _fileMeta(file.name, file.size);
    return SizedBox(
      width: width,
      child: Material(
        color: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: pending || file.localPath != null ? null : () => openAttachmentExternally(context, file),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: accent.withValues(alpha: p.dark ? 0.18 : 0.12), borderRadius: BorderRadius.circular(9)),
                child: pending
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2, value: progress > 0 && progress < 1 ? progress : null, color: accent),
                      )
                    : Icon(icon, size: 21, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(meta, style: TextStyle(fontSize: 11.5, color: p.label)),
                  ],
                ]),
              ),
              if (!pending && file.localPath == null) ...[
                const SizedBox(width: 6),
                Icon(Icons.open_in_new, size: 16, color: p.label),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Full-screen viewer ───────────────────────────────────────────────────

/// Swipe between a message's images; pinch to zoom.
class ChatMediaViewer extends StatefulWidget {
  final List<MarketAttachment> images;
  final int initialIndex;
  const ChatMediaViewer({super.key, required this.images, this.initialIndex = 0});

  @override
  State<ChatMediaViewer> createState() => _ChatMediaViewerState();
}

class _ChatMediaViewerState extends State<ChatMediaViewer> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.images.length;
    final current = widget.images[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(n > 1 ? '${_index + 1} of $n' : current.name,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
        actions: [
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => openAttachmentExternally(context, current),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: n,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) {
          final a = widget.images[i];
          final url = marketMediaUrl(a.url ?? a.previewUrl);
          const broken = Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48);
          return InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: url == null
                  ? broken
                  : CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                      placeholder: (_, _) => const SizedBox(
                          width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                      errorWidget: (_, _, _) => broken,
                    ),
            ),
          );
        },
      ),
    );
  }
}
