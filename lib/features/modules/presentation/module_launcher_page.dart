import 'package:flutter/material.dart';
import '../../../core/billing/paywall_state.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../accounting/presentation/accounting_home_page.dart';
import '../../billing/presentation/paywall_sheet.dart';
import '../../sell/market/presentation/widgets/market_ui.dart' show MarketPalette;
import '../../chat/presentation/chat_hub_page.dart';
import '../../../shared/ui/motion_kit.dart' show motionRoute;
import '../../hr/presentation/hr_hub_page.dart';
import '../../purchase/presentation/purchase_hub_page.dart';
import '../../jobs/presentation/jobs_list_page.dart';
import '../../market/presentation/market_page.dart';
import '../../note/presentation/note_page.dart';
import '../../notifications/data/module_unread_counts.dart';
import '../../sell/presentation/pos/pos_terminal_page.dart';
import '../../sell/presentation/sales_hub_page.dart';
import '../../stays/presentation/stays_list_page.dart';
import '../../store/presentation/store_home_page.dart';
import '../data/module_service.dart';
import '../models/module_model.dart';

/// The "Home" tab of the bottom-nav shell — the module launchpad grid.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _moduleService = ModuleService(ApiClient());

  bool _loading = true;
  String? _error;
  List<LaunchpadModule> _modules = [];

  @override
  void initState() {
    super.initState();
    // Fresh shell (login / workplace switch) — drop any previous scope's counts.
    ModuleUnreadCounts.clear();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Badges load alongside, independently — a failing/missing route just
    // means no badges, never a grid error.
    final badges = ModuleUnreadCounts.refresh();
    try {
      final results = await Future.wait([
        _moduleService.loadInstalledModules(),
        _moduleService.resolveAllowedModuleIds(),
      ]);
      final installedRows = results[0] as List<dynamic>;
      final allowedModuleIds = results[1] as Set<int>;
      if (!mounted) return;
      setState(() {
        _modules = buildLaunchpadModules(installedRows, allowedModuleIds);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load your modules. Pull to retry.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await badges;
  }

  /// Locked (paid but unpaid) modules open the subscription wall first;
  /// reads are never blocked on desktop, so the wall offers a view-only
  /// way in, and any write inside still hits the HTTP-level wall.
  void _onTileTap(LaunchpadModule module) {
    final block = PaywallState.blockForModuleCode(module.id);
    if (block == null) {
      _openModule(module);
      return;
    }
    showPaywallSheet(context, block, onViewOnly: () {
      if (mounted) _openModule(module);
    });
  }

  void _openModule(LaunchpadModule module) {
    if (module.id == 'chat') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChatHubPage()));
      return;
    }
    if (module.id == 'note') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotePage()));
      return;
    }
    if (module.id == 'market') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(appBar: AppBar(title: const Text('Market')), body: const MarketPage()),
      ));
      return;
    }
    if (module.id == 'aptigen') {
      // Only the Stays vertical is ported to mobile so far — erp/desktop's
      // aptigen module also covers a Market/services vertical, not
      // implemented here yet. (There's no live "Foods" vertical on
      // `frontend` either — its /foods page is a disconnected static mockup
      // with no backend, so it's deliberately not mirrored here.)
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StaysListPage()));
      return;
    }
    if (module.id == 'jobs') {
      // Read-only browse of this workplace's public job postings — mirrors
      // frontend's customer-facing /jobs page (same public API), no apply
      // flow (that stays a customer-only, unauthenticated-web action).
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JobsListPage()));
      return;
    }
    if (module.id == 'store') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StoreHomePage()));
      return;
    }
    if (module.id == 'sell') {
      // Sales home: today's numbers, quick actions (POS is one tap away via
      // its "New sale" button) and every Sales area.
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SalesHubPage()));
      return;
    }
    if (module.id == 'pharma') {
      // POS-first pass: the Pharma tile opens the same POS terminal in
      // pharma mode (pharma-flagged products/checkout/held bills), with a
      // trimmed menu down to Inventory + Sales — see PosTerminalPage's
      // `isPharma` flag. Full desktop parity (purchases/suppliers/
      // customers/expenses/reports/catalog as separate screens) is out of
      // scope for this pass.
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PosTerminalPage(isPharma: true)));
      return;
    }
    if (module.id == 'purchase') {
      Navigator.of(context).push(motionRoute(const PurchaseHubPage()));
      return;
    }
    if (module.id == 'accounting') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountingHomePage()));
      return;
    }
    if (!module.isHr) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${module.label} — coming soon')),
      );
      return;
    }

    Navigator.of(context).push(motionRoute(const HrHubPage()));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 12),
        itemCount: 9,
        itemBuilder: (_, _) => Container(
          decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(16)),
        ),
      );
    }

    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.error_outline, size: 40, color: AppColors.slate400),
          const SizedBox(height: 12),
          Center(child: Text(_error!, style: TextStyle(color: AppColors.slate600))),
        ],
      );
    }

    if (_modules.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.apps_outlined, size: 40, color: AppColors.slate400),
          const SizedBox(height: 12),
          Center(child: Text('No modules installed yet.', style: TextStyle(color: AppColors.slate600))),
        ],
      );
    }

    // Rebuilds tiles whenever the paywall snapshot changes (load, resume,
    // invoice created, billing:invoice-updated socket push).
    return ValueListenableBuilder<int>(
      valueListenable: PaywallState.revision,
      builder: (context, _, _) => _buildGrid(),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 12),
      itemCount: _modules.length,
      itemBuilder: (context, index) {
        final module = _modules[index];
        final block = PaywallState.blockForModuleCode(module.id);
        final p = MarketPalette.of(context);
        // Desktop Dashboard's status wording: Expired (critical) / Inactive
        // (neutral), plus the wall's "awaiting approval" for a pending invoice.
        final lockLabel = block == null
            ? null
            : block.pendingInvoice != null
                ? 'Pending approval'
                : block.isExpired
                    ? 'Expired'
                    : 'Inactive';
        final lockColor = block == null ? null : (block.isExpired ? p.error : (block.pendingInvoice != null ? p.warn : p.neutral));
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onTileTap(module),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.slate400.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  // Room for the badge pill overhanging the icon circle's
                  // top-right corner without clipping.
                  width: 64,
                  height: 50,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: block == null ? 1 : 0.5,
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: module.color.withValues(alpha: 0.15),
                          child: Icon(module.icon, color: module.color),
                        ),
                      ),
                      if (block != null)
                        Positioned(
                          bottom: 0,
                          left: 38,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: p.card,
                              shape: BoxShape.circle,
                              border: Border.all(color: p.line),
                            ),
                            child: Icon(Icons.lock, size: 12, color: lockColor),
                          ),
                        ),
                      if (module.moduleId > 0)
                        Positioned(
                          top: 0,
                          left: 38,
                          child: _ModuleUnreadBadge(moduleId: module.moduleId),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    module.label,
                    textAlign: TextAlign.center,
                    maxLines: lockLabel == null ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                if (lockLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    lockLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: lockColor),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// SAP-style unread pill on a launcher tile — error colour, white text,
/// "99+" cap, pops in (scale) when it appears or the count changes, hidden
/// at 0. Listens to [ModuleUnreadCounts.counts] directly so a socket bump
/// only rebuilds the affected badges, not the grid.
class _ModuleUnreadBadge extends StatelessWidget {
  final int moduleId;
  const _ModuleUnreadBadge({required this.moduleId});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<int, int>>(
      valueListenable: ModuleUnreadCounts.counts,
      builder: (context, counts, _) {
        final count = counts[moduleId] ?? 0;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: count <= 0
              ? const SizedBox.shrink(key: ValueKey(0))
              : Container(
                  key: ValueKey(count),
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Theme.of(context).cardColor, width: 1.5),
                  ),
                  child: Text(
                    formatBadgeCount(count),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, height: 1.1),
                  ),
                ),
        );
      },
    );
  }
}
