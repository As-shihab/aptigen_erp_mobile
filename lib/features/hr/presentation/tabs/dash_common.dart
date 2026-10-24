import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/employee_dashboard_service.dart';

// Shared plumbing for the employee dashboard sections. Each section is a
// widget that builds slivers (so the whole dashboard is one scroll view
// with a collapsing hero) and reloads whenever the page bumps
// [DashSection.refreshToken] (pull-to-refresh).

abstract class DashSection extends StatefulWidget {
  final int employeeId;
  final int refreshToken;
  const DashSection({super.key, required this.employeeId, this.refreshToken = 0});
}

mixin DashLoader<T extends DashSection> on State<T> {
  final service = EmployeeDashboardService(ApiClient());
  bool loading = true;
  String? error;

  /// Fetch and assign state; throw on failure.
  Future<void> fetch();

  Future<void> reload() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await fetch();
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e, 'Could not load this section'));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken || oldWidget.employeeId != widget.employeeId) reload();
  }

  /// Loading skeleton / error-with-retry sliver, or null when content is ready.
  Widget? stateSliver({int skeletons = 5, double height = 78}) {
    if (loading) return sliverSkeleton(count: skeletons, height: height);
    if (error != null) {
      return sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Something went wrong', message: error, actionLabel: 'Retry', onAction: reload);
    }
    return null;
  }
}

int asInt(dynamic v) => int.tryParse('${v ?? ''}') ?? 0;

String stripHtml(String? html) => (html ?? '').replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll('&nbsp;', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

String fullName(Map? m) => [m?['first_name'], m?['last_name']].where((s) => s != null && '$s'.trim().isNotEmpty).join(' ');

String hoursLabel(Duration d) => d.isNegative ? '0h 0m' : '${d.inHours}h ${d.inMinutes.remainder(60)}m';

/// Two-cell summary chip row used at the top of sections.
class MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final num value;
  final String Function(num v)? format;
  final MarketTone tone;
  const MiniStat({super.key, required this.icon, required this.label, required this.value, this.format, this.tone = MarketTone.brand});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final t = p.tone(tone);
    return GlowCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, size: 18, color: t.fg),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CountUp(
              value: value,
              format: format ?? (v) => '${v.round()}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.text),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.label)),
          ]),
        ),
      ]),
    );
  }
}

/// Grid of [MiniStat]s as a sliver.
Widget sliverStats(List<Widget> stats) => SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      sliver: SliverGrid.count(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.35,
        children: [for (var i = 0; i < stats.length; i++) FadeSlideIn(index: i, child: stats[i])],
      ),
    );
