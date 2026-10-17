import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'printer_device.dart';

/// Persists configured printer devices — device-local (SharedPreferences),
/// not synced to the backend, same as every other POS register preference
/// (`PosLocalPrefs`). Small list (a register has a handful of printers at
/// most), so a plain JSON blob is simpler than a database.
class PrinterDevicesService {
  static const _devicesKey = 'pos_printer_devices_v1';

  Future<List<PrinterDevice>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_devicesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.map((e) => PrinterDevice.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<PrinterDevice> devices) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_devicesKey, jsonEncode(devices.map((d) => d.toJson()).toList()));
  }

  /// Upserts [device] by id. If it's marked default (or it's the very first
  /// device ever saved), every other device is un-defaulted so there's
  /// always at most one.
  Future<void> save(PrinterDevice device) async {
    final devices = await loadAll();
    final index = devices.indexWhere((d) => d.id == device.id);
    final shouldBeDefault = device.isDefault || devices.isEmpty;
    final resolved = device.copyWith(isDefault: shouldBeDefault);

    final next = [
      for (final existing in devices)
        if (existing.id != device.id) (shouldBeDefault ? existing.copyWith(isDefault: false) : existing),
    ];
    if (index == -1) {
      next.add(resolved);
    } else {
      next.insert(index, resolved);
    }
    await _saveAll(next);
  }

  Future<void> delete(String id) async {
    final devices = await loadAll();
    final wasDefault = devices.any((d) => d.id == id && d.isDefault);
    final remaining = devices.where((d) => d.id != id).toList();
    if (wasDefault && remaining.isNotEmpty) {
      remaining[0] = remaining[0].copyWith(isDefault: true);
    }
    await _saveAll(remaining);
  }

  Future<void> setDefault(String id) async {
    final devices = await loadAll();
    await _saveAll(devices.map((d) => d.copyWith(isDefault: d.id == id)).toList());
  }

  Future<PrinterDevice?> getDefault() async {
    final devices = await loadAll();
    if (devices.isEmpty) return null;
    return devices.where((d) => d.isDefault).toList().firstOrNull ?? devices.first;
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
