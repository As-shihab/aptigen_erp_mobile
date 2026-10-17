import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../data/market_seller_service.dart';
import 'banners/form_kit.dart';
import 'banners/market_media.dart';
import 'storefront/storefront_header.dart';
import 'storefront/storefront_widgets.dart';
import 'widgets/market_ui.dart';

/// The store's public identity on the market (OData creator_profiles, one
/// per workplace) — desktop's StorePage.tsx header + profile form.
class MarketStorefrontPage extends StatefulWidget {
  const MarketStorefrontPage({super.key});

  @override
  State<MarketStorefrontPage> createState() => _MarketStorefrontPageState();
}

/// Editable text columns of creator_profiles (only columns that exist).
const _textFields = [
  'store_name',
  'slug',
  'tagline',
  'bio',
  'phone',
  'email',
  'website',
  'address',
  'city',
  'state',
  'country',
  'postal_code',
  'business_type',
  'registration_no',
  'tax_id',
  'facebook_url',
  'instagram_url',
  'twitter_url',
];

class _MarketStorefrontPageState extends State<MarketStorefrontPage> {
  final _svc = MarketSellerService();
  final Map<String, TextEditingController> _c = {for (final f in _textFields) f: TextEditingController()};

  Map<String, dynamic>? _profile;
  String? _avatar;
  String? _cover;
  String? _accent;
  int? _listings;
  int? _activeListings;
  int? _followers;

  bool _loading = true;
  String? _error;
  bool _saving = false;
  bool _justSaved = false;
  int _uploads = 0;
  Timer? _savedTimer;

  @override
  void initState() {
    super.initState();
    for (final c in _c.values) {
      c.addListener(_onEdit);
    }
    _load();
  }

  @override
  void dispose() {
    _savedTimer?.cancel();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onEdit() {
    if (mounted) setState(() => _justSaved = false);
  }

  void _fill(Map<String, dynamic> p) {
    for (final f in _textFields) {
      _c[f]!.text = (p[f] ?? '').toString();
    }
    _avatar = orNull('${p['avatar_url'] ?? ''}');
    _cover = orNull('${p['banner_url'] ?? ''}');
    _accent = orNull('${p['accent_color'] ?? ''}');
  }

  Future<void> _load() async {
    try {
      final profile = await _svc.storefront(create: true);
      if (!mounted) return;
      if (profile == null) {
        setState(() {
          _loading = false;
          _error = 'Your store profile could not be created';
        });
        return;
      }
      _fill(profile);
      setState(() {
        _profile = profile;
        _justSaved = false;
        _error = null;
        _loading = false;
      });
      _loadStats(toInt(profile['id']));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e, 'Could not load your storefront');
      });
    }
  }

  /// Listing + follower counts in one $batch; failures just leave dashes.
  Future<void> _loadStats(int id) async {
    try {
      final res = await _svc.http.batch([
        BatchRequest(id: '1', method: 'GET', url: r'market_listings?$count=true&$top=0'),
        BatchRequest(id: '2', method: 'GET', url: r"market_listings?$filter=status eq 'active'&$count=true&$top=0"),
        BatchRequest(id: '3', method: 'GET', url: 'market_store_followers?\$filter=creator_profile_id eq $id&\$count=true&\$top=0'),
      ]);
      int? count(String k) {
        final c = unwrapBatchBody(res, k)?['@odata.count'];
        return c == null ? null : toInt(c);
      }

      if (!mounted) return;
      setState(() {
        _listings = count('1');
        _activeListings = count('2');
        _followers = count('3');
      });
    } catch (_) {}
  }

  bool get _dirty {
    final p = _profile;
    if (p == null) return false;
    for (final f in _textFields) {
      if (_c[f]!.text.trim() != (p[f] ?? '').toString().trim()) return true;
    }
    return _avatar != orNull('${p['avatar_url'] ?? ''}') ||
        _cover != orNull('${p['banner_url'] ?? ''}') ||
        _accent != orNull('${p['accent_color'] ?? ''}');
  }

  static String _slugify(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

  Future<void> _save() async {
    final p = _profile;
    if (p == null) return;
    if (_c['store_name']!.text.trim().isEmpty) {
      marketToast(context, 'Store name is required', error: true);
      return;
    }
    final email = _c['email']!.text.trim();
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      marketToast(context, 'Enter a valid email address', error: true);
      return;
    }
    final slug = _slugify(_c['slug']!.text);
    if (_c['slug']!.text != slug) _c['slug']!.text = slug;

    final body = <String, dynamic>{
      for (final f in _textFields) f: orNull(_c[f]!.text),
      'avatar_url': _avatar,
      'banner_url': _cover,
      'accent_color': _accent,
    };
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await _svc.saveStorefront(toInt(p['id']), body);
      if (!mounted) return;
      setState(() {
        _profile = {...p, ...body};
        _saving = false;
        _justSaved = true;
      });
      _savedTimer?.cancel();
      _savedTimer = Timer(const Duration(milliseconds: 2200), () {
        if (mounted) setState(() => _justSaved = false);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      marketToast(context, errorText(e, 'Could not save your storefront'), error: true);
    }
  }

  StoreLook _look({required bool live}) {
    final p = _profile ?? const {};
    String? v(String k) => live ? orNull(_c[k]!.text) : orNull('${p[k] ?? ''}');
    final city = [v('city'), v('country')].whereType<String>().join(', ');
    return StoreLook(
      name: v('store_name') ?? '',
      tagline: v('tagline'),
      avatarUrl: live ? _avatar : orNull('${p['avatar_url'] ?? ''}'),
      coverUrl: live ? _cover : orNull('${p['banner_url'] ?? ''}'),
      accent: live ? _accent : orNull('${p['accent_color'] ?? ''}'),
      city: city.isEmpty ? null : city,
      verified: p['is_verified'] == true,
      active: p['is_active'] != false,
    );
  }

  void _busy(bool b) {
    if (mounted) setState(() => _uploads = (_uploads + (b ? 1 : -1)).clamp(0, 9));
  }

  @override
  Widget build(BuildContext context) {
    return MarketScaffold(
      title: 'Storefront',
      subtitle: 'How your store appears on the market',
      bottom: _loading || _error != null ? null : _saveBar(context),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: _loading
            ? ListView(
                key: const ValueKey('s'),
                padding: const EdgeInsets.all(16),
                physics: const NeverScrollableScrollPhysics(),
                children: const [
                  SkeletonBox(height: 250, radius: 12),
                  SizedBox(height: 14),
                  SkeletonBox(height: 180, radius: 12),
                  SizedBox(height: 14),
                  SkeletonBox(height: 220, radius: 12),
                ],
              )
            : _error != null
                ? Center(
                    key: const ValueKey('e'),
                    child: MarketEmpty(
                      icon: Icons.storefront_outlined,
                      title: 'Could not load your storefront',
                      message: _error,
                      actionLabel: 'Try again',
                      onAction: () {
                        setState(() => _loading = true);
                        _load();
                      },
                    ),
                  )
                : RefreshIndicator(key: const ValueKey('f'), onRefresh: _load, child: _form(context)),
      ),
    );
  }

  Widget _saveBar(BuildContext context) {
    final p = MarketPalette.of(context);
    final dirty = _dirty;
    return Container(
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a), child: child),
              ),
              child: _justSaved
                  ? const Align(key: ValueKey('saved'), alignment: Alignment.centerLeft, child: SavedBadge())
                  : Text(
                      _uploads > 0 ? 'Uploading image…' : (dirty ? 'Unsaved changes' : 'All changes saved'),
                      key: ValueKey('t$dirty$_uploads'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: dirty ? p.warn : p.label, fontWeight: dirty ? FontWeight.w600 : FontWeight.w400),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: _saving || _uploads > 0 || !dirty ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check, size: 18),
              label: const Text('Save'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _field(String key, String label, {String? hint, IconData? icon, int lines = 1, TextInputType? type, String? help, bool required = false, TextCapitalization cap = TextCapitalization.sentences}) =>
      FieldBlock(
        label: label,
        required: required,
        help: help,
        child: MarketTextField(controller: _c[key]!, hint: hint, icon: icon, maxLines: lines, keyboardType: type, capitalization: cap),
      );

  Widget _form(BuildContext context) {
    var i = 0;
    Widget sec(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 14), child: FadeSlideIn(index: i++, child: w));
    const none = TextCapitalization.none;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        sec(StorefrontHeader(store: _look(live: false), listings: _listings, activeListings: _activeListings, followers: _followers)),
        sec(StorePreviewCard(store: _look(live: true))),
        sec(FormSection(title: 'Identity', icon: Icons.badge_outlined, subtitle: 'Name and story buyers see', children: [
          _field('store_name', 'Store name', required: true, hint: 'e.g. Rahim fashion house', cap: TextCapitalization.words),
          _field('slug', 'Store link', hint: 'rahim-fashion', cap: none, help: 'Lowercase letters, numbers and dashes. Must be unique on the market.'),
          _field('tagline', 'Tagline', hint: 'One line about what you sell'),
          _field('bio', 'About', lines: 5, hint: 'Tell buyers about your store'),
        ])),
        sec(FormSection(title: 'Look', icon: Icons.palette_outlined, subtitle: 'Logo, cover and accent colour', children: [
          FieldBlock(
            label: 'Cover image',
            help: 'Wide image, shown at the top of your store page.',
            child: MediaPickTile(
              service: _svc,
              url: _cover,
              aspectRatio: 3 / 1,
              emptyLabel: 'Add cover image',
              onBusy: _busy,
              onChanged: (u) => setState(() {
                _cover = u;
                _justSaved = false;
              }),
            ),
          ),
          FieldBlock(
            label: 'Logo',
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 120,
                child: MediaPickTile(
                  service: _svc,
                  url: _avatar,
                  aspectRatio: 1,
                  emptyLabel: 'Add logo',
                  onBusy: _busy,
                  onChanged: (u) => setState(() {
                    _avatar = u;
                    _justSaved = false;
                  }),
                ),
              ),
            ),
          ),
          FieldBlock(
            label: 'Accent colour',
            help: 'Used for buttons and highlights on your store page.',
            child: AccentPicker(
              value: _accent,
              onChanged: (v) => setState(() {
                _accent = v;
                _justSaved = false;
              }),
            ),
          ),
        ])),
        sec(FormSection(title: 'Contact', icon: Icons.call_outlined, children: [
          _field('phone', 'Phone', icon: Icons.phone_outlined, type: TextInputType.phone, hint: '01XXXXXXXXX'),
          _field('email', 'Email', icon: Icons.mail_outline, type: TextInputType.emailAddress, cap: none),
          _field('website', 'Website', icon: Icons.language, type: TextInputType.url, cap: none, hint: 'https://'),
        ])),
        sec(FormSection(title: 'Location', icon: Icons.place_outlined, children: [
          _field('address', 'Address', lines: 2),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _field('city', 'City', cap: TextCapitalization.words)),
            const SizedBox(width: 10),
            Expanded(child: _field('state', 'State or division', cap: TextCapitalization.words)),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _field('country', 'Country', cap: TextCapitalization.words)),
            const SizedBox(width: 10),
            Expanded(child: _field('postal_code', 'Postal code', type: TextInputType.number)),
          ]),
        ])),
        sec(FormSection(title: 'Social links', icon: Icons.link, children: [
          _field('facebook_url', 'Facebook', icon: Icons.facebook, type: TextInputType.url, cap: none, hint: 'https://facebook.com/…'),
          _field('instagram_url', 'Instagram', icon: Icons.camera_alt_outlined, type: TextInputType.url, cap: none, hint: 'https://instagram.com/…'),
          _field('twitter_url', 'X (Twitter)', icon: Icons.alternate_email, type: TextInputType.url, cap: none, hint: 'https://x.com/…'),
        ])),
        sec(FormSection(title: 'Business', icon: Icons.business_outlined, subtitle: 'Optional, helps with verification', children: [
          _field('business_type', 'Business type', hint: 'e.g. Retail'),
          _field('registration_no', 'Registration number', cap: none),
          _field('tax_id', 'Tax ID', cap: none),
        ])),
      ],
    );
  }
}
