import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/network/socket_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../shared/widgets/aptigen_shell_header.dart';
import '../../auth/data/auth_service.dart';
import '../../market/presentation/market_page.dart';
import '../../modules/presentation/module_launcher_page.dart';
import '../../notifications/data/notifications_service.dart';
import '../../notifications/presentation/notifications_page.dart';
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
  int _currentIndex = 0;
  String _workplaceName = 'Aptigen ERP';
  int _unreadNotifications = 0;
  final _notificationsService = NotificationsService(ApiClient());

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
    _loadUnreadCount();
    // Belt-and-suspenders alongside _SessionGate's own refresh (app.dart) —
    // cheap to re-check here too, so this shell never renders currency-
    // dependent screens (Store/Sell) against a stale in-memory value.
    WorkplaceCurrency.refresh(ApiClient());
  }

  @override
  void dispose() {
    AppSocket.instance?.off('notification:created', _onNotificationCreated);
    super.dispose();
  }

  Future<void> _loadWorkplaceName() async {
    final user = await AuthService(ApiClient()).getStoredUser();
    if (!mounted) return;
    setState(() => _workplaceName = user?.companyName ?? 'Aptigen ERP');
  }

  Future<void> _connectRealtime() async {
    final context = await resolveSocketContext(ApiClient());
    if (context == null) return;
    AppSocket.connect(context);
    AppSocket.instance?.on('notification:created', _onNotificationCreated);
  }

  void _onNotificationCreated(dynamic _) {
    if (!mounted) return;
    setState(() => _unreadNotifications += 1);
  }

  Future<void> _loadUnreadCount() async {
    try {
      final result = await _notificationsService.list(unreadOnly: true, top: 1);
      if (!mounted) return;
      setState(() => _unreadNotifications = result.unreadCount);
    } catch (_) {
      // Header just shows no badge — the notifications page itself will
      // surface a real error if the user opens it.
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsPage()));
    _loadUnreadCount();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AptigenShellHeader(
        workplaceName: _workplaceName,
        onNotificationsTap: () => _openNotifications(),
        unreadNotifications: _unreadNotifications,
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
