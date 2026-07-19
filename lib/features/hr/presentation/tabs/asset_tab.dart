import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/async_state_view.dart';
import '../../data/employee_dashboard_service.dart';

class AssetTab extends StatefulWidget {
  final int employeeId;
  const AssetTab({super.key, required this.employeeId});

  @override
  State<AssetTab> createState() => _AssetTabState();
}

class _AssetTabState extends State<AssetTab> {
  final _service = EmployeeDashboardService(ApiClient());
  bool _loading = true;
  String? _error;
  List<dynamic> _rows = [];

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
      final rows = await _service.getAssets(widget.employeeId);
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load assets.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: AsyncStateView(
        loading: _loading,
        error: _error,
        isEmpty: _rows.isEmpty,
        emptyMessage: 'No assets assigned to you.',
        emptyIcon: Icons.laptop_mac,
        onRetry: _load,
        builder: (context) => ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final row = (_rows[index] as Map).cast<String, dynamic>();
            final asset = (row['asset'] as Map?)?.cast<String, dynamic>();
            final assetGroup = (asset?['asset_group'] as Map?)?['name']?.toString();
            final issuedDate = DateTime.tryParse((row['issued_date'] ?? '').toString());
            final returnDate = DateTime.tryParse((row['return_date'] ?? '').toString());
            final isActive = returnDate == null;
            final remarks = (row['remarks'] ?? row['note'] ?? '').toString();

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.brand.withValues(alpha: 0.12),
                child: const Icon(Icons.laptop_mac, color: AppColors.brand, size: 18),
              ),
              title: Text((asset?['name'] ?? '—').toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              subtitle: Text(
                [
                  assetGroup ?? 'Uncategorized',
                  if (issuedDate != null) 'Issued ${DateFormat('dd MMM yyyy').format(issuedDate)}',
                  if (returnDate != null) 'Returned ${DateFormat('dd MMM yyyy').format(returnDate)}',
                  if (remarks.isNotEmpty) '"$remarks"',
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: StatusChip(label: isActive ? 'Assigned' : 'Returned', color: isActive ? AppColors.success : AppColors.slate400),
            );
          },
        ),
      ),
    );
  }
}
