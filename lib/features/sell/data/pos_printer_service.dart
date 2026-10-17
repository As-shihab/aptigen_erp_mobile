import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// One paired Bluetooth device — a candidate to configure as a printer
/// (`Settings > Printers > Add Device`).
class PairedPrinter {
  final String name;
  final String macAddress;
  const PairedPrinter({required this.name, required this.macAddress});
}

/// Bluetooth printer transport, wrapping `print_bluetooth_thermal` (plain
/// Bluetooth Classic SPP byte writes — no location permission needed,
/// unlike most BLE-scanning printer packages). Purely the connection/write
/// layer — which device is configured/default lives in
/// `features/settings/data/printer_devices_service.dart`'s `PrinterDevice`
/// records, not here.
class PosPrinterService {
  /// Android 12+ (API 31) gates reading paired devices, connecting, and
  /// writing behind the runtime `BLUETOOTH_CONNECT` permission. The plugin
  /// declares it in its manifest but never actually requests it (that code
  /// path is dead in the native source) — without this, every native call
  /// silently no-ops, which looks like "no printers found" even though the
  /// device is paired in the phone's Bluetooth settings. Not needed below
  /// Android 12, where `BLUETOOTH`/`BLUETOOTH_ADMIN` are install-time only.
  ///
  /// `connect()` also calls `BluetoothAdapter.cancelDiscovery()` internally,
  /// which — despite connecting to an already-paired device having nothing
  /// to do with scanning — still requires `BLUETOOTH_SCAN` or it fails with
  /// "Need android.permission.BLUETOOTH_SCAN ... cancelDiscovery" and
  /// `connect` just returns false. So both permissions are requested
  /// together, not just `BLUETOOTH_CONNECT`.
  Future<bool> ensureBluetoothPermission() async {
    if (!Platform.isAndroid) return true;
    final statuses = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    return statuses.values.every((status) => status.isGranted);
  }

  /// The native side gates *every* method call behind the runtime
  /// permission check (not just the ones that logically need it), so this
  /// must also go through [ensureBluetoothPermission] first — otherwise the
  /// underlying platform-channel call never resolves at all when the
  /// permission is missing, rather than throwing.
  Future<bool> isBluetoothEnabled() async {
    if (!await ensureBluetoothPermission()) return false;
    return PrintBluetoothThermal.bluetoothEnabled;
  }

  /// Devices already paired in the phone's Bluetooth settings — this
  /// package can only connect to an already-paired printer.
  Future<List<PairedPrinter>> listPairedPrinters() async {
    if (!await ensureBluetoothPermission()) return [];
    final devices = await PrintBluetoothThermal.pairedBluetooths;
    return devices.map((d) => PairedPrinter(name: d.name, macAddress: d.macAdress)).toList();
  }

  Future<bool> get isConnected => PrintBluetoothThermal.connectionStatus;

  Future<bool> connectTo(String macAddress) async {
    if (!await ensureBluetoothPermission()) return false;
    return PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
  }

  Future<void> disconnect() => PrintBluetoothThermal.disconnect;

  /// Connects to [macAddress] (if not already connected) and writes
  /// [bytes]. Throws a plain `Exception` with a user-facing message on any
  /// failure, so callers can show it directly in a SnackBar.
  Future<void> printBytes(List<int> bytes, {required String macAddress}) async {
    if (!await ensureBluetoothPermission()) {
      throw Exception('Bluetooth permission was not granted. Enable "Nearby devices" for this app in system settings.');
    }

    final alreadyConnected = await PrintBluetoothThermal.connectionStatus;
    if (!alreadyConnected) {
      final connected = await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
      if (!connected) throw Exception('Could not connect to the printer. Make sure it\'s on and in range.');
    }

    final wrote = await PrintBluetoothThermal.writeBytes(bytes);
    if (!wrote) throw Exception('Print failed — the printer did not accept the data.');
  }
}
