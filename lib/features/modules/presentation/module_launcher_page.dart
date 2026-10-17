import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../accounting/presentation/accounting_home_page.dart';
import '../../chat/presentation/chat_hub_page.dart';
import '../../hr/presentation/employee_dashboard_page.dart';
import '../../hr/presentation/hr_analytics_page.dart';
import '../../jobs/presentation/jobs_list_page.dart';
import '../../market/presentation/market_page.dart';
import '../../note/presentation/note_page.dart';
import '../../profile/presentation/profile_page.dart';
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
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
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
    if (module.id == 'accounting') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountingHomePage()));
      return;
    }
    if (module.id == 'profile') {
      // Same account/billing/invoices screen as the bottom-nav Profile tab —
      // this tile was previously falling through to the generic "coming
      // soon" snackbar below since it had no explicit case here. ProfilePage
      // already renders its own full-bleed gradient hero header (with a
      // built-in back button when pushed as its own route — see
      // _ProfileHeader below), so it's pushed bare, not wrapped in a second
      // AppBar like the market case above.
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
      return;
    }
    if (!module.isHr) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${module.label} — coming soon')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.badge, color: AppColors.brand),
              title: const Text('Employee Dashboard'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmployeeDashboardPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.insights, color: AppColors.brand),
              title: const Text('Analytics'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HrAnalyticsPage()));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 12),
      itemCount: _modules.length,
      itemBuilder: (context, index) {
        final module = _modules[index];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openModule(module),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.slate400.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: module.color.withValues(alpha: 0.15),
                  child: Icon(module.icon, color: module.color),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    module.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
