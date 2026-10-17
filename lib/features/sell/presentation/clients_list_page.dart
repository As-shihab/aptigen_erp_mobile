import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../data/client_model.dart';
import '../data/client_service.dart';
import 'client_form_page.dart';
import 'widgets/sell_ui.dart';

/// Full CRUD over `clients` — mirrors desktop's ClientList.tsx. Reused by
/// POS's inline "Add new client" flow too (pushed the same way, caller pops
/// with the created `Client`).
class ClientsListPage extends StatefulWidget {
  const ClientsListPage({super.key});

  @override
  State<ClientsListPage> createState() => _ClientsListPageState();
}

class _ClientsListPageState extends State<ClientsListPage> {
  final _service = ClientService(ApiClient());
  final _searchController = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Client> _clients = [];
  final Set<int> _busyIds = {};
  String _filter = 'ALL'; // ALL | ACTIVE | INACTIVE

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.list();
      if (!mounted) return;
      setState(() => _clients = result);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load clients.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Client> get _visible {
    final query = _searchController.text.trim().toLowerCase();
    return _clients.where((c) {
      if (_filter == 'ACTIVE' && !c.isActive) return false;
      if (_filter == 'INACTIVE' && c.isActive) return false;
      if (query.isEmpty) return true;
      return c.name.toLowerCase().contains(query) || c.code.toLowerCase().contains(query) || (c.phone ?? '').contains(query);
    }).toList();
  }

  Future<void> _createOrEdit({Client? existing}) async {
    final saved = await Navigator.of(context).push<Client>(marketRoute(ClientFormPage(existing: existing)));
    if (saved != null) _load();
  }

  Future<void> _delete(Client client) async {
    final confirmed = await confirmMarket(
      context,
      title: 'Delete client',
      message: 'Delete "${client.name}"? This can\'t be undone.',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busyIds.add(client.id));
    try {
      await _service.delete(client.id);
      if (!mounted) return;
      setState(() => _clients.removeWhere((c) => c.id == client.id));
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Could not delete this client.', error: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(client.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final visible = _visible;
    final active = _clients.where((c) => c.isActive).length;
    final inactive = _clients.length - active;

    return MarketScaffold(
      title: 'Clients',
      subtitle: _loading && _clients.isEmpty ? 'Loading…' : '${visible.length} of ${_clients.length}',
      fab: FloatingActionButton.extended(onPressed: () => _createOrEdit(), icon: const Icon(Icons.add), label: const Text('New client')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: KpiTile(icon: Icons.people_alt_outlined, label: 'Clients', value: _clients.length, tone: MarketTone.brand)),
                  const SizedBox(width: 10),
                  Expanded(child: KpiTile(icon: Icons.verified_user_outlined, label: 'Active', value: active, tone: MarketTone.ok)),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search name, code or phone',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    fillColor: p.card,
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_searchController.clear)),
                  ),
                ),
                const SizedBox(height: 10),
                MarketSegmented<String>(
                  value: _filter,
                  onChanged: (v) => setState(() => _filter = v),
                  options: [
                    (id: 'ALL', label: 'All', count: _clients.length),
                    (id: 'ACTIVE', label: 'Active', count: active),
                    (id: 'INACTIVE', label: 'Inactive', count: inactive),
                  ],
                ),
              ]),
            ),
          ),
          ..._listSlivers(p, visible),
        ]),
      ),
    );
  }

  List<Widget> _listSlivers(MarketPalette p, List<Client> visible) {
    if (_loading && _clients.isEmpty) {
      return const [SliverFillRemaining(hasScrollBody: false, child: SkeletonList(count: 6, itemHeight: 64))];
    }
    if (_error != null) {
      return [SliverFillRemaining(hasScrollBody: false, child: MarketEmpty(icon: Icons.cloud_off_outlined, title: _error!, actionLabel: 'Try again', onAction: _load))];
    }
    if (visible.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: MarketEmpty(
            icon: Icons.people_alt_outlined,
            title: _clients.isEmpty ? 'No clients yet' : 'Nothing matches',
            message: _clients.isEmpty ? 'Clients you add here can be picked at checkout in the POS.' : 'Try another search or filter.',
            actionLabel: _clients.isEmpty ? 'Add client' : null,
            onAction: _clients.isEmpty ? () => _createOrEdit() : null,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        sliver: SliverList.separated(
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) => FadeSlideIn(index: i, child: _row(p, visible[i])),
        ),
      ),
    ];
  }

  Widget _row(MarketPalette p, Client client) {
    final busy = _busyIds.contains(client.id);
    final meta = [client.code, client.groupName, client.phone].where((s) => (s ?? '').isNotEmpty).join(' · ');
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: busy ? 0.5 : 1,
      child: MarketCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        onTap: busy ? null : () => _createOrEdit(existing: client),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: client.isActive ? p.brandSoft : p.neutralBg, borderRadius: BorderRadius.circular(10)),
            child: Text(
              client.name.isNotEmpty ? client.name[0].toUpperCase() : '?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: client.isActive ? p.brand : p.neutral),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(client.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                ),
                if (!client.isActive) ...[
                  const SizedBox(width: 6),
                  const StatusPill('Inactive', tone: MarketTone.neutral),
                ],
              ]),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
              ],
            ]),
          ),
          IconButton(
            tooltip: 'Delete client',
            icon: Icon(Icons.delete_outline, size: 20, color: p.error),
            onPressed: busy ? null : () => _delete(client),
          ),
        ]),
      ),
    );
  }
}
