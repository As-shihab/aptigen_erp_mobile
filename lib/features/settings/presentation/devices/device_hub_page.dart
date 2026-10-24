import 'package:flutter/material.dart';
import '../../../../core/network/socket_client.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/printer_devices_service.dart';
import '../../data/settings_service.dart';
import '../printers/printers_list_page.dart';
import '../widgets/settings_widgets.dart';
import 'device_config_pages.dart';

/// Settings → Device. Desktop DeviceHub.tsx has a Fingerprint tab (the
/// `devices` catalog with live MQTT status, edit, restart, clear
/// fingerprints, delete / factory reset and router setup) and a Printer
/// tab. This hub shows the fingerprint devices inline with live status from
/// the `device:status` socket event, and links to printers and the
/// device-local configuration pages.
class DeviceHubPage extends StatefulWidget {
  const DeviceHubPage({super.key});

  @override
  State<DeviceHubPage> createState() => _DeviceHubPageState();
}

class _DeviceHubPageState extends State<DeviceHubPage> {
  final _svc = DevicesService();
  List<JsonRow> _devices = [];
  final Map<String, ({bool online, String lastSeen})> _live = {};
  int _printers = 0;
  bool _loading = true;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
    final s = AppSocket.instance;
    s?.on('device:status', _onStatus);
    s?.on('device:fingerprints-cleared', _onCleared);
  }

  @override
  void dispose() {
    final s = AppSocket.instance;
    s?.off('device:status', _onStatus);
    s?.off('device:fingerprints-cleared', _onCleared);
    super.dispose();
  }

  void _onStatus(dynamic payload) {
    if (payload is! Map || !mounted) return;
    final id = str(payload['device_id']);
    if (id.isEmpty) return;
    setState(() => _live[id] = (online: asBool(payload['is_online']), lastSeen: str(payload['last_seen_at'])));
  }

  void _onCleared(dynamic payload) {
    if (payload is! Map || !mounted) return;
    final id = str(payload['device_id']);
    final ok = asBool(payload['status']);
    marketToast(context, ok ? 'All fingerprints cleared on "$id"' : '"$id" reported a failure clearing fingerprints', error: !ok);
  }

  Future<void> _load() async {
    setState(() {
      _loading = _devices.isEmpty;
      _error = null;
    });
    PrinterDevicesService().loadAll().then((p) {
      if (mounted) setState(() => _printers = p.length);
    });
    try {
      final rows = await _svc.list();
      if (mounted) setState(() => _devices = rows);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load devices'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _online(JsonRow d) => _live[str(d['device_id'])]?.online ?? asBool(d['is_online']);
  DateTime? _lastSeen(JsonRow d) => parseDate(_live[str(d['device_id'])]?.lastSeen ?? d['last_seen_at']);

  Future<void> _form([JsonRow? d]) async {
    final ok = await showMotionSheet<bool>(context, (_) => _DeviceForm(device: d, svc: _svc));
    if (ok == true) {
      if (mounted) marketToast(context, d == null ? 'Device created' : 'Device updated');
      _load();
    }
  }

  Future<void> _command(JsonRow d, String what) async {
    final id = positiveInt(d['id']);
    if (id == null) return;
    final name = str(d['device_id']);
    final (title, message, confirm) = switch (what) {
      'restart' => ('Restart device?', '"$name" will reboot and be briefly unreachable.', 'Restart'),
      'clear' => ('Clear fingerprints?', 'Every enrolled fingerprint on "$name" will be removed. This cannot be undone.', 'Clear'),
      _ => ('Delete device?', '"$name" will be factory reset and go back into pairing mode.', 'Delete'),
    };
    final ok = await confirmMarket(context, title: title, message: message, confirm: confirm, destructive: what != 'restart');
    if (!ok) return;
    try {
      switch (what) {
        case 'restart':
          await _svc.restart(id);
          if (mounted) marketToast(context, 'Restart command sent to "$name"');
        case 'clear':
          await _svc.clearFingerprints(id);
          if (mounted) marketToast(context, 'Clear command sent to "$name"');
        default:
          await _svc.delete(id);
          if (!mounted) return;
          marketToast(context, 'Device deleted');
          _load();
      }
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Command failed'), error: true);
    }
  }

  void _setup(JsonRow d) {
    if (!_online(d)) {
      showMotionSheet<void>(
        context,
        (ctx) => const SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SheetGrabber(),
              NoteBanner(
                icon: Icons.wifi_off_rounded,
                title: 'Device is offline',
                message: 'Remote router switching needs the device online. To set up an offline device, join its access point from the desktop app (device, setup).',
                tone: MarketTone.warn,
              ),
            ]),
          ),
        ),
      );
      return;
    }
    showMotionSheet<void>(context, (_) => _RemoteWifiSheet(device: d, svc: _svc));
  }

  Future<void> _actions(JsonRow d) async {
    final key = await showActionSheet(context, title: str(d['device_id']), actions: [
      (key: 'setup', label: 'Setup router', icon: Icons.router_outlined, destructive: false),
      (key: 'edit', label: 'Edit', icon: Icons.edit_outlined, destructive: false),
      (key: 'restart', label: 'Restart', icon: Icons.restart_alt_rounded, destructive: false),
      (key: 'clear', label: 'Clear fingerprints', icon: Icons.fingerprint_rounded, destructive: true),
      (key: 'delete', label: 'Delete and factory reset', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted || key == null) return;
    switch (key) {
      case 'setup':
        _setup(d);
      case 'edit':
        _form(d);
      default:
        _command(d, key);
    }
  }

  void _go(Widget page) => pushMotion(context, page).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = _devices.where((d) => q.isEmpty || '${str(d['device_id'])} ${str(d['device_type'])} ${str(d['connection_type'])}'.toLowerCase().contains(q)).toList();
    final online = _devices.where(_online).length;
    final tiles = [
      HubTile(icon: Icons.print_outlined, label: 'Printers', caption: '$_printers saved', accent: Accent.ocean, onTap: () => _go(const PrintersListPage())),
      HubTile(icon: Icons.fingerprint_rounded, label: 'Biometrics', caption: 'Verification prefs', accent: Accent.emerald, onTap: () => _go(const BiometricsSettingsPage())),
      HubTile(icon: Icons.sensors_rounded, label: 'Sensors', caption: 'Polling and sensors', accent: Accent.rose, onTap: () => _go(const SensorsSettingsPage())),
      HubTile(icon: Icons.toggle_on_outlined, label: 'Switches config', caption: 'Runtime switches', accent: Accent.violet, onTap: () => _go(const SwitchesConfigPage())),
      HubTile(icon: Icons.settings_input_antenna_rounded, label: 'WiFi provisioning', caption: 'Pairing steps', accent: Accent.indigo, onTap: () => _go(const WifiProvisioningPage())),
    ];
    return MotionScaffold(
      title: 'Device hub',
      subtitle: '${_devices.length} fingerprint devices · $online online',
      icon: Icons.devices_other_rounded,
      accent: Accent.sky,
      onRefresh: _load,
      onFab: () => _form(),
      fabLabel: 'Add device',
      headerExtra: HeaderSearch(hint: 'Search devices', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: KpiStrip(height: 112, children: [
              GradientKpi(icon: Icons.fingerprint_rounded, label: 'Fingerprint devices', value: _devices.length, accent: Accent.sky),
              GradientKpi(icon: Icons.wifi_rounded, label: 'Online now', value: online, accent: Accent.emerald),
              GradientKpi(icon: Icons.wifi_off_rounded, label: 'Offline', value: _devices.length - online, accent: Accent.rose),
              GradientKpi(icon: Icons.print_rounded, label: 'Printers', value: _printers, accent: Accent.ocean, onTap: () => _go(const PrintersListPage())),
            ]),
          ),
        ),
        sliverHubSection(title: 'Device settings', subtitle: 'Printers and device-local configuration', tiles: tiles),
        sliverBox(const SectionHeader('Fingerprint devices', subtitle: 'Tap a device for setup, restart and more'), padding: const EdgeInsets.fromLTRB(18, 4, 18, 0)),
        if (_loading)
          sliverSkeleton(count: 3, height: 120)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (list.isEmpty)
          sliverEmpty(icon: Icons.fingerprint_rounded, title: _devices.isEmpty ? 'No fingerprint devices yet' : 'No matches', message: _devices.isEmpty ? 'Pair a device from the desktop app, or add its catalog entry here.' : null)
        else
          sliverStagger(
            count: list.length,
            builder: (_, i) {
              final d = list[i];
              return _DeviceCard(device: d, online: _online(d), lastSeen: _lastSeen(d), onTap: () => _actions(d), onSetup: () => _setup(d));
            },
          ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final JsonRow device;
  final bool online;
  final DateTime? lastSeen;
  final VoidCallback onTap;
  final VoidCallback onSetup;
  const _DeviceCard({required this.device, required this.online, required this.lastSeen, required this.onTap, required this.onSetup});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final active = asBool(device['is_active'], fallback: true);
    return GlowCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(children: [
        Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Accent.sky.primary.withValues(alpha: 0.22), Accent.sky.primary.withValues(alpha: 0.04)]),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            const AccentIcon(Icons.fingerprint_rounded, accent: Accent.sky, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Text(str(device['device_id']), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.text)),
            ),
            _PulseDot(online: online),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              StatusPill(online ? 'Online' : 'Offline', tone: online ? MarketTone.ok : MarketTone.error, icon: online ? Icons.wifi_rounded : Icons.wifi_off_rounded),
              const SizedBox(width: 6),
              if (!active) const StatusPill('Inactive', tone: MarketTone.neutral),
              const Spacer(),
              Text('${str(device['device_type']).isEmpty ? 'Unknown type' : str(device['device_type'])} · ${str(device['connection_type']).isEmpty ? 'n/a' : str(device['connection_type'])}',
                  style: TextStyle(fontSize: 12, color: p.label)),
            ]),
            const SizedBox(height: 8),
            Text(str(device['api_url']).isEmpty ? 'No API address' : str(device['api_url']),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: p.label)),
            Row(children: [
              Expanded(child: Text(lastSeen == null ? 'Never seen' : 'Last seen ${timeAgo(lastSeen)}', style: TextStyle(fontSize: 11.5, color: p.label))),
              TextButton.icon(onPressed: onSetup, icon: const Icon(Icons.router_outlined, size: 18), label: const Text('Setup')),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Glowing status dot that pulses while the device is online.
class _PulseDot extends StatefulWidget {
  final bool online;
  const _PulseDot({required this.online});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final color = widget.online ? p.ok : p.error;
    return SizedBox(
      width: 22,
      height: 22,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Stack(alignment: Alignment.center, children: [
          if (widget.online)
            Container(
              width: 10 + 12 * _c.value,
              height: 10 + 12 * _c.value,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.35 * (1 - _c.value))),
            ),
          Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        ]),
      ),
    );
  }
}

class _DeviceForm extends StatefulWidget {
  final JsonRow? device;
  final DevicesService svc;
  const _DeviceForm({this.device, required this.svc});

  @override
  State<_DeviceForm> createState() => _DeviceFormState();
}

class _DeviceFormState extends State<_DeviceForm> {
  late final _id = TextEditingController(text: str(widget.device?['device_id']));
  late final _type = TextEditingController(text: str(widget.device?['device_type']));
  late final _conn = TextEditingController(text: str(widget.device?['connection_type']));
  late final _api = TextEditingController(text: str(widget.device?['api_url']));
  late final _socket = TextEditingController(text: str(widget.device?['socket_url']));
  late final _mqtt = TextEditingController(text: str(widget.device?['mqtt_url']));
  late bool _active = widget.device == null ? true : asBool(widget.device!['is_active'], fallback: true);
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_id, _type, _conn, _api, _socket, _mqtt]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (_id.text.trim().isEmpty) {
      marketToast(context, 'Device id is required', error: true);
      return;
    }
    setState(() => _busy = true);
    final body = {
      'device_id': _id.text.trim(),
      'device_type': _v(_type),
      'connection_type': _v(_conn),
      'api_url': _v(_api),
      'socket_url': _v(_socket),
      'mqtt_url': _v(_mqtt),
      'is_active': _active,
    };
    try {
      final id = positiveInt(widget.device?['id']);
      if (id == null) {
        await widget.svc.create(body);
      } else {
        await widget.svc.update(id, body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      marketToast(context, errorMessage(e, 'Could not save device'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => FormSheet(
        title: widget.device == null ? 'New device' : 'Edit device',
        subtitle: widget.device == null ? 'Catalog entry for a fingerprint device' : str(widget.device!['device_id']),
        busy: _busy,
        onSubmit: _save,
        submitLabel: widget.device == null ? 'Create device' : 'Save changes',
        children: [
          FormLabel(label: 'Device id', required: true, child: TextField(controller: _id, decoration: motionInput(context, hint: 'e.g. APTIGEN_FINGERPRINT', icon: Icons.fingerprint_rounded))),
          Row(children: [
            Expanded(child: FormLabel(label: 'Device type', child: TextField(controller: _type, decoration: motionInput(context, hint: 'e.g. esp32')))),
            const SizedBox(width: 12),
            Expanded(child: FormLabel(label: 'Connection type', child: TextField(controller: _conn, decoration: motionInput(context, hint: 'tcp, wifi or mqtt')))),
          ]),
          Wrap(spacing: 8, children: [
            for (final c in const ['mqtt', 'wifi', 'tcp'])
              ActionChip(label: Text(c), onPressed: () => setState(() => _conn.text = c)),
          ]),
          const SizedBox(height: 12),
          FormLabel(label: 'API address', child: TextField(controller: _api, keyboardType: TextInputType.url, decoration: motionInput(context, hint: 'http://192.168.1.50', icon: Icons.http_rounded))),
          FormLabel(label: 'Socket address', child: TextField(controller: _socket, keyboardType: TextInputType.url, decoration: motionInput(context, hint: 'ws://192.168.1.50:81', icon: Icons.cable_rounded))),
          FormLabel(label: 'MQTT address', child: TextField(controller: _mqtt, keyboardType: TextInputType.url, decoration: motionInput(context, hint: 'mqtt://192.168.1.50:1883', icon: Icons.hub_outlined))),
          SwitchField(label: 'Active', value: _active, onChanged: (v) => setState(() => _active = v)),
        ],
      );
}

/// Remote router switch for an online device: asks it to scan over MQTT,
/// waits for `device:networks`, then sends `switch-router`.
class _RemoteWifiSheet extends StatefulWidget {
  final JsonRow device;
  final DevicesService svc;
  const _RemoteWifiSheet({required this.device, required this.svc});

  @override
  State<_RemoteWifiSheet> createState() => _RemoteWifiSheetState();
}

class _RemoteWifiSheetState extends State<_RemoteWifiSheet> {
  List<({String ssid, int rssi, bool secure})> _nets = [];
  bool _scanning = false;
  bool _switching = false;
  String? _ssid;
  final _password = TextEditingController();
  final _manual = TextEditingController();
  bool _show = false;

  int get _id => positiveInt(widget.device['id']) ?? 0;
  String get _deviceId => str(widget.device['device_id']);

  @override
  void initState() {
    super.initState();
    AppSocket.instance?.on('device:networks', _onNets);
    _scan();
  }

  @override
  void dispose() {
    AppSocket.instance?.off('device:networks', _onNets);
    _password.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _onNets(dynamic payload) {
    if (payload is! Map || str(payload['device_id']) != _deviceId || !mounted) return;
    final raw = payload['networks'] is List ? payload['networks'] as List : const [];
    final nets = [
      for (final n in raw.whereType<Map>())
        if (!str(n['ssid']).toUpperCase().startsWith('APTIGEN') && str(n['ssid']).isNotEmpty) (ssid: str(n['ssid']), rssi: toInt(n['rssi']), secure: asBool(n['secure'], fallback: true)),
    ]..sort((a, b) => b.rssi.compareTo(a.rssi));
    setState(() {
      _nets = nets;
      _scanning = false;
    });
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _nets = [];
    });
    try {
      await widget.svc.scanNetworks(_id);
      Future.delayed(const Duration(seconds: 20), () {
        if (mounted && _scanning) setState(() => _scanning = false);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      marketToast(context, errorMessage(e, 'Could not request a network scan'), error: true);
    }
  }

  Future<void> _switch() async {
    final ssid = (_ssid ?? _manual.text).trim();
    if (ssid.isEmpty) {
      marketToast(context, 'Select a WiFi network', error: true);
      return;
    }
    setState(() => _switching = true);
    try {
      await widget.svc.switchRouter(_id, ssid, _password.text);
      if (!mounted) return;
      marketToast(context, 'Switch command sent. The device will reconnect shortly.');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _switching = false);
      marketToast(context, errorMessage(e, 'Could not send the switch command'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return FormSheet(
      title: 'Switch router',
      subtitle: _deviceId,
      busy: _switching,
      onSubmit: _switch,
      submitLabel: 'Switch network',
      extraAction: IconButton(onPressed: _scanning ? null : _scan, icon: Icon(Icons.refresh_rounded, color: p.label)),
      children: [
        if (_scanning)
          Column(children: [
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 8),
            Text('Asking the device to scan nearby networks', style: TextStyle(fontSize: 12.5, color: p.label)),
            const SizedBox(height: 12),
          ])
        else if (_nets.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: NoteBanner(title: 'No networks reported yet', message: 'Tap refresh to scan again, or type the network name below.', tone: MarketTone.warn),
          ),
        for (final n in _nets)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PressScale(
              onTap: () => setState(() => _ssid = n.ssid),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: _ssid == n.ssid ? p.brandSoft : p.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _ssid == n.ssid ? p.brand : Colors.transparent, width: 1.5),
                ),
                child: Row(children: [
                  Icon(n.rssi > -60 ? Icons.wifi_rounded : (n.rssi > -75 ? Icons.wifi_2_bar_rounded : Icons.wifi_1_bar_rounded),
                      color: n.rssi > -60 ? p.ok : (n.rssi > -75 ? p.warn : p.error)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(n.ssid, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text))),
                  if (n.secure) Icon(Icons.lock_outline_rounded, size: 16, color: p.label),
                  const SizedBox(width: 6),
                  Text('${n.rssi} dBm', style: TextStyle(fontSize: 11.5, color: p.label)),
                ]),
              ),
            ),
          ),
        if (_nets.isEmpty)
          FormLabel(label: 'Network name', child: TextField(controller: _manual, decoration: motionInput(context, hint: 'Router name', icon: Icons.router_outlined))),
        FormLabel(
          label: 'Password',
          child: TextField(
            controller: _password,
            obscureText: !_show,
            decoration: motionInput(context,
                hint: 'Router password',
                icon: Icons.lock_outline_rounded,
                suffix: IconButton(icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 19, color: p.label), onPressed: () => setState(() => _show = !_show))),
          ),
        ),
      ],
    );
  }
}
