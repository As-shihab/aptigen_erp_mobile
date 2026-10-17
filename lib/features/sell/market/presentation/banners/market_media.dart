import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/config/app_config.dart';
import '../../data/market_seller_service.dart';
import '../widgets/market_ui.dart';
import 'form_kit.dart';

// Media helpers for banners and the storefront: resolve the API's relative
// media paths (same convention as notification_model.dart's
// `_resolveMediaUrl`), show a cached image, and pick + upload a photo.

String? marketMediaUrl(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  if (url.startsWith('http') || url.startsWith('data:')) return url;
  return '${AppConfig.apiBase}${url.startsWith('/') ? '' : '/'}$url';
}

/// Cached network image with a flat placeholder; [fallback] when empty or broken.
class MarketNetImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final Widget? fallback;
  const MarketNetImage(this.url, {super.key, this.fit = BoxFit.cover, this.fallback});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final resolved = marketMediaUrl(url);
    final fb = fallback ?? Container(color: p.surface, child: Center(child: Icon(Icons.image_outlined, color: p.label)));
    if (resolved == null) return fb;
    return CachedNetworkImage(
      imageUrl: resolved,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      fadeInDuration: const Duration(milliseconds: 220),
      placeholder: (_, _) => Container(color: p.surface),
      errorWidget: (_, _, _) => fb,
    );
  }
}

/// Image slot: preview with change / remove, or an empty "add image" tile.
/// Picks from the gallery and uploads through [MarketSellerService.uploadMedia],
/// showing progress while it runs; reports the uploaded url via [onChanged].
class MediaPickTile extends StatefulWidget {
  final MarketSellerService service;
  final String? url;
  final double aspectRatio;
  final String emptyLabel;
  final ValueChanged<String?> onChanged;
  final ValueChanged<bool>? onBusy;
  const MediaPickTile({
    super.key,
    required this.service,
    required this.url,
    required this.onChanged,
    this.aspectRatio = 16 / 9,
    this.emptyLabel = 'Add image',
    this.onBusy,
  });

  @override
  State<MediaPickTile> createState() => _MediaPickTileState();
}

class _MediaPickTileState extends State<MediaPickTile> {
  final _picker = ImagePicker();
  bool _uploading = false;

  Future<void> _pick() async {
    if (_uploading) return;
    final XFile? file;
    try {
      file = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 2400, imageQuality: 88);
    } catch (_) {
      if (mounted) marketToast(context, 'Could not open the photo library', error: true);
      return;
    }
    if (file == null) return;
    setState(() => _uploading = true);
    widget.onBusy?.call(true);
    try {
      final bytes = await file.readAsBytes();
      final res = await widget.service.uploadMedia(bytes, file.name);
      widget.onChanged(res['url']?.toString());
    } catch (e) {
      if (mounted) marketToast(context, errorText(e, 'Upload failed'), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
      widget.onBusy?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final has = widget.url != null && widget.url!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Material(
          color: p.surface,
          child: InkWell(
            onTap: _pick,
            child: Stack(fit: StackFit.expand, children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: has
                    ? MarketNetImage(widget.url, key: ValueKey(widget.url))
                    : DecoratedBox(
                        key: const ValueKey('empty'),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.line, width: 1.2),
                        ),
                        child: Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.add_photo_alternate_outlined, color: p.brand, size: 26),
                            const SizedBox(height: 6),
                            Text(widget.emptyLabel, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.brand)),
                          ]),
                        ),
                      ),
              ),
              if (has && !_uploading)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Row(children: [
                    _RoundAction(icon: Icons.edit_outlined, tooltip: 'Change image', onTap: _pick),
                    const SizedBox(width: 6),
                    _RoundAction(icon: Icons.delete_outline, tooltip: 'Remove image', onTap: () => widget.onChanged(null)),
                  ]),
                ),
              if (_uploading)
                Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('Uploading…', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(minHeight: 4, color: Colors.white, backgroundColor: Colors.white24),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundAction({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.black.withValues(alpha: 0.55),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(7), child: Icon(icon, size: 16, color: Colors.white)),
          ),
        ),
      );
}
