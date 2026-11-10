import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../store/data/store_util.dart' show toIntOrNull;
import '../data/pos_local_prefs.dart';
import '../data/sell_settings_service.dart';
import 'widgets/sell_ui.dart';

/// Sell module feature toggles (`sell_settings`) — mirrors
/// store_settings_page.dart's pattern exactly. Approval-chain picker stays
/// out of scope (separate approvals system).
class SellSettingsPage extends StatefulWidget {
  const SellSettingsPage({super.key});

  @override
  State<SellSettingsPage> createState() => _SellSettingsPageState();
}

class _SellSettingsPageState extends State<SellSettingsPage> {
  final _client = ApiClient();
  late final _service = SellSettingsService(_client);

  bool _loading = true;
  bool _saving = false;
  SellFeatureToggles _toggles = const SellFeatureToggles();

  /// Last loaded values — only used to show the "unsaved changes" hint.
  SellFeatureToggles _saved = const SellFeatureToggles();

  /// Device-only (saved immediately, not part of the workplace settings).
  bool _autoPrintReceipt = false;

  @override
  void initState() {
    super.initState();
    _load();
    PosLocalPrefs.getAutoPrintReceipt().then((v) {
      if (mounted) setState(() => _autoPrintReceipt = v);
    });
  }

  Future<void> _setAutoPrint(bool v) async {
    setState(() => _autoPrintReceipt = v);
    await PosLocalPrefs.setAutoPrintReceipt(v);
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

  Future<int?> _resolveSellModuleId() async {
    final res = await _client.get(r"modules?$select=id,code&$filter=code eq 'SELL'&$top=1");
    final rows = unwrapList(res);
    if (rows.isEmpty) return null;
    return toIntOrNull((rows.first as Map)['id']);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      var moduleId = 0;
      if (_toggles.id == null) {
        final resolved = await _resolveSellModuleId();
        if (resolved == null) {
          if (mounted) marketToast(context, 'Could not resolve the Sales module — install it from Market first.', error: true);
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
      _toggles.hasPos != _saved.hasPos ||
      _toggles.hasReturns != _saved.hasReturns ||
      _toggles.hasQuotation != _saved.hasQuotation ||
      _toggles.hasDiscounts != _saved.hasDiscounts ||
      _toggles.hasSaleApproval != _saved.hasSaleApproval ||
      _toggles.hasProductCreate != _saved.hasProductCreate;

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketScaffold(
      title: 'Sales settings',
      subtitle: 'Choose which Sales features your team uses',
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
                    title: 'Point of sale',
                    subtitle: 'How sales are rung up at the counter',
                    rows: [
                      _toggleRow(
                        p,
                        icon: Icons.point_of_sale_outlined,
                        title: 'Use POS terminal',
                        subtitle: 'Show the touch-friendly POS screen for quick counter sales.',
                        value: _toggles.hasPos,
                        onChanged: (v) => setState(() => _toggles = _toggles.copyWith(hasPos: v)),
                      ),
                      _toggleRow(
                        p,
                        icon: Icons.local_offer_outlined,
                        title: 'Allow discounts',
                        subtitle: 'Let staff apply discounts on sales and at POS checkout.',
                        value: _toggles.hasDiscounts,
                        onChanged: (v) => setState(() => _toggles = _toggles.copyWith(hasDiscounts: v)),
                      ),
                      _toggleRow(
                        p,
                        icon: Icons.add_box_outlined,
                        title: 'Create products from Sales',
                        subtitle: 'Show the Product shortcut on the Sales home so staff can add new products. On by default.',
                        value: _toggles.hasProductCreate,
                        onChanged: (v) => setState(() => _toggles = _toggles.copyWith(hasProductCreate: v)),
                      ),
                    ],
                  ),
                ),
                FadeSlideIn(
                  index: 1,
                  child: _section(
                    p,
                    title: 'Receipt',
                    subtitle: 'This device only',
                    rows: [
                      _toggleRow(
                        p,
                        icon: Icons.print_outlined,
                        title: 'Auto print receipt after sale',
                        subtitle: 'Sends the receipt to the default Bluetooth printer when a sale completes.',
                        value: _autoPrintReceipt,
                        onChanged: _setAutoPrint,
                      ),
                    ],
                  ),
                ),
                FadeSlideIn(
                  index: 1,
                  child: _section(
                    p,
                    title: 'Documents',
                    subtitle: 'Extra sales documents you can create',
                    rows: [
                      _toggleRow(
                        p,
                        icon: Icons.assignment_return_outlined,
                        title: 'Enable sales returns',
                        subtitle: 'Refund completed sales and return items to stock.',
                        value: _toggles.hasReturns,
                        onChanged: (v) => setState(() => _toggles = _toggles.copyWith(hasReturns: v)),
                      ),
                      _toggleRow(
                        p,
                        icon: Icons.request_quote_outlined,
                        title: 'Enable quotations',
                        subtitle: 'Send price quotes to clients before turning them into sales.',
                        value: _toggles.hasQuotation,
                        onChanged: (v) => setState(() => _toggles = _toggles.copyWith(hasQuotation: v)),
                      ),
                    ],
                  ),
                ),
                FadeSlideIn(
                  index: 2,
                  child: _section(
                    p,
                    title: 'Approvals',
                    subtitle: 'Controls before a sale is final',
                    rows: [
                      _toggleRow(
                        p,
                        icon: Icons.verified_user_outlined,
                        title: 'Require approval before a sale completes',
                        subtitle: 'Sales wait for an approver before they are completed. Off by default.',
                        value: _toggles.hasSaleApproval,
                        onChanged: (v) => setState(() => _toggles = _toggles.copyWith(hasSaleApproval: v)),
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
