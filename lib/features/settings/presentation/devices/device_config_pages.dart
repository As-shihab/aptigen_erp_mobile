import 'package:flutter/material.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/settings_service.dart';
import '../widgets/settings_widgets.dart';

// Device-local configuration pages ported from desktop device-config:
// Biometrics, Sensors, Switches config (desktop keeps these in localStorage
// under the same keys; here they live in SharedPreferences), and the WiFi
// provisioning walkthrough (read only — joining a device's access point
// needs the desktop app's network bridge).

/// Shared loader for a local preferences map.
mixin _LocalPrefsState<T extends StatefulWidget> on State<T> {
  String get prefsKey;
  JsonRow get defaults;
  JsonRow values = {};
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    values = {...defaults};
    LocalPrefs.read(prefsKey, defaults).then((v) {
      if (mounted) {
        setState(() {
          values = v;
          loaded = true;
        });
      }
    });
  }

  void patch(JsonRow p) {
    setState(() => values = {...values, ...p});
    LocalPrefs.write(prefsKey, values);
  }
}

// ── Biometrics ──────────────────────────────────────────────────────────

class BiometricsSettingsPage extends StatefulWidget {
  const BiometricsSettingsPage({super.key});

  @override
  State<BiometricsSettingsPage> createState() => _BiometricsSettingsPageState();
}

class _BiometricsSettingsPageState extends State<BiometricsSettingsPage> with _LocalPrefsState {
  @override
  String get prefsKey => LocalPrefs.biometricsKey;
  @override
  JsonRow get defaults => const {'biometricsEnabled': false, 'biometricMethod': 'fingerprint', 'approvalVerification': true};

  static const _methods = [
    (id: 'fingerprint', label: 'Fingerprint', desc: 'Use a fingerprint scanner for fast unlock.', icon: Icons.fingerprint_rounded),
    (id: 'face', label: 'Face ID', desc: 'Use the front camera for identity verification.', icon: Icons.face_retouching_natural_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final on = asBool(values['biometricsEnabled']);
    final method = str(values['biometricMethod']);
    final approval = asBool(values['approvalVerification'], fallback: true);
    final methodLabel = _methods.where((m) => m.id == method).firstOrNull?.label ?? 'Configured';
    return MotionScaffold(
      title: 'Biometrics',
      subtitle: 'Verification before sensitive device actions',
      icon: Icons.fingerprint_rounded,
      accent: Accent.emerald,
      slivers: [
        sliverBox(Row(children: [
          Expanded(child: StatChip(label: 'Biometric access', value: on ? methodLabel : 'Disabled', tone: on ? MarketTone.ok : MarketTone.neutral)),
          const SizedBox(width: 8),
          Expanded(child: StatChip(label: 'Approval check', value: approval ? 'Required' : 'Optional', tone: MarketTone.info)),
          const SizedBox(width: 8),
          Expanded(child: StatChip(label: 'Enrollment', value: on ? 'Active' : 'Inactive', tone: on ? MarketTone.ok : MarketTone.neutral)),
        ])),
        sliverBox(FadeSlideIn(
          child: SettingsSection(
            icon: Icons.fingerprint_rounded,
            accent: Accent.emerald,
            title: 'Biometrics',
            subtitle: 'Verification for device approval, sign-in and unlock',
            trailing: Switch.adaptive(value: on, onChanged: loaded ? (v) => patch({'biometricsEnabled': v}) : null),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: on ? 1 : 0.5,
              child: Column(children: [
                for (final m in _methods)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: PressScale(
                      onTap: on ? () => patch({'biometricMethod': m.id}) : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: method == m.id ? p.okBg : p.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: method == m.id ? p.ok : Colors.transparent, width: 1.5),
                        ),
                        child: Row(children: [
                          Icon(m.icon, color: method == m.id ? p.ok : p.label),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(m.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
                              Text(m.desc, style: TextStyle(fontSize: 12, color: p.label)),
                            ]),
                          ),
                          if (method == m.id) Icon(Icons.check_circle_rounded, color: p.ok),
                        ]),
                      ),
                    ),
                  ),
                SwitchField(
                  label: 'Approval verification',
                  sub: 'Ask for biometric confirmation before device-level approval or unlock',
                  value: approval,
                  onChanged: (v) => on ? patch({'approvalVerification': v}) : null,
                ),
              ]),
            ),
          ),
        )),
        sliverBox(const NoteBanner(
          title: 'Saved on this phone',
          message: 'Like the desktop app, these preferences are stored on this device only. Employee fingerprint and face enrollment lives in HR, biometrics.',
        )),
      ],
    );
  }
}

// ── Sensors ─────────────────────────────────────────────────────────────

class SensorsSettingsPage extends StatefulWidget {
  const SensorsSettingsPage({super.key});

  @override
  State<SensorsSettingsPage> createState() => _SensorsSettingsPageState();
}

class _SensorsSettingsPageState extends State<SensorsSettingsPage> with _LocalPrefsState {
  @override
  String get prefsKey => LocalPrefs.sensorsKey;
  @override
  JsonRow get defaults => const {'temperatureEnabled': true, 'motionEnabled': true, 'humidityEnabled': false, 'pollInterval': '15'};

  late final _interval = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _interval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loaded && !_seeded) {
      _seeded = true;
      _interval.text = str(values['pollInterval']);
    }
    final sensors = [
      (key: 'temperatureEnabled', title: 'Temperature sensor', sub: 'Thermal values for environment-aware automation', icon: Icons.thermostat_rounded, accent: Accent.rose),
      (key: 'motionEnabled', title: 'Motion sensor', sub: 'Movement and idle state changes on connected devices', icon: Icons.directions_run_rounded, accent: Accent.sky),
      (key: 'humidityEnabled', title: 'Humidity sensor', sub: 'Humidity-sensitive devices and thresholds', icon: Icons.water_drop_outlined, accent: Accent.emerald),
    ];
    final active = sensors.where((s) => asBool(values[s.key])).length;
    return MotionScaffold(
      title: 'Sensors',
      subtitle: 'Connected sensor monitoring and polling',
      icon: Icons.sensors_rounded,
      accent: Accent.rose,
      slivers: [
        sliverBox(Row(children: [
          Expanded(child: StatChip(label: 'Active sensors', value: '$active of ${sensors.length}', tone: MarketTone.ok)),
          const SizedBox(width: 8),
          Expanded(child: StatChip(label: 'Polling interval', value: '${str(values['pollInterval'])} sec', tone: MarketTone.info)),
        ])),
        sliverBox(FadeSlideIn(
          child: SettingsSection(
            icon: Icons.timer_outlined,
            accent: Accent.indigo,
            title: 'Polling interval',
            subtitle: 'How often connected sensors are checked',
            child: TextField(
              controller: _interval,
              keyboardType: TextInputType.number,
              onChanged: (v) => patch({'pollInterval': v.trim().isEmpty ? '15' : v.trim()}),
              decoration: motionInput(context, hint: 'Seconds', icon: Icons.av_timer_rounded),
            ),
          ),
        )),
        sliverStagger(
          count: sensors.length,
          builder: (_, i) {
            final s = sensors[i];
            final on = asBool(values[s.key]);
            return GlowCard(
              onTap: () => patch({s.key: !on}),
              child: Row(children: [
                AnimatedOpacity(duration: const Duration(milliseconds: 220), opacity: on ? 1 : 0.45, child: AccentIcon(s.icon, accent: s.accent, size: 42)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: MarketPalette.of(context).text)),
                    Text(s.sub, style: TextStyle(fontSize: 12, color: MarketPalette.of(context).label)),
                    const SizedBox(height: 4),
                    StatusPill(on ? 'Online' : 'Paused', tone: on ? MarketTone.ok : MarketTone.neutral),
                  ]),
                ),
                Switch.adaptive(value: on, onChanged: (v) => patch({s.key: v})),
              ]),
            );
          },
        ),
      ],
    );
  }
}

// ── Switches config ─────────────────────────────────────────────────────

class SwitchesConfigPage extends StatefulWidget {
  const SwitchesConfigPage({super.key});

  @override
  State<SwitchesConfigPage> createState() => _SwitchesConfigPageState();
}

class _SwitchesConfigPageState extends State<SwitchesConfigPage> with _LocalPrefsState {
  static const _items = [
    (id: 'auto-discovery', title: 'Auto device discovery', sub: 'Scan for nearby approved hardware when the app starts', icon: Icons.radar_rounded, accent: Accent.sky),
    (id: 'usb-watch', title: 'Hot-plug monitoring', sub: 'Track supported device connections and disconnects in real time', icon: Icons.usb_rounded, accent: Accent.amber),
    (id: 'offline-buffer', title: 'Offline event buffer', sub: 'Store device events locally while the workspace is offline', icon: Icons.cloud_sync_outlined, accent: Accent.emerald),
    (id: 'power-save', title: 'Power save mode', sub: 'Reduce polling frequency when the device is idle', icon: Icons.battery_saver_rounded, accent: Accent.violet),
  ];

  @override
  String get prefsKey => LocalPrefs.switchesKey;
  @override
  JsonRow get defaults => {for (final i in _items) i.id: true};

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final enabled = _items.where((i) => asBool(values[i.id], fallback: true)).length;
    return MotionScaffold(
      title: 'Switches config',
      subtitle: 'Runtime switches for connected devices',
      icon: Icons.toggle_on_outlined,
      accent: Accent.violet,
      actions: [
        TextButton(
          onPressed: () => patch({for (final i in _items) i.id: true}),
          child: const Text('Enable all', style: TextStyle(color: Colors.white)),
        ),
      ],
      slivers: [
        sliverBox(Row(children: [
          Expanded(child: StatChip(label: 'Enabled switches', value: '$enabled of ${_items.length}', tone: MarketTone.ok)),
          const SizedBox(width: 8),
          Expanded(child: StatChip(label: 'Runtime mode', value: enabled == _items.length ? 'Full access' : 'Custom', tone: MarketTone.info)),
        ])),
        sliverStagger(
          count: _items.length,
          builder: (_, i) {
            final it = _items[i];
            final on = asBool(values[it.id], fallback: true);
            return GlowCard(
              onTap: () => patch({it.id: !on}),
              child: Row(children: [
                AccentIcon(it.icon, accent: it.accent, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it.title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text)),
                    Text(it.sub, style: TextStyle(fontSize: 12, color: p.label)),
                  ]),
                ),
                Switch.adaptive(value: on, onChanged: (v) => patch({it.id: v})),
              ]),
            );
          },
        ),
      ],
    );
  }
}

// ── WiFi provisioning (read only) ───────────────────────────────────────

class WifiProvisioningPage extends StatelessWidget {
  const WifiProvisioningPage({super.key});

  static const _steps = [
    (title: 'Scan', sub: 'Find the device\'s own WiFi network. Its name starts with APTIGEN.', icon: Icons.wifi_find_rounded),
    (title: 'Connect', sub: 'Join the device\'s access point. The password is built into the firmware.', icon: Icons.wifi_tethering_rounded),
    (title: 'Configure', sub: 'Pick the shop router and enter its password. The device saves it and restarts.', icon: Icons.router_outlined),
    (title: 'Done', sub: 'The device joins your router, connects to the cloud and appears in the device list.', icon: Icons.check_circle_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MotionScaffold(
      title: 'WiFi provisioning',
      subtitle: 'How a new fingerprint device is paired',
      icon: Icons.settings_input_antenna_rounded,
      accent: Accent.indigo,
      slivers: [
        sliverBox(const NoteBanner(
          icon: Icons.desktop_windows_outlined,
          title: 'Pair new devices from the desktop app',
          message: 'Joining a device\'s access point and talking to it directly needs the desktop app\'s network bridge. Once a device is online, you can switch its router from this phone in device hub, setup.',
          tone: MarketTone.warn,
        )),
        sliverStagger(
          count: _steps.length,
          builder: (_, i) {
            final s = _steps[i];
            return IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  width: 40,
                  child: Column(children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(gradient: Accent.ocean.gradient, shape: BoxShape.circle),
                      child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                    if (i < _steps.length - 1) Expanded(child: Container(width: 2, margin: const EdgeInsets.only(top: 4), color: p.line)),
                  ]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GlowCard(
                    child: Row(children: [
                      Icon(s.icon, color: Accent.indigo.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text)),
                          Text(s.sub, style: TextStyle(fontSize: 12.5, height: 1.35, color: p.label)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ]),
            );
          },
        ),
      ],
    );
  }
}
