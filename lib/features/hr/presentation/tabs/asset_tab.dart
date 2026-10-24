import 'package:flutter/material.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'dash_common.dart';

/// Ported from desktop tabs/AssetTab.tsx — assets issued to the employee,
/// with an assigned / returned filter.
class AssetTab extends DashSection {
  const AssetTab({super.key, required super.employeeId, super.refreshToken});

  @override
  State<AssetTab> createState() => _AssetTabState();
}

class _AssetTabState extends State<AssetTab> with DashLoader<AssetTab> {
  List<Map<String, dynamic>> _rows = [];
  String _filter = 'all';

  @override
  Future<void> fetch() async {
    final rows = await service.getAssets(widget.employeeId);
    if (mounted) setState(() => _rows = rows);
  }

  bool _active(Map<String, dynamic> r) => r['return_date'] == null;

  @override
  Widget build(BuildContext context) {
    final state = stateSliver();
    if (state != null) return state;
    if (_rows.isEmpty) return sliverEmpty(icon: Icons.laptop_chromebook_rounded, title: 'No assets assigned to you');

    final active = _rows.where(_active).length;
    final list = _rows.where((r) => _filter == 'all' || (_filter == 'assigned') == _active(r)).toList();

    return SliverMainAxisGroup(slivers: [
      sliverStats([
        MiniStat(icon: Icons.devices_rounded, label: 'Currently assigned', value: active, tone: MarketTone.ok),
        MiniStat(icon: Icons.assignment_return_rounded, label: 'Returned', value: _rows.length - active, tone: MarketTone.neutral),
      ]),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: ChipFilter<String>(
            value: _filter,
            onChanged: (v) => setState(() => _filter = v),
            options: [
              (id: 'all', label: 'All', count: _rows.length),
              (id: 'assigned', label: 'Assigned', count: active),
              (id: 'returned', label: 'Returned', count: _rows.length - active),
            ],
          ),
        ),
      ),
      if (list.isEmpty)
        sliverEmpty(icon: Icons.filter_alt_off_rounded, title: 'Nothing matches this filter')
      else
        sliverStagger(
          count: list.length,
          builder: (_, i) {
            final r = list[i];
            final asset = (r['asset'] as Map?) ?? const {};
            final group = (asset['asset_group'] as Map?)?['name'];
            final issued = parseDate(r['issued_date']);
            final returned = parseDate(r['return_date']);
            final note = '${r['remarks'] ?? r['note'] ?? ''}'.trim();
            final meta = [
              if (issued != null) 'Issued ${fmtDate(issued)}',
              if (returned != null) 'Returned ${fmtDate(returned)}',
            ].join(' · ');
            return MotionTile(
              leading: AccentIcon(Icons.laptop_mac_rounded, accent: _active(r) ? Accent.ocean : Accent.ocean, size: 42),
              title: '${asset['name'] ?? '-'}',
              subtitle: [group ?? 'Uncategorized', if (note.isNotEmpty) note].join('\n'),
              meta: meta,
              trailing: StatusPill(_active(r) ? 'Assigned' : 'Returned', tone: _active(r) ? MarketTone.ok : MarketTone.neutral),
            );
          },
        ),
    ]);
  }
}
