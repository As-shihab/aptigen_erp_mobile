import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/storage/app_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../shared/ui/motion_kit.dart';
import '../../store/data/store_util.dart';

/// Common ISO 4217 codes offered as quick picks — mirrors desktop's
/// ProfileGeneral.tsx `CURRENCY_OPTIONS`. The field itself is a plain string
/// column (`workplaces.currency`, no lookup table backs it), so anything
/// typed that isn't in this shortlist is still accepted, same as desktop.
const _currencyOptions = ['USD', 'EUR', 'GBP', 'BDT', 'INR', 'AED', 'SAR', 'JPY', 'CNY', 'AUD', 'CAD', 'SGD'];

String _ownerName(Map<String, dynamic> w) {
  final owner = w['owner'] as Map?;
  final name = (owner?['name'] ?? '').toString().trim();
  if (name.isNotEmpty) return name;
  final email = (owner?['email'] ?? '').toString().trim();
  return email.isEmpty ? '—' : email;
}

String _text(dynamic v) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? '—' : s;
}

/// Edit a workplace's name/description/location/currency — mirrors
/// desktop's Profile › General slide-in editor (ProfileGeneral.tsx).
///
/// Pass a [workplace] row from `GET workplace/mine` to edit that workplace;
/// without one, the current workplace is loaded from `workplace/me`. The
/// current workplace saves through `PUT workplace/me` (and patches the
/// cached session + currency); any other through `PUT workplace/:id`. The
/// server rejects both with 403 unless the user is the owner or holds a
/// role with the workplace edit permission.
class EditWorkplacePage extends StatefulWidget {
  final Map<String, dynamic>? workplace;
  const EditWorkplacePage({super.key, this.workplace});

  @override
  State<EditWorkplacePage> createState() => _EditWorkplacePageState();
}

class _EditWorkplacePageState extends State<EditWorkplacePage> {
  final _client = ApiClient();
  final _currencyController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _workplace;

  late final _nameController = TextEditingController();
  late final _descriptionController = TextEditingController();
  late final _locationController = TextEditingController();

  bool get _isCurrent => widget.workplace == null || widget.workplace!['is_current'] == true;

  @override
  void initState() {
    super.initState();
    final given = widget.workplace;
    if (given != null) {
      _fill(given);
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  void _fill(Map<String, dynamic> workplace) {
    _workplace = workplace;
    _nameController.text = (workplace['name'] ?? '').toString();
    _descriptionController.text = (workplace['description'] ?? '').toString();
    _locationController.text = (workplace['location'] ?? '').toString();
    _currencyController.text = (workplace['currency'] ?? 'USD').toString();
  }

  Future<void> _load() async {
    try {
      final res = await _client.get('workplace/me', isV8: false);
      final map = (res is Map && res['value'] is Map) ? res['value'] as Map : res as Map;
      if (!mounted) return;
      setState(() => _fill(map.cast<String, dynamic>()));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load workplace details.')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required.')));
      return;
    }
    final currency = _currencyController.text.trim().toUpperCase().isEmpty ? 'USD' : _currencyController.text.trim().toUpperCase();
    setState(() => _saving = true);
    try {
      final payload = {
        'name': name,
        'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        'location': _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
        'currency': currency,
      };
      final Object target = _isCurrent ? 'me' : (_workplace?['id'] ?? widget.workplace?['id'] ?? 'me');
      await _client.put('workplace', target, payload, isV8: false);

      if (_isCurrent) {
        // Mirrors desktop's `patchCachedWorkplace` — merge straight into the
        // cached user blob's workplace/selectedWorkplace so every other
        // screen (workplace name in the shell header, currency everywhere)
        // reflects the change immediately, then re-derive the currency.
        final storedUser = await AppStorage.getUser();
        if (storedUser != null) {
          final currentWorkplace = ((storedUser['selectedWorkplace'] ?? storedUser['workplace']) as Map?) ?? {};
          final patchedWorkplace = {...currentWorkplace, 'name': name, 'currency': currency};
          await AppStorage.setUser({...storedUser, 'workplace': patchedWorkplace, 'selectedWorkplace': patchedWorkplace});
        }
        WorkplaceCurrency.set(currency);
        await WorkplaceCurrency.refresh(_client);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      final msg = e.statusCode == 403 ? e.message : 'Could not save workplace details.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save workplace details.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workplace = _workplace;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit workplace')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Name *')),
                const SizedBox(height: 12),
                TextField(controller: _descriptionController, maxLines: 3, minLines: 2, decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true)),
                const SizedBox(height: 12),
                TextField(controller: _locationController, decoration: const InputDecoration(labelText: 'Location')),
                const SizedBox(height: 12),
                DropdownMenu<String>(
                  controller: _currencyController,
                  width: double.infinity,
                  enableFilter: true,
                  requestFocusOnTap: true,
                  label: const Text('Currency'),
                  helperText: 'Reported currency for money figures across the workplace (e.g. Store Analytics\' Stock Value). Pick a common code or type your own.',
                  dropdownMenuEntries: _currencyOptions.map((c) => DropdownMenuEntry(value: c, label: c)).toList(),
                  onSelected: (v) => _currencyController.text = v ?? _currencyController.text,
                ),
                if (workplace != null) ...[
                  const SizedBox(height: 24),
                  Text('Details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.slate600)),
                  const SizedBox(height: 8),
                  InfoRow('Code', _text(workplace['code'])),
                  InfoRow('Slug', _text(workplace['slug'])),
                  InfoRow('Owner', _ownerName(workplace)),
                  InfoRow('Status', _text(workplace['status'])),
                  InfoRow('Created', displayDate(workplace['created_at'])),
                ],
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: (_saving || _loading) ? null : _save,
              child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save changes'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Read-only view of a workplace the user belongs to but may not edit
/// (no `can_edit` from `GET workplace/mine`) — no edit controls at all.
class WorkplaceDetailsPage extends StatelessWidget {
  final Map<String, dynamic> workplace;
  const WorkplaceDetailsPage({super.key, required this.workplace});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final isOwner = workplace['relation'] == 'owner';
    final roles = (workplace['roles'] as List?)?.map((r) => r.toString()).where((r) => r.isNotEmpty).toList() ?? const <String>[];
    final memberRole = (workplace['member_role'] ?? '').toString();
    final roleText = roles.isNotEmpty ? roles.join(', ') : (memberRole.isEmpty ? '—' : memberRole);
    final name = (workplace['name'] ?? '').toString();

    return MarketScaffold(
      title: 'Workplace',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          FadeSlideIn(
            child: MarketCard(
              child: Row(children: [
                InitialsAvatar(name, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      StatusPill(isOwner ? 'Owner' : 'Member', tone: isOwner ? MarketTone.info : MarketTone.neutral),
                      if (workplace['is_current'] == true) const StatusPill('Current', tone: MarketTone.ok, icon: Icons.check_circle_outline),
                      const StatusPill('Read only', icon: Icons.lock_outline),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
          const SectionHeader('Details'),
          FadeSlideIn(
            index: 1,
            child: MarketCard(
              child: Column(children: [
                InfoRow('Code', _text(workplace['code'])),
                InfoRow('Owner', _ownerName(workplace)),
                InfoRow('Your role', roleText),
                InfoRow('Currency', _text(workplace['currency'])),
                InfoRow('Country', _text(workplace['country'])),
                InfoRow('Language', _text(workplace['language'])),
                InfoRow('Location', _text(workplace['location'])),
                InfoRow('Status', _text(workplace['status'])),
                InfoRow('Created', displayDate(workplace['created_at'])),
              ]),
            ),
          ),
          if (_text(workplace['description']) != '—') ...[
            const SectionHeader('Description'),
            FadeSlideIn(
              index: 2,
              child: MarketCard(child: Text(workplace['description'].toString(), style: TextStyle(fontSize: 13, color: p.text))),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Only the owner or a role with workplace edit permission can change these details.',
            style: TextStyle(fontSize: 12, color: p.label),
          ),
        ],
      ),
    );
  }
}
