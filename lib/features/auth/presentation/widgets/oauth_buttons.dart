import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// "or continue with" + Google / Apple buttons — mirrors erp/desktop's
/// WelcomeScreen.tsx step-0 block (both sign-in and sign-up). Apple is
/// shown disabled ("coming soon") exactly like desktop.
class OAuthButtons extends StatelessWidget {
  final bool googleLoading;
  final bool disabled;
  final VoidCallback onGoogle;

  const OAuthButtons({super.key, required this.googleLoading, required this.disabled, required this.onGoogle});

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).dividerColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: dividerColor, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or continue with', style: TextStyle(fontSize: 12, color: AppColors.slate400)),
            ),
            Expanded(child: Divider(color: dividerColor, height: 1)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: disabled ? null : onGoogle,
              icon: googleLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const _GoogleMark(),
              label: const Text('Google'),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: 'Apple sign-in is coming soon',
              triggerMode: TooltipTriggerMode.tap,
              child: Opacity(
                opacity: 0.5,
                child: OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.apple, size: 18),
                  label: const Text('Apple'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The four-colour Google "G", drawn from the official 48×48 logo paths.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 18, height: 18, child: CustomPaint(painter: _GoogleMarkPainter()));
  }
}

class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    void fill(Color color, Path path) => canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);

    fill(const Color(0xFFEA4335), Path()
      ..moveTo(24, 9.5)
      ..cubicTo(27.54, 9.5, 30.71, 10.72, 33.21, 13.1)
      ..lineTo(40.06, 6.25)
      ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
      ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
      ..lineTo(10.54, 19.41)
      ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
      ..close());
    fill(const Color(0xFF4285F4), Path()
      ..moveTo(46.98, 24.55)
      ..cubicTo(46.98, 22.98, 46.83, 21.46, 46.6, 20)
      ..lineTo(24, 20)
      ..lineTo(24, 29.02)
      ..lineTo(36.94, 29.02)
      ..cubicTo(36.36, 31.98, 34.68, 34.5, 32.16, 36.2)
      ..lineTo(39.89, 42.2)
      ..cubicTo(44.4, 38.02, 46.98, 31.84, 46.98, 24.55)
      ..close());
    fill(const Color(0xFFFBBC05), Path()
      ..moveTo(10.53, 28.59)
      ..cubicTo(10.05, 27.14, 9.77, 25.6, 9.77, 24)
      ..cubicTo(9.77, 22.4, 10.04, 20.86, 10.53, 19.41)
      ..lineTo(2.55, 13.22)
      ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
      ..cubicTo(0, 27.88, 0.92, 31.54, 2.56, 34.78)
      ..lineTo(10.53, 28.59)
      ..close());
    fill(const Color(0xFF34A853), Path()
      ..moveTo(24, 48)
      ..cubicTo(30.48, 48, 35.93, 45.87, 39.89, 42.19)
      ..lineTo(32.16, 36.19)
      ..cubicTo(30.01, 37.64, 27.24, 38.49, 24, 38.49)
      ..cubicTo(17.74, 38.49, 12.43, 34.27, 10.53, 28.58)
      ..lineTo(2.55, 34.77)
      ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
      ..close());
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
