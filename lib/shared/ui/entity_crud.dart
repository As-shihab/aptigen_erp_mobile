import 'package:flutter/material.dart';
import '../../core/network/http_client.dart';
import 'motion_kit.dart';
import 'motion_wizard.dart';

// Config-driven list + form for flat OData entities (departments, leave
// types, bonus types, ...). Each entity only describes its fields and how a
// row reads; the page handles loading (one $batch for the list and every
// lookup), search, active filter, swipe-to-delete and the bottom-sheet form.
// Endpoints are Prisma model names (snake_case); the backend scopes
// workplace_id itself, so payloads never send it.

enum EField { text, multiline, number, decimal, toggle, date, dateTime, time, lookup, choice, color }

class EntityField {
  final String key;
  final String label;
  final EField kind;
  final bool required;
  final dynamic defaultValue;
  final String? hint;
  final IconData? icon;

  /// For [EField.lookup]: key into [EntityConfig.lookups].
  final String? lookup;

  /// For [EField.lookup]: label for an option row (defaults to `name`).
  final String Function(Map<String, dynamic> row)? lookupLabel;

  /// For [EField.choice]: fixed (value, label) pairs.
  final List<(String, String)>? choices;

  /// Hide the field in the form when this returns false (e.g. dependent fields).
  final bool Function(Map<String, dynamic> values)? visibleWhen;

  const EntityField(
    this.key,
    this.label, {
    this.kind = EField.text,
    this.required = false,
    this.defaultValue,
    this.hint,
    this.icon,
    this.lookup,
    this.lookupLabel,
    this.choices,
    this.visibleWhen,
  });
}

class EntityConfig {
  final String title;
  final String? subtitle;
  final String endpoint;
  final IconData icon;
  final Accent accent;
  final List<EntityField> fields;

  /// Lookup name → OData query (entity + query string), loaded in the same batch.
  final Map<String, String> lookups;
  final String? expand;
  final String? select;
  final String? filter;
  final String orderBy;
  final int top;

  final String Function(Map<String, dynamic> row) rowTitle;
  final String? Function(Map<String, dynamic> row, Map<String, List<Map<String, dynamic>>> lookups)? rowSubtitle;
  final String? Function(Map<String, dynamic> row, Map<String, List<Map<String, dynamic>>> lookups)? rowMeta;
  final ({String label, MarketTone tone})? Function(Map<String, dynamic> row)? rowPill;
  final Widget Function(Map<String, dynamic> row)? rowLeading;

  /// Keys searched by the header search box (defaults to the title).
  final List<String> searchKeys;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;

  /// Last-chance payload transform before POST/PUT.
  final Map<String, dynamic> Function(Map<String, dynamic> payload, Map<String, dynamic>? existing)? beforeSave;

  /// Extra per-row actions shown in the long-press sheet.
  final List<RowAction> rowActions;

  /// Optional custom detail page instead of the edit sheet on tap.
  final Widget Function(Map<String, dynamic> row)? detailPage;

  /// Extra chip filters: label → predicate.
  final Map<String, bool Function(Map<String, dynamic> row)> chipFilters;

  /// Groups the form into wizard steps (title → field keys). When null, a
  /// form with more than [EntityConfig.wizardThreshold] fields is split
  /// automatically: inputs in groups of five, then switches as "Options".
  final List<({String title, List<String> keys})>? formSteps;
  static const wizardThreshold = 7;

  const EntityConfig({
    required this.title,
    this.subtitle,
    required this.endpoint,
    required this.icon,
    this.accent = Accent.ocean,
    required this.fields,
    this.lookups = const {},
    this.expand,
    this.select,
    this.filter,
    this.orderBy = 'id desc',
    this.top = 500,
    required this.rowTitle,
    this.rowSubtitle,
    this.rowMeta,
    this.rowPill,
    this.rowLeading,
    this.searchKeys = const ['name'],
    this.canCreate = true,
    this.canEdit = true,
    this.canDelete = true,
    this.beforeSave,
    this.rowActions = const [],
    this.detailPage,
    this.chipFilters = const {},
    this.formSteps,
  });

  String get listUrl {
    final params = <String>[];
    if (select != null) params.add('\$select=$select');
    if (expand != null) params.add('\$expand=$expand');
    if (filter != null) params.add('\$filter=${Uri.encodeComponent(filter!)}');
    params.add('\$orderby=${Uri.encodeComponent(orderBy)}');
    params.add('\$top=$top');
    return '$endpoint?${params.join('&')}';
  }
}

class RowAction {
  final String label;
  final IconData icon;
  final bool destructive;

  /// Return true to reload the list afterwards.
  final Future<bool> Function(BuildContext context, Map<String, dynamic> row) run;
  const RowAction(this.label, this.icon, this.run, {this.destructive = false});
}

/// Thin CRUD client for one OData entity.
class EntityApi {
  final ApiClient client;
  final String endpoint;
  EntityApi(this.client, this.endpoint);

  static Map<String, dynamic> unwrapOne(dynamic res) {
    final v = (res is Map && res['value'] is Map) ? res['value'] : res;
    return v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async => unwrapOne(await client.post(endpoint, body, isV8: true));
  Future<Map<String, dynamic>> update(Object id, Map<String, dynamic> body) async => unwrapOne(await client.put(endpoint, id, body));
  Future<void> delete(Object id) => client.delete(endpoint, id);
}

/// Loads several OData queries in one $batch, keyed by name.
Future<Map<String, List<Map<String, dynamic>>>> batchLoad(ApiClient client, Map<String, String> queries) async {
  if (queries.isEmpty) return {};
  final keys = queries.keys.toList();
  final res = await client.batch([
    for (var i = 0; i < keys.length; i++) BatchRequest(id: '${i + 1}', method: 'GET', url: queries[keys[i]]!),
  ]);
  return {
    for (var i = 0; i < keys.length; i++) keys[i]: unwrapList(unwrapBatchBody(res, '${i + 1}')).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList(),
  };
}

String lookupName(List<Map<String, dynamic>>? rows, dynamic id, [String key = 'name']) {
  if (id == null || rows == null) return '';
  for (final r in rows) {
    if (r['id'].toString() == id.toString()) return str(r[key]);
  }
  return '';
}

class EntityListPage extends StatefulWidget {
  final EntityConfig config;
  const EntityListPage({super.key, required this.config});

  @override
  State<EntityListPage> createState() => _EntityListPageState();
}

class _EntityListPageState extends State<EntityListPage> {
  final _client = ApiClient();
  late final _api = EntityApi(_client, widget.config.endpoint);
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  Map<String, List<Map<String, dynamic>>> _lookups = {};
  String _q = '';
  String _chip = 'All';

  EntityConfig get c => widget.config;

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
      final data = await batchLoad(_client, {'__rows': c.listUrl, ...c.lookups});
      if (!mounted) return;
      setState(() {
        _rows = data.remove('__rows') ?? [];
        _lookups = data;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load ${c.title.toLowerCase()}'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasActive => _rows.any((r) => r.containsKey('is_active'));

  Map<String, bool Function(Map<String, dynamic>)> get _chips => {
        'All': (_) => true,
        if (_hasActive) 'Active': (r) => asBool(r['is_active'], fallback: true),
        if (_hasActive) 'Inactive': (r) => !asBool(r['is_active'], fallback: true),
        ...c.chipFilters,
      };

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    final pred = _chips[_chip] ?? (_) => true;
    return _rows.where((r) {
      if (!pred(r)) return false;
      if (q.isEmpty) return true;
      final hay = [c.rowTitle(r), ...c.searchKeys.map((k) => str(r[k]))].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _openForm([Map<String, dynamic>? row]) async {
    final saved = await showMotionSheet<bool>(context, (_) => EntityFormSheet(config: c, lookups: _lookups, existing: row));
    if (saved == true) {
      if (mounted) marketToast(context, row == null ? '${c.title} entry created' : 'Changes saved');
      _load();
    }
  }

  Future<bool> _delete(Map<String, dynamic> row) async {
    final ok = await confirmMarket(context, title: 'Delete this entry?', message: '"${c.rowTitle(row)}" will be removed permanently.');
    if (!ok) return false;
    try {
      await _api.delete(row['id']);
      if (mounted) {
        setState(() => _rows.removeWhere((r) => r['id'] == row['id']));
        marketToast(context, 'Deleted');
      }
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete'), error: true);
      return false;
    }
  }

  Future<void> _more(Map<String, dynamic> row) async {
    final key = await showActionSheet(context, title: c.rowTitle(row), actions: [
      if (c.canEdit) (key: '__edit', label: 'Edit', icon: Icons.edit_outlined, destructive: false),
      for (var i = 0; i < c.rowActions.length; i++)
        (key: '$i', label: c.rowActions[i].label, icon: c.rowActions[i].icon, destructive: c.rowActions[i].destructive),
      if (c.canDelete) (key: '__delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (key == null || !mounted) return;
    if (key == '__edit') return _openForm(row);
    if (key == '__delete') {
      await _delete(row);
      return;
    }
    final action = c.rowActions[int.parse(key)];
    final reload = await action.run(context, row);
    if (reload) _load();
  }

  void _tap(Map<String, dynamic> row) {
    if (c.detailPage != null) {
      pushMotion(context, c.detailPage!(row)).then((_) => _load());
    } else if (c.canEdit) {
      _openForm(row);
    } else {
      _more(row);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final chips = _chips;
    return MotionScaffold(
      title: c.title,
      subtitle: c.subtitle ?? '${_rows.length} ${_rows.length == 1 ? 'entry' : 'entries'}',
      icon: c.icon,
      accent: c.accent,
      onRefresh: _load,
      onFab: c.canCreate ? () => _openForm() : null,
      fabLabel: 'Add',
      headerExtra: HeaderSearch(hint: 'Search ${c.title.toLowerCase()}', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        if (chips.length > 1)
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
            icon: c.icon,
            title: _rows.isEmpty ? 'Nothing here yet' : 'No matches',
            message: _rows.isEmpty && c.canCreate ? 'Tap add to create the first one.' : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final pill = c.rowPill?.call(r) ??
                  (r.containsKey('is_active') ? (label: asBool(r['is_active'], fallback: true) ? 'Active' : 'Inactive', tone: asBool(r['is_active'], fallback: true) ? MarketTone.ok : MarketTone.neutral) : null);
              return MotionTile(
                key: ValueKey(r['id']),
                leading: c.rowLeading?.call(r) ?? AccentIcon(c.icon, accent: c.accent, size: 40),
                title: c.rowTitle(r),
                subtitle: c.rowSubtitle?.call(r, _lookups),
                meta: c.rowMeta?.call(r, _lookups),
                trailing: pill == null ? null : StatusPill(pill.label, tone: pill.tone),
                onTap: () => _tap(r),
                onLongPress: () => _more(r),
                onDelete: c.canDelete ? () => _delete(r) : null,
              );
            },
          ),
      ],
    );
  }
}

/// Bottom-sheet create/edit form driven by [EntityConfig.fields].
class EntityFormSheet extends StatefulWidget {
  final EntityConfig config;
  final Map<String, List<Map<String, dynamic>>> lookups;
  final Map<String, dynamic>? existing;
  const EntityFormSheet({super.key, required this.config, required this.lookups, this.existing});

  @override
  State<EntityFormSheet> createState() => _EntityFormSheetState();
}

class _EntityFormSheetState extends State<EntityFormSheet> {
  late final Map<String, dynamic> _v;
  final Map<String, TextEditingController> _ctrl = {};
  bool _busy = false;

  EntityConfig get c => widget.config;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _v = {for (final f in c.fields) f.key: e != null && e.containsKey(f.key) ? e[f.key] : f.defaultValue};
    for (final f in c.fields) {
      if (const {EField.text, EField.multiline, EField.number, EField.decimal, EField.color}.contains(f.kind)) {
        _ctrl[f.key] = TextEditingController(text: _v[f.key] == null ? '' : _v[f.key].toString());
      }
    }
  }

  @override
  void dispose() {
    for (final t in _ctrl.values) {
      t.dispose();
    }
    super.dispose();
  }

  dynamic _read(EntityField f) {
    final t = _ctrl[f.key]?.text.trim();
    switch (f.kind) {
      case EField.text:
      case EField.multiline:
      case EField.color:
        return (t == null || t.isEmpty) ? null : t;
      case EField.number:
        return (t == null || t.isEmpty) ? null : int.tryParse(t);
      case EField.decimal:
        return (t == null || t.isEmpty) ? null : double.tryParse(t);
      case EField.toggle:
        return asBool(_v[f.key]);
      case EField.date:
      case EField.dateTime:
        final d = _v[f.key] is DateTime ? _v[f.key] as DateTime : parseDate(_v[f.key]);
        if (d == null) return null;
        return f.kind == EField.date ? DateTime.utc(d.year, d.month, d.day).toIso8601String() : d.toUtc().toIso8601String();
      case EField.lookup:
        final v = _v[f.key];
        return v == null ? null : int.tryParse(v.toString()) ?? v;
      case EField.time:
      case EField.choice:
        return _v[f.key];
    }
  }

  Future<bool> _save() async {
    final payload = <String, dynamic>{};
    for (final f in c.fields) {
      if (f.visibleWhen != null && !f.visibleWhen!(_v)) continue;
      final val = _read(f);
      if (f.required && (val == null || (val is String && val.isEmpty))) {
        marketToast(context, '${f.label} is required', error: true);
        return false;
      }
      payload[f.key] = val;
    }
    final body = c.beforeSave?.call(payload, widget.existing) ?? payload;
    setState(() => _busy = true);
    try {
      final api = EntityApi(ApiClient(), c.endpoint);
      if (widget.existing == null) {
        await api.create(body);
      } else {
        await api.update(widget.existing!['id'], body);
      }
      if (mounted) Navigator.pop(context, true);
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(e, 'Could not save'), error: true);
      }
      return false;
    }
  }

  Widget _field(EntityField f) {
    Widget input;
    switch (f.kind) {
      case EField.text:
      case EField.color:
        input = TextField(controller: _ctrl[f.key], decoration: motionInput(context, hint: f.hint, icon: f.icon));
      case EField.multiline:
        input = TextField(controller: _ctrl[f.key], minLines: 3, maxLines: 6, decoration: motionInput(context, hint: f.hint));
      case EField.number:
        input = TextField(controller: _ctrl[f.key], keyboardType: TextInputType.number, decoration: motionInput(context, hint: f.hint, icon: f.icon));
      case EField.decimal:
        input = TextField(
            controller: _ctrl[f.key], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: motionInput(context, hint: f.hint, icon: f.icon));
      case EField.toggle:
        return SwitchField(label: f.label, sub: f.hint, value: asBool(_v[f.key]), onChanged: (v) => setState(() => _v[f.key] = v));
      case EField.date:
      case EField.dateTime:
        input = DatePickField(
          value: _v[f.key] is DateTime ? _v[f.key] as DateTime : parseDate(_v[f.key]),
          withTime: f.kind == EField.dateTime,
          onChanged: (d) => setState(() => _v[f.key] = d),
        );
      case EField.time:
        input = TimePickField(value: _v[f.key]?.toString(), onChanged: (t) => setState(() => _v[f.key] = t));
      case EField.lookup:
        final rows = widget.lookups[f.lookup] ?? const [];
        input = PickerField(
          value: _v[f.key],
          hint: f.hint ?? 'Select ${f.label.toLowerCase()}',
          icon: f.icon,
          options: [for (final r in rows) PickOption(r['id'], f.lookupLabel?.call(r) ?? str(r['name']))],
          onChanged: (v) => setState(() => _v[f.key] = v),
        );
      case EField.choice:
        final opts = f.choices ?? const [];
        input = Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in opts)
            ChoiceChip(
              label: Text(o.$2),
              selected: _v[f.key]?.toString() == o.$1,
              onSelected: (_) => setState(() => _v[f.key] = o.$1),
            ),
        ]);
    }
    return FormLabel(label: f.label, required: f.required, child: input);
  }

  bool _visible(EntityField f) => f.visibleWhen == null || f.visibleWhen!(_v);

  List<({String title, List<EntityField> fields})> get _groups {
    final byKey = {for (final f in c.fields) f.key: f};
    final explicit = c.formSteps;
    if (explicit != null) {
      return [
        for (final g in explicit) (title: g.title, fields: [for (final k in g.keys) ?byKey[k]]),
      ];
    }
    final inputs = c.fields.where((f) => f.kind != EField.toggle).toList();
    final toggles = c.fields.where((f) => f.kind == EField.toggle).toList();
    final groups = <({String title, List<EntityField> fields})>[];
    for (var i = 0; i < inputs.length; i += 5) {
      groups.add((title: i == 0 ? 'Basics' : (i == 5 ? 'Details' : 'More'), fields: inputs.sublist(i, (i + 5).clamp(0, inputs.length))));
    }
    if (toggles.isNotEmpty) groups.add((title: 'Options', fields: toggles));
    return groups;
  }

  String? _checkRequired(List<EntityField> fields) {
    for (final f in fields) {
      if (!f.required || !_visible(f)) continue;
      final val = _read(f);
      if (val == null || (val is String && val.isEmpty)) return '${f.label} is required';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.existing == null ? 'New ${c.title.toLowerCase()}' : 'Edit ${c.title.toLowerCase()}';
    final submitLabel = widget.existing == null ? 'Create' : 'Save changes';
    final useWizard = c.formSteps != null || c.fields.length > EntityConfig.wizardThreshold;
    if (useWizard) {
      final groups = _groups.where((g) => g.fields.isNotEmpty).toList();
      return MotionWizardSheet(
        title: title,
        subtitle: widget.existing == null ? null : c.rowTitle(widget.existing!),
        submitLabel: submitLabel,
        onSubmit: _save,
        steps: [
          for (final g in groups)
            WizardStep(
              title: g.title,
              validate: () => _checkRequired(g.fields),
              builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final f in g.fields)
                  if (_visible(f)) _field(f),
              ]),
            ),
        ],
      );
    }
    return FormSheet(
      title: title,
      subtitle: widget.existing == null ? null : c.rowTitle(widget.existing!),
      busy: _busy,
      onSubmit: _save,
      submitLabel: submitLabel,
      children: [
        for (final f in c.fields)
          if (_visible(f)) _field(f),
      ],
    );
  }
}
