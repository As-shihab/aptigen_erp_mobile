import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/network/socket_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/aptigen_shell_header.dart';
import '../../auth/data/auth_service.dart';
import '../../market/presentation/market_page.dart';
import '../../modules/presentation/module_launcher_page.dart';
import '../../profile/presentation/profile_page.dart';
import '../../settings/presentation/settings_page.dart';

/// Bottom-nav shell — Home / Settings / Market / Profile, with the
/// persistent SAP-style brand+workplace+Wi-Fi+notifications header.
class HomeShellPage extends StatefulWidget {
  const HomeShellPage({super.key});

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage> {
  final _authService = AuthService(ApiClient());
  int _currentIndex = 0;
  String _workplaceName = 'Aptigen ERP';

  static const _tabs = [
    HomeTab(),
    SettingsPage(),
    MarketPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _loadWorkplaceName();
    _connectRealtime();
  }

  Future<void> _loadWorkplaceName() async {
    final user = await _authService.getStoredUser();
    if (!mounted) return;
    setState(() => _workplaceName = user?.companyName ?? 'Aptigen ERP');
  }

  Future<void> _connectRealtime() async {
    final context = await resolveSocketContext(ApiClient());
    if (context == null) return;
    AppSocket.connect(context);
  }

  void _openNotifications() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none, size: 36, color: AppColors.slate400),
              const SizedBox(height: 12),
              const Text('No notifications yet.', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AptigenShellHeader(
        workplaceName: _workplaceName,
        onNotificationsTap: _openNotifications,
      ),
      body: IndexedStack(index: _currentIndex, children: _tabs),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF12161F) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08), blurRadius: 20, offset: const Offset(0, -6)),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              height: 60,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              indicatorColor: AppColors.brand.withValues(alpha: 0.15),
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  fontSize: 11,
                  fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
                  color: states.contains(WidgetState.selected) ? AppColors.brand : AppColors.slate600,
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) => setState(() => _currentIndex = index),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
                NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Market'),
                NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
