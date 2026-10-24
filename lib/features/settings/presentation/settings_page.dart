import 'package:flutter/material.dart';
import '../../../core/theme/theme_controller.dart';
import '../../sell/market/presentation/widgets/market_ui.dart';
import 'approver_chain/approver_chain_pages.dart';
import 'audit/audit_logs_page.dart';
import 'device_requests/device_requests_page.dart';
import 'devices/device_hub_page.dart';
import 'media/media_library_page.dart';
import 'notifications/notification_settings_page.dart';
import 'printers/printers_list_page.dart';
import 'roles/role_permission_page.dart';
import 'update_data/update_data_page.dart';
import 'users/user_list_page.dart';

/// Settings tab — theme (with a live preview card per mode), then every
/// desktop settings area: people and access, activity, workplace tools and
/// this app.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return ColoredBox(
      color: p.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const _SectionTitle('Theme'),
          MarketCard(
            padding: const EdgeInsets.all(12),
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: AppController.themeMode,
              builder: (context, mode, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  for (final m in const [ThemeMode.light, ThemeMode.dark, ThemeMode.system]) ...[
                    if (m != ThemeMode.light) const SizedBox(width: 10),
                    Expanded(
                      child: _ThemeOption(mode: m, selected: mode == m, onTap: () => AppController.setThemeMode(m)),
                    ),
                  ],
                ]),
                const SizedBox(height: 10),
                Text(
                  switch (mode) {
                    ThemeMode.light => 'Always light, whatever your phone uses.',
                    ThemeMode.dark => 'Always dark — easier on the eyes at night.',
                    ThemeMode.system => 'Follows your phone\'s light or dark setting.',
                  },
                  style: TextStyle(fontSize: 12, color: p.label),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 22),
          const _SectionTitle('People and access'),
          _NavGroup(rows: [
            _NavRow(icon: Icons.people_alt_outlined, tone: MarketTone.brand, title: 'User list', subtitle: 'Users, roles and access to this workplace', onTap: () => _open(context, const UserListPage())),
            _NavRow(icon: Icons.admin_panel_settings_outlined, tone: MarketTone.info, title: 'Role permission', subtitle: 'What each role can see and do', onTap: () => _open(context, const RolePermissionPage())),
            _NavRow(icon: Icons.link_rounded, tone: MarketTone.neutral, title: 'Approver chain', subtitle: 'Approval steps for requests', onTap: () => _open(context, const ApproveTypesPage())),
            _NavRow(icon: Icons.verified_user_outlined, tone: MarketTone.warn, title: 'Device request', subtitle: 'Approve or reject device sign-ins', onTap: () => _open(context, const DeviceRequestsPage())),
          ]),
          const SizedBox(height: 22),
          const _SectionTitle('Activity'),
          _NavGroup(rows: [
            _NavRow(icon: Icons.history_rounded, tone: MarketTone.neutral, title: 'Audit logs', subtitle: 'Who changed what, and when', onTap: () => _open(context, const AuditLogsPage())),
            _NavRow(icon: Icons.notifications_none_rounded, tone: MarketTone.info, title: 'Notifications', subtitle: 'Push and email preferences', onTap: () => _open(context, const NotificationSettingsPage())),
          ]),
          const SizedBox(height: 22),
          const _SectionTitle('Workplace'),
          _NavGroup(rows: [
            _NavRow(icon: Icons.perm_media_outlined, tone: MarketTone.info, title: 'Media', subtitle: 'Photos and files used across products, listings and banners', onTap: () => _open(context, const MediaLibraryPage())),
            _NavRow(icon: Icons.print_outlined, tone: MarketTone.brand, title: 'Printers', subtitle: 'Receipt printers for the point of sale', onTap: () => _open(context, const PrintersListPage())),
            _NavRow(icon: Icons.router_outlined, tone: MarketTone.ok, title: 'Device', subtitle: 'Fingerprint devices, sensors and switches', onTap: () => _open(context, const DeviceHubPage())),
          ]),
          const SizedBox(height: 22),
          const _SectionTitle('This app'),
          _NavGroup(rows: [
            _NavRow(icon: Icons.sync_rounded, tone: MarketTone.neutral, title: 'Update and data', subtitle: 'Version, cache and local data', onTap: () => _open(context, const UpdateDataPage())),
          ]),
        ],
      ),
    );
  }
}

void _open(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

/// One card of navigation rows separated by hairlines.
class _NavGroup extends StatelessWidget {
  final List<_NavRow> rows;
  const _NavGroup({required this.rows});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 62, color: p.line),
          rows[i],
        ],
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.label)),
    );
  }
}

/// One theme choice: a miniature screen in that theme, its name, and a
/// check when selected. "System" shows half light, half dark.
class _ThemeOption extends StatelessWidget {
  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeOption({required this.mode, required this.selected, required this.onTap});

  static const _light = (bg: Color(0xFFF5F6F7), card: Colors.white, line: Color(0xFFE5E8EB), bar: Color(0xFFD5DADD));
  static const _dark = (bg: Color(0xFF12171C), card: Color(0xFF1D232A), line: Color(0xFF34404B), bar: Color(0xFF3A4651));

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final label = switch (mode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'System',
    };
    Widget screen(({Color bg, Color card, Color line, Color bar}) c) => Container(
          color: c.bg,
          padding: const EdgeInsets.all(6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 6, width: 26, decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(3))),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(5), border: Border.all(color: c.line)),
                padding: const EdgeInsets.all(5),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(height: 4, decoration: BoxDecoration(color: c.bar, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 4),
                  FractionallySizedBox(
                    widthFactor: 0.6,
                    child: Container(height: 4, decoration: BoxDecoration(color: c.bar, borderRadius: BorderRadius.circular(2))),
                  ),
                ]),
              ),
            ),
          ]),
        );

    return Semantics(
      button: true,
      selected: selected,
      label: '$label theme',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 86,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? p.brand : p.line, width: selected ? 2 : 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: switch (mode) {
                ThemeMode.light => screen(_light),
                ThemeMode.dark => screen(_dark),
                ThemeMode.system => Row(children: [
                    Expanded(child: screen(_light)),
                    Expanded(child: screen(_dark)),
                  ]),
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                key: ValueKey(selected),
                size: 16,
                color: selected ? p.brand : p.label,
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? p.brand : p.text),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final MarketTone tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _NavRow({required this.icon, required this.tone, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final c = p.tone(tone);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: c.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.3, color: p.label)),
            ]),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: p.label),
        ]),
      ),
    );
  }
}
