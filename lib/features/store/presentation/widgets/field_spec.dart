import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../sell/market/presentation/banners/form_kit.dart' show FieldBlock, MarketTextField, SwitchRow, marketInput;
import '../../data/simple_crud_service.dart';
import '../../data/store_lookup_service.dart';
import '../../data/store_util.dart' hide toDouble;
import 'barcode_print_sheet.dart';
import 'store_ui.dart';

enum FieldKind { text, multiline, number, decimal, boolSwitch, date, dropdown, choice }

/// Config-driven field description for `SimpleEntityFormPage` — covers the
/// "flat record, a few typed fields, optional cascading FK" shape shared by
/// Categories/Sub-Categories/UOMs/Packagings/Batches/Warehouses/Corridors/
/// Racks/Bins, so those 9 entities need only a config object each instead of
/// a bespoke form file.
class FieldSpec {
  final String key;
  final String label;
  final FieldKind kind;
  final bool required;
  final dynamic defaultValue;
  final String? hint;

  /// Dropdown/dependent-dropdown options — recomputed from the current form
  /// values on every build so a child field (e.g. rack) can filter by
  /// whichever parent (e.g. corridor) is currently selected.
  final List<LookupOption> Function(Map<String, dynamic> values)? options;

  /// Fixed string choices for `FieldKind.choice` (e.g. a Prisma `status`
  /// enum) — distinct from `dropdown`, which resolves to an int FK id.
  final List<String>? choices;

  const FieldSpec({
    required this.key,
    required this.label,
    required this.kind,
    this.required = false,
    this.defaultValue,
    this.hint,
    this.options,
    this.choices,
  });
}

/// Static configuration for one `SimpleEntityListPage`/`SimpleEntityFormPage`
/// pair — endpoint, fields, and how to render a list row.
class SimpleCrudConfig {
  final String title;
  final String endpoint;
  final List<FieldSpec> fields;
  final IconData icon;
  final String Function(Map<String, dynamic> row) rowTitle;
  final String? Function(Map<String, dynamic> row)? rowSubtitle;
  final String orderBy;

  /// When true, a row whose [barcodeValue] resolves to a non-empty string
  /// renders a live CODE128 preview in place of the leading icon, plus a
  /// print action that opens `showBarcodePrintSheet` — used by Packaging
  /// rows, which are the only one of the 9 flat lookup entities that carry
  /// a real barcode.
  final bool showBarcode;
  final String? Function(Map<String, dynamic> row)? barcodeValue;

  /// Extra label->value info (price, product name, qty, ...) offered on the
  /// print sheet as individually toggle-able lines — only meaningful when
  /// [showBarcode] is true.
  final Map<String, String> Function(Map<String, dynamic> row)? barcodeInfo;

  const SimpleCrudConfig({
    required this.title,
    required this.endpoint,
    required this.fields,
    required this.icon,
    required this.rowTitle,
    this.rowSubtitle,
    this.orderBy = 'id desc',
    this.showBarcode = false,
    this.barcodeInfo,
    this.barcodeValue,
  });
}

enum _ActiveFilter { all, active, inactive }

class SimpleEntityListPage extends StatefulWidget {
  final SimpleCrudConfig config;
  const SimpleEntityListPage({super.key, required this.config});

  @override
  State<SimpleEntityListPage> createState() => _SimpleEntityListPageState();
}

class _SimpleEntityListPageState extends State<SimpleEntityListPage> {
  late final _service = SimpleCrudService(ApiClient(), widget.config.endpoint);
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  final Set<int> _busyIds = {};
  _ActiveFilter _filter = _ActiveFilter.all;

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
      final result = await _service.list(orderBy: widget.config.orderBy);
      if (!mounted) return;
      setState(() => _rows = result);
    } catch (_) {
      // leave whatever's already loaded on failure
      if (mounted && _rows.isEmpty) setState(() => _error = 'Could not load ${widget.config.title.toLowerCase()}.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isActive(Map<String, dynamic> r) => r.containsKey('is_active') ? toBool(r['is_active'], fallback: true) : true;

  bool get _hasActiveFlag => _rows.any((r) => r.containsKey('is_active'));

  List<Map<String, dynamic>> get _visible {
    final query = _searchController.text.trim().toLowerCase();
    return _rows.where((r) {
      final matchesFilter = switch (_filter) {
        _ActiveFilter.all => true,
        _ActiveFilter.active => _isActive(r),
        _ActiveFilter.inactive => !_isActive(r),
      };
      if (!matchesFilter) return false;
      if (query.isEmpty) return true;
      return widget.config.rowTitle(r).toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _createOrEdit({Map<String, dynamic>? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      marketRoute<bool>(SimpleEntityFormPage(config: widget.config, existing: existing)),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = toNum(row['id']);
    final confirmed = await confirmMarket(
      context,
      title: 'Delete record',
      message: 'Delete "${widget.config.rowTitle(row)}" from ${widget.config.title.toLowerCase()}? This can\'t be undone.',
    );
    if (!confirmed) return;
    setState(() => _busyIds.add(id));
    try {
      await _service.delete(id);
      if (!mounted) return;
      setState(() => _rows.removeWhere((r) => toNum(r['id']) == id));
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Could not delete this record.', error: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final visible = _visible;
    return MarketScaffold(
      title: widget.config.title,
      subtitle: _loading && _rows.isEmpty ? 'Loading…' : '${visible.length} of ${_rows.length}',
      fab: FloatingActionButton.extended(
        onPressed: () => _createOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search ${widget.config.title.toLowerCase()}',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      fillColor: p.card,
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_searchController.clear)),
                    ),
                  ),
                  if (_hasActiveFlag) ...[
                    const SizedBox(height: 10),
                    MarketSegmented<_ActiveFilter>(
                      value: _filter,
                      onChanged: (v) => setState(() => _filter = v),
                      options: [
                        (id: _ActiveFilter.all, label: 'All', count: _rows.length),
                        (id: _ActiveFilter.active, label: 'Active', count: null),
                        (id: _ActiveFilter.inactive, label: 'Inactive', count: _rows.where((r) => !_isActive(r)).length),
                      ],
                    ),
                  ],
                ]),
              ),
            ),
            ..._listSlivers(p, visible),
          ],
        ),
      ),
    );
  }

  List<Widget> _listSlivers(MarketPalette p, List<Map<String, dynamic>> rows) {
    if (_loading && _rows.isEmpty) {
      return const [SliverFillRemaining(hasScrollBody: false, child: SkeletonList(count: 6, itemHeight: 64))];
    }
    if (_error != null && _rows.isEmpty) {
      return [SliverFillRemaining(hasScrollBody: false, child: MarketEmpty(icon: Icons.cloud_off_outlined, title: _error!, actionLabel: 'Try again', onAction: _load))];
    }
    if (rows.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _rows.isEmpty
              ? MarketEmpty(
                  icon: widget.config.icon,
                  title: 'Nothing here yet',
                  message: 'Records you add to ${widget.config.title.toLowerCase()} show up here.',
                  actionLabel: 'Add the first one',
                  onAction: () => _createOrEdit(),
                )
              : const MarketEmpty(icon: Icons.search_off_outlined, title: 'Nothing matches', message: 'Try another search or filter.'),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        sliver: SliverList.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => FadeSlideIn(index: i, child: _row(p, rows[i])),
        ),
      ),
    ];
  }

  Widget _row(MarketPalette p, Map<String, dynamic> row) {
    final id = toNum(row['id']);
    final subtitle = widget.config.rowSubtitle?.call(row);
    final busy = _busyIds.contains(id);
    final isActive = _isActive(row);
    final barcode = widget.config.showBarcode ? (widget.config.barcodeValue?.call(row) ?? row['barcode']?.toString()) : null;
    final hasBarcode = barcode != null && barcode.isNotEmpty;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: busy ? 0.5 : 1,
      child: MarketCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        onTap: busy ? null : () => _createOrEdit(existing: row),
        child: Row(
          children: [
            hasBarcode
                ? Container(
                    width: 60,
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.line)),
                    child: BarcodeWidget(
                      barcode: Barcode.code128(),
                      data: barcode,
                      drawText: false,
                      errorBuilder: (context, error) => const Icon(Icons.qr_code_2_outlined, color: Colors.black38, size: 18),
                    ),
                  )
                : Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: isActive ? p.brandSoft : p.neutralBg, borderRadius: BorderRadius.circular(10)),
                    child: Icon(widget.config.icon, size: 20, color: isActive ? p.brand : p.neutral),
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.config.rowTitle(row),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: p.text)),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
                  ],
                  if (!isActive) ...[
                    const SizedBox(height: 5),
                    const StatusPill('Inactive', tone: MarketTone.neutral),
                  ],
                ],
              ),
            ),
            if (hasBarcode)
              IconButton(
                icon: Icon(Icons.print_outlined, size: 20, color: p.brand),
                tooltip: 'Print barcode',
                onPressed: busy ? null : () => showBarcodePrintSheet(context, code: barcode, title: widget.config.rowTitle(row), infoLines: widget.config.barcodeInfo?.call(row) ?? const {}),
              ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 20, color: p.error),
              tooltip: 'Delete',
              onPressed: busy ? null : () => _delete(row),
            ),
          ],
        ),
      ),
    );
  }
}

class SimpleEntityFormPage extends StatefulWidget {
  final SimpleCrudConfig config;
  final Map<String, dynamic>? existing;
  const SimpleEntityFormPage({super.key, required this.config, this.existing});

  @override
  State<SimpleEntityFormPage> createState() => _SimpleEntityFormPageState();
}

class _SimpleEntityFormPageState extends State<SimpleEntityFormPage> {
  late final _service = SimpleCrudService(ApiClient(), widget.config.endpoint);
  final Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _controllers = {};
  bool _submitting = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    for (final field in widget.config.fields) {
      final existingValue = widget.existing?[field.key];
      switch (field.kind) {
        case FieldKind.text:
        case FieldKind.multiline:
          _controllers[field.key] = TextEditingController(text: existingValue?.toString() ?? field.defaultValue?.toString() ?? '');
          break;
        case FieldKind.number:
          _controllers[field.key] = TextEditingController(text: toIntOrNull(existingValue)?.toString() ?? field.defaultValue?.toString() ?? '');
          break;
        case FieldKind.decimal:
          _controllers[field.key] = TextEditingController(text: toDoubleOrNull(existingValue)?.toString() ?? field.defaultValue?.toString() ?? '');
          break;
        case FieldKind.boolSwitch:
          _values[field.key] = existingValue != null ? toBool(existingValue) : (field.defaultValue ?? false);
          break;
        case FieldKind.date:
          _values[field.key] = toStringOrNull(existingValue);
          break;
        case FieldKind.dropdown:
          _values[field.key] = toIntOrNull(existingValue) ?? field.defaultValue;
          break;
        case FieldKind.choice:
          _values[field.key] = toStringOrNull(existingValue) ?? field.defaultValue;
          break;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _currentValues() {
    final all = <String, dynamic>{..._values};
    for (final entry in _controllers.entries) {
      all[entry.key] = entry.value.text;
    }
    return all;
  }

  Future<void> _submit() async {
    for (final field in widget.config.fields) {
      if (!field.required) continue;
      final value = field.kind == FieldKind.dropdown || field.kind == FieldKind.boolSwitch || field.kind == FieldKind.date || field.kind == FieldKind.choice
          ? _values[field.key]
          : _controllers[field.key]?.text.trim();
      if (value == null || value == '') {
        marketToast(context, '${field.label} is required.', error: true);
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final payload = <String, dynamic>{};
      for (final field in widget.config.fields) {
        switch (field.kind) {
          case FieldKind.text:
          case FieldKind.multiline:
            final text = _controllers[field.key]!.text.trim();
            payload[field.key] = text.isEmpty ? null : text;
            break;
          case FieldKind.number:
            payload[field.key] = toIntOrNull(_controllers[field.key]!.text.trim());
            break;
          case FieldKind.decimal:
            payload[field.key] = toDoubleOrNull(_controllers[field.key]!.text.trim());
            break;
          case FieldKind.boolSwitch:
            payload[field.key] = _values[field.key] ?? false;
            break;
          case FieldKind.date:
          case FieldKind.dropdown:
          case FieldKind.choice:
            payload[field.key] = _values[field.key];
            break;
        }
      }
      if (_isEdit) {
        await _service.update(toNum(widget.existing!['id']), payload);
      } else {
        await _service.create(payload);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Could not save this ${widget.config.title.toLowerCase()}.', error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickDate(FieldSpec field) async {
    final initial = DateTime.tryParse(_values[field.key]?.toString() ?? '') ?? DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (picked == null) return;
    setState(() => _values[field.key] = formatDateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final fields = widget.config.fields.where((f) => f.kind != FieldKind.boolSwitch).toList();
    final switches = widget.config.fields.where((f) => f.kind == FieldKind.boolSwitch).toList();
    final existingTitle = _isEdit ? widget.config.rowTitle(widget.existing!) : '';
    var section = 0;
    Widget block(Widget child) => FadeSlideIn(index: section++, child: child);

    return MarketScaffold(
      title: _isEdit ? (existingTitle.isEmpty ? 'Edit record' : existingTitle) : 'New record',
      subtitle: widget.config.title,
      bottom: _saveBar(p),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (fields.isNotEmpty) ...[
              block(SectionHeader('Details', subtitle: _isEdit ? 'Update this record' : 'Fill in the fields below')),
              block(_card(fields.map((f) => _buildField(p, f)).toList())),
            ],
            if (switches.isNotEmpty) ...[
              block(SectionHeader(switches.length == 1 && switches.first.key == 'is_active' ? 'Status' : 'Options')),
              block(_card(switches.map((f) => _buildField(p, f)).toList())),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) => MarketCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

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
                    : Icon(_isEdit ? Icons.check : Icons.add, size: 20),
                label: Text(_isEdit ? 'Save changes' : 'Create'),
              ),
            ),
          ),
        ),
      );

  Widget _buildField(MarketPalette p, FieldSpec field) {
    switch (field.kind) {
      case FieldKind.text:
        return FieldBlock(
          label: field.label,
          required: field.required,
          child: MarketTextField(controller: _controllers[field.key]!, hint: field.hint ?? field.label),
        );
      case FieldKind.multiline:
        return FieldBlock(
          label: field.label,
          required: field.required,
          child: MarketTextField(controller: _controllers[field.key]!, hint: field.hint, maxLines: 4),
        );
      case FieldKind.number:
        return FieldBlock(
          label: field.label,
          required: field.required,
          child: MarketTextField(controller: _controllers[field.key]!, hint: field.hint ?? '0', keyboardType: TextInputType.number),
        );
      case FieldKind.decimal:
        return FieldBlock(
          label: field.label,
          required: field.required,
          child: MarketTextField(controller: _controllers[field.key]!, hint: field.hint ?? '0.00', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        );
      case FieldKind.boolSwitch:
        final value = (_values[field.key] ?? false) as bool;
        return SwitchRow(
          title: field.label,
          subtitle: field.hint ?? (field.key == 'is_active' ? (value ? 'Available for selection' : 'Hidden from pickers') : null),
          value: value,
          onChanged: (v) => setState(() => _values[field.key] = v),
        );
      case FieldKind.date:
        final value = _values[field.key] as String?;
        return FieldBlock(
          label: field.label,
          required: field.required,
          child: Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _pickDate(field),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                constraints: const BoxConstraints(minHeight: 46),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
                child: Row(children: [
                  Icon(Icons.event_outlined, size: 18, color: p.label),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(value ?? 'Select date', style: TextStyle(fontSize: 13.5, color: value == null ? p.label : p.text)),
                  ),
                  Icon(Icons.expand_more, size: 18, color: p.label),
                ]),
              ),
            ),
          ),
        );
      case FieldKind.dropdown:
        final options = field.options?.call(_currentValues()) ?? const <LookupOption>[];
        final currentValue = _values[field.key] as int?;
        final validValue = options.any((o) => o.id == currentValue) ? currentValue : null;
        return FieldBlock(
          label: field.label,
          required: field.required,
          child: DropdownButtonFormField<int>(
            initialValue: validValue,
            isExpanded: true,
            dropdownColor: p.card,
            style: TextStyle(fontSize: 14, color: p.text),
            decoration: marketInput(context, hint: options.isEmpty ? 'Nothing to choose yet' : 'Choose ${field.label.toLowerCase()}'),
            items: options.map((o) => DropdownMenuItem(value: o.id, child: Text(o.label, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _values[field.key] = v),
          ),
        );
      case FieldKind.choice:
        final choices = field.choices ?? const <String>[];
        final currentValue = _values[field.key] as String?;
        return FieldBlock(
          label: field.label,
          required: field.required,
          child: DropdownButtonFormField<String>(
            initialValue: choices.contains(currentValue) ? currentValue : null,
            isExpanded: true,
            dropdownColor: p.card,
            style: TextStyle(fontSize: 14, color: p.text),
            decoration: marketInput(context, hint: 'Choose ${field.label.toLowerCase()}'),
            // Stored values stay as-is (e.g. MAIN_STORE); only the label is humanised.
            items: choices.map((c) => DropdownMenuItem(value: c, child: Text(storeStatusLabel(c), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _values[field.key] = v),
          ),
        );
    }
  }
}
