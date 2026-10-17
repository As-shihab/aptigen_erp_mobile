import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import 'invoices_page.dart';

/// One subscription row from `module_subscriptions` — mirrors desktop's
/// `ProfileBilling.tsx` `SubscriptionRow` (module_subscriptions.prisma).
class _SubscriptionRow {
  final int id;
  final bool isActive;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final String moduleName;

  _SubscriptionRow({required this.id, required this.isActive, required this.startsAt, required this.expiresAt, required this.moduleName});

  factory _SubscriptionRow.fromJson(Map json) {
    final module = json['module'] is Map ? json['module'] as Map : const {};
    return _SubscriptionRow(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      isActive: json['is_active'] == true,
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      moduleName: (module['name'] ?? 'Module ${json['module_id']}').toString(),
    );
  }

  bool get isExpired => !isActive || (expiresAt != null && expiresAt!.isBefore(DateTime.now()));

  double get cycleProgress {
    final end = expiresAt;
    if (end == null) return 1.0;
    final start = startsAt ?? end.subtract(const Duration(days: 30));
    final total = end.difference(start).inMilliseconds;
    if (total <= 0) return 1.0;
    final elapsed = DateTime.now().difference(start).inMilliseconds.clamp(0, total);
    return elapsed / total;
  }
}

String _formatDate(DateTime? value) {
  if (value == null) return 'No expiry';
  final local = value.toLocal();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${local.day.toString().padLeft(2, '0')} ${months[local.month - 1]} ${local.year}';
}

String _initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return (parts[0][0] + (parts.length > 1 ? parts[1][0] : '')).toUpperCase();
}

/// Subscriptions overview for this workplace — mirrors desktop's
/// `ProfileBilling.tsx`: reads `module_subscriptions` directly (same table
/// the Market install flow writes to), shows active/expired/next-renewal
/// summary tiles and a per-module cycle progress bar. Detailed billing
/// documents live on [InvoicesPage].
class BillingPage extends StatefulWidget {
  const BillingPage({super.key});

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  final _client = ApiClient();
  bool _loading = true;
  List<_SubscriptionRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _client.get('module_subscriptions?\$expand=module&\$top=500');
      final rows = unwrapList(res).cast<Map>().map(_SubscriptionRow.fromJson).toList();
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _rows = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _rows.where((r) => !r.isExpired).length;
    final expired = _rows.length - active;
    final nextExpiry = ([..._rows.where((r) => !r.isExpired && r.expiresAt != null)]..sort((a, b) => a.expiresAt!.compareTo(b.expiresAt!)))
        .map((r) => r.expiresAt)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'View Invoices',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InvoicesPage())),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Row(
                    children: [
                      Expanded(child: _SummaryTile(icon: Icons.check_circle_outline, iconColor: AppColors.success, value: '$active', label: 'Active')),
                      const SizedBox(width: 10),
                      Expanded(child: _SummaryTile(icon: Icons.cancel_outlined, iconColor: AppColors.error, value: '$expired', label: 'Expired')),
                      const SizedBox(width: 10),
                      Expanded(child: _SummaryTile(icon: Icons.event_outlined, iconColor: AppColors.info, value: _formatDate(nextExpiry), label: 'Next renewal')),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Subscriptions', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 10),
                  if (_rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text(
                          'No subscriptions found — chargeable modules you install from the Market will show up here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.slate600),
                        ),
                      ),
                    )
                  else
                    ..._rows.map((row) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _SubscriptionCard(row: row),
                        )),
                ],
              ),
            ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  const _SummaryTile({required this.icon, required this.iconColor, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slate400.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(height: 8),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: AppColors.slate600)),
        ],
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  final _SubscriptionRow row;
  const _SubscriptionCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final isExpired = row.isExpired;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate400.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.slate100,
                child: Text(_initialsOf(row.moduleName), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.moduleName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text('Renews / expires: ${_formatDate(row.expiresAt)}', style: TextStyle(fontSize: 11, color: AppColors.slate600)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isExpired ? AppColors.error : AppColors.success).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isExpired ? 'Expired' : 'Active',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isExpired ? AppColors.error : AppColors.success),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: row.cycleProgress.toDouble(),
              minHeight: 6,
              backgroundColor: AppColors.slate100,
              color: isExpired || row.cycleProgress > 0.85 ? AppColors.error : AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
