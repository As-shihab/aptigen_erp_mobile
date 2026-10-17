import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../storage/app_storage.dart';

/// Identifies this install to the backend's device-approval gate (see
/// AuthService.activateWorkplace / auth.service.ts's assertDeviceApproved).
/// Desktop/web never sends any of this — it's mobile-only, which is exactly
/// what makes the gate mobile-only on the backend side too.
class DeviceIdentity {
  static const _uuid = Uuid();

  /// Get-or-create a persistent random UUID for this install. Not a device
  /// hardware fingerprint (those need extra platform permissions/entitlements
  /// and can change on OS updates) — a plain generated ID persisted locally
  /// is enough to recognize "this app install" across launches, which is all
  /// the approval gate needs.
  static Future<String> id() async {
    final existing = await AppStorage.getDeviceId();
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = _uuid.v4();
    await AppStorage.setDeviceId(generated);
    return generated;
  }

  static String get platform {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return Platform.operatingSystem;
  }

  /// Display label only (e.g. "iPhone 15 Pro, iOS 17.4") — shown to admins
  /// on Settings → Device Request, never used to identify the device itself.
  static Future<String?> name() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return '${info.name}, iOS ${info.systemVersion}';
      }
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return '${info.manufacturer} ${info.model}, Android ${info.version.release}';
      }
    } catch (_) {
      // Best-effort — a missing display name shouldn't block login.
    }
    return null;
  }

  /// Best-effort current position — never throws. A denied/unavailable
  /// location just means the device_requests row has no lat/long, it never
  /// blocks the login attempt itself.
  static Future<({double? latitude, double? longitude})> location() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return (latitude: null, longitude: null);

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (latitude: null, longitude: null);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return (latitude: position.latitude, longitude: position.longitude);
    } catch (_) {
      return (latitude: null, longitude: null);
    }
  }
}
