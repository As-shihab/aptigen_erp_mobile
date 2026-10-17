import 'package:flutter/material.dart';
import '../data/market_seller_service.dart';
import 'banners/banner_card.dart';
import 'banners/banner_editor_sheet.dart';
import 'banners/banner_meta.dart';
import 'banners/form_kit.dart';
import 'widgets/market_ui.dart';

/// Store banners on the public market (OData market_banners) — desktop's
/// Banners.tsx + CreateBanner.tsx. Every change goes to platform approval.
class MarketBannersPage extends StatefulWidget {
  const MarketBannersPage({super.key});

  @override
  State<MarketBannersPage> createState() => _MarketBannersPageState();
}

class _MarketBannersPageState extends State<MarketBannersPage> {
  final _svc = MarketSellerService();
  List<Map<String, dynamic>> _rows = [];
  int? _profileId;
  String _placement = 'hero';
  bool _loading = true;
  String? _error;
  final Set<int> _toggling = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait([_svc.banners(), _svc.storefront(create: true)]);
      if (!mounted) return;
      final profile = res[1] as Map<String, dynamic>?;
      setState(() {
        _rows = res[0] as List<Map<String, dynamic>>;
        _profileId = profile?['id'] == null ? null : toInt(profile!['id']);
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e, 'Could not load banners');
      });
    }
  }

  Future<void> _open({Map<String, dynamic>? row}) async {
    final saved = await showBannerEditor(context, _svc, row: row, placement: _placement, creatorProfileId: _profileId);
    if (saved) await _load();
  }

  Future<void> _toggle(Map<String, dynamic> b, bool on) async {
    final id = toInt(b['id']);
    setState(() {
      _toggling.add(id);
      b['is_active'] = on;
    });
    try {
      await _svc.saveBanner(bannerBody({...b, 'is_active': on}), id: id);
    } catch (e) {
      if (mounted) {
        setState(() => b['is_active'] = !on);
        marketToast(context, errorText(e, 'Could not update the banner'), error: true);
      }
    } finally {
      if (mounted) setState(() => _toggling.remove(id));
    }
  }

  Future<void> _delete(Map<String, dynamic> b) async {
    final ok = await confirmMarket(context, title: 'Delete banner', message: 'Delete "${b['title'] ?? 'this banner'}"? This can\'t be undone.');
    if (!ok || !mounted) return;
    try {
      await _svc.deleteBanner(toInt(b['id']));
      if (!mounted) return;
      setState(() => _rows.removeWhere((r) => r['id'] == b['id']));
      marketToast(context, 'Banner deleted');
    } catch (e) {
      if (mounted) marketToast(context, errorText(e, 'Could not delete the banner'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MarketScaffold(
      title: 'Banners',
      subtitle: 'Promote your store on the market home page',
      fab: _loading || _error != null
          ? null
          : FloatingActionButton.extended(onPressed: () => _open(), icon: const Icon(Icons.add), label: const Text('New banner')),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: _loading
            ? const SkeletonList(key: ValueKey('s'), count: 3, itemHeight: 220)
            : _error != null
                ? Center(
                    key: const ValueKey('e'),
                    child: MarketEmpty(
                      icon: Icons.cloud_off_outlined,
                      title: 'Could not load banners',
                      message: _error,
                      actionLabel: 'Try again',
                      onAction: () {
                        setState(() => _loading = true);
                        _load();
                      },
                    ),
                  )
                : _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final p = MarketPalette.of(context);
    final items = _rows.where((r) => (r['placement'] ?? 'hero') == _placement).toList()
      ..sort((a, b) => toInt(a['sort_order']).compareTo(toInt(b['sort_order'])));
    final pending = _rows.where((r) => (r['approval_status'] ?? 'pending') == 'pending').length;
    final pl = bannerPlacement(_placement);

    return Column(key: const ValueKey('c'), children: [
      Container(
        color: p.card,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MarketSegmented<String>(
            value: _placement,
            options: [
              for (final o in bannerPlacements)
                (id: o.id, label: o.segment, count: _rows.where((r) => (r['placement'] ?? 'hero') == o.id).length),
            ],
            onChanged: (v) => setState(() => _placement = v),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.verified_user_outlined, size: 15, color: p.label),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                pending > 0
                    ? 'Changes go to platform approval · $pending awaiting review'
                    : 'Changes go to platform approval before they show',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: p.label),
              ),
            ),
          ]),
        ]),
      ),
      Divider(height: 1, color: p.line),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: items.isEmpty
                ? ListView(
                    key: ValueKey('empty$_placement'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      MarketEmpty(
                        icon: pl.icon,
                        title: 'No ${pl.segment.toLowerCase()} banners yet',
                        message: pl.desc,
                        actionLabel: 'New banner',
                        onAction: () => _open(),
                      ),
                    ],
                  )
                : ListView.separated(
                    key: ValueKey('list$_placement'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => FadeSlideIn(
                      key: ValueKey('b${items[i]['id']}'),
                      index: i,
                      child: BannerCard(
                        row: items[i],
                        busy: _toggling.contains(toInt(items[i]['id'])),
                        onToggle: (v) => _toggle(items[i], v),
                        onEdit: () => _open(row: items[i]),
                        onDelete: () => _delete(items[i]),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    ]);
  }
}
