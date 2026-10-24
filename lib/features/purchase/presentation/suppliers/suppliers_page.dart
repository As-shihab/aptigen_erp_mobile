import 'package:flutter/material.dart';
import '../../../../core/utils/currency.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../../../shared/ui/motion_wizard.dart';
import '../../data/purchase_dashboard_service.dart' show purchaseSpendStatuses, purchaseAwaitingDelivery, purchaseStatusLabel;
import '../../data/supplier_service.dart';

// Suppliers — port of desktop Supplier.tsx: list with status / code / name /
// group / email / phone / country, search, create (auto supplier code via
// generate-code) and edit as a step wizard, delete. On the phone a tap
// opens a detail view with the supplier's purchase orders and spend.

const _statuses = [('ACTIVE', 'Active'), ('INACTIVE', 'Inactive')];

String _statusLabel(String s) => s == 'ACTIVE' ? 'Active' : (s == 'INACTIVE' ? 'Inactive' : humanize(s));
MarketTone _statusTone(String s) => s == 'ACTIVE' ? MarketTone.ok : MarketTone.error;

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  final _service = SupplierService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _groups = [];
  String _q = '';
  String _chip = 'All';

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
      final d = await _service.loadSuppliers();
      if (!mounted) return;
      setState(() {
        _rows = d.suppliers;
        _groups = d.groups;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load suppliers'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, bool Function(Map<String, dynamic>)> get _chips => {
        'All': (_) => true,
        'Active': (r) => str(r['status']) == 'ACTIVE',
        'Inactive': (r) => str(r['status']) != 'ACTIVE',
      };

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    final pred = _chips[_chip]!;
    return _rows.where((r) {
      if (!pred(r)) return false;
      if (q.isEmpty) return true;
      final hay = [r['supplier_code'], r['supplier_name'], r['email'], r['phone'], r['city'], r['country'], nested(r, 'group', 'group_name')]
          .map(str)
          .join(' ')
          .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _openForm([Map<String, dynamic>? row]) async {
    final saved = await showMotionSheet<bool>(context, (_) => SupplierFormSheet(service: _service, groups: _groups, existing: row));
    if (saved == true) {
      if (mounted) marketToast(context, row == null ? 'Supplier created' : 'Supplier updated');
      _load();
    }
  }

  Future<bool> _delete(Map<String, dynamic> row) async {
    final ok = await confirmMarket(context, title: 'Delete supplier?', message: 'Delete supplier "${str(row['supplier_name'])}"?');
    if (!ok) return false;
    try {
      await _service.deleteSupplier(row['id']);
      if (mounted) {
        setState(() => _rows.removeWhere((r) => r['id'] == row['id']));
        marketToast(context, 'Supplier deleted');
      }
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete supplier'), error: true);
      return false;
    }
  }

  Future<void> _more(Map<String, dynamic> row) async {
    final key = await showActionSheet(context, title: str(row['supplier_name']), actions: [
      (key: 'view', label: 'View details', icon: Icons.visibility_outlined, destructive: false),
      (key: 'edit', label: 'Edit', icon: Icons.edit_outlined, destructive: false),
      (key: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted || key == null) return;
    if (key == 'view') _openDetail(row);
    if (key == 'edit') _openForm(row);
    if (key == 'delete') _delete(row);
  }

  void _openDetail(Map<String, dynamic> row) {
    pushMotion(context, SupplierDetailPage(supplier: row, groups: _groups, service: _service)).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final chips = _chips;
    return MotionScaffold(
      title: 'Suppliers',
      subtitle: '${_rows.length} ${_rows.length == 1 ? 'supplier' : 'suppliers'}',
      icon: Icons.local_shipping_outlined,
      onRefresh: _load,
      onFab: () => _openForm(),
      fabLabel: 'New',
      headerExtra: HeaderSearch(hint: 'Search code, name, email, phone', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _chip,
              options: [for (final k in chips.keys) (id: k, label: k, count: _rows.where(chips[k]!).length)],
              onChanged: (v) => setState(() => _chip = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton()
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.local_shipping_outlined,
            title: _rows.isEmpty ? 'No suppliers yet' : 'No matches',
            message: _rows.isEmpty ? 'Add the companies you buy from.' : null,
            actionLabel: _rows.isEmpty ? 'New supplier' : null,
            onAction: _rows.isEmpty ? () => _openForm() : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final group = nested(r, 'group', 'group_name');
              final contact = [str(r['email']), str(r['phone'])].where((s) => s.isNotEmpty).join(' · ');
              final meta = [str(r['supplier_code']), if (group.isNotEmpty) group, if (str(r['country']).isNotEmpty) str(r['country'])].join(' · ');
              return MotionTile(
                key: ValueKey(r['id']),
                leading: InitialsAvatar(str(r['supplier_name']), size: 42),
                title: str(r['supplier_name']),
                subtitle: contact.isEmpty ? null : contact,
                meta: meta,
                trailing: StatusPill(_statusLabel(str(r['status'])), tone: _statusTone(str(r['status']))),
                onTap: () => _openDetail(r),
                onLongPress: () => _more(r),
                onDelete: () => _delete(r),
              );
            },
          ),
      ],
    );
  }
}

// ── Create / edit wizard ────────────────────────────────────────────────

class SupplierFormSheet extends StatefulWidget {
  final SupplierService service;
  final List<Map<String, dynamic>> groups;
  final Map<String, dynamic>? existing;
  const SupplierFormSheet({super.key, required this.service, required this.groups, this.existing});

  @override
  State<SupplierFormSheet> createState() => _SupplierFormSheetState();
}

class _SupplierFormSheetState extends State<SupplierFormSheet> {
  late final _code = TextEditingController(text: str(widget.existing?['supplier_code']));
  late final _name = TextEditingController(text: str(widget.existing?['supplier_name']));
  late final _email = TextEditingController(text: str(widget.existing?['email']));
  late final _phone = TextEditingController(text: str(widget.existing?['phone']));
  late final _address = TextEditingController(text: str(widget.existing?['address']));
  late final _city = TextEditingController(text: str(widget.existing?['city']));
  late final _country = TextEditingController(text: str(widget.existing?['country']));
  late Object? _groupId = widget.existing?['group_id'];
  late String _status = str(widget.existing?['status']).isEmpty ? 'ACTIVE' : str(widget.existing?['status']);
  bool _generating = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (!_isEdit) _generateCode();
  }

  Future<void> _generateCode() async {
    setState(() => _generating = true);
    final code = await widget.service.generateSupplierCode();
    if (!mounted) return;
    setState(() {
      _generating = false;
      if (code != null && _code.text.trim().isEmpty) _code.text = code;
    });
  }

  @override
  void dispose() {
    for (final c in [_code, _name, _email, _phone, _address, _city, _country]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _nullable(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  List<PickOption> get _groupOptions {
    final opts = [for (final g in widget.groups) PickOption(g['id'], str(g['group_name']))];
    // Keep an inactive group the supplier already belongs to selectable.
    final current = widget.existing?['group'];
    if (_groupId != null && current is Map && !opts.any((o) => o.id.toString() == _groupId.toString())) {
      opts.add(PickOption(_groupId!, str(current['group_name'])));
    }
    return opts;
  }

  String get _groupName => _groupOptions.where((o) => o.id.toString() == _groupId?.toString()).firstOrNull?.label ?? '';

  Future<bool> _save() async {
    final body = {
      'group_id': _groupId == null ? null : int.tryParse(_groupId.toString()) ?? _groupId,
      'supplier_code': _code.text.trim(),
      'supplier_name': _name.text.trim(),
      'email': _nullable(_email),
      'phone': _nullable(_phone),
      'address': _nullable(_address),
      'city': _nullable(_city),
      'country': _nullable(_country),
      'status': _status,
    };
    try {
      await widget.service.saveSupplier(body, id: widget.existing?['id']);
      if (mounted) Navigator.pop(context, true);
      return true;
    } catch (e) {
      if (mounted) {
        marketToast(context, supplierErrorMessage(e, 'Failed to save supplier', codeColumn: 'supplier_code', codeLabel: 'supplier code'), error: true);
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MotionWizardSheet(
      title: _isEdit ? 'Edit supplier' : 'New supplier',
      subtitle: _isEdit ? str(widget.existing!['supplier_name']) : null,
      submitLabel: _isEdit ? 'Save changes' : 'Create',
      onSubmit: _save,
      steps: [
        WizardStep(
          title: 'Basics',
          icon: Icons.badge_outlined,
          caption: 'Code, name, group and status',
          validate: () {
            if (_code.text.trim().isEmpty) return 'Supplier code is required';
            if (_name.text.trim().isEmpty) return 'Supplier name is required';
            return null;
          },
          builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FormLabel(
              label: 'Supplier code',
              required: true,
              child: TextField(
                controller: _code,
                enabled: !_generating,
                decoration: motionInput(
                  context,
                  hint: 'e.g. SUP-2026-0001',
                  icon: Icons.tag_rounded,
                  suffix: _generating
                      ? Padding(padding: const EdgeInsets.all(13), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.brand)))
                      : null,
                ),
              ),
            ),
            FormLabel(
              label: 'Supplier name',
              required: true,
              child: TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: motionInput(context, hint: 'Enter supplier name', icon: Icons.storefront_outlined)),
            ),
            FormLabel(
              label: 'Group',
              child: PickerField(
                value: _groupId,
                hint: 'Optional',
                icon: Icons.folder_outlined,
                options: _groupOptions,
                onChanged: (v) => setState(() => _groupId = v),
              ),
            ),
            FormLabel(
              label: 'Status',
              child: Wrap(spacing: 8, children: [
                for (final s in _statuses)
                  ChoiceChip(label: Text(s.$2), selected: _status == s.$1, onSelected: (_) => setState(() => _status = s.$1)),
              ]),
            ),
          ]),
        ),
        WizardStep(
          title: 'Contact',
          icon: Icons.contact_mail_outlined,
          caption: 'How to reach the supplier',
          builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FormLabel(
              label: 'Email',
              child: TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: motionInput(context, hint: 'Optional', icon: Icons.mail_outline_rounded)),
            ),
            FormLabel(
              label: 'Phone',
              child: TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: motionInput(context, hint: 'Optional', icon: Icons.phone_outlined)),
            ),
          ]),
        ),
        WizardStep(
          title: 'Address',
          icon: Icons.place_outlined,
          caption: 'Where the supplier is based',
          builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FormLabel(label: 'Address', child: TextField(controller: _address, minLines: 2, maxLines: 4, decoration: motionInput(context, hint: 'Optional'))),
            FormLabel(label: 'City', child: TextField(controller: _city, decoration: motionInput(context, hint: 'Optional', icon: Icons.location_city_outlined))),
            FormLabel(label: 'Country', child: TextField(controller: _country, decoration: motionInput(context, hint: 'Optional', icon: Icons.public_rounded))),
          ]),
        ),
        WizardStep(
          title: 'Review',
          icon: Icons.fact_check_outlined,
          caption: 'Check the details before saving',
          builder: (_) => reviewGrid([
            ('Supplier code', _code.text.trim()),
            ('Supplier name', _name.text.trim()),
            ('Group', _groupName),
            ('Status', _statusLabel(_status)),
            ('Email', _email.text.trim()),
            ('Phone', _phone.text.trim()),
            ('Address', _address.text.trim()),
            ('City', _city.text.trim()),
            ('Country', _country.text.trim()),
          ]),
        ),
      ],
    );
  }
}

// ── Detail ──────────────────────────────────────────────────────────────

class SupplierDetailPage extends StatefulWidget {
  final Map<String, dynamic> supplier;
  final List<Map<String, dynamic>> groups;
  final SupplierService service;
  const SupplierDetailPage({super.key, required this.supplier, required this.groups, required this.service});

  @override
  State<SupplierDetailPage> createState() => _SupplierDetailPageState();
}

class _SupplierDetailPageState extends State<SupplierDetailPage> {
  late Map<String, dynamic> _s = {...widget.supplier};
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _orders.isEmpty;
      _error = null;
    });
    try {
      final o = await widget.service.supplierOrders(_s['id']);
      if (mounted) setState(() => _orders = o);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load purchase orders'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    final saved = await showMotionSheet<bool>(context, (_) => SupplierFormSheet(service: widget.service, groups: widget.groups, existing: _s));
    if (saved != true || !mounted) return;
    marketToast(context, 'Supplier updated');
    // Refresh the header from the server copy (with group).
    try {
      final d = await widget.service.loadSuppliers();
      final fresh = d.suppliers.where((r) => r['id'].toString() == _s['id'].toString()).firstOrNull;
      if (fresh != null && mounted) setState(() => _s = fresh);
    } catch (_) {}
  }

  Future<void> _delete() async {
    final ok = await confirmMarket(context, title: 'Delete supplier?', message: 'Delete supplier "${str(_s['supplier_name'])}"?');
    if (!ok) return;
    try {
      await widget.service.deleteSupplier(_s['id']);
      if (!mounted) return;
      marketToast(context, 'Supplier deleted');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete supplier'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final status = str(_s['status']);
    final committed = _orders.where((o) => purchaseSpendStatuses.contains(str(o['status'])));
    final spend = committed.fold<double>(0, (a, o) => a + purchaseOrderValue(o));
    final open = _orders.where((o) => purchaseAwaitingDelivery.contains(str(o['status'])) || str(o['status']) == 'PENDING').length;
    final info = [
      ('Supplier code', str(_s['supplier_code'])),
      ('Group', nested(_s, 'group', 'group_name')),
      ('Email', str(_s['email'])),
      ('Phone', str(_s['phone'])),
      ('Address', str(_s['address'])),
      ('City', str(_s['city'])),
      ('Country', str(_s['country'])),
    ];
    return MotionScaffold(
      title: str(_s['supplier_name']),
      subtitle: str(_s['supplier_code']),
      onRefresh: _load,
      actions: [
        IconButton(tooltip: 'Edit', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
        IconButton(tooltip: 'Delete', onPressed: _delete, icon: Icon(Icons.delete_outline_rounded, color: p.error)),
      ],
      slivers: [
        sliverBox(FadeSlideIn(
          child: GlowCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                InitialsAvatar(str(_s['supplier_name']), size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(str(_s['supplier_name']), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
                    const SizedBox(height: 4),
                    StatusPill(_statusLabel(status), tone: _statusTone(status)),
                  ]),
                ),
              ]),
              Divider(height: 24, color: p.line),
              for (final i in info) InfoRow(i.$1, i.$2.isEmpty ? '—' : i.$2),
            ]),
          ),
        )),
        SliverPadding(
          padding: const EdgeInsets.only(top: 16),
          sliver: SliverToBoxAdapter(
            child: KpiStrip(children: [
              GradientKpi(icon: Icons.receipt_long_outlined, label: 'Purchase orders', value: _orders.length, accent: Accent.ocean),
              GradientKpi(icon: Icons.account_balance_wallet_outlined, label: 'Committed spend', value: spend, format: (v) => formatMoney(v, decimalDigits: 0), accent: Accent.violet),
              GradientKpi(icon: Icons.local_shipping_outlined, label: 'Open orders', value: open, accent: Accent.amber),
            ]),
          ),
        ),
        sliverBox(SectionHeader('Purchase orders', subtitle: 'Orders raised with this supplier'), padding: const EdgeInsets.symmetric(horizontal: 16)),
        if (_loading)
          sliverSkeleton(count: 3, height: 70)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (_orders.isEmpty)
          sliverEmpty(icon: Icons.receipt_long_outlined, title: 'No purchase orders yet', message: 'Orders for this supplier will show here.')
        else
          sliverStagger(
            count: _orders.length,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            builder: (_, i) {
              final o = _orders[i];
              final st = str(o['status']);
              final expected = parseDate(o['expected_date']);
              return MotionTile(
                leading: const AccentIcon(Icons.receipt_long_outlined, size: 40),
                title: str(o['po_no']),
                subtitle: formatMoney(purchaseOrderValue(o)),
                meta: [
                  'Ordered ${fmtDate(parseDate(o['order_date']))}',
                  if (expected != null) 'Expected ${fmtDate(expected)}',
                ].join(' · '),
                trailing: StatusPill(purchaseStatusLabel(st), tone: toneForStatus(st)),
              );
            },
          ),
      ],
    );
  }
}
