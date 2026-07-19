import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/market_service.dart';
import '../models/market_app.dart';

const _features = [
  'Real-time sync across your workplace',
  'Role-based permissions built in',
  'Works across web, desktop, and mobile',
  'Includes standard reports & exports',
];

/// The "App Marketplace" — browse, install, and uninstall the workplace's
/// own ERP modules (erp/desktop's Market.tsx), not a 3rd-party plugin store.
/// Renders as body content only (no own Scaffold/AppBar) so it can sit
/// inside the bottom-nav shell's IndexedStack; callers pushing it as a
/// standalone screen should wrap it in their own Scaffold+AppBar.
class MarketPage extends StatefulWidget {
  const MarketPage({super.key});

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  final _service = MarketService(ApiClient());
  final _searchController = TextEditingController();
  Timer? _debounce;

  bool _loading = true;
  bool _showInstalledOnly = false;
  String _category = 'all';
  List<String> _categories = [];
  List<MarketApp> _apps = [];
  final Set<int> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.loadCatalog(search: _searchController.text, category: _category),
        _service.loadCategories(),
        _service.loadInstalledModuleIds(),
      ]);
      final apps = results[0] as List<MarketApp>;
      final categories = results[1] as List<String>;
      final installedIds = results[2] as Set<int>;
      for (final app in apps) {
        app.installed = installedIds.contains(app.id);
      }
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _categories = categories;
      });
    } catch (_) {
      // leave whatever's already loaded on failure
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  /// Quick uninstall — instant call, spinner on the button. Install gets
  /// its own step-by-step progress sheet via [_installWithProgress] instead.
  Future<void> _uninstall(MarketApp app) async {
    if (_busyIds.contains(app.id)) return;
    setState(() => _busyIds.add(app.id));
    try {
      await _service.uninstall(app.id);
      if (!mounted) return;
      setState(() => app.installed = false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not uninstall ${app.name}.')));
    } finally {
      if (mounted) setState(() => _busyIds.remove(app.id));
    }
  }

  /// Install opens a non-dismissible bottom sheet that steps through
  /// verifying/creating/configuring before confirming — mirrors desktop's
  /// Market.tsx install progress overlay.
  Future<void> _installWithProgress(MarketApp app) async {
    if (_busyIds.contains(app.id)) return;
    setState(() => _busyIds.add(app.id));
    final succeeded = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => _InstallProgressSheet(app: app, performInstall: () => _service.install(app.id)),
    );
    if (!mounted) return;
    setState(() {
      _busyIds.remove(app.id);
      if (succeeded == true) app.installed = true;
    });
    if (succeeded == false) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not install ${app.name}.')));
    }
  }

  void _openDetails(MarketApp app) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => _AppDetailsSheet(
        app: app,
        onUninstall: () async {
          await _service.uninstall(app.id);
          app.installed = false;
          if (mounted) setState(() {});
        },
      ),
    );
    if (action == 'install' && mounted) _installWithProgress(app);
  }

  List<MarketApp> get _visibleApps => _showInstalledOnly ? _apps.where((a) => a.installed).toList() : _apps;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(color: AppColors.slate400.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(24)),
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search apps',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _ViewModeToggle(
                  showInstalledOnly: _showInstalledOnly,
                  onChanged: (value) => setState(() => _showInstalledOnly = value),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _categoryChip('all', 'All'),
                ..._categories.map((c) => _categoryChip(c, c)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _categoryChip(String value, String label) {
    final selected = _category == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _category = value);
          _load();
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.92),
        itemCount: 6,
        itemBuilder: (_, _) => Container(decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(18))),
      );
    }

    final apps = _visibleApps;
    if (apps.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Icon(Icons.storefront_outlined, size: 40, color: AppColors.slate400),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _showInstalledOnly ? 'No installed apps yet.' : 'No apps found.',
              style: TextStyle(color: AppColors.slate600),
            ),
          ),
        ],
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.92),
      itemCount: apps.length,
      itemBuilder: (context, index) => _MarketAppCard(
        app: apps[index],
        busy: _busyIds.contains(apps[index].id),
        onTap: () => _openDetails(apps[index]),
        onInstall: () => _installWithProgress(apps[index]),
        onUninstall: () => _uninstall(apps[index]),
      ),
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  final bool showInstalledOnly;
  final ValueChanged<bool> onChanged;
  const _ViewModeToggle({required this.showInstalledOnly, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.slate400.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeButton(icon: Icons.grid_view_rounded, selected: !showInstalledOnly, onTap: () => onChanged(false)),
          _modeButton(icon: Icons.check_circle_outline, selected: showInstalledOnly, onTap: () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _modeButton({required IconData icon, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(color: selected ? AppColors.brand : Colors.transparent, borderRadius: BorderRadius.circular(16)),
        child: Icon(icon, size: 18, color: selected ? Colors.white : AppColors.slate600),
      ),
    );
  }
}

class _MarketAppCard extends StatelessWidget {
  final MarketApp app;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;

  const _MarketAppCard({required this.app, required this.busy, required this.onTap, required this.onInstall, required this.onUninstall});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CircleAvatar(radius: 20, backgroundColor: app.color.withValues(alpha: 0.15), child: Icon(app.icon, color: app.color, size: 20)),
                if (app.installed) const Icon(Icons.check_circle, color: AppColors.success, size: 18),
              ],
            ),
            const SizedBox(height: 10),
            Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 2),
            Text(app.category, style: TextStyle(fontSize: 11, color: AppColors.slate600)),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 32,
              child: OutlinedButton(
                onPressed: busy ? null : (app.installed ? onUninstall : onInstall),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: app.installed ? null : AppColors.brand,
                  foregroundColor: app.installed ? AppColors.slate600 : Colors.white,
                  side: BorderSide(color: app.installed ? AppColors.slate400.withValues(alpha: 0.4) : AppColors.brand),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: busy
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(app.installed ? 'Uninstall' : 'Install', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppDetailsSheet extends StatefulWidget {
  final MarketApp app;
  final Future<void> Function() onUninstall;

  const _AppDetailsSheet({required this.app, required this.onUninstall});

  @override
  State<_AppDetailsSheet> createState() => _AppDetailsSheetState();
}

class _AppDetailsSheetState extends State<_AppDetailsSheet> {
  bool _busy = false;

  Future<void> _handleUninstall() async {
    setState(() => _busy = true);
    try {
      await widget.onUninstall();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not uninstall ${widget.app.name}.')));
      setState(() => _busy = false);
    }
  }

  void _handlePress() {
    if (widget.app.installed) {
      _handleUninstall();
    } else {
      Navigator.of(context).pop('install');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final busy = _busy;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.slate400.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(
            children: [
              CircleAvatar(radius: 28, backgroundColor: app.color.withValues(alpha: 0.15), child: Icon(app.icon, color: app.color, size: 26)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(app.category, style: TextStyle(color: AppColors.slate600, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (app.shortInfo != null && app.shortInfo!.isNotEmpty)
            Text(app.shortInfo!, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (app.description != null && app.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(app.description!, style: TextStyle(color: AppColors.slate600, height: 1.4)),
          ],
          const SizedBox(height: 18),
          const Text('Capabilities', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          ..._features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 16, color: AppColors.brand),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f, style: const TextStyle(fontSize: 12))),
                  ],
                ),
              )),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: busy || (!app.installed && !app.isInstallable) || (app.installed && !app.isUninstallable) ? null : _handlePress,
              style: FilledButton.styleFrom(
                backgroundColor: app.installed ? AppColors.error : AppColors.brand,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(app.installed ? 'Uninstall' : 'Install', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

const _installSteps = ['Verifying module', 'Creating workspace record', 'Configuring permissions', 'Installation complete'];

/// Non-dismissible progress sheet shown while installing — mirrors
/// desktop's Market.tsx 4-step install overlay (`INSTALL_STEPS`), with the
/// same artificial delays around the real `market/{id}/install` call so the
/// steps read naturally instead of flashing past instantly.
class _InstallProgressSheet extends StatefulWidget {
  final MarketApp app;
  final Future<void> Function() performInstall;

  const _InstallProgressSheet({required this.app, required this.performInstall});

  @override
  State<_InstallProgressSheet> createState() => _InstallProgressSheetState();
}

class _InstallProgressSheetState extends State<_InstallProgressSheet> {
  int _stepIndex = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() => _stepIndex = 1);

      await widget.performInstall();
      if (!mounted) return;
      setState(() => _stepIndex = 2);

      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      setState(() => _stepIndex = 3);

      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _failed,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 22, backgroundColor: widget.app.color.withValues(alpha: 0.15), child: Icon(widget.app.icon, color: widget.app.color)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Installing ${widget.app.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Text(
                          _failed ? 'Installation failed' : 'Please wait…',
                          style: TextStyle(color: _failed ? AppColors.error : AppColors.slate600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              ..._installSteps.asMap().entries.map((entry) => _buildStepRow(entry.key, entry.value)),
              if (_failed) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepRow(int index, String label) {
    final isLast = index == _installSteps.length - 1;
    final done = isLast ? _stepIndex >= index : _stepIndex > index;
    final failedHere = _failed && index == _stepIndex;
    final active = !done && !failedHere && index == _stepIndex;
    final pending = !done && !active && !failedHere;

    Widget leading;
    if (failedHere) {
      leading = const Icon(Icons.error_outline, size: 20, color: AppColors.error);
    } else if (active) {
      leading = const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand));
    } else if (done) {
      leading = const Icon(Icons.check_circle, size: 20, color: AppColors.success);
    } else {
      leading = Icon(Icons.radio_button_unchecked, size: 20, color: AppColors.slate400.withValues(alpha: 0.6));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(width: 22, height: 22, child: Center(child: leading)),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: done || active ? FontWeight.w700 : FontWeight.w500,
              color: pending ? AppColors.slate400 : null,
            ),
          ),
        ],
      ),
    );
  }
}
