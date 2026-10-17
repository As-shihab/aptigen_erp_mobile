import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/storage/app_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../store/data/store_util.dart';

/// Common ISO 4217 codes offered as quick picks — mirrors desktop's
/// ProfileGeneral.tsx `CURRENCY_OPTIONS`. The field itself is a plain string
/// column (`workplaces.currency`, no lookup table backs it), so anything
/// typed that isn't in this shortlist is still accepted, same as desktop.
const _currencyOptions = ['USD', 'EUR', 'GBP', 'BDT', 'INR', 'AED', 'SAR', 'JPY', 'CNY', 'AUD', 'CAD', 'SGD'];

/// Edit the current workplace's name/description/location/currency —
/// mirrors desktop's Profile > General "Edit Workplace" dialog
/// (ProfileGeneral.tsx), including the currency picker that drives
/// `formatMoney()`/`currencySymbol()` everywhere in the app. Any workplace
/// member can edit (no owner-only guard on `PUT workplace/me` server-side).
class EditWorkplacePage extends StatefulWidget {
  const EditWorkplacePage({super.key});

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _client.get('workplace/me', isV8: false);
      final workplace = (res as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _workplace = workplace;
        _nameController.text = (workplace['name'] ?? '').toString();
        _descriptionController.text = (workplace['description'] ?? '').toString();
        _locationController.text = (workplace['location'] ?? '').toString();
        _currencyController.text = (workplace['currency'] ?? 'USD').toString();
      });
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
      await _client.put('workplace', 'me', payload, isV8: false);

      // Mirrors desktop's `patchCachedWorkplace` — merge straight into the
      // cached user blob's workplace/selectedWorkplace so every other
      // screen (workplace name in the shell header, currency everywhere)
      // reflects the change immediately, not just after the next restart.
      final storedUser = await AppStorage.getUser();
      if (storedUser != null) {
        final currentWorkplace = ((storedUser['selectedWorkplace'] ?? storedUser['workplace']) as Map?) ?? {};
        final patchedWorkplace = {...currentWorkplace, 'name': name, 'currency': currency};
        await AppStorage.setUser({...storedUser, 'workplace': patchedWorkplace, 'selectedWorkplace': patchedWorkplace});
      }
      WorkplaceCurrency.set(currency);

      if (!mounted) return;
      Navigator.of(context).pop(true);
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
      appBar: AppBar(title: const Text('Workplace')),
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
                  _infoRow('Code', (workplace['code'] ?? '—').toString()),
                  _infoRow('Slug', (workplace['slug'] ?? '—').toString()),
                  _infoRow('Owner', ((workplace['owner'] as Map?)?['name'] ?? (workplace['owner'] as Map?)?['email'] ?? '—').toString()),
                  _infoRow('Status', (workplace['status'] ?? '—').toString()),
                  _infoRow('Created', displayDate(workplace['created_at'])),
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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppColors.slate600, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
