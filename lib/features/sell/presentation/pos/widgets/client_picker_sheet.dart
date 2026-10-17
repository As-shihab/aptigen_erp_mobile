import 'package:flutter/material.dart';
import '../../../data/client_model.dart';
import '../../client_form_page.dart';
import '../../widgets/sell_ui.dart' show MarketPalette, MarketCard, MarketEmpty, showMarketSheet;

/// Search + pick a client for the active cart, or quick-add a new one —
/// mirrors desktop's inline "Add new client" flow in PosTerminal.tsx (same
/// `ClientFormPage` full-screen form the standalone Clients list uses,
/// popped with the created client so the caller can auto-select it).
Future<Client?> showClientPickerSheet(BuildContext context, {required List<Client> clients}) {
  return showMarketSheet<Client>(
    context,
    builder: (_) => _ClientPickerSheet(clients: clients),
  );
}

class _ClientPickerSheet extends StatefulWidget {
  final List<Client> clients;
  const _ClientPickerSheet({required this.clients});

  @override
  State<_ClientPickerSheet> createState() => _ClientPickerSheetState();
}

class _ClientPickerSheetState extends State<_ClientPickerSheet> {
  final _searchController = TextEditingController();
  late List<Client> _clients = widget.clients;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Client> get _visible {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _clients;
    return _clients.where((c) => c.name.toLowerCase().contains(query) || c.code.toLowerCase().contains(query) || (c.phone ?? '').contains(query)).toList();
  }

  Future<void> _addNew() async {
    final created = await Navigator.of(context).push<Client>(MaterialPageRoute(builder: (_) => const ClientFormPage()));
    if (created == null) return;
    setState(() => _clients = [created, ..._clients]);
    if (!mounted) return;
    Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        final p = MarketPalette.of(context);
        final clients = _visible;
        return Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Select a client', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: p.text)),
                        const SizedBox(height: 2),
                        Text('${_clients.length} client${_clients.length == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: p.label)),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: p.brand),
                    icon: const Icon(Icons.person_off_outlined, size: 16),
                    label: const Text('Walk-in'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(fontSize: 14, color: p.text),
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 20, color: p.label),
                        hintText: 'Search name, code, phone…',
                        hintStyle: TextStyle(fontSize: 14, color: p.label),
                        isDense: true,
                        filled: true,
                        fillColor: p.surface,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.brand, width: 1.5)),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Add new client',
                    child: Material(
                      color: p.brandSoft,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _addNew,
                        child: SizedBox(width: 46, height: 46, child: Icon(Icons.person_add_alt_1, color: p.brand)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: clients.isEmpty
                  ? ListView(
                      controller: scrollController,
                      children: [
                        MarketEmpty(
                          icon: Icons.person_search_outlined,
                          title: 'No matching clients',
                          message: 'Try another name, code or phone, or add a new client.',
                          actionLabel: 'Add client',
                          onAction: _addNew,
                        ),
                      ],
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: clients.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final client = clients[index];
                        final sub = [client.code, client.phone].where((s) => (s ?? '').isNotEmpty).join(' · ');
                        return MarketCard(
                          onTap: () => Navigator.of(context).pop(client),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: p.brandSoft, shape: BoxShape.circle),
                                child: Text(client.name.isNotEmpty ? client.name[0].toUpperCase() : '?', style: TextStyle(fontWeight: FontWeight.w700, color: p.brand, fontSize: 13)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(client.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: p.text)),
                                    if (sub.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
                                    ],
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, size: 18, color: p.label),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
