import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'fingerprint_page.dart';

/// Face recognition — erp/desktop hrm/face-recognition/FaceRecognition.tsx is
/// still a placeholder page (static copy, no backend: there is no face
/// enrollment model or API yet). Mobile shows an honest "coming soon" state
/// with the planned capabilities, plus the real numbers that already exist:
/// active employees who would need a face capture and the attendance
/// devices registered to this workplace.
class FaceRecognitionPage extends StatefulWidget {
  const FaceRecognitionPage({super.key});

  @override
  State<FaceRecognitionPage> createState() => _FaceRecognitionPageState();
}

class _FaceRecognitionPageState extends State<FaceRecognitionPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  int _employees = 0;
  int _devices = 0;
  int _online = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await batchLoad(_client, {
        'employees': 'employees?\$select=id&\$filter=${Uri.encodeComponent('is_active eq true')}&\$top=5000',
        'devices': 'devices?\$select=id,is_online&\$top=500',
      });
      if (!mounted) return;
      setState(() {
        _employees = data['employees']?.length ?? 0;
        final d = data['devices'] ?? [];
        _devices = d.length;
        _online = d.where((x) => asBool(x['is_online'])).length;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load workplace numbers'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _panels = [
    (
      icon: Icons.face_retouching_natural_outlined,
      accent: Accent.ocean,
      title: 'Enrollment',
      items: ['Capture employee face data', 'Link to identity record', 'Store device mapping'],
    ),
    (
      icon: Icons.verified_user_outlined,
      accent: Accent.ocean,
      title: 'Verification',
      items: ['Show current enrollment state', 'Surface sync issues', 'Flag duplicate attempts'],
    ),
    (
      icon: Icons.fact_check_outlined,
      accent: Accent.emerald,
      title: 'Attendance link',
      items: ['Biometric check-in handoff', 'Device activity log', 'Supervisor exception review'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MotionScaffold(
      title: 'Face recognition',
      subtitle: 'Biometric identity for attendance',
      icon: Icons.face_retouching_natural_outlined,
      accent: Accent.ocean,
      onRefresh: _load,
      slivers: [
        sliverBox(
          FadeSlideIn(
            child: GlowCard(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
              child: Column(children: [
                const _FaceScanner(),
                const SizedBox(height: 18),
                Text('Coming soon', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: p.text)),
                const SizedBox(height: 6),
                Text(
                  'Face enrollment is not available yet. Until it ships, employees can check in with fingerprint devices or the punch button on their dashboard.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: p.label, height: 1.4),
                ),
                const SizedBox(height: 16),
                GradientButton(
                  label: 'Open fingerprint',
                  icon: Icons.fingerprint_rounded,
                  accent: Accent.ocean,
                  onTap: () => pushMotion(context, const FingerprintPage()),
                ),
              ]),
            ),
          ),
        ),
        if (_loading)
          sliverBox(const SkeletonBox(height: 118, radius: 12))
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else
          SliverPadding(
            padding: const EdgeInsets.only(top: 16),
            sliver: SliverToBoxAdapter(
              child: KpiGrid(children: [
                KpiTile(icon: Icons.people_alt_rounded, label: 'Awaiting capture', value: _employees, tone: MarketTone.brand),
                KpiTile(icon: Icons.router_rounded, label: 'Devices', value: _devices, tone: MarketTone.brand),
                KpiTile(icon: Icons.wifi_tethering_rounded, label: 'Online now', value: _online, tone: MarketTone.ok),
              ]),
            ),
          ),
        sliverBox(const SectionHeader('What it will do', subtitle: 'Planned capabilities')),
        sliverStagger(
          count: _panels.length,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          builder: (_, i) {
            final panel = _panels[i];
            return GlowCard(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AccentIcon(panel.icon, accent: panel.accent),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(panel.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text))),
                      const StatusPill('Planned', tone: MarketTone.info),
                    ]),
                    const SizedBox(height: 8),
                    for (final item in panel.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(children: [
                          Icon(Icons.radio_button_unchecked_rounded, size: 14, color: panel.accent.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(item, style: TextStyle(fontSize: 12.5, color: p.label))),
                        ]),
                      ),
                  ]),
                ),
              ]),
            );
          },
        ),
      ],
    );
  }
}

/// Face outline with a sweeping scan line.
class _FaceScanner extends StatefulWidget {
  const _FaceScanner();

  @override
  State<_FaceScanner> createState() => _FaceScannerState();
}

class _FaceScannerState extends State<_FaceScanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Accent.ocean.colors;
    return SizedBox(
      width: 120,
      height: 120,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = Curves.easeInOut.transform(_c.value);
          return Stack(children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: colors.first.withValues(alpha: 0.1),
                border: Border.all(color: colors.first.withValues(alpha: 0.35), width: 1.5),
              ),
              child: Center(child: Icon(Icons.face_rounded, size: 64, color: colors.first.withValues(alpha: 0.85))),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 12 + 92 * t,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: colors.last,
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
