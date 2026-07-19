import 'package:flutter/material.dart';
import '../core/config/app_config.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../features/auth/presentation/splash_page.dart';
import '../features/auth/presentation/welcome_page.dart';
import '../features/modules/presentation/module_launcher_page.dart';

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
          initialRoute: '/splash',
          onGenerateRoute: (settings) {
            final builder = switch (settings.name) {
              '/splash' => (BuildContext _) => const SplashPage(),
              '/welcome' => (BuildContext _) => const WelcomePage(),
              '/launcher' => (BuildContext _) => const ModuleLauncherPage(),
              _ => (BuildContext _) => const SplashPage(),
            };
            return _FadeSlideRoute(builder: builder, settings: settings);
          },
        );
      },
    );
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
