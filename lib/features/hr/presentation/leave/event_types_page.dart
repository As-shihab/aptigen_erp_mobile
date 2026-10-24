import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'hr_extras.dart';

// Event types — port of desktop EventType.tsx: event_types with calendar
// colour (swatch palette + hex), off-day flag and optional bonus
// (bonus type, percentage / fixed payment).

const _swatches = <Color>[
  Color(0xFF168EFF), Color(0xFFC87B00), Color(0xFF75980B), Color(0xFFDF1278), Color(0xFF8B47D7), Color(0xFF049F9A),
  Color(0xFF0070F2), Color(0xFFCC00DC), Color(0xFF798C77), Color(0xFFDA6C6C), Color(0xFF5D36FF), Color(0xFF5B738B),
];

class EventTypesPage extends StatefulWidget {
  const EventTypesPage({super.key});

  @override
  State<EventTypesPage> createState() => _EventTypesPageState();
}

class _EventTypesPageState extends State<EventTypesPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _bonusTypes = [];
  String _chip = 'all';
  String _q = '';

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
      final d = await batchLoad(_client, {
        'rows': 'event_types?\$expand=bonus_type(\$select=id,name)&\$orderby=id desc&\$top=500',
        'bonus': 'bonus_types?\$select=id,name&\$filter=is_active eq true&\$top=200',
      });
      if (!mounted) return;
      setState(() {
        _rows = d['rows'] ?? [];
        _bonusTypes = d['bonus'] ?? [];
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load event types'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool Function(Map<String, dynamic>) _pred(String k) => switch (k) {
        'active' => (r) => asBool(r['is_active'], fallback: true),
        'inactive' => (r) => !asBool(r['is_active'], fallback: true),
        'off' => (r) => asBool(r['is_off']),
        'bonus' => (r) => asBool(r['has_bonus']),
        _ => (_) => true,
      };

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    return _rows.where(_pred(_chip)).where((r) => q.isEmpty || '${r['name']} ${r['description'] ?? ''}'.toLowerCase().contains(q)).toList();
  }

  Future<void> _form([Map<String, dynamic>? row]) async {
    final ok = await showMotionSheet<bool>(context, (_) => _EventTypeForm(existing: row, bonusTypes: _bonusTypes));
    if (ok == true) {
      if (mounted) marketToast(context, row == null ? 'Event type created' : 'Event type updated');
      _load();
    }
  }

  Future<bool> _delete(Map<String, dynamic> row) async {
    final ok = await confirmMarket(context, title: 'Delete event type?', message: 'Delete event type "${str(row['name'])}"?');
    if (!ok) return false;
    try {
      await _client.delete('event_types', row['id']);
      if (mounted) {
        setState(() => _rows.removeWhere((r) => r['id'] == row['id']));
        marketToast(context, 'Event type deleted');
      }
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete'), error: true);
      return false;
    }
  }

  String _payment(Map<String, dynamic> r) {
    if (!asBool(r['has_bonus']) || r['payment_value'] == null) return '';
    return r['payment_type'] == 'PERCENTAGE' ? '${fmtNum(toNum(r['payment_value']))}%' : money(toNum(r['payment_value']) ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    return MotionScaffold(
      title: 'Event types',
      subtitle: '${_rows.length} ${_rows.length == 1 ? 'type' : 'types'} · colours used on the HR calendar',
      icon: Icons.palette_rounded,
      accent: Accent.ocean,
      onRefresh: _load,
      onFab: () => _form(),
      fabLabel: 'New type',
      headerExtra: HeaderSearch(hint: 'Search event types', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _chip,
              options: [
                for (final k in const [('all', 'All'), ('active', 'Active'), ('inactive', 'Inactive'), ('off', 'Off day'), ('bonus', 'With bonus')])
                  (id: k.$1, label: k.$2, count: _rows.where(_pred(k.$1)).length),
              ],
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
            icon: Icons.palette_outlined,
            title: _rows.isEmpty ? 'No event types yet' : 'No matches',
            message: _rows.isEmpty ? 'Create types like holiday, reminder or weekend.' : null,
            actionLabel: _rows.isEmpty ? 'New type' : null,
            onAction: _rows.isEmpty ? _form : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final c = hexColor(str(r['color'])) ?? colorForEventType(toInt(r['id']));
              final active = asBool(r['is_active'], fallback: true);
              final pay = _payment(r);
              return MotionTile(
                key: ValueKey(r['id']),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(asBool(r['is_off']) ? Icons.weekend_rounded : Icons.event_rounded, color: Colors.white, size: 20),
                ),
                title: str(r['name']),
                subtitle: str(r['description']).isEmpty ? (str(r['color']).isEmpty ? null : str(r['color']).toUpperCase()) : str(r['description']),
                meta: [
                  if (asBool(r['is_off'])) 'Off day',
                  if (asBool(r['has_bonus'])) 'Bonus${nested(r, 'bonus_type').isNotEmpty ? ': ${nested(r, 'bonus_type')}' : ''}${pay.isNotEmpty ? ' · $pay' : ''}',
                ].join(' · '),
                trailing: StatusPill(active ? 'Active' : 'Inactive', tone: active ? MarketTone.ok : MarketTone.neutral),
                onTap: () => _form(r),
                onDelete: () => _delete(r),
              );
            },
          ),
      ],
    );
  }
}

class _EventTypeForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> bonusTypes;
  const _EventTypeForm({this.existing, required this.bonusTypes});

  @override
  State<_EventTypeForm> createState() => _EventTypeFormState();
}

class _EventTypeFormState extends State<_EventTypeForm> {
  Map<String, dynamic>? get e => widget.existing;
  late final _name = TextEditingController(text: str(e?['name']));
  late final _desc = TextEditingController(text: str(e?['description']));
  late final _hex = TextEditingController(text: str(e?['color']).isEmpty ? '#3B82F6' : str(e?['color']).toUpperCase());
  late final _value = TextEditingController(text: e?['payment_value'] == null ? '' : fmtPlain(e!['payment_value']));
  late bool _active = asBool(e?['is_active'], fallback: true);
  late bool _off = asBool(e?['is_off']);
  late bool _bonus = asBool(e?['has_bonus']);
  late Object? _bonusType = e?['bonus_type_id'];
  late String _payType = str(e?['payment_type']);
  bool _busy = false;

  static String fmtPlain(dynamic v) {
    final n = toNum(v);
    if (n == null) return '';
    return n == n.roundToDouble() ? n.round().toString() : n.toString();
  }

  @override
  void initState() {
    super.initState();
    _hex.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _hex.dispose();
    _value.dispose();
    super.dispose();
  }

  Color? get _color => hexColor(_hex.text);

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      marketToast(context, 'Name is required', error: true);
      return;
    }
    if (_bonus && _payType.isEmpty) {
      marketToast(context, 'Select a payment type for this bonus', error: true);
      return;
    }
    if (_hex.text.trim().isNotEmpty && _color == null) {
      marketToast(context, 'Enter a valid colour like #3B82F6', error: true);
      return;
    }
    setState(() => _busy = true);
    final body = {
      'name': _name.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'is_off': _off,
      'has_bonus': _bonus,
      'bonus_type_id': _bonus ? _bonusType : null,
      'payment_type': _bonus && _payType.isNotEmpty ? _payType : null,
      'payment_value': _bonus && _value.text.trim().isNotEmpty ? double.tryParse(_value.text.trim()) : null,
      'color': _color == null ? null : colorHex(_color!),
      'is_active': _active,
    };
    try {
      final api = EntityApi(ApiClient(), 'event_types');
      if (e == null) {
        await api.create(body);
      } else {
        await api.update(e!['id'], body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(err, 'Failed to save event type'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final c = _color;
    return FormSheet(
      title: e == null ? 'New event type' : 'Edit event type',
      subtitle: e == null ? null : str(e!['name']),
      busy: _busy,
      onSubmit: _save,
      submitLabel: e == null ? 'Create' : 'Save changes',
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (c ?? p.brand).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: (c ?? p.brand).withValues(alpha: 0.4)),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: c ?? p.line, borderRadius: BorderRadius.circular(13)),
              child: Icon(_off ? Icons.weekend_rounded : Icons.event_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_name.text.trim().isEmpty ? 'Preview' : _name.text.trim(), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
                Text(_off ? 'Marks the day as off' : 'Calendar event', style: TextStyle(fontSize: 12, color: p.label)),
              ]),
            ),
          ]),
        ),
        SwitchField(label: 'Active', value: _active, onChanged: (v) => setState(() => _active = v)),
        SwitchField(label: 'Off day', sub: 'Days with this type count as off', value: _off, onChanged: (v) => setState(() => _off = v)),
        FormLabel(
          label: 'Name',
          required: true,
          child: TextField(controller: _name, onChanged: (_) => setState(() {}), decoration: motionInput(context, hint: 'e.g. Eid holiday', icon: Icons.label_outline_rounded)),
        ),
        FormLabel(label: 'Description', child: TextField(controller: _desc, decoration: motionInput(context, hint: 'Enter description'))),
        FormLabel(
          label: 'Calendar colour',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final s in _swatches)
                PressScale(
                  onTap: () => _hex.text = colorHex(s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: s,
                      shape: BoxShape.circle,
                      border: Border.all(color: c?.toARGB32() == s.toARGB32() ? p.text : Colors.transparent, width: 2.5),
                    ),
                    child: AnimatedScale(
                      scale: c?.toARGB32() == s.toARGB32() ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutBack,
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _hex,
              decoration: motionInput(
                context,
                hint: '#3B82F6',
                icon: Icons.tag_rounded,
                suffix: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Container(width: 22, height: 22, decoration: BoxDecoration(color: c ?? Colors.transparent, borderRadius: BorderRadius.circular(6), border: Border.all(color: p.line))),
                ),
              ),
            ),
          ]),
        ),
        SwitchField(label: 'Has bonus', sub: 'Pay a bonus for working on these days', value: _bonus, onChanged: (v) => setState(() => _bonus = v)),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: !_bonus
              ? const SizedBox(width: double.infinity)
              : Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    FormLabel(
                      label: 'Bonus type',
                      required: true,
                      child: PickerField(
                        value: _bonusType,
                        hint: 'Select bonus type',
                        icon: Icons.card_giftcard_rounded,
                        options: [for (final b in widget.bonusTypes) PickOption(b['id'], str(b['name']))],
                        onChanged: (v) => setState(() => _bonusType = v),
                      ),
                    ),
                    FormLabel(
                      label: 'Payment type',
                      required: true,
                      child: MarketSegmented<String>(
                        value: _payType,
                        options: const [(id: 'PERCENTAGE', label: 'Percentage', count: null), (id: 'FIXED', label: 'Fixed', count: null)],
                        onChanged: (v) => setState(() => _payType = v),
                      ),
                    ),
                    FormLabel(
                      label: _payType == 'PERCENTAGE' ? 'Percentage (%)' : 'Amount',
                      required: true,
                      child: TextField(
                        controller: _value,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: motionInput(context, hint: _payType == 'PERCENTAGE' ? 'e.g. 50' : 'e.g. 5000', icon: Icons.payments_outlined),
                      ),
                    ),
                  ]),
                ),
        ),
      ],
    );
  }
}
