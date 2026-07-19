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

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
    _restore();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final authService = AuthService(ApiClient());
    final loggedIn = await authService.isLoggedIn();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(loggedIn ? '/launcher' : '/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.slate900 : AppColors.slate50,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _PulseRing(controller: _pulseController, delay: 0.0),
                  _PulseRing(controller: _pulseController, delay: 0.33),
                  _PulseRing(controller: _pulseController, delay: 0.66),
                  const SizedBox(
                    width: 96,
                    height: 96,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.brand),
                  ),
                  Container(
                    width: 74,
                    height: 74,
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF12161F) : Colors.white,
                      boxShadow: [BoxShadow(color: AppColors.brand.withValues(alpha: 0.25), blurRadius: 18, spreadRadius: 1)],
                    ),
                    child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.contain),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Text('Aptigen ERP', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
            const SizedBox(height: 6),
            Text('Connecting workspace…', style: TextStyle(color: AppColors.slate600, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// One ring of a staggered "neural link" ping — three of these, phase-offset
/// by a third of the cycle, expand out from the logo and fade as they grow,
/// like a signal pulsing outward.
class _PulseRing extends StatelessWidget {
  final AnimationController controller;
  final double delay;
  const _PulseRing({required this.controller, required this.delay});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = (controller.value + delay) % 1.0;
        final scale = 0.6 + t * 0.9;
        final opacity = (1 - t).clamp(0.0, 1.0) * 0.55;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.brand, width: 1.6)),
            ),
          ),
        );
      },
    );
  }
}
