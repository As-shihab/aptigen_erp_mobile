import 'package:flutter/material.dart';
import '../../../../../core/network/http_client.dart';
import '../../../../auth/data/auth_service.dart';
import '../../widgets/sell_ui.dart' show MarketPalette, SectionHeader, showMarketSheet, marketToast;
import '../../../../settings/data/printer_device.dart';
import '../../../../settings/data/printer_devices_service.dart';
import '../../../../settings/presentation/printers/printers_list_page.dart';
import '../../../../store/data/store_util.dart';
import '../../../data/esc_pos_builder.dart';
import '../../../data/order_settings_service.dart';
import '../../../data/pos_local_prefs.dart';
import '../../../data/pos_printer_service.dart';

/// POS register settings — mirrors desktop's "POS Settings" dialog
/// (PosTerminal.tsx). Returns the saved `OrderSettings` on save, or null if
/// dismissed without saving.
Future<OrderSettings?> showPosSettingsSheet(BuildContext context, {required OrderSettings settings, required List<Map<String, dynamic>> warehouses, bool isPharma = false}) {
  return showMarketSheet<OrderSettings>(
    context,
    builder: (_) => _PosSettingsSheet(settings: settings, warehouses: warehouses, isPharma: isPharma),
  );
}

class _PosSettingsSheet extends StatefulWidget {
  final OrderSettings settings;
  final List<Map<String, dynamic>> warehouses;
  final bool isPharma;
  const _PosSettingsSheet({required this.settings, required this.warehouses, this.isPharma = false});

  @override
  State<_PosSettingsSheet> createState() => _PosSettingsSheetState();
}

class _PosSettingsSheetState extends State<_PosSettingsSheet> {
  late final _service = OrderSettingsService(ApiClient());
  final _printerService = PosPrinterService();
  late final _taxController = TextEditingController(text: widget.settings.defaultTaxRate.toString());
  late final _currencyController = TextEditingController(text: widget.settings.currencySymbolOverride);
  late final _footerController = TextEditingController(text: widget.settings.receiptFooter ?? '');
  late int? _warehouseId = widget.settings.defaultWarehouseId;
  bool _saving = false;
  bool _showReceiptLoading = true;
  bool _showReceiptAfterCheckout = true;
  bool _autoPrintReceipt = false;

  bool _printerLoading = true;
  PrinterDevice? _defaultPrinter;
  bool _testPrinting = false;

  @override
  void initState() {
    super.initState();
    _loadLocalPrefs();
    _loadDefaultPrinter();
  }

  Future<void> _loadLocalPrefs() async {
    final value = await PosLocalPrefs.getShowReceiptAfterCheckout();
    final autoPrint = await PosLocalPrefs.getAutoPrintReceipt(isPharma: widget.isPharma);
    if (!mounted) return;
    setState(() {
      _showReceiptAfterCheckout = value;
      _autoPrintReceipt = autoPrint;
      _showReceiptLoading = false;
    });
  }

  Future<void> _loadDefaultPrinter() async {
    setState(() => _printerLoading = true);
    final device = await PrinterDevicesService().getDefault();
    if (!mounted) return;
    setState(() {
      _defaultPrinter = device;
      _printerLoading = false;
    });
  }

  Future<void> _managePrinters() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrintersListPage()));
    _loadDefaultPrinter();
  }

  Future<void> _testPrint() async {
    final device = _defaultPrinter;
    if (device?.macAddress == null) return;
    setState(() => _testPrinting = true);
    try {
      final workplace = (await AuthService(ApiClient()).getStoredUser())?.workplaceName ?? '';
      final bytes = (EscPosBuilder()
            ..initialize()
            ..alignCenter()
            ..boldOn()
            ..line(workplace)
            ..boldOff()
            ..line('Test print')
            ..line(DateTime.now().toString())
            ..feedPaper(3)
            ..cut(full: device!.fullCut))
          .build();
      await _printerService.printBytes(bytes, macAddress: device.macAddress!);
      if (!mounted) return;
      marketToast(context, 'Test receipt sent to printer.');
    } catch (error) {
      if (!mounted) return;
      marketToast(context, error.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _testPrinting = false);
    }
  }

  @override
  void dispose() {
    _taxController.dispose();
    _currencyController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = widget.settings.copyWith(
        defaultTaxRate: double.tryParse(_taxController.text.trim()) ?? 0,
        currencySymbolOverride: _currencyController.text.trim(),
        receiptFooter: _footerController.text.trim().isEmpty ? null : _footerController.text.trim(),
        defaultWarehouseId: _warehouseId,
        clearWarehouse: _warehouseId == null,
      );
      await _service.save(updated);
      // Local-only preference, not part of the workplace-wide
      // `order_settings` row — same distinction as desktop's sound-mute
      // toggle, which also stays in localStorage rather than the server.
      await PosLocalPrefs.setShowReceiptAfterCheckout(_showReceiptAfterCheckout);
      await PosLocalPrefs.setAutoPrintReceipt(_autoPrintReceipt, isPharma: widget.isPharma);
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Could not save settings.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(9)),
                    child: Icon(Icons.settings_outlined, size: 18, color: p.brand),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('POS settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: p.text)),
                        const SizedBox(height: 2),
                        Text('Register defaults, receipt and printer', style: TextStyle(fontSize: 12, color: p.label)),
                      ],
                    ),
                  ),
                ],
              ),
              const SectionHeader('Checkout'),
              TextField(controller: _taxController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Default tax rate (%)')),
              const SizedBox(height: 12),
              TextField(controller: _currencyController, decoration: const InputDecoration(labelText: 'Currency symbol override', hintText: 'Leave blank to use workplace currency')),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: widget.warehouses.any((w) => toNum(w['id']) == _warehouseId) ? _warehouseId : null,
                decoration: const InputDecoration(labelText: 'Default warehouse'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('None — skip ledger posting')),
                  ...widget.warehouses.map((w) => DropdownMenuItem<int?>(value: toNum(w['id']), child: Text((w['name'] ?? '').toString()))),
                ],
                onChanged: (v) => setState(() => _warehouseId = v),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Checkouts and refunds post to Store > Stock ledger against this warehouse. Leave unset to skip the ledger (stock levels still update as before).',
                  style: TextStyle(fontSize: 11.5, color: p.label, height: 1.35),
                ),
              ),
              const SectionHeader('Receipt'),
              TextField(controller: _footerController, maxLines: 2, decoration: const InputDecoration(labelText: 'Receipt footer')),
              if (!_showReceiptLoading) ...[
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    title: Text('Show invoice after checkout', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                    subtitle: Text('This device only — off skips straight back to the terminal after a sale.', style: TextStyle(fontSize: 11.5, color: p.label)),
                    value: _showReceiptAfterCheckout,
                    onChanged: (v) => setState(() => _showReceiptAfterCheckout = v),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    title: Text('Auto print receipt after sale', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                    subtitle: Text('Sends the receipt to the default Bluetooth printer when a sale completes.', style: TextStyle(fontSize: 11.5, color: p.label)),
                    value: _autoPrintReceipt,
                    onChanged: (v) => setState(() => _autoPrintReceipt = v),
                  ),
                ),
              ],
              const SectionHeader('Receipt printer'),
              if (_printerLoading)
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator())
              else
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                  decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: _defaultPrinter == null ? p.neutralBg : p.brandSoft, borderRadius: BorderRadius.circular(9)),
                        child: Icon(_defaultPrinter == null ? Icons.print_disabled_outlined : Icons.print_outlined, size: 18, color: _defaultPrinter == null ? p.neutral : p.brand),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _defaultPrinter == null ? 'No printer configured' : _defaultPrinter!.name,
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: p.text),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(_defaultPrinter == null ? 'Add one to print receipts' : 'Default receipt printer', style: TextStyle(fontSize: 11.5, color: p.label)),
                          ],
                        ),
                      ),
                      TextButton(onPressed: _managePrinters, style: TextButton.styleFrom(foregroundColor: p.brand), child: const Text('Manage')),
                    ],
                  ),
                ),
              if (!_printerLoading && _defaultPrinter != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _testPrinting ? null : _testPrint,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.text,
                      side: BorderSide(color: p.line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _testPrinting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.print_outlined, size: 18),
                    label: Text(_testPrinting ? 'Printing…' : 'Test print'),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: p.brand,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save settings', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
