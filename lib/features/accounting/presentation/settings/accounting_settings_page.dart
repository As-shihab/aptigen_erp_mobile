import 'package:flutter/material.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/accounting_ledger_service.dart';

// Accounting settings — port of desktop settings/AccountSettings.tsx. The
// workplace's single account_settings row: default POS and payroll
// accounts. Nothing creates the row on workplace setup, so this page
// creates it on first load. Like desktop, each pick saves right away
// (optimistic, rolled back on failure).

class AccountingSettingsPage extends StatefulWidget {
  const AccountingSettingsPage({super.key});

  @override
  State<AccountingSettingsPage> createState() => _AccountingSettingsPageState();
}

class _AccountingSettingsPageState extends State<AccountingSettingsPage> {
  final _service = AccountingLedgerService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _row;
  List<SettingsAccountOption> _accounts = [];
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
      final d = await _service.loadSettings();
      var row = d.settings;
      if (row == null && d.workplaceId != null) row = await _service.createSettings(d.workplaceId!);
      if (!mounted) return;
      setState(() {
        _accounts = d.accounts;
        _row = row;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Failed to load accounting settings'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _patch(String key, Object? value) async {
    final row = _row;
    if (row == null || row['id'] == null) return;
    final previous = row[key];
    final next = value == null ? null : int.tryParse(value.toString());
    setState(() {
      row[key] = next;
      _saving++;
    });
    try {
      await _service.patchSettings(row['id'], {key: next});
    } catch (e) {
      if (mounted) {
        setState(() => row[key] = previous);
        marketToast(context, errorMessage(e, 'Failed to save accounting settings'), error: true);
      }
    } finally {
      if (mounted) setState(() => _saving--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final disabled = _row?['id'] == null;
    final options = [for (final a in _accounts) PickOption(a.id, a.label)];

    final settings = [
      (
        key: 'default_pos_account_id',
        icon: Icons.point_of_sale_outlined,
        title: 'Default POS account',
        desc: 'Income account credited when a POS sale posts to the ledger. Leave unset to keep using a "Sales revenue" account, created automatically if needed.',
      ),
      (
        key: 'default_payroll_account_id',
        icon: Icons.account_balance_wallet_outlined,
        title: 'Default payroll account',
        desc: 'Expense account payroll runs will post against once payroll-to-ledger posting is wired up.',
      ),
    ];

    return MotionScaffold(
      title: 'Accounting settings',
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
          sliverSkeleton(count: 2, height: 140)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else ...[
          sliverBox(const SectionHeader('Default accounts'), padding: const EdgeInsets.symmetric(horizontal: 16)),
          if (disabled)
            sliverBox(
              GlowCard(
                child: Row(children: [
                  const AccentIcon(Icons.info_outline_rounded, accent: Accent.amber, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Accounting settings could not be set up for this workplace. Pull down to try again.',
                      style: TextStyle(fontSize: 12.5, color: p.label),
                    ),
                  ),
                ]),
              ),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            ),
          sliverStagger(
            count: settings.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            builder: (_, i) {
              final s = settings[i];
              return Opacity(
                opacity: disabled ? 0.6 : 1,
                child: GlowCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      AccentIcon(s.icon, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                          const SizedBox(height: 3),
                          Text(s.desc, style: TextStyle(fontSize: 12, color: p.label, height: 1.35)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    IgnorePointer(
                      ignoring: disabled,
                      child: PickerField(
                        value: _row?[s.key],
                        hint: 'Select an account',
                        icon: Icons.account_tree_outlined,
                        options: options,
                        onChanged: (v) => _patch(s.key, v),
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
