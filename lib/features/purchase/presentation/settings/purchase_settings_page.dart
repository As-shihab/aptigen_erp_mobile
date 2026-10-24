import 'package:flutter/material.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../../settings/presentation/approver_chain/approver_chain_pages.dart';
import '../../data/purchase_settings_service.dart';
import '../approvals/purchase_approvals_page.dart';

// Purchase settings — port of desktop settings/PurchaseSettings.tsx. Feature
// switches (RFQ, returns, require supplier, lock approved orders) and the
// purchase order approval chain. Like desktop, each change saves right
// away (optimistic, rolled back on failure).

class PurchaseSettingsPage extends StatefulWidget {
  const PurchaseSettingsPage({super.key});

  @override
  State<PurchaseSettingsPage> createState() => _PurchaseSettingsPageState();
}

class _PurchaseSettingsPageState extends State<PurchaseSettingsPage> {
  final _service = PurchaseSettingsService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _row;
  List<Map<String, dynamic>> _approveTypes = [];
  int _saving = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _row == null;
      _error = null;
    });
    try {
      final d = await _service.load();
      if (!mounted) return;
      setState(() {
        _row = d.settings;
        _approveTypes = d.approveTypes;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Failed to load purchase settings'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _patch(Map<String, dynamic> partial) async {
    final row = _row;
    if (row == null) return;
    final previous = {for (final k in partial.keys) k: row[k]};
    setState(() {
      row.addAll(partial);
      _saving++;
    });
    try {
      await _service.patch(row['id'], partial);
    } catch (e) {
      if (mounted) {
        setState(() => row.addAll(previous));
        marketToast(context, errorMessage(e, 'Failed to save purchase settings'), error: true);
      }
    } finally {
      if (mounted) setState(() => _saving--);
    }
  }

  bool _flag(String key, bool fallback) => _row == null ? fallback : asBool(_row![key], fallback: fallback);

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final disabled = _row == null;
    final hasApproval = _flag('has_po_approval', false);
    final chainId = _row?['po_approver_type_id'];
    final chain = _approveTypes.where((t) => t['id'].toString() == chainId?.toString()).firstOrNull;

    final features = [
      (
        key: 'has_rfq',
        icon: Icons.request_quote_outlined,
        title: 'Use requests for quotation',
        desc: 'Ask several suppliers for prices, compare quotes side by side and turn the best one into a purchase order.',
        fallback: true,
      ),
      (
        key: 'has_returns',
        icon: Icons.assignment_return_outlined,
        title: 'Use purchase returns',
        desc: 'Send damaged or wrong goods back to the supplier against a received MRR.',
        fallback: true,
      ),
      (
        key: 'require_supplier',
        icon: Icons.local_shipping_outlined,
        title: 'Require supplier on orders',
        desc: 'A purchase order can only be saved with a supplier picked from the supplier list.',
        fallback: false,
      ),
      (
        key: 'lock_approved_po',
        icon: Icons.lock_outline_rounded,
        title: 'Lock approved orders',
        desc: 'Once a purchase order is approved, its product lines can no longer be edited.',
        fallback: true,
      ),
    ];

    return MotionScaffold(
      title: 'Purchase settings',
      subtitle: 'Features and approvals',
      icon: Icons.tune_rounded,
      onRefresh: _load,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _saving > 0
                  ? SizedBox(key: const ValueKey('saving'), width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.brand))
                  : const SizedBox(key: ValueKey('idle'), width: 18),
            ),
          ),
        ),
      ],
      slivers: [
        if (_loading)
          sliverSkeleton(count: 5, height: 88)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else ...[
          sliverBox(const SectionHeader('Feature configuration'), padding: const EdgeInsets.symmetric(horizontal: 16)),
          if (disabled)
            sliverBox(
              GlowCard(
                child: Row(children: [
                  const AccentIcon(Icons.info_outline_rounded, accent: Accent.amber, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No purchase settings found for this workplace yet. Reinstall the Purchase module from the marketplace to create them.',
                      style: TextStyle(fontSize: 12.5, color: p.label),
                    ),
                  ),
                ]),
              ),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            ),
          sliverStagger(
            count: features.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            builder: (_, i) {
              final f = features[i];
              return _SettingCard(
                icon: f.icon,
                title: f.title,
                description: f.desc,
                value: _flag(f.key, f.fallback),
                enabled: !disabled,
                onChanged: (v) => _patch({f.key: v}),
              );
            },
          ),
          sliverBox(const SectionHeader('Approval configuration'), padding: const EdgeInsets.symmetric(horizontal: 16)),
          sliverBox(
            FadeSlideIn(
              index: features.length,
              child: Opacity(
                opacity: disabled ? 0.6 : 1,
                child: GlowCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _SettingRow(
                      icon: Icons.verified_outlined,
                      title: 'Purchase order approval',
                      description: hasApproval
                          ? 'On. New purchase orders go through the selected approver chain, one step at a time, before they can be sent to the supplier.'
                          : 'Off. Purchase orders can be approved and sent directly by anyone with purchase access.',
                      value: hasApproval,
                      enabled: !disabled,
                      onChanged: (v) => _patch({'has_po_approval': v}),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: !hasApproval
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                FormLabel(
                                  label: 'Approver chain',
                                  child: IgnorePointer(
                                    ignoring: disabled,
                                    child: PickerField(
                                      value: chainId,
                                      hint: 'Select a chain',
                                      icon: Icons.link_rounded,
                                      options: [for (final t in _approveTypes) PickOption(t['id'], str(t['name']))],
                                      onChanged: (v) => _patch({'po_approver_type_id': v == null ? null : int.tryParse(v.toString()) ?? v}),
                                    ),
                                  ),
                                ),
                                if (chain == null)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: p.warnBg, borderRadius: BorderRadius.circular(8)),
                                    child: Text(
                                      'No chain selected. Orders stay pending until someone changes their status by hand.',
                                      style: TextStyle(fontSize: 12, color: p.warn),
                                    ),
                                  ),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  OutlinedButton.icon(
                                    onPressed: () => pushMotion(context, const ApproveTypesPage()).then((_) => _load()),
                                    icon: const Icon(Icons.settings_outlined, size: 18),
                                    label: const Text('Manage chains'),
                                    style: OutlinedButton.styleFrom(side: BorderSide(color: p.line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => pushMotion(context, const PurchaseApprovalsPage()),
                                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                                    label: const Text('Review pending orders'),
                                    style: OutlinedButton.styleFrom(side: BorderSide(color: p.line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                  ),
                                ]),
                              ]),
                            ),
                    ),
                  ]),
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          ),
        ],
      ],
    );
  }
}

class _SettingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _SettingCard({required this.icon, required this.title, required this.description, required this.value, required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: enabled ? 1 : 0.6,
        child: GlowCard(
          child: _SettingRow(icon: icon, title: title, description: description, value: value, enabled: enabled, onChanged: onChanged),
        ),
      );
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _SettingRow({required this.icon, required this.title, required this.description, required this.value, required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AccentIcon(icon, size: 36),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
          const SizedBox(height: 3),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(description, key: ValueKey(description), style: TextStyle(fontSize: 12, color: p.label, height: 1.35)),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      Switch.adaptive(value: value, onChanged: enabled ? onChanged : null),
    ]);
  }
}
