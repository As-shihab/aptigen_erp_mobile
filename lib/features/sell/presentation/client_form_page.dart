import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../store/data/store_util.dart' show toNum;
import '../data/client_model.dart';
import '../data/client_service.dart';
import '../market/presentation/banners/form_kit.dart' show FieldBlock, MarketTextField, SwitchRow, marketInput;
import 'widgets/sell_ui.dart';

/// Create/edit a client. On create, prefills `code` via desktop's
/// `generate-code` helper (still freely editable) — used both from the
/// Clients list and POS's inline "Add new client" flow, both of which pop
/// with the created/edited `Client` so the caller can auto-select it.
class ClientFormPage extends StatefulWidget {
  final Client? existing;
  const ClientFormPage({super.key, this.existing});

  @override
  State<ClientFormPage> createState() => _ClientFormPageState();
}

class _ClientFormPageState extends State<ClientFormPage> {
  final _client = ApiClient();
  late final _service = ClientService(_client);

  bool get _isEdit => widget.existing != null;

  late final _codeController = TextEditingController(text: widget.existing?.code ?? '');
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late final _phoneController = TextEditingController(text: widget.existing?.phone ?? '');
  late final _emailController = TextEditingController(text: widget.existing?.email ?? '');
  late final _addressController = TextEditingController(text: widget.existing?.address ?? '');
  late final _cityController = TextEditingController(text: widget.existing?.city ?? '');
  late final _countryController = TextEditingController(text: widget.existing?.country ?? '');
  late bool _isActive = widget.existing?.isActive ?? true;
  late int? _groupId = widget.existing?.groupId;

  bool _codeLoading = false;
  bool _groupsLoading = true;
  List<Map<String, dynamic>> _groups = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (!_isEdit) _prefillCode();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final res = await _client.get(r'client_groups?$select=id,name&$filter=is_active eq true&$top=500');
      if (!mounted) return;
      setState(() => _groups = unwrapList(res).cast<Map<String, dynamic>>());
    } catch (_) {
    } finally {
      if (mounted) setState(() => _groupsLoading = false);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _prefillCode() async {
    setState(() => _codeLoading = true);
    final code = await _service.generateCode();
    if (!mounted) return;
    if (code != null && _codeController.text.isEmpty) _codeController.text = code;
    setState(() => _codeLoading = false);
  }

  String? _groupName() {
    for (final g in _groups) {
      if (toNum(g['id']) == _groupId) return (g['name'] ?? '').toString();
    }
    return null;
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    if (code.isEmpty || name.isEmpty) {
      marketToast(context, 'Code and name are required.', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final payload = {
        'code': code,
        'name': name,
        'group_id': _groupId,
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'address': _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        'city': _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
        'country': _countryController.text.trim().isEmpty ? null : _countryController.text.trim(),
        'is_active': _isActive,
      };
      Client saved;
      if (_isEdit) {
        await _service.update(widget.existing!.id, payload);
        saved = Client(
          id: widget.existing!.id,
          code: code,
          name: name,
          phone: payload['phone'] as String?,
          email: payload['email'] as String?,
          address: payload['address'] as String?,
          city: payload['city'] as String?,
          country: payload['country'] as String?,
          isActive: _isActive,
          groupId: _groupId,
          groupName: _groupName(),
        );
      } else {
        saved = await _service.create(payload);
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Could not save this client.', error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    var section = 0;
    Widget block(Widget child) => FadeSlideIn(index: section++, child: child);

    return MarketScaffold(
      title: _isEdit ? 'Edit client' : 'New client',
      subtitle: _isEdit ? widget.existing!.name : 'Customer you can pick in the POS',
      bottom: _saveBar(p),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            block(const SectionHeader('Identity', subtitle: 'How this client shows up on sales and invoices')),
            block(_card([
              FieldBlock(
                label: 'Code',
                required: true,
                child: TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(fontSize: 14, color: p.text),
                  decoration: marketInput(
                    context,
                    hint: 'e.g. CL-0001',
                    prefixIcon: Icon(Icons.tag, size: 18, color: p.label),
                    suffix: _codeLoading
                        ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                        : null,
                  ),
                ),
              ),
              FieldBlock(
                label: 'Name',
                required: true,
                child: MarketTextField(controller: _nameController, hint: 'Full name or business name', icon: Icons.person_outline, capitalization: TextCapitalization.words),
              ),
              FieldBlock(label: 'Client group', help: 'Optional', child: _groupField(p)),
            ])),
            block(const SectionHeader('Contact')),
            block(_card([
              FieldBlock(
                label: 'Phone',
                child: MarketTextField(controller: _phoneController, hint: 'Phone number', keyboardType: TextInputType.phone, icon: Icons.phone_outlined),
              ),
              FieldBlock(
                label: 'Email',
                child: MarketTextField(
                  controller: _emailController,
                  hint: 'name@example.com',
                  keyboardType: TextInputType.emailAddress,
                  icon: Icons.mail_outline,
                  capitalization: TextCapitalization.none,
                ),
              ),
            ])),
            block(const SectionHeader('Address')),
            block(_card([
              FieldBlock(label: 'Street address', child: MarketTextField(controller: _addressController, hint: 'House, road, area', maxLines: 2)),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: FieldBlock(label: 'City', child: MarketTextField(controller: _cityController, hint: 'City', capitalization: TextCapitalization.words))),
                const SizedBox(width: 10),
                Expanded(child: FieldBlock(label: 'Country', child: MarketTextField(controller: _countryController, hint: 'Country', capitalization: TextCapitalization.words))),
              ]),
            ])),
            block(const SectionHeader('Status')),
            block(_card([
              SwitchRow(
                title: 'Active',
                subtitle: _isActive ? 'Shown in the POS client picker' : 'Hidden from new sales',
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
            ])),
          ],
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) => MarketCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _groupField(MarketPalette p) {
    if (_groupsLoading) return const SkeletonBox(height: 44, radius: 10);
    return DropdownButtonFormField<int>(
      initialValue: _groups.any((g) => toNum(g['id']) == _groupId) ? _groupId : null,
      isExpanded: true,
      dropdownColor: p.card,
      style: TextStyle(fontSize: 14, color: p.text),
      decoration: marketInput(context, hint: _groups.isEmpty ? 'No groups yet' : 'Choose a group', prefixIcon: Icon(Icons.folder_shared_outlined, size: 18, color: p.label)),
      items: _groups.map((g) => DropdownMenuItem(value: toNum(g['id']), child: Text((g['name'] ?? '').toString(), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (v) => setState(() => _groupId = v),
    );
  }

  Widget _saveBar(MarketPalette p) => Container(
        decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(_isEdit ? Icons.check : Icons.person_add_alt_1_outlined, size: 20),
                label: Text(_isEdit ? 'Save changes' : 'Create client'),
              ),
            ),
          ),
        ),
      );
}
