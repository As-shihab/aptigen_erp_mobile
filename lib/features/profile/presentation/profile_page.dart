import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/ui/motion_kit.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/models/user_model.dart';
import 'billing_page.dart';
import 'edit_workplace_page.dart';
import 'invoices_page.dart';
import '../../seller_verification/presentation/seller_verification_page.dart';

/// Same visual format as D:\Mobile\aptigen's profile_page.dart (gradient
/// hero header, avatar, grouped settings list with icon+chevron rows,
/// outlined sign-out button) — minus the travel-app-specific stats
/// (Bookings/Wishlist/Reviews) and settings items (Wishlist, Booking
/// History, Language, Help & Support) that don't apply to this app.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _authService = AuthService(ApiClient());
  UserModel? _user;
  String? _avatarUrl;
  bool _loading = true;
  List<Map<String, dynamic>> _workplaces = const [];
  bool _workplacesLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = await _authService.getStoredUser();
    if (!mounted) return;
    setState(() {
      _user = user;
      _loading = false;
    });
    if (user != null) _loadAvatar(user.id);
    _loadWorkplaces();
  }

  // Every workplace this user owns or was added to, with relation and
  // edit permission (cloud's WorkplaceController.getMyWorkplaces).
  Future<void> _loadWorkplaces() async {
    try {
      final rows = await _authService.fetchMyWorkplaces();
      if (!mounted) return;
      setState(() => _workplaces = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _workplaces = const []);
    } finally {
      if (mounted) setState(() => _workplacesLoading = false);
    }
  }

  // Same source as erp/desktop's header avatar (AppHeaderBar.tsx): the
  // photo lives on this person's workplace_members row, not on `users`.
  Future<void> _loadAvatar(int userId) async {
    try {
      final res = await ApiClient().get('workplace_members?\$filter=user_id eq $userId&\$select=id,image_url&\$top=1');
      final rows = unwrapList(res);
      final raw = rows.isEmpty ? '' : ((rows.first as Map)['image_url'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() => _avatarUrl = raw.isEmpty
          ? null
          : (raw.startsWith('http') || raw.startsWith('data:')
              ? raw
              : '${AppConfig.apiBase}${raw.startsWith('/') ? '' : '/'}$raw'));
    } catch (_) {
      // Keep the initials avatar.
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Sign out', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text('Are you sure you want to sign out?', style: GoogleFonts.poppins()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: GoogleFonts.poppins())),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sign out', style: GoogleFonts.poppins(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (route) => false);
  }

  // Editable workplaces open the editor; others open a read-only view.
  Future<void> _openWorkplace(Map<String, dynamic> workplace) async {
    if (workplace['can_edit'] == true) {
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => EditWorkplacePage(workplace: workplace)));
      if (saved == true) _load();
    } else {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkplaceDetailsPage(workplace: workplace)));
    }
  }

  void _openBilling() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BillingPage()));
  }

  void _openSellerVerification() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SellerVerificationPage()));
  }

  void _openInvoices() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InvoicesPage()));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final top = MediaQuery.of(context).padding.top;

    if (_loading) {
      return Center(child: const CircularProgressIndicator(color: AppColors.brand));
    }

    return Container(
      color: isDark ? AppColors.pageDark : AppColors.pageLight,
      child: SingleChildScrollView(
        child: Column(
          children: [
            _ProfileHeader(user: _user, avatarUrl: _avatarUrl, isDark: isDark, top: top),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _WorkplacesSection(
                    workplaces: _workplaces,
                    loading: _workplacesLoading,
                    onOpen: _openWorkplace,
                  ),
                  const SizedBox(height: 16),
                  _SettingsSection(
                    title: 'Account',
                    isDark: isDark,
                    items: [
                      _SettingItem(Icons.credit_card_outlined, 'Billing', _openBilling),
                      _SettingItem(Icons.receipt_long_outlined, 'Invoices', _openInvoices),
                      _SettingItem(Icons.verified_user_outlined, 'Verify seller', _openSellerVerification),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _LogoutButton(onLogout: _logout),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final UserModel? user;
  final String? avatarUrl;
  final bool isDark;
  final double top;

  const _ProfileHeader({required this.user, required this.avatarUrl, required this.isDark, required this.top});

  @override
  Widget build(BuildContext context) {
    final initials = (user?.name ?? '').trim().isNotEmpty
        ? user!.name.trim().split(RegExp(r'\s+')).map((s) => s[0].toUpperCase()).take(2).join()
        : 'G';
    final initialsText = Text(
      initials,
      style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
    );

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF312E81)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, top + 20, 24, 28),
      child: Column(
        children: [
          Row(
            children: [
              // Only shown when this page was pushed as its own route (e.g.
              // the Home tab's module grid tile) — as the bottom-nav Profile
              // tab there's nothing to pop back to, so canPop is false and
              // this stays hidden, same as before.
              if (Navigator.canPop(context))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
                    ),
                  ),
                ),
              Text(
                'Profile',
                style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.brand, Color(0xFF4F46E5)]),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 3),
            ),
            child: ClipOval(
              child: avatarUrl == null
                  ? Center(child: initialsText)
                  : CachedNetworkImage(
                      imageUrl: avatarUrl!,
                      fit: BoxFit.cover,
                      width: 80,
                      height: 80,
                      fadeInDuration: const Duration(milliseconds: 200),
                      placeholder: (_, _) => Center(child: initialsText),
                      errorWidget: (_, _, _) => Center(child: initialsText),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            user?.name ?? 'Guest',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          if (user?.email != null && user!.email.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              user!.email,
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Every workplace the user belongs to — Owner/Member pill, current
/// marker, owner + location + currency, and an edit or lock affordance.
class _WorkplacesSection extends StatelessWidget {
  final List<Map<String, dynamic>> workplaces;
  final bool loading;
  final ValueChanged<Map<String, dynamic>> onOpen;

  const _WorkplacesSection({required this.workplaces, required this.loading, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 4),
          child: Row(children: [
            Expanded(
              child: Text('Workplaces', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate600)),
            ),
            if (!loading) StatusPill('${workplaces.length}'),
          ]),
        ),
        if (loading)
          const Column(children: [SkeletonBox(height: 68, radius: 12), SizedBox(height: 8), SkeletonBox(height: 68, radius: 12)])
        else if (workplaces.isEmpty)
          MarketCard(child: Text("You don't belong to any workplace yet.", style: TextStyle(fontSize: 13, color: p.label)))
        else
          ...workplaces.asMap().entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FadeSlideIn(index: entry.key, child: _WorkplaceRow(workplace: entry.value, onTap: () => onOpen(entry.value))),
              )),
      ],
    );
  }
}

class _WorkplaceRow extends StatelessWidget {
  final Map<String, dynamic> workplace;
  final VoidCallback onTap;
  const _WorkplaceRow({required this.workplace, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final name = (workplace['name'] ?? '').toString();
    final code = (workplace['code'] ?? '').toString().trim();
    final isOwner = workplace['relation'] == 'owner';
    final isCurrent = workplace['is_current'] == true;
    final canEdit = workplace['can_edit'] == true;
    final owner = workplace['owner'] as Map?;
    final ownerName = (owner?['name'] ?? owner?['email'] ?? '').toString().trim();
    final meta = [
      if (ownerName.isNotEmpty) 'Owner: $ownerName',
      (workplace['location'] ?? '').toString().trim(),
      (workplace['currency'] ?? '').toString().trim(),
    ].where((s) => s.isNotEmpty).join(' · ');

    return MarketCard(
      onTap: onTap,
      color: isCurrent ? p.brandSoft : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        InitialsAvatar(name, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
              ),
              if (code.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text('#$code', style: TextStyle(fontSize: 11, color: p.label)),
              ],
            ]),
            const SizedBox(height: 5),
            Wrap(spacing: 6, runSpacing: 4, children: [
              StatusPill(isOwner ? 'Owner' : 'Member', tone: isOwner ? MarketTone.info : MarketTone.neutral, icon: isOwner ? Icons.workspace_premium_outlined : null),
              if (isCurrent) const StatusPill('Current', tone: MarketTone.ok, icon: Icons.check_circle_outline),
            ]),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        Icon(canEdit ? Icons.edit_outlined : Icons.lock_outline, size: 18, color: canEdit ? p.brand : p.label),
      ]),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final bool isDark;
  final List<_SettingItem> items;

  const _SettingsSection({required this.title, required this.isDark, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 4),
          child: Text(
            title,
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate600),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.slate400.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final isLast = entry.key == items.length - 1;
              return Column(
                children: [
                  _SettingRow(item: entry.value, isDark: isDark, index: entry.key),
                  if (!isLast) Divider(height: 1, indent: 54, color: AppColors.slate400.withValues(alpha: 0.2)),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _SettingItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SettingItem(this.icon, this.label, this.onTap);
}

class _SettingRow extends StatelessWidget {
  final _SettingItem item;
  final bool isDark;
  final int index;
  const _SettingRow({required this.item, required this.isDark, this.index = 0});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              AccentListIcon(item.icon, index: index, size: 34),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  item.label,
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: isDark ? Colors.white : AppColors.slate900),
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.slate400),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  final VoidCallback onLogout;
  const _LogoutButton({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onLogout,
        icon: const Icon(Icons.logout_rounded, color: AppColors.error),
        label: Text('Sign out', style: GoogleFonts.poppins(color: AppColors.error, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.error, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
