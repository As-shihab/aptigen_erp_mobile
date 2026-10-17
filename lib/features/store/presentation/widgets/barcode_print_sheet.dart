import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import '../../../settings/data/printer_devices_service.dart';
import '../../../settings/presentation/printers/printers_list_page.dart';
import '../../../sell/data/pos_printer_service.dart';
import '../../../sell/market/presentation/banners/form_kit.dart' show FieldBlock, SheetHeader, SwitchRow, marketInput;
import '../../data/barcode_label_bytes.dart';
import '../../data/barcode_print_prefs.dart';
import 'store_ui.dart';

/// "Print barcode" bottom sheet — live CODE128 preview + copies stepper,
/// sends the label to the workplace's default `PrinterDevice` on print.
/// Shared by the Packaging list's per-row print action and the Barcode Lab.
///
/// [infoLines] is label->value extra info (price, product name, qty, ...) —
/// each entry gets its own on/off switch so what actually prints on the
/// label is chosen per print, not fixed.
Future<void> showBarcodePrintSheet(BuildContext context, {required String code, String? title, Map<String, String> infoLines = const {}}) {
  return showMarketSheet<void>(context, builder: (_) => _BarcodePrintSheet(code: code, title: title, infoLines: infoLines));
}

class _BarcodePrintSheet extends StatefulWidget {
  final String code;
  final String? title;
  final Map<String, String> infoLines;
  const _BarcodePrintSheet({required this.code, this.title, this.infoLines = const {}});

  @override
  State<_BarcodePrintSheet> createState() => _BarcodePrintSheetState();
}

class _BarcodePrintSheetState extends State<_BarcodePrintSheet> {
  final _printerService = PosPrinterService();
  final _labelWidthController = TextEditingController();
  final _labelHeightController = TextEditingController();
  int _copies = 1;
  int _barHeight = BarcodePrintPrefs.defaultBarHeight;
  int _barWidth = BarcodePrintPrefs.defaultBarWidth;
  double _labelWidthMm = BarcodePrintPrefs.defaultLabelWidthMm;
  double _labelHeightMm = BarcodePrintPrefs.defaultLabelHeightMm;
  bool _showBarcodeText = true;
  late final Map<String, bool> _infoEnabled = {for (final key in widget.infoLines.keys) key: true};
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _labelWidthController.dispose();
    _labelHeightController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final results = await Future.wait([
      BarcodePrintPrefs.getBarHeight(),
      BarcodePrintPrefs.getBarWidth(),
      BarcodePrintPrefs.getLabelWidthMm(),
      BarcodePrintPrefs.getLabelHeightMm(),
      BarcodePrintPrefs.getShowBarcodeText(),
    ]);
    if (!mounted) return;
    setState(() {
      _barHeight = results[0] as int;
      _barWidth = results[1] as int;
      _labelWidthMm = results[2] as double;
      _labelHeightMm = results[3] as double;
      _showBarcodeText = results[4] as bool;
      _labelWidthController.text = _formatMm(_labelWidthMm);
      _labelHeightController.text = _formatMm(_labelHeightMm);
    });
  }

  String _formatMm(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  void _setBarHeight(int value) {
    setState(() => _barHeight = value);
    BarcodePrintPrefs.setBarHeight(value);
  }

  void _setBarWidth(int value) {
    setState(() => _barWidth = value);
    BarcodePrintPrefs.setBarWidth(value);
  }

  void _setShowBarcodeText(bool value) {
    setState(() => _showBarcodeText = value);
    BarcodePrintPrefs.setShowBarcodeText(value);
  }

  void _setLabelWidthMm(String text) {
    final value = double.tryParse(text.trim());
    if (value == null || value <= 0) return;
    _labelWidthMm = value;
    BarcodePrintPrefs.setLabelWidthMm(value);
    setState(() {});
  }

  void _setLabelHeightMm(String text) {
    final value = double.tryParse(text.trim());
    if (value == null || value <= 0) return;
    _labelHeightMm = value;
    BarcodePrintPrefs.setLabelHeightMm(value);
    setState(() {});
  }

  void _fitToLabel() => _setBarHeight(BarcodePrintPrefs.suggestBarHeight(_labelHeightMm));

  List<String> get _enabledFooterLines => [
        for (final entry in widget.infoLines.entries)
          if (_infoEnabled[entry.key] == true) '${entry.key}: ${entry.value}',
      ];

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      final device = await PrinterDevicesService().getDefault();
      if (device?.macAddress == null) {
        if (!mounted) return;
        final goToPrinters = await confirmMarket(
          context,
          title: 'No printer configured',
          message: 'Add a printer in Settings > Printers first.',
          confirm: 'Open printers',
          destructive: false,
        );
        if (goToPrinters && mounted) {
          await Navigator.of(context).push(marketRoute<void>(const PrintersListPage()));
        }
        return;
      }
      final bytes = buildBarcodeLabelEscPosBytes(
        code: widget.code,
        title: widget.title,
        footerLines: _enabledFooterLines,
        showBarcodeText: _showBarcodeText,
        copies: _copies,
        fullCut: device!.fullCut,
        barHeight: _barHeight,
        barWidth: _barWidth,
      );
      await _printerService.printBytes(bytes, macAddress: device.macAddress!);
      if (!mounted) return;
      marketToast(context, 'Label sent to printer.');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      marketToast(context, error.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final aspect = (_labelWidthMm / _labelHeightMm).clamp(0.4, 3.0);
    const previewWidth = 220.0;
    final previewHeight = (previewWidth / aspect).clamp(70.0, 260.0);
    final footerPreview = _enabledFooterLines;
    const decimal = TextInputType.numberWithOptions(decimal: true);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: 'Print barcode', subtitle: widget.code),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Preview — the label itself stays black on white in every theme.
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
                    child: Column(children: [
                      Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          width: previewWidth,
                          height: previewHeight,
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: p.line),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: p.dark ? 0.3 : 0.06), blurRadius: 6, offset: const Offset(0, 2))],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if ((widget.title ?? '').isNotEmpty)
                                Text(widget.title!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Expanded(
                                child: BarcodeWidget(
                                  barcode: Barcode.code128(),
                                  data: widget.code,
                                  drawText: _showBarcodeText,
                                  style: const TextStyle(fontSize: 10, color: Colors.black87),
                                  errorBuilder: (context, error) => const Center(child: Icon(Icons.qr_code_2_outlined, color: Colors.black38, size: 32)),
                                ),
                              ),
                              for (final line in footerPreview)
                                Text(line, style: const TextStyle(fontSize: 10, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Preview shaped to your label size, not exact print scale', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: p.label)),
                    ]),
                  ),
                  const SectionHeader('Included on label'),
                  _card(p, [
                    for (final entry in widget.infoLines.entries)
                      SwitchRow(
                        title: entry.key,
                        subtitle: entry.value,
                        value: _infoEnabled[entry.key] ?? true,
                        onChanged: (v) => setState(() => _infoEnabled[entry.key] = v),
                      ),
                    SwitchRow(
                      title: 'Show barcode number',
                      subtitle: 'Prints the code under the bars',
                      value: _showBarcodeText,
                      onChanged: _setShowBarcodeText,
                    ),
                  ]),
                  const SectionHeader('Label size'),
                  _card(p, [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: FieldBlock(
                          label: 'Width (mm)',
                          child: TextField(
                            controller: _labelWidthController,
                            keyboardType: decimal,
                            style: TextStyle(fontSize: 14, color: p.text),
                            decoration: marketInput(context, hint: 'Width', prefixIcon: Icon(Icons.swap_horiz, size: 18, color: p.label)),
                            onChanged: _setLabelWidthMm,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FieldBlock(
                          label: 'Height (mm)',
                          child: TextField(
                            controller: _labelHeightController,
                            keyboardType: decimal,
                            style: TextStyle(fontSize: 14, color: p.text),
                            decoration: marketInput(context, hint: 'Height', prefixIcon: Icon(Icons.swap_vert, size: 18, color: p.label)),
                            onChanged: _setLabelHeightMm,
                          ),
                        ),
                      ),
                    ]),
                  ]),
                  const SectionHeader('Print settings'),
                  _card(p, [
                    _stepperRow(
                      p,
                      title: 'Copies',
                      value: _copies,
                      onMinus: _copies > 1 ? () => setState(() => _copies--) : null,
                      onPlus: _copies < 20 ? () => setState(() => _copies++) : null,
                    ),
                    _stepperRow(
                      p,
                      title: 'Bar height',
                      subtitle: 'Dots',
                      value: _barHeight,
                      onMinus: _barHeight > 40 ? () => _setBarHeight(_barHeight - 10) : null,
                      onPlus: _barHeight < 250 ? () => _setBarHeight(_barHeight + 10) : null,
                    ),
                    _stepperRow(
                      p,
                      title: 'Bar width',
                      subtitle: 'Module',
                      value: _barWidth,
                      onMinus: _barWidth > 2 ? () => _setBarWidth(_barWidth - 1) : null,
                      onPlus: _barWidth < 6 ? () => _setBarWidth(_barWidth + 1) : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(onPressed: _fitToLabel, icon: const Icon(Icons.auto_fix_high, size: 16), label: const Text('Fit bar height to label')),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: _printing ? null : _print,
                  icon: _printing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.print_outlined),
                  label: Text(_printing ? 'Printing…' : (_copies > 1 ? 'Print $_copies labels' : 'Print')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(MarketPalette p, List<Widget> children) => MarketCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _stepperRow(MarketPalette p, {required String title, String? subtitle, required int value, VoidCallback? onMinus, VoidCallback? onPlus}) {
    Widget btn(IconData icon, VoidCallback? on) => IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: on,
          icon: Icon(icon, size: 18, color: on == null ? p.line : p.brand),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
            if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 11.5, color: p.label)),
          ]),
        ),
        Container(
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            btn(Icons.remove, onMinus),
            SizedBox(
              width: 40,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: Text('$value', key: ValueKey(value), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
              ),
            ),
            btn(Icons.add, onPlus),
          ]),
        ),
      ]),
    );
  }
}
