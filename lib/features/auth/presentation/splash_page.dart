import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_service.dart';

/// Restores a stored session on launch, mirroring WelcomeScreen.tsx's
/// restoreAuthorizedSession — skips straight to the launcher when a token
/// and a workplace-scoped user are already present.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final authService = AuthService(ApiClient());
    final loggedIn = await authService.isLoggedIn();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(loggedIn ? '/launcher' : '/welcome');
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: AppColors.brand),
      ),
    );
  }
}
