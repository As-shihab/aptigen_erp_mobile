import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../leave/hr_extras.dart';

// Promotion history — port of desktop PromotionHistory.tsx: a read-only
// view of the append-only promotions log, shown as a timeline grouped by
// year.

class PromotionHistoryPage extends StatefulWidget {
  const PromotionHistoryPage({super.key});

  @override
  State<PromotionHistoryPage> createState() => _PromotionHistoryPageState();
}

class _PromotionHistoryPageState extends State<PromotionHistoryPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _q = '';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    try {
      final res = await _client.get('promotions?\$expand=employee,from_designation,to_designation&\$orderby=effective_date desc&\$top=1000');
      if (!mounted) return;
      setState(() => _rows = unwrapList(res).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList());
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load promotion history'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _hasRaise(Map<String, dynamic> r) => (toNum(r['raise_value']) ?? 0) > 0;
  bool _hasMove(Map<String, dynamic> r) => r['to_designation_id'] != null || r['to_designation'] is Map;

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    return _rows.where((r) {
      if (_filter == 'raise' && !_hasRaise(r)) return false;
      if (_filter == 'designation' && !_hasMove(r)) return false;
      if (q.isEmpty) return true;
      return '${empName(r['employee'])} ${nested(r, 'employee', 'employee_no')} ${nested(r, 'from_designation')} ${nested(r, 'to_designation')} ${r['remarks'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final thisYear = _rows.where((r) => parseDate(r['effective_date'])?.year == DateTime.now().year).length;
    // flatten into year headers + entries
    final entries = <Object>[];
    int? year;
    for (final r in rows) {
      final y = parseDate(r['effective_date'])?.toLocal().year;
      if (y != year) {
        year = y;
        entries.add(y ?? 0);
      }
      entries.add(r);
    }
    return MotionScaffold(
      title: 'Promotion history',
      subtitle: '${_rows.length} ${_rows.length == 1 ? 'promotion' : 'promotions'} recorded',
      icon: Icons.history_rounded,
      accent: Accent.ocean,
      onRefresh: _load,
      headerExtra: HeaderSearch(hint: 'Search employee or designation', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        if (!_loading && _error == null)
          SliverPadding(
            padding: const EdgeInsets.only(top: 16),
            sliver: SliverToBoxAdapter(
              child: KpiGrid(children: [
                KpiTile(icon: Icons.workspace_premium_rounded, label: 'Total', value: _rows.length, tone: MarketTone.brand),
                KpiTile(icon: Icons.event_repeat_rounded, label: 'This year', value: thisYear, tone: MarketTone.ok),
                KpiTile(icon: Icons.payments_rounded, label: 'With a raise', value: _rows.where(_hasRaise).length, tone: MarketTone.ok),
              ]),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _filter,
              options: [
                (id: 'all', label: 'All', count: _rows.length),
                (id: 'designation', label: 'Designation change', count: _rows.where(_hasMove).length),
                (id: 'raise', label: 'Salary raise', count: _rows.where(_hasRaise).length),
              ],
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton(height: 110)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(icon: Icons.history_toggle_off_rounded, title: _rows.isEmpty ? 'No promotions yet' : 'No matches')
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (ctx, i) {
                final e = entries[i];
                final last = i == entries.length - 1 || entries[i + 1] is int;
                return FadeSlideIn(index: i, offsetY: 18, child: e is int ? _yearHeader(ctx, e) : _entry(ctx, e as Map<String, dynamic>, last));
              },
            ),
          ),
      ],
    );
  }

  Widget _yearHeader(BuildContext context, int y) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(gradient: Accent.ocean.gradient, borderRadius: BorderRadius.circular(12)),
          child: Text(y == 0 ? 'Undated' : '$y', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: p.line)),
      ]),
    );
  }

  Widget _entry(BuildContext context, Map<String, dynamic> r, bool last) {
    final p = MarketPalette.of(context);
    final name = empName(r['employee']);
    final from = nested(r, 'from_designation');
    final to = nested(r, 'to_designation');
    final date = parseDate(r['effective_date']);
    final raise = toNum(r['raise_value']);
    final lastSal = toNum(r['last_salary']);
    final newSal = toNum(r['new_salary']);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 52,
          child: Column(children: [
            Text(date == null ? '' : DateFormat('d MMM').format(date.toLocal()), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 4),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.card,
                border: Border.all(color: Accent.ocean.primary, width: 3),
              ),
            ),
            Expanded(child: Container(width: 2, color: last ? Colors.transparent : p.line)),
          ]),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlowCard(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  InitialsAvatar(name.isEmpty ? '?' : name, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name.isEmpty ? 'Employee' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                      if (nested(r, 'employee', 'employee_no').isNotEmpty)
                        Text(nested(r, 'employee', 'employee_no'), style: TextStyle(fontSize: 11.5, color: p.label)),
                    ]),
                  ),
                  if (raise != null && raise > 0)
                    StatusPill(r['raise_type'] == 'PERCENTAGE' ? '+${fmtNum(raise)}%' : '+${fmtNum(raise)}', tone: MarketTone.ok, icon: Icons.trending_up_rounded),
                ]),
                const SizedBox(height: 10),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
                  StatusPill(from.isEmpty ? '—' : from, tone: MarketTone.neutral),
                  Icon(Icons.arrow_forward_rounded, size: 15, color: p.label),
                  StatusPill(to.isEmpty ? (from.isEmpty ? '—' : from) : to, tone: MarketTone.brand),
                ]),
                if (lastSal != null || newSal != null) ...[
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'Salary ${fmtNum(lastSal)} → '),
                      TextSpan(text: fmtNum(newSal), style: TextStyle(fontWeight: FontWeight.w700, color: p.ok)),
                    ]),
                    style: TextStyle(fontSize: 12.5, color: p.label),
                  ),
                ],
                if (str(r['remarks']).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(str(r['remarks']), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.text, height: 1.4)),
                ],
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
