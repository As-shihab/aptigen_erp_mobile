import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../data/sales_report_service.dart';
import 'widgets/sell_ui.dart';

const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Mirrors desktop's SalesReport.tsx — date-range filter, two lists (Daily
/// Sales, Sales by Cashier) plus 4 summary tiles computed client-side by
/// summing the daily rows.
class SalesReportPage extends StatefulWidget {
  const SalesReportPage({super.key});

  @override
  State<SalesReportPage> createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
  final _service = SalesReportService(ApiClient());
  DateTimeRange _range = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 30)), end: DateTime.now());

  bool _loading = true;
  List<DailySalesRow> _daily = [];
  List<CashierSalesRow> _cashier = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _service.load(start: _range.start, end: _range.end);
      if (!mounted) return;
      setState(() {
        _daily = result.daily;
        _cashier = result.cashier;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(context: context, firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)), lastDate: DateTime.now(), initialDateRange: _range);
    if (picked == null) return;
    setState(() => _range = picked);
    _load();
  }

  /// Quick range presets — same shape as the default range (now − N days → now).
  void _setPreset(int days) {
    if (days == 0) {
      _pickRange();
      return;
    }
    setState(() => _range = DateTimeRange(start: DateTime.now().subtract(Duration(days: days)), end: DateTime.now()));
    _load();
  }

  int get _activePreset {
    final now = DateTime.now();
    final endIsToday = _range.end.year == now.year && _range.end.month == now.month && _range.end.day == now.day;
    final days = _range.end.difference(_range.start).inDays;
    return endIsToday && const [7, 30, 90].contains(days) ? days : 0;
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final totalOrders = _daily.fold<int>(0, (sum, d) => sum + d.orders);
    final totalRevenue = _daily.fold<double>(0, (sum, d) => sum + d.revenue);
    final totalDiscount = _daily.fold<double>(0, (sum, d) => sum + d.discount);
    final totalTax = _daily.fold<double>(0, (sum, d) => sum + d.tax);
    final firstLoad = _loading && _daily.isEmpty && _cashier.isEmpty;

    return MarketScaffold(
      title: 'Sales reports',
      subtitle: _rangeLabel(_range),
      body: RefreshIndicator(
        onRefresh: _load,
        color: p.brand,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _rangeRow(p),
            if (firstLoad)
              _skeleton()
            else
              AnimatedOpacity(
                opacity: _loading ? 0.5 : 1,
                duration: const Duration(milliseconds: 200),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SectionHeader('Summary', subtitle: 'Totals across every day in the range'),
                  _kpis(totalOrders, totalRevenue, totalDiscount, totalTax),
                  SectionHeader('Daily sales', subtitle: _daily.isEmpty ? null : '${_daily.length} ${_daily.length == 1 ? 'day' : 'days'} with sales'),
                  FadeSlideIn(index: 4, child: _dailyCard(p)),
                  SectionHeader('Sales by cashier', subtitle: _cashier.isEmpty ? null : 'Share of revenue per cashier'),
                  FadeSlideIn(index: 5, child: _cashierCard(p, totalRevenue)),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rangeRow(MarketPalette p) {
    return Row(children: [
      Expanded(
        child: MarketSegmented<int>(
          value: _activePreset,
          options: const [
            (id: 7, label: '7 days', count: null),
            (id: 30, label: '30 days', count: null),
            (id: 90, label: '90 days', count: null),
            (id: 0, label: 'Custom', count: null),
          ],
          onChanged: _setPreset,
        ),
      ),
      const SizedBox(width: 8),
      Material(
        color: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: p.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _pickRange,
          child: Padding(padding: const EdgeInsets.all(9), child: Icon(Icons.date_range_outlined, size: 20, color: p.brand)),
        ),
      ),
    ]);
  }

  Widget _kpis(int orders, double revenue, double discount, double tax) {
    String m(num v) => money(v);
    final tiles = [
      KpiTile(icon: Icons.receipt_long_outlined, label: 'Orders', value: orders),
      KpiTile(icon: Icons.trending_up, label: 'Revenue', value: revenue, format: m, tone: MarketTone.ok),
      KpiTile(icon: Icons.local_offer_outlined, label: 'Discount', value: discount, format: m, tone: MarketTone.warn),
      KpiTile(icon: Icons.account_balance_outlined, label: 'Tax', value: tax, format: m, tone: MarketTone.info),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.35,
      children: [for (var i = 0; i < tiles.length; i++) FadeSlideIn(index: i, child: tiles[i])],
    );
  }

  Widget _dailyCard(MarketPalette p) {
    if (_daily.isEmpty) return _emptyCard(p, Icons.calendar_month_outlined, 'No sales in this range', 'Pick a wider range to see daily totals.');
    final head = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.label);
    return MarketCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Container(
          color: p.surface,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(children: [
            Expanded(flex: 5, child: Text('Date', style: head)),
            Expanded(flex: 2, child: Text('Orders', textAlign: TextAlign.right, style: head)),
            Expanded(flex: 4, child: Text('Revenue', textAlign: TextAlign.right, style: head)),
          ]),
        ),
        for (var i = 0; i < _daily.length; i++) ...[
          Divider(height: 1, color: p.line),
          _dailyRow(p, _daily[i]),
        ],
      ]),
    );
  }

  Widget _dailyRow(MarketPalette p, DailySalesRow d) {
    final extras = [
      if (d.discount > 0) 'Discount ${money(d.discount)}',
      if (d.tax > 0) 'Tax ${money(d.tax)}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Expanded(
          flex: 5,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_dayTitle(d.date), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
            if (extras.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(extras.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.label)),
            ],
          ]),
        ),
        Expanded(flex: 2, child: Text('${d.orders}', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: p.text))),
        Expanded(
          flex: 4,
          child: Text(money(d.revenue), textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text)),
        ),
      ]),
    );
  }

  Widget _cashierCard(MarketPalette p, double totalRevenue) {
    if (_cashier.isEmpty) return _emptyCard(p, Icons.badge_outlined, 'No cashier sales yet', 'Sales rung up at the POS appear here by cashier.');
    final maxRevenue = _cashier.fold<double>(0, (m, c) => math.max(m, c.revenue));
    return MarketCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < _cashier.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 62, color: p.line),
          _cashierRow(p, _cashier[i], totalRevenue, maxRevenue),
        ],
      ]),
    );
  }

  Widget _cashierRow(MarketPalette p, CashierSalesRow c, double totalRevenue, double maxRevenue) {
    final name = c.cashierName.trim().isEmpty ? 'Unknown' : c.cashierName.trim();
    final share = totalRevenue > 0 ? c.revenue / totalRevenue : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: p.brandSoft, shape: BoxShape.circle),
          child: Text(name[0].toUpperCase(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.brand)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text))),
              const SizedBox(width: 8),
              Text(money(c.revenue), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
            ]),
            const SizedBox(height: 3),
            Text('${c.orders} ${c.orders == 1 ? 'order' : 'orders'} · ${(share * 100).toStringAsFixed(0)}% of revenue', style: TextStyle(fontSize: 11.5, color: p.label)),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: maxRevenue > 0 ? (c.revenue / maxRevenue).clamp(0, 1).toDouble() : 0,
                minHeight: 5,
                color: p.brand,
                backgroundColor: p.surface,
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _emptyCard(MarketPalette p, IconData icon, String title, String message) => MarketCard(
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: p.label),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
              const SizedBox(height: 2),
              Text(message, style: TextStyle(fontSize: 12, color: p.label)),
            ]),
          ),
        ]),
      );

  Widget _skeleton() => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.35,
            children: List.generate(4, (_) => const SkeletonBox(radius: 12)),
          ),
          const SizedBox(height: 18),
          const SkeletonBox(height: 280, radius: 12),
        ]),
      );
}

String _rangeLabel(DateTimeRange r) {
  final s = r.start, e = r.end;
  if (s.year == e.year) return '${s.day} ${_monthsShort[s.month - 1]} – ${e.day} ${_monthsShort[e.month - 1]} ${e.year}';
  return '${s.day} ${_monthsShort[s.month - 1]} ${s.year} – ${e.day} ${_monthsShort[e.month - 1]} ${e.year}';
}

/// "2026-10-12" → "Today" / "Yesterday" / "12 Oct 2026"; raw text otherwise.
String _dayTitle(String raw) {
  final d = DateTime.tryParse(raw);
  return d == null ? raw : dayLabel(d);
}
