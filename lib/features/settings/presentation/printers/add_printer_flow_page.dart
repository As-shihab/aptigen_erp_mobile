import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../sell/data/esc_pos_builder.dart';
import '../../../sell/data/pos_printer_service.dart';
import '../../data/printer_device.dart';
import '../../data/printer_devices_service.dart';

/// "+ Add Device" wizard — choose a connection type, pick/connect a device
/// on that connection, then configure it as a printer. Only Bluetooth is
/// wired up today; Wi-Fi/USB are shown as future connection types so the
/// step-1 choice already has the shape it'll need later.
class AddPrinterFlowPage extends StatefulWidget {
  const AddPrinterFlowPage({super.key});

  @override
  State<AddPrinterFlowPage> createState() => _AddPrinterFlowPageState();
}

enum _Step { chooseType, bluetoothPick, configure }

class _AddPrinterFlowPageState extends State<AddPrinterFlowPage> {
  final _printerService = PosPrinterService();
  final _devicesService = PrinterDevicesService();

  _Step _step = _Step.chooseType;

  bool _btLoading = true;
  bool _btEnabled = true;
  bool _permissionDenied = false;
  List<PairedPrinter> _pairedPrinters = [];
  String? _connectingMac;

  // Step 3 state (prefilled once a device is picked/connected).
  String? _macAddress;
  final _nameController = TextEditingController();
  int _paperWidthMm = 58;
  bool _fullCut = false;
  bool _autoCut = true;
  bool _setAsDefault = true;
  bool _testPrinting = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _openBluetoothStep() async {
    setState(() => _step = _Step.bluetoothPick);
    await _loadPairedPrinters();
  }

  Future<void> _loadPairedPrinters() async {
    setState(() {
      _btLoading = true;
      _permissionDenied = false;
    });
    try {
      final granted = await _printerService.ensureBluetoothPermission();
      if (!granted) {
        if (!mounted) return;
        setState(() {
          _permissionDenied = true;
          _pairedPrinters = [];
        });
        return;
      }
      final enabled = await _printerService.isBluetoothEnabled();
      final paired = enabled ? await _printerService.listPairedPrinters() : <PairedPrinter>[];
      if (!mounted) return;
      setState(() {
        _btEnabled = enabled;
        _pairedPrinters = paired;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _btEnabled = false;
        _pairedPrinters = [];
      });
    } finally {
      if (mounted) setState(() => _btLoading = false);
    }
  }

  Future<void> _connect(PairedPrinter printer) async {
    setState(() => _connectingMac = printer.macAddress);
    try {
      final connected = await _printerService.connectTo(printer.macAddress);
      if (!mounted) return;
      if (!connected) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not connect. Make sure the printer is on and in range.')));
        return;
      }
      setState(() {
        _macAddress = printer.macAddress;
        _nameController.text = printer.name;
        _step = _Step.configure;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not connect to this device.')));
    } finally {
      if (mounted) setState(() => _connectingMac = null);
    }
  }

  Future<void> _testPrint() async {
    final mac = _macAddress;
    if (mac == null) return;
    setState(() => _testPrinting = true);
    try {
      final bytes = (EscPosBuilder()
            ..initialize()
            ..alignCenter()
            ..boldOn()
            ..line(_nameController.text.trim())
            ..boldOff()
            ..line('Test print')
            ..line(DateTime.now().toString())
            ..feedPaper(3)
            ..cut(full: _fullCut))
          .build();
      await _printerService.printBytes(bytes, macAddress: mac);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Test receipt sent.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _testPrinting = false);
    }
  }

  Future<void> _save() async {
    final mac = _macAddress;
    if (mac == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please name this printer.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final device = PrinterDevice(
        id: mac,
        name: name,
        connectionType: PrinterConnectionType.bluetooth,
        macAddress: mac,
        paperWidthMm: _paperWidthMm,
        fullCut: _fullCut,
        autoCut: _autoCut,
        isDefault: _setAsDefault,
      );
      await _devicesService.save(device);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save this printer.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titleFor(_step))),
      body: switch (_step) {
        _Step.chooseType => _buildChooseType(),
        _Step.bluetoothPick => _buildBluetoothPick(),
        _Step.configure => _buildConfigure(),
      },
    );
  }

  String _titleFor(_Step step) => switch (step) {
        _Step.chooseType => 'Add Device',
        _Step.bluetoothPick => 'Select Bluetooth printer',
        _Step.configure => 'Configure printer',
      };

  Widget _buildChooseType() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Choose how this printer connects.', style: TextStyle(color: AppColors.slate600, fontSize: 13)),
        const SizedBox(height: 16),
        _typeTile(icon: Icons.bluetooth, label: 'Bluetooth', enabled: true, onTap: _openBluetoothStep),
        const SizedBox(height: 10),
        _typeTile(icon: Icons.wifi, label: 'Wi-Fi', enabled: false),
        const SizedBox(height: 10),
        _typeTile(icon: Icons.usb, label: 'USB', enabled: false),
      ],
    );
  }

  Widget _typeTile({required IconData icon, required String label, required bool enabled, VoidCallback? onTap}) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.slate400.withValues(alpha: 0.25))),
          child: Row(
            children: [
              CircleAvatar(radius: 20, backgroundColor: AppColors.brand.withValues(alpha: 0.12), child: Icon(icon, color: AppColors.brand)),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              if (!enabled) Text('Coming soon', style: TextStyle(fontSize: 11, color: AppColors.slate600)) else const Icon(Icons.chevron_right, color: AppColors.slate400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBluetoothPick() {
    return RefreshIndicator(
      onRefresh: _loadPairedPrinters,
      child: _btLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : _permissionDenied
              ? ListView(children: [
                  const SizedBox(height: 100),
                  Icon(Icons.bluetooth_disabled, size: 40, color: AppColors.slate400),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text('Bluetooth permission was denied. Allow "Nearby devices" for this app in system settings, then come back here.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.slate600)),
                  ),
                  const SizedBox(height: 16),
                  Center(child: OutlinedButton(onPressed: openAppSettings, child: const Text('Open app settings'))),
                ])
              : !_btEnabled
              ? ListView(children: [
                  const SizedBox(height: 100),
                  Icon(Icons.bluetooth_disabled, size: 40, color: AppColors.slate400),
                  const SizedBox(height: 12),
                  Center(child: Text('Bluetooth is off. Turn it on and pull to refresh.', style: TextStyle(color: AppColors.slate600))),
                ])
              : _pairedPrinters.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 100),
                      Icon(Icons.print_disabled_outlined, size: 40, color: AppColors.slate400),
                      const SizedBox(height: 12),
                      Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Text('No paired printers found. Pair your thermal printer in the phone\'s Bluetooth settings first, then pull to refresh.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.slate600)))),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _pairedPrinters.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final printer = _pairedPrinters[index];
                        final connecting = _connectingMac == printer.macAddress;
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: connecting ? null : () => _connect(printer),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14)),
                            child: Row(
                              children: [
                                const Icon(Icons.print_outlined, color: AppColors.brand),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(printer.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                      Text(printer.macAddress, style: TextStyle(fontSize: 11, color: AppColors.slate600)),
                                    ],
                                  ),
                                ),
                                if (connecting) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) else const Icon(Icons.chevron_right, color: AppColors.slate400),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _buildConfigure() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Printer name *')),
              const SizedBox(height: 16),
              Text('Paper width', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.slate600)),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [ButtonSegment(value: 58, label: Text('58mm')), ButtonSegment(value: 80, label: Text('80mm'))],
                selected: {_paperWidthMm},
                onSelectionChanged: (s) => setState(() => _paperWidthMm = s.first),
              ),
              const SizedBox(height: 16),
              Text('Cut type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.slate600)),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: false, label: Text('Partial')), ButtonSegment(value: true, label: Text('Full'))],
                selected: {_fullCut},
                onSelectionChanged: (s) => setState(() => _fullCut = s.first),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-cut after printing'),
                value: _autoCut,
                onChanged: (v) => setState(() => _autoCut = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Set as default printer'),
                subtitle: Text('Used automatically by POS checkout and invoices.', style: TextStyle(fontSize: 11, color: AppColors.slate600)),
                value: _setAsDefault,
                onChanged: (v) => setState(() => _setAsDefault = v),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _testPrinting ? null : _testPrint,
                icon: _testPrinting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.print_outlined, size: 18),
                label: Text(_testPrinting ? 'Printing…' : 'Test print'),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save printer'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
