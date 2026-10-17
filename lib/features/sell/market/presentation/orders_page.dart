import 'package:flutter/material.dart';
import '../data/market_seller_service.dart';
import 'orders/order_common.dart';
import 'orders/order_detail_page.dart';
import 'widgets/market_ui.dart';

/// Website (market) orders that include this store's items — GET
/// /api/market/seller-orders. Filter by status, search, open an order to
/// accept / pack / deliver / cancel it.
class MarketOrdersPage extends StatefulWidget {
  const MarketOrdersPage({super.key});

  @override
  State<MarketOrdersPage> createState() => _MarketOrdersPageState();
}

class _MarketOrdersPageState extends State<MarketOrdersPage> {
  final _service = MarketSellerService();
  final _search = TextEditingController();

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _filter = 'pending';
  String _query = '';

  static const _filters = [
    ('pending', 'Pending'),
    ('paid', 'Accepted'),
    ('packaged', 'Packed'),
    ('delivered', 'Delivered'),
    ('cancelled', 'Cancelled'),
    ('all', 'All'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final rows = await _service.sellerOrders();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (_rows.isEmpty) setState(() => _error = errorText(e, 'Could not load website orders'));
      marketToast(context, errorText(e, 'Could not load website orders'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, int> get _counts {
    final c = <String, int>{'all': _rows.length};
    for (final r in _rows) {
      final s = '${r['status']}';
      c[s] = (c[s] ?? 0) + 1;
    }
    return c;
  }

  List<Map<String, dynamic>> get _visible {
    final q = _query.trim().toLowerCase();
    return _rows.where((r) {
      if (_filter != 'all' && r['status'] != _filter) return false;
      if (q.isEmpty) return true;
      final b = asMap(r['buyer']);
      final d = asMap(r['delivery']);
      return [r['order_no'], b['name'], b['phone'], b['email'], d['name'], d['phone']]
          .any((v) => (v ?? '').toString().toLowerCase().contains(q));
    }).toList();
  }

  void _onStatusChanged(int id, String status) {
    setState(() {
      _rows = [
        for (final r in _rows) toInt(r['id']) == id ? {...r, 'status': status} : r,
      ];
    });
  }

  void _open(Map<String, dynamic> order) {
    Navigator.of(context).push(marketRoute(MarketOrderDetailPage(order: order, onStatusChanged: _onStatusChanged)));
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final counts = _counts;
    final visible = _visible;

    return MarketScaffold(
      title: 'Website orders',
      subtitle: _loading && _rows.isEmpty ? null : '${_rows.length} orders · ${counts['pending'] ?? 0} pending',
      actions: [
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : () => _load(), icon: const Icon(Icons.refresh)),
      ],
      body: Column(children: [
        Container(
          color: p.card,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(children: [
            TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 14, color: p.text),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search order no, customer or phone',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: p.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: MarketSegmented<String>(
                value: _filter,
                options: [for (final f in _filters) (id: f.$1, label: f.$2, count: counts[f.$1] ?? 0)],
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
          ]),
        ),
        Divider(height: 1, color: p.line),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(silent: true),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _buildBody(visible),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> visible) {
    if (_loading && _rows.isEmpty) return const SkeletonList(key: ValueKey('loading'), itemHeight: 104);
    if (_error != null && _rows.isEmpty) {
      return ListView(key: const ValueKey('error'), children: [
        MarketEmpty(icon: Icons.cloud_off_outlined, title: 'Could not load orders', message: _error, actionLabel: 'Try again', onAction: _load),
      ]);
    }
    if (visible.isEmpty) {
      return ListView(key: ValueKey('empty-$_filter-${_query.isEmpty}'), children: [
        MarketEmpty(
          icon: Icons.receipt_long_outlined,
          title: _query.isNotEmpty ? 'No matching orders' : (_rows.isEmpty ? 'No website orders yet' : 'Nothing here'),
          message: _query.isNotEmpty
              ? 'Try a different order no, name or phone.'
              : 'Orders placed on the Aptigen market for your listings show up here.',
        ),
      ]);
    }
    return ListView.separated(
      key: ValueKey('list-$_filter'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => FadeSlideIn(
        key: ValueKey('o-${visible[i]['id']}'),
        index: i,
        child: _OrderCard(order: visible[i], onTap: () => _open(visible[i])),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onTap;
  const _OrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final status = '${order['status']}';
    final buyer = asMap(order['buyer']);
    final items = toInt(order['item_count']);
    final multi = order['multi_store'] == true;
    final currency = str(order['currency']);

    return MarketCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(str(order['order_no']) ?? '#${order['id']}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text)),
          ),
          const SizedBox(width: 8),
          StatusPill(orderStatusLabel[status] ?? status, tone: orderStatusTone(status), icon: orderStatusIcon(status)),
        ]),
        const SizedBox(height: 4),
        Text(fmtDateTime(order['created_at']), style: TextStyle(fontSize: 12, color: p.label)),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.person_outline, size: 16, color: p.label),
          const SizedBox(width: 6),
          Expanded(
            child: Text(str(buyer['name']) ?? 'Unknown customer',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.text, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          Text(money(toDouble(order['seller_total']), currency: currency),
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.shopping_bag_outlined, size: 15, color: p.label),
          const SizedBox(width: 6),
          Text(items == 1 ? '1 item' : '$items items', style: TextStyle(fontSize: 12, color: p.label)),
          const SizedBox(width: 12),
          Icon(Icons.payments_outlined, size: 15, color: p.label),
          const SizedBox(width: 6),
          Expanded(
            child: Text(paymentName(order['payment_method']),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
          ),
        ]),
        if (multi) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.storefront_outlined, size: 14, color: p.info),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Multi-store order · total shown is your share',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.info)),
            ),
          ]),
        ],
      ]),
    );
  }
}
