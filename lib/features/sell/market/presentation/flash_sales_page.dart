import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../data/market_seller_service.dart';
import 'flash_sales/flash_sale_card.dart';
import 'flash_sales/flash_sale_editor_page.dart';
import 'widgets/market_ui.dart';

/// Flash sales — time-boxed sale prices on the seller's own listings
/// (desktop Sell → Online → Market → Flash sales). One shared one-second
/// ticker drives every countdown on screen.
class MarketFlashSalesPage extends StatefulWidget {
  const MarketFlashSalesPage({super.key});

  @override
  State<MarketFlashSalesPage> createState() => _MarketFlashSalesPageState();
}

class _MarketFlashSalesPageState extends State<MarketFlashSalesPage> {
  final _api = MarketSellerService();
  final _clock = ValueNotifier<DateTime>(DateTime.now());
  Timer? _ticker;

  List<Map<String, dynamic>> _sales = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _clock.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final needs = _sales.any((s) => s['state'] == 'live' || s['state'] == 'scheduled');
    if (needs && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _clock.value = DateTime.now());
    } else if (!needs) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      if (_sales.isEmpty) _loading = true;
    });
    try {
      final list = await _api.flashSales();
      if (!mounted) return;
      setState(() => _sales = list);
      _syncTicker();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load flash sales');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open([Map<String, dynamic>? sale]) async {
    final changed = await Navigator.of(context).push<bool>(marketRoute(FlashSaleEditorPage(sale: sale)));
    if (changed == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> sale) async {
    final ok = await confirmMarket(context,
        title: 'Delete flash sale', message: 'Delete "${sale['name'] ?? ''}"? Its sale prices stop applying right away.');
    if (!ok || !mounted) return;
    try {
      await _api.deleteFlashSale(toInt(sale['id']));
      if (!mounted) return;
      marketToast(context, 'Flash sale deleted');
      _load();
    } on ApiException catch (e) {
      if (mounted) marketToast(context, e.message, error: true);
    }
  }

  int _count(String state) => _sales.where((s) => s['state'] == state).length;

  @override
  Widget build(BuildContext context) {
    final visible = _filter == 'all' ? _sales : _sales.where((s) => s['state'] == _filter).toList();
    final units = _sales.fold<double>(0, (a, s) => a + toDouble(s['units_sold']));
    final revenue = _sales.fold<double>(0, (a, s) => a + toDouble(s['revenue']));

    Widget body;
    if (_loading) {
      body = const SkeletonList(key: ValueKey('loading'), count: 4, itemHeight: 180);
    } else if (_error != null && _sales.isEmpty) {
      body = ListView(key: const ValueKey('error'), children: [
        MarketEmpty(icon: Icons.cloud_off_outlined, title: 'Could not load flash sales', message: _error, actionLabel: 'Try again', onAction: _load),
      ]);
    } else {
      body = ListView(
        key: const ValueKey('list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          LayoutBuilder(builder: (context, c) {
            final w = (c.maxWidth - 10) / 2;
            return Wrap(spacing: 10, runSpacing: 10, children: [
              SizedBox(width: w, child: KpiTile(icon: Icons.bolt, label: 'Live', value: _count('live'), tone: MarketTone.ok)),
              SizedBox(width: w, child: KpiTile(icon: Icons.schedule, label: 'Scheduled', value: _count('scheduled'), tone: MarketTone.info)),
              SizedBox(width: w, child: KpiTile(icon: Icons.inventory_2_outlined, label: 'Units sold', value: units, tone: MarketTone.brand)),
              SizedBox(
                width: w,
                child: KpiTile(icon: Icons.account_balance_wallet_outlined, label: 'Revenue', value: revenue, format: (v) => money(v), tone: MarketTone.brand),
              ),
            ]);
          }),
          const SizedBox(height: 16),
          MarketSegmented<String>(
            value: _filter,
            onChanged: (v) => setState(() => _filter = v),
            options: [
              (id: 'all', label: 'All', count: _sales.length),
              (id: 'live', label: 'Live', count: _count('live')),
              (id: 'scheduled', label: 'Scheduled', count: _count('scheduled')),
              (id: 'paused', label: 'Paused', count: _count('paused')),
              (id: 'ended', label: 'Ended', count: _count('ended')),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: visible.isEmpty
                ? MarketEmpty(
                    key: ValueKey('empty-$_filter'),
                    icon: Icons.bolt_outlined,
                    title: _sales.isEmpty ? 'No flash sales yet' : 'Nothing here',
                    message: _sales.isEmpty
                        ? 'Run a time-boxed sale price on your listings, with an optional stock limit.'
                        : 'No ${_filter == 'all' ? '' : '$_filter '}flash sales right now.',
                    actionLabel: _sales.isEmpty ? 'New flash sale' : null,
                    onAction: _sales.isEmpty ? () => _open() : null,
                  )
                : Column(
                    key: ValueKey('list-$_filter'),
                    children: [
                      for (var i = 0; i < visible.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: FadeSlideIn(
                            index: i,
                            child: FlashSaleCard(
                              sale: visible[i],
                              clock: _clock,
                              onTap: () => _open(visible[i]),
                              onDelete: () => _delete(visible[i]),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      );
    }

    return MarketScaffold(
      title: 'Flash sales',
      subtitle: 'Time-boxed prices on your listings',
      actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load)],
      fab: FloatingActionButton.extended(onPressed: () => _open(), icon: const Icon(Icons.add), label: const Text('New sale')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: body),
      ),
    );
  }
}
