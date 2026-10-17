import 'package:flutter/material.dart';
import '../core/config/app_config.dart';
import '../core/network/http_client.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../core/utils/currency.dart';
import '../features/auth/data/auth_service.dart';
import '../features/auth/presentation/welcome_page.dart';
import '../features/shell/presentation/home_shell_page.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class AptigenApp extends StatelessWidget {
  const AptigenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppController.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          home: const _SessionGate(),
          onGenerateRoute: (settings) {
            final builder = switch (settings.name) {
              '/welcome' => (BuildContext _) => const WelcomePage(),
              '/launcher' => (BuildContext _) => const HomeShellPage(),
              _ => (BuildContext _) => const WelcomePage(),
            };
            return _FadeSlideRoute(builder: builder, settings: settings);
          },
        );
      },
    );
  }
}

/// Decides Home vs Welcome directly — no dedicated splash screen. The
/// underlying restore (a couple of local storage reads, an optional
/// currency-refresh network call) is fast enough that there's nothing
/// worth showing a branded loading page for; a blank themed background for
/// the one frame it takes reads better than a logo+progress screen that
/// can only ever be in the way.
class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  bool? _loggedIn;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    var loggedIn = false;
    try {
      final authService = AuthService(ApiClient());
      final results = await Future.wait([
        authService.isLoggedIn(),
        WorkplaceCurrency.refresh(ApiClient()),
      ]);
      loggedIn = results[0] as bool;
    } catch (_) {
      loggedIn = false;
    }
    if (!mounted) return;
    setState(() => _loggedIn = loggedIn);
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = _loggedIn;
    if (loggedIn == null) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Scaffold(backgroundColor: isDark ? Colors.black : Colors.white);
    }
    return loggedIn ? const HomeShellPage() : const WelcomePage();
  }
}

class _FadeSlideRoute extends PageRouteBuilder {
  final WidgetBuilder builder;
  _FadeSlideRoute({required this.builder, required super.settings})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(curved),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 250),
        );
}
