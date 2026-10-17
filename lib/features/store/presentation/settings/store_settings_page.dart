import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../data/store_settings_service.dart';
import '../../data/store_util.dart' show toIntOrNull;
import '../widgets/store_ui.dart';

/// Store feature toggles (`store_settings`) — approver-type chain fields are
/// intentionally out of scope (separate approvals system), per the plan.
class StoreSettingsPage extends StatefulWidget {
  const StoreSettingsPage({super.key});

  @override
  State<StoreSettingsPage> createState() => _StoreSettingsPageState();
}

class _StoreSettingsPageState extends State<StoreSettingsPage> {
  final _client = ApiClient();
  late final _service = StoreSettingsService(_client);

  bool _loading = true;
  bool _saving = false;
  StoreFeatureToggles _toggles = const StoreFeatureToggles();

  /// Last loaded values — only used to show the "unsaved changes" hint.
  StoreFeatureToggles _saved = const StoreFeatureToggles();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _service.load();
      if (!mounted) return;
      setState(() {
        _toggles = result;
        _saved = result;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<int?> _resolveStoreModuleId() async {
    final res = await _client.get(r"modules?$select=id,code&$filter=code eq 'STORE'&$top=1");
    final rows = unwrapList(res);
    if (rows.isEmpty) return null;
    return toIntOrNull((rows.first as Map)['id']);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      var moduleId = 0;
      if (_toggles.id == null) {
        final resolved = await _resolveStoreModuleId();
        if (resolved == null) {
          if (mounted) marketToast(context, 'Could not resolve the Store module — install it from Market first.', error: true);
          return;
        }
        moduleId = resolved;
      }
      await _service.save(_toggles, moduleId: moduleId);
      if (!mounted) return;
      marketToast(context, 'Settings saved.');
      _load();
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Could not save settings.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _dirty =>
      _toggles.hasSpr != _saved.hasSpr ||
      _toggles.hasSprApproval != _saved.hasSprApproval ||
      _toggles.hasSr != _saved.hasSr ||
      _toggles.hasRepairMrr != _saved.hasRepairMrr;

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketScaffold(
      title: 'Store settings',
      subtitle: 'Choose which Store features your team uses',
      body: _loading
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                SkeletonBox(height: 16, width: 140),
                SizedBox(height: 12),
                SkeletonBox(height: 150, radius: 12),
                SizedBox(height: 24),
                SkeletonBox(height: 16, width: 120),
                SizedBox(height: 12),
                SkeletonBox(height: 150, radius: 12),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                FadeSlideIn(
                  child: _section(
                    p,
                    title: 'Purchasing',
                    subtitle: 'How the store asks for new stock',
                    rows: [
                      _toggleRow(
                        p,
                        icon: Icons.request_page_outlined,
                        title: 'Enable purchase requisitions (SPR)',
                        subtitle: 'Let staff request items to buy; approved requests go on to purchasing.',
                        value: _toggles.hasSpr,
                        onChanged: (v) => setState(() => _toggles = _toggles.copyWith(hasSpr: v)),
                      ),
                      _toggleRow(
                        p,
                        icon: Icons.verified_user_outlined,
                        title: 'Require approval for purchase requisitions',
                        subtitle: 'Requisitions wait for an approver before they reach purchasing. Off by default.',
                        value: _toggles.hasSprApproval,
                        onChanged: (v) => setState(() => _toggles = _toggles.copyWith(hasSprApproval: v)),
                      ),
                    ],
                  ),
                ),
                FadeSlideIn(
                  index: 1,
                  child: _section(
                    p,
                    title: 'Issuing',
                    subtitle: 'How stock leaves the store',
                    rows: [
                      _toggleRow(
                        p,
                        icon: Icons.description_outlined,
                        title: 'Enable store requisitions (SR)',
                        subtitle: 'Departments request items from the store, which issues them from stock.',
                        value: _toggles.hasSr,
                        onChanged: (v) => setState(() => _toggles = _toggles.copyWith(hasSr: v)),
                      ),
                    ],
                  ),
                ),
                FadeSlideIn(
                  index: 2,
                  child: _section(
                    p,
                    title: 'Receiving',
                    subtitle: 'Extra kinds of goods receipt',
                    rows: [
                      _toggleRow(
                        p,
                        icon: Icons.build_outlined,
                        title: 'Enable repair receipts',
                        subtitle: 'Record items coming back from repair as a separate material receipt (MRR).',
                        value: _toggles.hasRepairMrr,
                        onChanged: (v) => setState(() => _toggles = _toggles.copyWith(hasRepairMrr: v)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FadeSlideIn(
                  index: 3,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline, size: 16, color: p.label),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Changes apply to everyone in this workplace once saved. Approval chains are set up in the desktop app.',
                        style: TextStyle(fontSize: 12, color: p.label, height: 1.4),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
      bottom: Container(
        decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _dirty && !_loading
                      ? const StatusPill('Unsaved changes', key: ValueKey('dirty'), tone: MarketTone.warn, icon: Icons.edit_outlined)
                      : Text('All changes saved', key: const ValueKey('clean'), style: TextStyle(fontSize: 12.5, color: p.label)),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: p.brand, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 22)),
                  onPressed: _saving || _loading ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, size: 18),
                  label: const Text('Save'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _section(MarketPalette p, {required String title, String? subtitle, required List<Widget> rows}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(title, subtitle: subtitle),
      MarketCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 62, color: p.line),
            rows[i],
          ],
        ]),
      ),
    ]);
  }

  Widget _toggleRow(
    MarketPalette p, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: value ? p.brandSoft : p.surface, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 19, color: value ? p.brand : p.label),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: p.label, height: 1.35)),
            ]),
          ),
          const SizedBox(width: 6),
          Switch(value: value, onChanged: onChanged),
        ]),
      ),
    );
  }
}
