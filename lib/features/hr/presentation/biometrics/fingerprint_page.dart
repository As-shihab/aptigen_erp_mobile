import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/network/socket_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../../chat/data/chat_socket.dart';
import '../shift/shift_common.dart';

/// Fingerprint management — mirrors erp/desktop hrm/fingerprint/Fingerprint.tsx.
///
/// * Employees list (pick who to enroll, live "matched" highlight from
///   `device:match-result`).
/// * Devices (online / offline, type, connection) with Enroll and an
///   enrolled-fingerprints list per device (delete also tells the sensor).
/// * Enroll: POST /api/devices/:id/enroll, then live steps over the
///   `device:enroll-progress` socket event; on success the
///   employee_fingerprints record is saved. Closing early sends
///   /api/devices/:id/cancel-enroll.
///
/// The finger scan itself always happens on the physical sensor — the phone
/// only sends the command and follows progress, exactly like desktop.
class FingerprintPage extends StatefulWidget {
  const FingerprintPage({super.key});

  @override
  State<FingerprintPage> createState() => _FingerprintPageState();
}

class _FingerprintPageState extends State<FingerprintPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _devices = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _prints = [];
  String _tab = 'devices';
  String _active = 'All';
  String _q = '';
  Map<String, dynamic>? _selected;
  int? _matchedId;
  final List<VoidCallback> _subs = [];

  @override
  void initState() {
    super.initState();
    _load();
    // Live match — a scan on any device highlights that employee until the next one.
    _subs.add(subscribeChatSocket('device:match-result', (payload) {
      if (payload is! Map || payload['status'] == null || payload['status'] == false) return;
      final id = int.tryParse(str(payload['employee_id']));
      if (id == null || id <= 0 || !mounted) return;
      setState(() => _matchedId = id);
    }));
    // The sensor confirms whether it actually dropped a deleted template.
    _subs.add(subscribeChatSocket('device:fingerprint-deleted', (payload) {
      if (payload is! Map || !mounted) return;
      final deviceId = str(payload['device_id']);
      if (deviceId.isEmpty) return;
      if (payload['status'] != true) marketToast(context, '"$deviceId" reported it could not remove that fingerprint from the sensor', error: true);
    }));
  }

  @override
  void dispose() {
    for (final u in _subs) {
      u();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _devices.isEmpty && _employees.isEmpty;
      _error = null;
    });
    try {
      final data = await batchLoad(_client, {
        'devices': 'devices?\$select=id,device_id,device_type,connection_type,is_online,is_active,last_seen_at&\$orderby=${Uri.encodeComponent('id desc')}&\$top=500',
        'employees': 'employees?\$select=id,employee_no,first_name,last_name,email,is_active,profile_photo&\$orderby=${Uri.encodeComponent('id desc')}&\$top=2000',
        'prints': 'employee_fingerprints?\$select=id,employee_id,device_id&\$top=5000',
      });
      if (!mounted) return;
      setState(() {
        _devices = data['devices'] ?? [];
        _employees = data['employees'] ?? [];
        _prints = data['prints'] ?? [];
        if (_selected != null) {
          _selected = _employees.where((e) => e['id'] == _selected!['id']).firstOrNull ?? _selected;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load devices and employees'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _printsFor({Object? employeeId, String? deviceId}) => _prints.where((f) {
        if (employeeId != null && f['employee_id'].toString() != employeeId.toString()) return false;
        if (deviceId != null && str(f['device_id']) != deviceId) return false;
        return true;
      }).length;

  Future<void> _pickEmployee() async {
    final picked = await showPickerSheet(context,
        title: 'Enroll for',
        selected: _selected?['id'],
        options: [for (final e in _employees.where((e) => asBool(e['is_active'], fallback: true))) employeeOption(e)]);
    if (picked == null) return;
    setState(() => _selected = _employees.firstWhere((e) => e['id'].toString() == picked.id.toString()));
  }

  Future<void> _enroll(Map<String, dynamic> device) async {
    final emp = _selected;
    if (emp == null) {
      marketToast(context, 'Select an employee first', error: true);
      await _pickEmployee();
      return;
    }
    if (!asBool(device['is_online'])) {
      marketToast(context, 'Device is offline', error: true);
      return;
    }
    final ok = await showMotionSheet<bool>(context, (_) => _EnrollSheet(client: _client, device: device, employee: emp));
    if (ok == true) _load();
  }

  Future<void> _openPrints(Map<String, dynamic> device) async {
    await showMotionSheet<void>(context, (_) => _DevicePrintsSheet(client: _client, device: device));
    _load();
  }

  List<Map<String, dynamic>> get _visibleEmployees {
    final q = _q.trim().toLowerCase();
    return _employees.where((e) {
      final active = asBool(e['is_active'], fallback: true);
      if (_active == 'Active' && !active) return false;
      if (_active == 'Inactive' && active) return false;
      if (q.isEmpty) return true;
      return [personName(e), str(e['employee_no']), str(e['email'])].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> get _visibleDevices {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return _devices;
    return _devices.where((d) => [str(d['device_id']), str(d['device_type']), str(d['connection_type'])].join(' ').toLowerCase().contains(q)).toList();
  }

  Widget _banner(MarketPalette p) {
    final emp = _selected;
    return GlowCard(
      gradient: emp == null ? null : Accent.ocean.gradient,
      onTap: _pickEmployee,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        emp == null
            ? const AccentIcon(Icons.fingerprint_rounded, accent: Accent.ocean)
            : InitialsAvatar(personName(emp).isEmpty ? '?' : personName(emp), imageUrl: str(emp['profile_photo']), size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: Column(
              key: ValueKey(emp?['id']),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emp == null ? 'Who are you enrolling?' : 'Enrolling for ${personName(emp)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: emp == null ? p.text : Colors.white)),
                const SizedBox(height: 2),
                Text(
                  emp == null
                      ? 'Select an employee, then enroll on an online device'
                      : '${str(emp['employee_no']).isEmpty ? 'No employee no' : str(emp['employee_no'])} · ${_printsFor(employeeId: emp['id'])} fingerprints on file',
                  maxLines: 2,
                  style: TextStyle(fontSize: 12, color: emp == null ? p.label : Colors.white.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ),
        Icon(emp == null ? Icons.person_search_rounded : Icons.swap_horiz_rounded, color: emp == null ? p.brand : Colors.white),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final online = _devices.where((d) => asBool(d['is_online'])).length;
    final enrolledPeople = {for (final f in _prints) f['employee_id'].toString()}.length;
    final slivers = <Widget>[
      SliverPadding(
        padding: const EdgeInsets.only(top: 16),
        sliver: SliverToBoxAdapter(
          child: KpiGrid(children: [
            KpiTile(icon: Icons.router_rounded, label: 'Devices', value: _devices.length, tone: MarketTone.brand, onTap: () => setState(() => _tab = 'devices')),
            KpiTile(icon: Icons.wifi_tethering_rounded, label: 'Online now', value: online, tone: MarketTone.ok, onTap: () => setState(() => _tab = 'devices')),
            KpiTile(icon: Icons.fingerprint_rounded, label: 'Fingerprints', value: _prints.length, tone: MarketTone.brand),
            KpiTile(icon: Icons.verified_user_outlined, label: 'People enrolled', value: enrolledPeople, tone: MarketTone.brand, onTap: () => setState(() => _tab = 'employees')),
          ]),
        ),
      ),
      sliverBox(_banner(p)),
      sliverBox(
        Row(children: [
          SegmentToggle<String>(value: _tab, options: const [('devices', 'Devices'), ('employees', 'Employees')], onChanged: (v) => setState(() => _tab = v)),
          const Spacer(),
          if (_matchedId != null)
            FadeSlideIn(
              child: Row(children: [
                PulseDot(color: p.ok, size: 7),
                Text('Live match', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.ok)),
              ]),
            ),
        ]),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      ),
    ];

    if (_loading) {
      slivers.add(sliverSkeleton(count: 4, height: 120));
    } else if (_error != null) {
      slivers.add(sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load));
    } else if (_tab == 'devices') {
      final devices = _visibleDevices;
      if (devices.isEmpty) {
        slivers.add(sliverEmpty(
          icon: Icons.router_outlined,
          title: _devices.isEmpty ? 'No devices registered' : 'No matches',
          message: _devices.isEmpty ? 'Fingerprint devices appear here once they connect to this workplace.' : null,
        ));
      } else {
        slivers.add(SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 244),
            itemCount: devices.length,
            itemBuilder: (_, i) => FadeSlideIn(
              index: i,
              offsetY: 22,
              child: _DeviceCard(
                device: devices[i],
                prints: _printsFor(deviceId: str(devices[i]['device_id'])),
                canEnroll: _selected != null,
                onEnroll: () => _enroll(devices[i]),
                onPrints: () => _openPrints(devices[i]),
              ),
            ),
          ),
        ));
      }
      slivers.add(sliverBox(const _HardwareNote()));
    } else {
      final emps = _visibleEmployees;
      slivers.add(SliverPadding(
        padding: const EdgeInsets.only(top: 12),
        sliver: SliverToBoxAdapter(
          child: ChipFilter<String>(
            value: _active,
            options: [
              (id: 'All', label: 'All', count: _employees.length),
              (id: 'Active', label: 'Active', count: _employees.where((e) => asBool(e['is_active'], fallback: true)).length),
              (id: 'Inactive', label: 'Inactive', count: _employees.where((e) => !asBool(e['is_active'], fallback: true)).length),
            ],
            onChanged: (v) => setState(() => _active = v),
          ),
        ),
      ));
      if (emps.isEmpty) {
        slivers.add(sliverEmpty(icon: Icons.people_outline_rounded, title: _employees.isEmpty ? 'No employees yet' : 'No matches'));
      } else {
        slivers.add(sliverStagger(
          count: emps.length,
          builder: (_, i) {
            final e = emps[i];
            final matched = _matchedId != null && e['id'].toString() == _matchedId.toString();
            final selected = _selected != null && e['id'] == _selected!['id'];
            final active = asBool(e['is_active'], fallback: true);
            final n = _printsFor(employeeId: e['id']);
            return AnimatedContainer(
              key: ValueKey(e['id']),
              duration: const Duration(milliseconds: 260),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? p.brand : (matched ? p.ok : Colors.transparent), width: 1.6),
              ),
              child: MotionTile(
                leading: InitialsAvatar(personName(e).isEmpty ? '?' : personName(e), imageUrl: str(e['profile_photo']), size: 42),
                title: personName(e).isEmpty ? 'Employee #${e['id']}' : personName(e),
                subtitle: [if (str(e['employee_no']).isNotEmpty) str(e['employee_no']), if (str(e['email']).isNotEmpty) str(e['email'])].join(' · '),
                meta: n == 0 ? 'No fingerprints enrolled' : '$n ${n == 1 ? 'fingerprint' : 'fingerprints'} enrolled',
                trailing: matched
                    ? Row(mainAxisSize: MainAxisSize.min, children: [PulseDot(color: p.ok, size: 7), StatusPill('Matched', tone: MarketTone.ok, icon: Icons.check_rounded)])
                    : StatusPill(active ? 'Active' : 'Inactive', tone: active ? MarketTone.ok : MarketTone.error),
                onTap: () {
                  setState(() {
                    _selected = e;
                    _tab = 'devices';
                  });
                  marketToast(context, 'Now pick an online device to enroll ${personName(e)}');
                },
              ),
            );
          },
        ));
      }
    }

    return MotionScaffold(
      title: 'Fingerprint',
      subtitle: 'Enroll employees on attendance devices',
      icon: Icons.fingerprint_rounded,
      accent: Accent.ocean,
      onRefresh: _load,
      headerExtra: HeaderSearch(hint: _tab == 'devices' ? 'Search devices' : 'Search employees', onChanged: (v) => setState(() => _q = v)),
      slivers: slivers,
    );
  }
}

// ── Device card ─────────────────────────────────────────────────────────

const _devicePalette = [
  Color(0xFF168EFF), Color(0xFFC87B00), Color(0xFF75980B), Color(0xFFDF1278), Color(0xFF8B47D7), Color(0xFF049F9A),
  Color(0xFF0070F2), Color(0xFFCC00DC),
];

IconData _deviceIcon(String? connection) {
  final t = (connection ?? '').toLowerCase();
  if (t.contains('wifi')) return Icons.wifi_rounded;
  if (t.contains('mqtt') || t.contains('tcp')) return Icons.router_rounded;
  return Icons.memory_rounded;
}

class _DeviceCard extends StatelessWidget {
  final Map<String, dynamic> device;
  final int prints;
  final bool canEnroll;
  final VoidCallback onEnroll;
  final VoidCallback onPrints;
  const _DeviceCard({required this.device, required this.prints, required this.canEnroll, required this.onEnroll, required this.onPrints});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final id = str(device['device_id']).isEmpty ? 'device' : str(device['device_id']);
    final accent = _devicePalette[(id.codeUnitAt(0) + (id.length > 1 ? id.codeUnitAt(1) : 0)) % _devicePalette.length];
    final online = asBool(device['is_online']);
    final enabled = canEnroll && online;
    final seen = parseDate(device['last_seen_at']);
    return GlowCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        SizedBox(
          height: 92,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
            ),
            Positioned(top: 4, right: 4, child: PulseDot(color: online ? const Color(0xFF30914C) : const Color(0xFF8396A8), active: online, size: 8)),
            Positioned(
              top: 28,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Color.lerp(accent, Colors.white, p.dark ? 0.2 : 0.88),
                    shape: BoxShape.circle,
                    border: Border.all(color: p.card, width: 3),
                  ),
                  child: Icon(_deviceIcon(str(device['connection_type'])), color: accent, size: 24),
                ),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
          child: Column(children: [
            Text(id, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
            Text(str(device['device_type']).isEmpty ? 'Unknown type' : str(device['device_type']), maxLines: 1, style: TextStyle(fontSize: 11, color: p.label)),
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 4, children: [
              SoftChip(str(device['connection_type']).isEmpty ? 'n/a' : str(device['connection_type']), color: accent),
              SoftChip(online ? 'Online' : 'Offline', color: online ? const Color(0xFF30914C) : null),
            ]),
            const SizedBox(height: 4),
            Text(
              online ? '$prints enrolled' : (seen == null ? '$prints enrolled' : 'Seen ${fmtDateTime(seen)}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: p.label),
            ),
          ]),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Row(children: [
            PressScale(
              onTap: onPrints,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.list_rounded, size: 18, color: accent),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PressScale(
                onTap: onEnroll,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 36,
                  decoration: BoxDecoration(color: enabled ? accent : p.surface, borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.fingerprint_rounded, size: 16, color: enabled ? Colors.white : p.label),
                    const SizedBox(width: 4),
                    Text('Enroll', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: enabled ? Colors.white : p.label)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _HardwareNote extends StatelessWidget {
  const _HardwareNote();

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.infoBg, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, color: p.info, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Scanning happens on the device sensor itself. The employee needs to be at the device — this phone only sends the enroll command and follows the progress live. Device setup (wifi, pairing) is done on the device.',
            style: TextStyle(fontSize: 12, color: p.text, height: 1.35),
          ),
        ),
      ]),
    );
  }
}

// ── Enroll progress ─────────────────────────────────────────────────────

const _stepLabel = {
  'idle': 'Sending the enroll command',
  'waiting_scan_1': 'Place finger on sensor',
  'lift_finger': 'Lift finger',
  'waiting_scan_2': 'Place the same finger again',
  'processing': 'Processing',
  'enrolled': 'Enrolled successfully',
  'error': 'Enrollment failed',
};

const _stepOrder = ['idle', 'waiting_scan_1', 'lift_finger', 'waiting_scan_2', 'processing', 'enrolled'];

class _EnrollSheet extends StatefulWidget {
  final ApiClient client;
  final Map<String, dynamic> device;
  final Map<String, dynamic> employee;
  const _EnrollSheet({required this.client, required this.device, required this.employee});

  @override
  State<_EnrollSheet> createState() => _EnrollSheetState();
}

class _EnrollSheetState extends State<_EnrollSheet> with SingleTickerProviderStateMixin {
  String _step = 'idle';
  String _message = '';
  VoidCallback? _unsub;
  bool _recorded = false;
  bool _cancelSent = false;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();

  bool get _done => _step == 'enrolled' || _step == 'error';
  int get _empId => int.tryParse(str(widget.employee['id'])) ?? 0;

  @override
  void initState() {
    super.initState();
    _unsub = subscribeChatSocket('device:enroll-progress', (payload) {
      if (payload is! Map || int.tryParse(str(payload['employee_id'])) != _empId || !mounted) return;
      final step = str(payload['step']);
      if (!_stepLabel.containsKey(step)) return;
      setState(() {
        _step = step;
        _message = str(payload['message']);
      });
      if (step == 'enrolled') _record();
      if (_done) _pulse.stop();
    });
    _start();
  }

  @override
  void dispose() {
    // Sheet dragged away mid-scan — still release the device.
    _cancelIfRunning();
    _unsub?.call();
    _pulse.dispose();
    super.dispose();
  }

  void _cancelIfRunning() {
    if (_done || _cancelSent) return;
    _cancelSent = true;
    unawaited(widget.client.post('devices/${widget.device['id']}/cancel-enroll', {}).catchError((_) => null));
  }

  Future<void> _start() async {
    try {
      await widget.client.post('devices/${widget.device['id']}/enroll', {'employee_id': _empId});
      if (mounted && _step == 'idle') setState(() => _step = 'waiting_scan_1');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _step = 'error';
        _message = 'Could not reach the device';
      });
      _pulse.stop();
    }
  }

  // Once the sensor confirms the template is stored, record which
  // employee / device pair it belongs to.
  Future<void> _record() async {
    if (_recorded) return;
    _recorded = true;
    try {
      final existing = await widget.client.get('employee_fingerprints?\$filter=${Uri.encodeComponent('employee_id eq $_empId')}&\$select=id&\$top=10');
      final next = unwrapList(existing).length.clamp(0, 9);
      await EntityApi(widget.client, 'employee_fingerprints').create({
        'employee_id': _empId,
        'device_id': str(widget.device['device_id']),
        'finger_index': next,
        'template': 'stored-on-device',
        'is_active': true,
      });
    } catch (_) {
      if (mounted) marketToast(context, 'Enrolled on device, but failed to save the fingerprint record', error: true);
    }
  }

  void _close() {
    // Tell the device to abandon the scan instead of waiting forever.
    _cancelIfRunning();
    Navigator.pop(context, _step == 'enrolled');
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final ok = _step == 'enrolled';
    final err = _step == 'error';
    final color = ok ? p.ok : (err ? p.error : p.brand);
    final idx = _stepOrder.indexOf(_step);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SheetGrabber(),
            Text('Enroll ${personName(widget.employee)}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
            Text(str(widget.device['device_id']), style: TextStyle(fontSize: 12.5, color: p.label)),
            const SizedBox(height: 22),
            SizedBox(
              width: 130,
              height: 130,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, _) => Stack(alignment: Alignment.center, children: [
                  if (!_done)
                    for (final k in [0.0, 0.5])
                      Opacity(
                        opacity: (1 - ((_pulse.value + k) % 1)) * 0.5,
                        child: Container(
                          width: 70 + 60 * ((_pulse.value + k) % 1),
                          height: 70 + 60 * ((_pulse.value + k) % 1),
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
                        ),
                      ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.14)),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                      child: Icon(
                        ok ? Icons.check_circle_rounded : (err ? Icons.error_rounded : Icons.fingerprint_rounded),
                        key: ValueKey(_step),
                        size: 42,
                        color: color,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: Column(key: ValueKey('$_step$_message'), children: [
                Text(_stepLabel[_step] ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
                if (_message.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_message, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: p.label)),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            if (!err)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 1; i < _stepOrder.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i <= idx ? 26 : 10,
                    height: 6,
                    decoration: BoxDecoration(color: i <= idx ? color : p.line, borderRadius: BorderRadius.circular(3)),
                  ),
              ]),
            if (AppSocket.instance == null && !_done) ...[
              const SizedBox(height: 12),
              Text('Live progress is unavailable while the realtime connection is offline. Check the device screen.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: p.warn)),
            ],
            const SizedBox(height: 20),
            _done
                ? GradientButton(label: 'Close', accent: ok ? Accent.emerald : Accent.ocean, onTap: _close)
                : SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _close,
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Cancel'),
                    ),
                  ),
          ]),
        ),
      ),
    );
  }
}

// ── Enrolled fingerprints on one device ─────────────────────────────────

class _DevicePrintsSheet extends StatefulWidget {
  final ApiClient client;
  final Map<String, dynamic> device;
  const _DevicePrintsSheet({required this.client, required this.device});

  @override
  State<_DevicePrintsSheet> createState() => _DevicePrintsSheetState();
}

class _DevicePrintsSheetState extends State<_DevicePrintsSheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = str(widget.device['device_id']).replaceAll("'", "''");
      final res = await widget.client.get(
          "employee_fingerprints?\$filter=${Uri.encodeComponent("device_id eq '$id'")}&\$select=id,employee_id,finger_index,device_id,created_at&\$expand=employee(\$select=id,first_name,last_name,employee_no,profile_photo)&\$top=1000");
      if (mounted) setState(() => _list = rowsOf(res));
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Failed to load fingerprints'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> fp) async {
    final name = personName(fp['employee']).isEmpty ? 'this employee' : personName(fp['employee']);
    final ok = await confirmMarket(context, title: 'Delete fingerprint?', message: "Remove $name's fingerprint from \"${widget.device['device_id']}\"? This cannot be undone.");
    if (!ok) return;
    try {
      await widget.client.delete('employee_fingerprints', fp['id']);
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete'), error: true);
      return;
    }
    try {
      await widget.client.post('devices/${widget.device['id']}/delete-fingerprint', {'employee_id': fp['employee_id']});
    } catch (_) {
      if (mounted) marketToast(context, 'Removed the record, but failed to notify the device', error: true);
    }
    if (!mounted) return;
    marketToast(context, 'Fingerprint deleted');
    setState(() => _list.removeWhere((x) => x['id'] == fp['id']));
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(children: [
        const SheetGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(children: [
            const AccentIcon(Icons.fingerprint_rounded, accent: Accent.ocean, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Fingerprints', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
                Text(str(widget.device['device_id']), style: TextStyle(fontSize: 12.5, color: p.label)),
              ]),
            ),
            IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: p.label)),
          ]),
        ),
        Expanded(
          child: _loading
              ? ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: 4,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, _) => const SkeletonBox(height: 62, radius: 12),
                )
              : _error != null
                  ? MarketEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
                  : _list.isEmpty
                      ? const MarketEmpty(icon: Icons.fingerprint_rounded, title: 'No fingerprints enrolled on this device')
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: _list.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final fp = _list[i];
                            final name = personName(fp['employee']);
                            return FadeSlideIn(
                              index: i,
                              child: MotionTile(
                                key: ValueKey(fp['id']),
                                leading: InitialsAvatar(name.isEmpty ? '?' : name, imageUrl: fp['employee'] is Map ? str((fp['employee'] as Map)['profile_photo']) : null, size: 40),
                                title: name.isEmpty ? 'Employee #${fp['employee_id']}' : name,
                                subtitle: 'Finger slot ${fp['finger_index']}',
                                meta: fp['created_at'] == null ? null : 'Enrolled ${fmtDate(parseDate(fp['created_at']))}',
                                trailing: IconButton(
                                  tooltip: 'Delete',
                                  onPressed: () => _delete(fp),
                                  icon: Icon(Icons.delete_outline_rounded, color: p.error),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
