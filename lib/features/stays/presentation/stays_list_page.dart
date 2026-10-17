import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../data/stays_service.dart';
import '../models/stay_model.dart';
import 'stay_form_page.dart';

/// Ported from erp/desktop's aptigen module StaysList.tsx — list, create,
/// edit and delete `stays` listings. Renders as body content only (no own
/// Scaffold/AppBar) so callers push it inside their own Scaffold+AppBar,
/// matching this app's MarketPage/NotePage convention.
class StaysListPage extends StatefulWidget {
  const StaysListPage({super.key});

  @override
  State<StaysListPage> createState() => _StaysListPageState();
}

class _StaysListPageState extends State<StaysListPage> {
  final _service = StaysService(ApiClient());
  final _searchController = TextEditingController();
  Timer? _debounce;

  bool _loading = true;
  String? _statusFilter; // null | 'active' | 'draft' | 'inactive'
  List<Stay> _stays = [];
  final Set<int> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _service.loadStays();
      if (!mounted) return;
      setState(() => _stays = result);
    } catch (_) {
      // leave whatever's already loaded on failure
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => setState(() {}));
  }

  List<Stay> get _visibleStays {
    var list = _stays;
    if (_statusFilter != null) list = list.where((s) => s.status == _statusFilter).toList();
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list
          .where((s) =>
              s.title.toLowerCase().contains(query) ||
              (s.city ?? '').toLowerCase().contains(query) ||
              (s.country ?? '').toLowerCase().contains(query))
          .toList();
    }
    return list;
  }

  Future<void> _createOrEdit({Stay? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => StayFormPage(existing: existing)),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Stay stay) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete listing'),
        content: Text('Delete "${stay.title}"? This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busyIds.add(stay.id));
    try {
      await _service.delete(stay.id);
      if (!mounted) return;
      setState(() => _stays.removeWhere((s) => s.id == stay.id));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete "${stay.title}".')));
    } finally {
      if (mounted) setState(() => _busyIds.remove(stay.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stays')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search listings…', isDense: true),
                onChanged: _onSearchChanged,
              ),
            ),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _statusChip(null, 'All'),
                  _statusChip('active', 'Published'),
                  _statusChip('draft', 'Draft'),
                  _statusChip('inactive', 'Inactive'),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String? value, String label) {
    final selected = _statusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _statusFilter = selected ? null : value),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.brand));
    }

    final stays = _visibleStays;
    if (stays.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Icon(Icons.home_outlined, size: 40, color: AppColors.slate400),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _stays.isEmpty ? 'No stays yet. Create your first listing.' : 'No results.',
              style: TextStyle(color: AppColors.slate600),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
      itemCount: stays.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _StayCard(
        stay: stays[index],
        busy: _busyIds.contains(stays[index].id),
        onTap: () => _createOrEdit(existing: stays[index]),
        onDelete: () => _delete(stays[index]),
      ),
    );
  }
}

class _StayCard extends StatelessWidget {
  final Stay stay;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _StayCard({required this.stay, required this.busy, required this.onTap, required this.onDelete});

  Color _statusColor() {
    switch (stay.status) {
      case 'active':
        return AppColors.success;
      case 'inactive':
        return AppColors.slate600;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = [stay.city, stay.country].where((s) => (s ?? '').isNotEmpty).join(', ');
    return Opacity(
      opacity: busy ? 0.5 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: stay.coverUrl != null
                    ? Image.network(stay.coverUrl!, width: 76, height: 76, fit: BoxFit.cover, errorBuilder: (_, _, _) => _placeholderThumb())
                    : _placeholderThumb(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(stay.title.isEmpty ? 'Untitled listing' : stay.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: _statusColor().withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                          child: Text(stay.status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _statusColor())),
                        ),
                      ],
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.place_outlined, size: 13, color: AppColors.slate600),
                          const SizedBox(width: 3),
                          Expanded(child: Text(location, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.slate600))),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (stay.pricePerNight != null)
                          Text('${formatMoney(stay.pricePerNight!, decimalDigits: 0)} / night', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        const Spacer(),
                        if (stay.avgRating != null) ...[
                          const Icon(Icons.star, size: 13, color: AppColors.warning),
                          const SizedBox(width: 2),
                          Text(stay.avgRating!.toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                          onPressed: busy ? null : onDelete,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderThumb() => Container(
        width: 76,
        height: 76,
        color: AppColors.slate100,
        child: const Icon(Icons.home_outlined, color: AppColors.slate400),
      );
}
