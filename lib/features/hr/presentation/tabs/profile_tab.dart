import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'dash_common.dart';
import 'hr_charts.dart';

/// The desktop dashboard's "My profile" tab (inline in EmployeeDashboard.tsx):
/// month attendance progress, late vs on-time donut, payroll summary,
/// devices + mobile login requests and the always-expanded details.
/// The punch / today ring and leave balances live in the dashboard hero.
class ProfileTab extends DashSection {
  final Map<String, dynamic> employee;
  final Map<String, dynamic> kpi;
  const ProfileTab({super.key, required super.employeeId, required this.employee, required this.kpi, super.refreshToken});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> with DashLoader<ProfileTab> {
  Map<String, List<Map<String, dynamic>>> _data = const {};

  @override
  Future<void> fetch() async {
    final d = await service.getOverview(widget.employeeId);
    if (mounted) setState(() => _data = d);
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final e = widget.employee;
    final present = toInt(widget.kpi['presentDaysThisMonth']);
    final elapsed = DateTime.now().day;
    final rate = (present / (elapsed < 1 ? 1 : elapsed)).clamp(0.0, 1.0);

    final logs = _data['logs'] ?? const [];
    final late = logs.where((r) => asBool(r['has_late'])).length;
    final payrolls = (_data['payrolls'] ?? const []).reversed.toList();
    final totalPaid = payrolls.fold<double>(0, (a, r) => a + toDouble(r['net_salary']));
    final devices = _data['devices'] ?? const [];
    final deviceReqs = _data['deviceRequests'] ?? const [];

    String v(dynamic x) => x == null || '$x'.trim().isEmpty ? '-' : '$x';
    String date(dynamic x) => parseDate(x) == null ? '-' : fmtDate(parseDate(x));

    return SliverMainAxisGroup(slivers: [
      // This month progress
      sliverBox(GlowCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const AccentIcon(Icons.event_available_rounded, accent: Accent.emerald, size: 34),
            const SizedBox(width: 10),
            Expanded(child: Text('This month', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text))),
            CountUp(value: rate * 100, format: (x) => '${x.round()}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.ok)),
          ]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            CountUp(value: present, format: (x) => '${x.round()}', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: p.text, height: 1)),
            Padding(padding: const EdgeInsets.only(left: 6, bottom: 3), child: Text('of $elapsed days present so far', style: TextStyle(fontSize: 12, color: p.label))),
          ]),
          const SizedBox(height: 10),
          GrowBar(value: rate, color: const Color(0xFF30914C), height: 9),
          const SizedBox(height: 6),
          Text('${(rate * 100).round()}% attendance rate', style: TextStyle(fontSize: 11.5, color: p.label)),
        ]),
      )),
      if (loading)
        sliverSkeleton(count: 3, height: 200)
      else if (error != null)
        sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load your overview', message: error, actionLabel: 'Retry', onAction: reload)
      else ...[
        sliverBox(ChartPanel(
          title: 'Late vs on time',
          subtitle: '${logs.length} recorded days',
          icon: Icons.alarm_rounded,
          accent: Accent.amber,
          height: 170,
          empty: logs.isEmpty,
          child: DonutLegend(centerLabel: 'Days', slices: [
            ChartSlice('On time', (logs.length - late).toDouble(), const Color(0xFF30914C)),
            ChartSlice('Late', late.toDouble(), const Color(0xFFE76500)),
          ]),
        )),
        sliverBox(ChartPanel(
          title: 'Total payroll paid',
          subtitle: 'Net pay across last ${payrolls.length} pay period(s)',
          icon: Icons.account_balance_wallet_rounded,
          accent: Accent.emerald,
          height: 170,
          empty: payrolls.isEmpty,
          trailing: CountUp(value: totalPaid, format: (x) => money(x), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.ok)),
          child: GroupedBarChart(
            categories: payrolls.map((r) {
              final d = parseDate(r['start_date']);
              return d == null ? '' : DateFormat('MMM').format(d.toLocal());
            }).toList(),
            series: [ChartSeries('Net pay', payrolls.map((r) => toDouble(r['net_salary'])).toList(), const Color(0xFF30914C))],
          ),
        )),
        sliverBox(GlowCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const AccentIcon(Icons.laptop_mac_rounded, accent: Accent.ocean, size: 34),
              const SizedBox(width: 10),
              Text('My devices', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
            ]),
            const SizedBox(height: 10),
            if (devices.isEmpty)
              Text('No devices currently assigned to you.', style: TextStyle(fontSize: 12.5, color: p.label))
            else
              for (final d in devices)
                _miniRow(p, Icons.devices_other_rounded, '${(d['asset'] as Map?)?['name'] ?? '-'}', '${((d['asset'] as Map?)?['asset_group'] as Map?)?['name'] ?? 'Uncategorized'}', null),
            Divider(height: 24, color: p.line),
            Text('Mobile login requests', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.label)),
            const SizedBox(height: 8),
            if (deviceReqs.isEmpty)
              Text('No mobile device requests yet.', style: TextStyle(fontSize: 12.5, color: p.label))
            else
              for (final r in deviceReqs)
                _miniRow(p, Icons.smartphone_rounded, v(r['device_name']) == '-' ? 'Unknown device' : '${r['device_name']}', v(r['platform']),
                    StatusPill(humanize('${r['status']}'), tone: toneForStatus('${r['status']}'))),
          ]),
        )),
      ],
      sliverBox(const SectionHeader('Employee details')),
      sliverStagger(count: 4, padding: const EdgeInsets.fromLTRB(16, 0, 16, 0), builder: (_, i) {
        final sections = [
          ('Personal', Icons.person_rounded, Accent.ocean, [
            ('First name', v(e['first_name'])),
            ('Last name', v(e['last_name'])),
            ('Gender', humanize(v(e['gender']))),
            ('Date of birth', date(e['date_of_birth'])),
            ('Blood group', v(e['blood_group'])),
            ('Religion', v(e['religion'])),
            ('NID number', v(e['nid'])),
          ]),
          ('Employment', Icons.apartment_rounded, Accent.emerald, [
            ('Department', v((e['department'] as Map?)?['name'])),
            ('Designation', v((e['designation'] as Map?)?['name'])),
            ('Shift', v((e['shift'] as Map?)?['name'])),
            ('Joining date', date(e['joining_date'])),
          ]),
          ('Contact', Icons.call_rounded, Accent.ocean, [
            ('Email', v(e['email'])),
            ('Phone', v(e['contact_number'])),
          ]),
          ('Emergency contact', Icons.health_and_safety_rounded, Accent.rose, [
            ('Name', v(e['emergency_contact_name'])),
            ('Number', v(e['emergency_contact_number'])),
          ]),
        ];
        final s = sections[i];
        return GlowCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              AccentIcon(s.$2, accent: s.$3, size: 30),
              const SizedBox(width: 10),
              Text(s.$1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: s.$3.primary)),
            ]),
            const SizedBox(height: 8),
            for (final f in s.$4) InfoRow(f.$1, f.$2),
          ]),
        );
      }),
    ]);
  }

  Widget _miniRow(MarketPalette p, IconData icon, String title, String sub, Widget? trailing) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, size: 18, color: p.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
            ]),
          ),
          ?trailing,
        ]),
      );
}
