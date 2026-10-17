import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/printer_device.dart';
import '../../data/printer_devices_service.dart';
import 'add_printer_flow_page.dart';

/// Settings > Devices > Printers — every saved `PrinterDevice`, with a
/// "+ Add device" entry point into the connection wizard.
class PrintersListPage extends StatefulWidget {
  const PrintersListPage({super.key});

  @override
  State<PrintersListPage> createState() => _PrintersListPageState();
}

class _PrintersListPageState extends State<PrintersListPage> {
  final _service = PrinterDevicesService();
  List<PrinterDevice> _devices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final devices = await _service.loadAll();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _loading = false;
    });
  }

  Future<void> _addDevice() async {
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AddPrinterFlowPage()));
    if (added == true) _load();
  }

  Future<void> _setDefault(PrinterDevice device) async {
    await _service.setDefault(device.id);
    _load();
  }

  Future<void> _delete(PrinterDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove printer?'),
        content: Text('This will remove "${device.name}" from your saved printers.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.delete(device.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Printers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDevice,
        icon: const Icon(Icons.add),
        label: const Text('Add device'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : RefreshIndicator(
              onRefresh: _load,
              child: _devices.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 100),
                        Icon(Icons.print_outlined, size: 40, color: AppColors.slate400),
                        const SizedBox(height: 12),
                        Center(child: Text('No printers added yet.', style: TextStyle(color: AppColors.slate600))),
                        const SizedBox(height: 4),
                        Center(child: Text('Tap "Add device" to connect one.', style: TextStyle(fontSize: 12, color: AppColors.slate400))),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      itemCount: _devices.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final device = _devices[index];
                        return Container(
                          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.slate400.withValues(alpha: 0.2))),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                leading: CircleAvatar(radius: 20, backgroundColor: AppColors.brand.withValues(alpha: 0.12), child: const Icon(Icons.print_outlined, color: AppColors.brand)),
                                title: Row(
                                  children: [
                                    Flexible(child: Text(device.name, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                                    if (device.isDefault) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                                        child: const Text('Default', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.brand)),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Text('${printerConnectionTypeLabel(device.connectionType)} · ${device.paperWidthMm}mm · ${device.fullCut ? 'Full cut' : 'Partial cut'}'),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'default') _setDefault(device);
                                    if (value == 'delete') _delete(device);
                                  },
                                  itemBuilder: (context) => [
                                    if (!device.isDefault) const PopupMenuItem(value: 'default', child: Text('Set as default')),
                                    const PopupMenuItem(value: 'delete', child: Text('Remove')),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
