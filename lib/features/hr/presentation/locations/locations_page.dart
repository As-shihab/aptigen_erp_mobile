import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';

/// Work locations (attendance geofences) — port of erp/desktop's
/// Locations.tsx. Desktop picks coordinates on a Google map; mobile edits
/// latitude / longitude / radius directly and can fill them from the
/// device's current position.
class LocationsPage extends StatefulWidget {
  const LocationsPage({super.key});

  @override
  State<LocationsPage> createState() => _LocationsPageState();
}

class _LocationsPageState extends State<LocationsPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _q = '';
  String _status = 'all';

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
      final res = await _client.get('work_locations?\$top=500');
      if (!mounted) return;
      setState(() => _rows = unwrapList(res).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList());
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load locations'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _visible {
    final q = _q.trim().toLowerCase();
    return _rows.where((r) {
      final a = asBool(r['is_active'], fallback: true);
      if (_status == 'active' && !a) return false;
      if (_status == 'inactive' && a) return false;
      return q.isEmpty || '${str(r['name'])} ${str(r['address'])}'.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openForm([Map<String, dynamic>? row]) async {
    final saved = await showMotionSheet<bool>(context, (_) => _LocationForm(existing: row));
    if (saved == true) {
      if (mounted) marketToast(context, row == null ? 'Location created' : 'Location updated');
      _load();
    }
  }

  Future<bool> _delete(Map<String, dynamic> row) async {
    final ok = await confirmMarket(context, title: 'Delete location?', message: 'Delete location "${str(row['name'])}"?');
    if (!ok) return false;
    try {
      await _client.delete('work_locations', row['id']);
      if (mounted) {
        setState(() => _rows.removeWhere((r) => r['id'] == row['id']));
        marketToast(context, 'Location deleted');
      }
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete location'), error: true);
      return false;
    }
  }

  Future<void> _more(Map<String, dynamic> row) async {
    final key = await showActionSheet(context, title: str(row['name']), actions: [
      (key: 'edit', label: 'Edit', icon: Icons.edit_outlined, destructive: false),
      (key: 'copy', label: 'Copy coordinates', icon: Icons.copy_rounded, destructive: false),
      (key: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted) return;
    switch (key) {
      case 'edit':
        _openForm(row);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: '${row['latitude']}, ${row['longitude']}'));
        if (mounted) marketToast(context, 'Coordinates copied');
      case 'delete':
        _delete(row);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final active = _rows.where((r) => asBool(r['is_active'], fallback: true)).length;
    final avgRadius = _rows.isEmpty ? 0 : _rows.fold<num>(0, (s, r) => s + toDouble(r['radius_meters'])) / _rows.length;
    return MotionScaffold(
      title: 'Locations',
      subtitle: 'Work sites and attendance geofences',
      icon: Icons.place_outlined,
      accent: Accent.sunset,
      onRefresh: _load,
      onFab: () => _openForm(),
      fabLabel: 'New location',
      fabIcon: Icons.add_location_alt_outlined,
      headerExtra: HeaderSearch(hint: 'Search name or address', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        if (!_loading && _error == null && _rows.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.only(top: 16),
            sliver: SliverToBoxAdapter(
              child: KpiGrid(children: [
                KpiTile(icon: Icons.place_rounded, label: 'Locations', value: _rows.length, tone: MarketTone.brand),
                KpiTile(icon: Icons.check_circle_rounded, label: 'Active', value: active, tone: MarketTone.ok),
                KpiTile(icon: Icons.radar_rounded, label: 'Average radius (m)', value: avgRadius, tone: MarketTone.brand),
              ]),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _status,
              options: [
                (id: 'all', label: 'All', count: _rows.length),
                (id: 'active', label: 'Active', count: active),
                (id: 'inactive', label: 'Inactive', count: _rows.length - active),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton(height: 96)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.location_off_outlined,
            title: _rows.isEmpty ? 'No locations yet' : 'No matches',
            message: _rows.isEmpty ? 'Add a work site so employees can punch in within its radius.' : null,
            actionLabel: _rows.isEmpty ? 'New location' : null,
            onAction: _rows.isEmpty ? () => _openForm() : null,
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              final a = asBool(r['is_active'], fallback: true);
              return MotionTile(
                key: ValueKey(r['id']),
                leading: _GeofenceBadge(active: a),
                title: str(r['name']),
                subtitle: str(r['address']).isEmpty ? 'No address' : str(r['address']),
                meta: '${toDouble(r['latitude']).toStringAsFixed(5)}, ${toDouble(r['longitude']).toStringAsFixed(5)} · ${toInt(r['radius_meters'])} m radius',
                trailing: StatusPill(a ? 'Active' : 'Inactive', tone: a ? MarketTone.ok : MarketTone.neutral),
                onTap: () => _openForm(r),
                onLongPress: () => _more(r),
                onDelete: () => _delete(r),
              );
            },
          ),
      ],
    );
  }
}

/// Pulsing geofence icon.
class _GeofenceBadge extends StatefulWidget {
  final bool active;
  const _GeofenceBadge({required this.active});

  @override
  State<_GeofenceBadge> createState() => _GeofenceBadgeState();
}

class _GeofenceBadgeState extends State<_GeofenceBadge> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _GeofenceBadge old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.active ? Accent.sunset : Accent.ocean;
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(alignment: Alignment.center, children: [
        AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Container(
            width: 30 + 16 * _c.value,
            height: 30 + 16 * _c.value,
            decoration: BoxDecoration(shape: BoxShape.circle, color: accent.primary.withValues(alpha: 0.25 * (1 - _c.value))),
          ),
        ),
        AccentIcon(Icons.place_rounded, accent: accent, size: 34),
      ]),
    );
  }
}

class _LocationForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _LocationForm({this.existing});

  @override
  State<_LocationForm> createState() => _LocationFormState();
}

class _LocationFormState extends State<_LocationForm> {
  // Desktop's default centre (Dhaka) and radius.
  late final _name = TextEditingController(text: str(widget.existing?['name']));
  late final _address = TextEditingController(text: str(widget.existing?['address']));
  late final _lat = TextEditingController(text: str(widget.existing?['latitude'] ?? 23.8103));
  late final _lng = TextEditingController(text: str(widget.existing?['longitude'] ?? 90.4125));
  late final _radius = TextEditingController(text: str(widget.existing?['radius_meters'] ?? 100));
  late bool _active = asBool(widget.existing?['is_active'], fallback: true);
  bool _busy = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _radius.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _lat, _lng, _radius]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _useCurrent() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw 'Location services are turned off';
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw 'Location permission denied';
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
      if (!mounted) return;
      setState(() {
        _lat.text = pos.latitude.toStringAsFixed(6);
        _lng.text = pos.longitude.toStringAsFixed(6);
      });
      marketToast(context, 'Current location applied (accuracy ${pos.accuracy.round()} m)');
    } catch (e) {
      if (mounted) marketToast(context, e is String ? e : 'Could not get current location', error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      marketToast(context, 'Name is required', error: true);
      return;
    }
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      marketToast(context, 'Enter a valid latitude and longitude', error: true);
      return;
    }
    final radius = int.tryParse(_radius.text.trim());
    setState(() => _busy = true);
    final body = {
      'name': _name.text.trim(),
      'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      'latitude': lat,
      'longitude': lng,
      'radius_meters': (radius == null || radius <= 0) ? 100 : radius,
      'is_active': _active,
    };
    try {
      final api = EntityApi(ApiClient(), 'work_locations');
      if (widget.existing == null) {
        await api.create(body);
      } else {
        await api.update(widget.existing!['id'], body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(e, 'Failed to save location'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final radius = (double.tryParse(_radius.text) ?? 100).clamp(10, 2000).toDouble();
    return FormSheet(
      title: widget.existing == null ? 'New location' : 'Edit location',
      subtitle: widget.existing == null ? null : str(widget.existing!['name']),
      busy: _busy,
      onSubmit: _save,
      submitLabel: widget.existing == null ? 'Create' : 'Save changes',
      children: [
        SwitchField(label: 'Active', value: _active, onChanged: (v) => setState(() => _active = v)),
        FormLabel(label: 'Name', required: true, child: TextField(controller: _name, decoration: motionInput(context, hint: 'e.g. Head office', icon: Icons.business_outlined))),
        FormLabel(label: 'Address', child: TextField(controller: _address, decoration: motionInput(context, hint: 'Enter address', icon: Icons.signpost_outlined))),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: PressScale(
            onTap: _locating ? null : _useCurrent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.brand.withValues(alpha: 0.3))),
              child: Row(children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _locating
                      ? SizedBox(key: const ValueKey('l'), width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: p.brand))
                      : Icon(Icons.my_location_rounded, key: const ValueKey('i'), color: p.brand, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_locating ? 'Getting your location…' : 'Use my current location', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.brand)),
                    Text('Fills latitude and longitude from this device', style: TextStyle(fontSize: 11.5, color: p.label)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        Row(children: [
          Expanded(
            child: FormLabel(
              label: 'Latitude',
              child: TextField(controller: _lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: motionInput(context, hint: '23.8103')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FormLabel(
              label: 'Longitude',
              child: TextField(controller: _lng, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: motionInput(context, hint: '90.4125')),
            ),
          ),
        ]),
        FormLabel(
          label: 'Radius (m)',
          help: 'Employees must be within this distance to punch in here.',
          child: Column(children: [
            TextField(controller: _radius, keyboardType: TextInputType.number, decoration: motionInput(context, hint: '100', icon: Icons.radar_rounded)),
            Slider(
              value: radius,
              min: 10,
              max: 2000,
              divisions: 199,
              label: '${radius.round()} m',
              onChanged: (v) => _radius.text = v.round().toString(),
            ),
          ]),
        ),
      ],
    );
  }
}
