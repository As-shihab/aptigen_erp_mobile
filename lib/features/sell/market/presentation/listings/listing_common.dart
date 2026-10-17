import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../../core/config/app_config.dart';
import '../widgets/market_ui.dart';

// Shared helpers for the listings screens (card, detail sheet, form) —
// mirrors erp/desktop's ListingList.tsx helpers (listingCover, isVideo,
// LISTING_STATUS / APPROVAL maps).

/// Media URLs from the API may be relative ("/uploads/…") — same rule as
/// media_library_item.dart / desktop's LazyImage `resolveMediaUrl`.
String resolveMediaUrl(String url) {
  if (url.isEmpty) return url;
  if (url.startsWith('http') || url.startsWith('data:')) return url;
  return '${AppConfig.apiBase}${url.startsWith('/') ? '' : '/'}$url';
}

final _videoExt = RegExp(r'\.(mp4|webm|mov|m4v|ogv|ogg|mkv)(\?|#|$)', caseSensitive: false);

bool isVideoUrl(String url) => _videoExt.hasMatch(url);
bool isVideoMedia(Map m) => m['type'] == 'video' || isVideoUrl('${m['url'] ?? ''}');

List<Map<String, dynamic>> listingMedias(Map<String, dynamic> row) {
  final list = row['medias'] is List
      ? (row['medias'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : <Map<String, dynamic>>[];
  list.sort((a, b) => toInt(a['position']).compareTo(toInt(b['position'])));
  return list;
}

/// Cover photo: thumbnail unless it's a video, else the first photo.
String? listingCover(Map<String, dynamic> row) {
  final medias = listingMedias(row);
  final thumb = (row['thumbnail_url'] ?? '').toString();
  if (thumb.isNotEmpty && !isVideoUrl(thumb) && !medias.any((m) => isVideoMedia(m) && m['url'] == thumb)) return thumb;
  for (final m in medias) {
    if (!isVideoMedia(m) && '${m['url'] ?? ''}'.isNotEmpty) return '${m['url']}';
  }
  return null;
}

int listingVideoCount(Map<String, dynamic> row) => listingMedias(row).where(isVideoMedia).length;

const listingStatusLabels = {
  'active': 'Active',
  'draft': 'Draft',
  'paused': 'Paused',
  'sold': 'Sold',
  'expired': 'Expired',
};

MarketTone listingStatusTone(String? s) => switch (s) {
      'active' => MarketTone.ok,
      'paused' => MarketTone.warn,
      'sold' => MarketTone.info,
      'expired' => MarketTone.error,
      _ => MarketTone.neutral,
    };

const approvalLabels = {'approved': 'Approved', 'pending': 'Awaiting approval', 'rejected': 'Rejected'};

MarketTone approvalTone(String? s) => switch (s) {
      'approved' => MarketTone.ok,
      'rejected' => MarketTone.error,
      _ => MarketTone.warn,
    };

const conditionLabels = {'new': 'New', 'used': 'Used', 'refurbished': 'Refurbished'};
const listingTypeLabels = {'fixed': 'Fixed price', 'negotiable': 'Negotiable', 'auction': 'Auction'};

String sentenceCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

/// Is the platform moderation pipeline still working on this listing?
bool listingProcessing(Map<String, dynamic> row) =>
    (row['approval_status'] ?? 'pending') == 'pending' && const ['queued', 'processing'].contains(row['moderation_state']);

String fmtCount(num v) {
  final s = v.round().toString();
  return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

/// Conversion = orders ÷ unique views, in percent.
double conversionOf(Map<String, dynamic>? s) {
  if (s == null) return 0;
  final u = toDouble(s['unique_views']);
  return u > 0 ? toDouble(s['orders']) / u * 100 : 0;
}

/// Network image with the market placeholder / error look.
class MarketNetImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final double iconSize;
  const MarketNetImage(this.url, {super.key, this.fit = BoxFit.cover, this.iconSize = 26});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    Widget ph(IconData i) => Container(
          color: p.surface,
          alignment: Alignment.center,
          child: Icon(i, size: iconSize, color: p.label),
        );
    final u = url;
    if (u == null || u.isEmpty) return ph(Icons.image_not_supported_outlined);
    if (isVideoUrl(u)) return ph(Icons.videocam_outlined);
    return CachedNetworkImage(
      imageUrl: resolveMediaUrl(u),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, _) => Container(color: p.surface),
      errorWidget: (_, _, _) => ph(Icons.broken_image_outlined),
    );
  }
}
