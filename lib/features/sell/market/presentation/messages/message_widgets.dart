import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/market_messages_service.dart';
import '../banners/market_media.dart';
import '../widgets/market_ui.dart';

// Shared bits for the seller inbox and chat screens.

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

bool isSameChatDay(DateTime a, DateTime b) => _sameDay(a, b);

/// "3:05 pm" — lower-case meridiem, like desktop's moment `h:mm a`.
String chatClock(DateTime t) => DateFormat('h:mm a').format(t).toLowerCase();

/// Inbox row time: today → clock, yesterday, this week → weekday, else date.
String chatListTime(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  if (_sameDay(t, now)) return chatClock(t);
  if (_sameDay(t, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  final weekStart = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
  if (t.isAfter(weekStart)) return DateFormat('EEE').format(t);
  if (t.year == now.year) return DateFormat('d MMM').format(t);
  return DateFormat('d MMM y').format(t);
}

/// Day separator label inside a thread.
String chatDayLabel(DateTime t) {
  final now = DateTime.now();
  if (_sameDay(t, now)) return 'Today';
  if (_sameDay(t, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return t.year == now.year ? DateFormat('EEEE, d MMMM').format(t) : DateFormat('d MMMM y').format(t);
}

String chatListingPrice(MarketChatListing l) => l.price == null ? '' : money(l.price!, currency: (l.currency ?? '').isEmpty ? null : l.currency);

String chatInitials(String? name) {
  final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final a = parts.first.characters.first;
  final b = parts.length > 1 ? parts.last.characters.first : '';
  return (a + b).toUpperCase();
}

/// Round buyer avatar with an initials fallback.
class BuyerAvatar extends StatelessWidget {
  final MarketChatPerson person;
  final double size;
  const BuyerAvatar(this.person, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.infoBg, shape: BoxShape.circle),
      child: Text(chatInitials(person.name), style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: p.info)),
    );
    final url = marketMediaUrl(person.avatarUrl);
    if (url == null) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

/// Square product thumbnail with a package icon fallback.
class ListingThumb extends StatelessWidget {
  final MarketChatListing listing;
  final double size;
  const ListingThumb(this.listing, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: MarketNetImage(
          listing.thumbnailUrl,
          fallback: Container(color: p.surface, child: Icon(Icons.inventory_2_outlined, size: size * 0.45, color: p.label)),
        ),
      ),
    );
  }
}

/// Red count pill (99+ cap).
class UnreadBadge extends StatelessWidget {
  final int count;
  const UnreadBadge(this.count, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.error, borderRadius: BorderRadius.circular(10)),
      child: Text(count > 99 ? '99+' : '$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.card)),
    );
  }
}
