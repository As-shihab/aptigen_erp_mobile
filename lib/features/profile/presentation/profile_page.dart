import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/models/user_model.dart';

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
  bool _loading = true;

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

  void _showThemePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _ThemePicker(),
    );
  }

  void _showWorkplaceInfo() {
    final workplace = _user?.selectedWorkplace;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Workplace', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(workplace?.name ?? 'No workplace selected', style: GoogleFonts.poppins()),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final top = MediaQuery.of(context).padding.top;

    if (_loading) {
      return Center(child: const CircularProgressIndicator(color: AppColors.brand));
    }

    return Container(
      color: isDark ? AppColors.slate900 : AppColors.slate50,
      child: SingleChildScrollView(
        child: Column(
          children: [
            _ProfileHeader(user: _user, isDark: isDark, top: top),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _SettingsSection(
                    title: 'Account',
                    isDark: isDark,
                    items: [
                      _SettingItem(Icons.apartment_outlined, 'Workplace', _showWorkplaceInfo),
                      _SettingItem(Icons.dark_mode_outlined, 'Appearance', _showThemePicker),
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
  final bool isDark;
  final double top;

  const _ProfileHeader({required this.user, required this.isDark, required this.top});

  @override
  Widget build(BuildContext context) {
    final initials = (user?.name ?? '').trim().isNotEmpty
        ? user!.name.trim().split(RegExp(r'\s+')).map((s) => s[0].toUpperCase()).take(2).join()
        : 'G';

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
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Profile',
              style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
            ),
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
            child: Center(
              child: Text(
                initials,
                style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
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
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate600, letterSpacing: 0.5),
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
                  _SettingRow(item: entry.value, isDark: isDark),
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
  const _SettingRow({required this.item, required this.isDark});

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
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(item.icon, color: AppColors.brand, size: 18),
              ),
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
        label: Text('Sign Out', style: GoogleFonts.poppins(color: AppColors.error, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.error, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const icons = {
      ThemeMode.light: Icons.light_mode_outlined,
      ThemeMode.dark: Icons.dark_mode_outlined,
      ThemeMode.system: Icons.brightness_auto_outlined,
    };
    const labels = {
      ThemeMode.light: 'Light',
      ThemeMode.dark: 'Dark',
      ThemeMode.system: 'System default',
    };

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Appearance',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: isDark ? Colors.white : AppColors.slate900),
          ),
          const SizedBox(height: 16),
          ...ThemeMode.values.map((mode) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icons[mode], color: isDark ? Colors.white : AppColors.slate900),
              title: Text(labels[mode]!, style: GoogleFonts.poppins(color: isDark ? Colors.white : AppColors.slate900)),
              onTap: () async {
                await AppController.setThemeMode(mode);
                if (context.mounted) Navigator.pop(context);
              },
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
