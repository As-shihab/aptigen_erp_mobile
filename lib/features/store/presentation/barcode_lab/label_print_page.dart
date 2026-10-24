import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../../sell/data/pos_printer_service.dart';
import '../../../settings/data/printer_device.dart';
import '../../../settings/data/printer_devices_service.dart';
import '../../../settings/presentation/printers/printers_list_page.dart';
import '../../data/label_model.dart';
import '../../data/label_pdf.dart';
import '../../data/label_print_prefs.dart';
import '../../data/label_raster.dart';
import '../../data/label_render.dart';
import 'lab_widgets.dart';

typedef LabelJob = ({Map<String, String> data, int copies, String title});

/// Print as image: renders each label to a bitmap at the print resolution,
/// converts it to 1-bit monochrome (threshold / dither) and either streams
/// it to a Bluetooth thermal printer as ESC/POS raster, or lays it out as a
/// PDF for the system print dialog / sharing.
class LabelPrintPage extends StatefulWidget {
  final LabelDesign design;
  final List<LabelJob> jobs;
  final bool batch;
  final bool hasDataSource;
  const LabelPrintPage({super.key, required this.design, required this.jobs, this.batch = false, this.hasDataSource = true});

  @override
  State<LabelPrintPage> createState() => _LabelPrintPageState();
}

class _LabelPrintPageState extends State<LabelPrintPage> {
  LabelPrintOptions _o = LabelPrintOptions();
  List<PrinterDevice> _printers = [];
  bool _ready = false;
  ui.Image? _preview;
  MonoBitmap? _previewMono;
  bool _rendering = false;
  int _renderToken = 0;
  bool _busy = false;
  String? _status;
  late int _threshold = _o.threshold;

  LabelDesign get d => widget.design;
  int get _totalLabels => widget.jobs.fold(0, (a, j) => a + (widget.batch ? j.copies : _o.copies));

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final res = await Future.wait([LabelPrintOptions.load(), PrinterDevicesService().loadAll()]);
    if (!mounted) return;
    final o = res[0] as LabelPrintOptions;
    final printers = res[1] as List<PrinterDevice>;
    if (o.printerId == null || !printers.any((pr) => pr.id == o.printerId)) {
      final def = printers.where((pr) => pr.isDefault).firstOrNull ?? printers.firstOrNull;
      o.printerId = def?.id;
      if (def != null) o.paperWidthMm = def.paperWidthMm >= 80 ? 80 : 58;
    }
    setState(() {
      _o = o;
      _threshold = o.threshold;
      _printers = printers;
      _ready = true;
    });
    _renderPreview();
  }

  void _set(VoidCallback fn, {bool rerender = false}) {
    setState(fn);
    _o.save();
    if (rerender) _renderPreview();
  }

  PrinterDevice? get _printer => _printers.where((pr) => pr.id == _o.printerId).firstOrNull;

  int get _paperDots => paperDotsForWidth(_o.paperWidthMm);

  /// Thermal output resolution — the design's dpi, scaled down when the
  /// label is wider than the printer's head.
  double get _thermalDpi {
    final fitDpi = _paperDots / d.widthMm * 25.4;
    return math.min(d.dpi.toDouble(), fitDpi);
  }

  double get _outputDpi => _o.method == LabelPrintMethod.bluetooth ? _thermalDpi : d.dpi.toDouble();

  Future<void> _renderPreview() async {
    if (widget.jobs.isEmpty) return;
    final token = ++_renderToken;
    setState(() => _rendering = true);
    try {
      final img = await renderLabelImage(d, widget.jobs.first.data, dpi: _outputDpi);
      final mono = await imageToMono(img, threshold: _threshold, dither: _o.dither);
      img.dispose();
      final view = await monoToImage(mono);
      if (!mounted || token != _renderToken) {
        view.dispose();
        return;
      }
      setState(() {
        _preview?.dispose();
        _preview = view;
        _previewMono = mono;
        _rendering = false;
      });
    } catch (_) {
      if (mounted && token == _renderToken) setState(() => _rendering = false);
    }
  }

  // ── Output ────────────────────────────────────────────────────────────

  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Preparing';
    });
    try {
      switch (_o.method) {
        case LabelPrintMethod.bluetooth:
          await _printBluetooth();
        case LabelPrintMethod.system:
          final bytes = await _buildPdf();
          await Printing.layoutPdf(
            name: d.name,
            format: _o.pdfLayout == LabelPdfLayout.a4Sheet ? PdfPageFormat.a4 : labelPageFormat(d.widthMm, d.heightMm),
            onLayout: (_) async => bytes,
          );
        case LabelPrintMethod.pdf:
          await _sharePdf();
      }
    } catch (e) {
      if (mounted) marketToast(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _sharePdf() async {
    final bytes = await _buildPdf();
    final safe = d.name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    await Printing.sharePdf(bytes: bytes, filename: '${safe.isEmpty ? 'labels' : safe}.pdf');
  }

  Future<void> _printBluetooth() async {
    final printer = _printer;
    if (printer?.macAddress == null) {
      if (!mounted) return;
      final go = await confirmMarket(context, title: 'No printer configured', message: 'Add a Bluetooth printer in Settings > Printers first.', confirm: 'Open printers', destructive: false);
      if (go && mounted) {
        await Navigator.of(context).push(motionRoute<void>(const PrintersListPage()));
        final printers = await PrinterDevicesService().loadAll();
        if (mounted) setState(() => _printers = printers);
      }
      return;
    }
    final dpi = _thermalDpi;
    final labels = <({MonoBitmap bitmap, int copies})>[];
    for (var i = 0; i < widget.jobs.length; i++) {
      if (mounted) setState(() => _status = 'Rendering ${i + 1} of ${widget.jobs.length}');
      final job = widget.jobs[i];
      final img = await renderLabelImage(d, job.data, dpi: dpi);
      final mono = await imageToMono(img, threshold: _threshold, dither: _o.dither);
      img.dispose();
      labels.add((bitmap: mono, copies: widget.batch ? job.copies : _o.copies));
    }
    final bytes = buildLabelRasterJob(
      labels: labels,
      paperDots: _paperDots,
      feedDots: (_o.feedMm / 25.4 * dpi).round(),
      cut: _o.cut,
      fullCut: printer!.fullCut,
    );
    if (mounted) setState(() => _status = 'Sending to ${printer.name}');
    await PosPrinterService().printBytes(bytes, macAddress: printer.macAddress!);
    if (mounted) marketToast(context, _totalLabels == 1 ? 'Label sent to printer.' : '$_totalLabels labels sent to printer.');
  }

  Future<Uint8List> _buildPdf() async {
    final items = <({Uint8List png, int copies})>[];
    for (var i = 0; i < widget.jobs.length; i++) {
      if (mounted) setState(() => _status = 'Rendering ${i + 1} of ${widget.jobs.length}');
      final job = widget.jobs[i];
      final img = await renderLabelImage(d, job.data);
      Uint8List png;
      if (_o.monochromePdf) {
        final mono = await imageToMono(img, threshold: _threshold, dither: _o.dither);
        final monoImg = await monoToImage(mono);
        png = await imageToPng(monoImg);
        monoImg.dispose();
      } else {
        png = await imageToPng(img);
      }
      img.dispose();
      items.add((png: png, copies: widget.batch ? job.copies : _o.copies));
    }
    if (mounted) setState(() => _status = 'Building PDF');
    return buildLabelPdf(
      labels: items,
      labelWidthMm: d.widthMm,
      labelHeightMm: d.heightMm,
      sheet: _o.pdfLayout == LabelPdfLayout.a4Sheet ? _o.sheet : null,
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final label = switch (_o.method) {
      LabelPrintMethod.bluetooth => _totalLabels == 1 ? 'Print label' : 'Print $_totalLabels labels',
      LabelPrintMethod.system => 'Open print dialog',
      LabelPrintMethod.pdf => 'Share PDF',
    };
    return MarketScaffold(
      title: 'Print labels',
      subtitle: '${d.name} · ${d.sizeLabel}',
      bottom: Container(
        decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: _status == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('$_status…', style: TextStyle(fontSize: 12, color: p.label)),
                      ),
              ),
              Row(children: [
                if (_o.method != LabelPrintMethod.pdf) ...[
                  SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.brand,
                        side: BorderSide(color: p.line),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _busy || !_ready ? null : () => _guard(_sharePdf),
                      child: const Icon(Icons.ios_share_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: GradientButton(
                    label: label,
                    icon: _o.method == LabelPrintMethod.pdf ? Icons.picture_as_pdf_outlined : Icons.print_outlined,
                    busy: _busy,
                    onTap: _ready && widget.jobs.isNotEmpty ? _run : null,
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
      body: !_ready
          ? const SkeletonList(count: 4, itemHeight: 120)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                FadeSlideIn(index: 0, child: _previewCard(p)),
                FadeSlideIn(index: 1, child: _labelsGroup(p)),
                FadeSlideIn(
                  index: 2,
                  child: LabChoice<LabelPrintMethod>(
                    label: 'Print with',
                    value: _o.method,
                    options: const [(LabelPrintMethod.bluetooth, 'Bluetooth printer'), (LabelPrintMethod.system, 'System print'), (LabelPrintMethod.pdf, 'PDF')],
                    onChanged: (v) => _set(() => _o.method = v, rerender: true),
                  ),
                ),
                FadeSlideIn(
                  index: 3,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a), child: child)),
                    child: KeyedSubtree(
                      key: ValueKey(_o.method == LabelPrintMethod.bluetooth),
                      child: _o.method == LabelPrintMethod.bluetooth ? _bluetoothGroup(p) : _pdfGroup(p),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _guard(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) marketToast(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  Widget _previewCard(MarketPalette p) {
    final mono = _previewMono;
    final scaled = _o.method == LabelPrintMethod.bluetooth && _thermalDpi < d.dpi - 0.5;
    return LabGroup(
      title: 'Output preview',
      trailing: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _rendering ? 1 : 0,
        child: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      children: [
        Container(
          height: 210,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _preview == null
                  ? const SizedBox(key: ValueKey('none'), width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : AspectRatio(
                      key: ValueKey(_preview),
                      aspectRatio: _preview!.width / _preview!.height,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: p.dark ? 0.4 : 0.1), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: RawImage(image: _preview, fit: BoxFit.contain, filterQuality: FilterQuality.none),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          mono == null
              ? 'Rendering exact printer output'
              : 'Exact 1-bit output · ${mono.width} × ${mono.height} dots · ${_outputDpi.round()} dpi${scaled ? ' · scaled to fit ${_o.paperWidthMm} mm paper' : ''}',
          style: TextStyle(fontSize: 11.5, color: p.label),
        ),
        const SizedBox(height: 12),
        LabSlider(
          label: 'Darkness threshold',
          value: _threshold.toDouble(),
          min: 40,
          max: 240,
          divisions: 200,
          format: (v) => '${v.round()}',
          onChanged: (v) => setState(() => _threshold = v.round()),
          onChangeEnd: (v) => _set(() => _o.threshold = v.round(), rerender: true),
        ),
        LabSwitch(label: 'Dither', sub: 'Floyd–Steinberg, better for photos and logos', value: _o.dither, onChanged: (v) => _set(() => _o.dither = v, rerender: true)),
      ],
    );
  }

  Widget _labelsGroup(MarketPalette p) {
    final missing = widget.hasDataSource ? const <String>[] : [for (final f in kLabelMergeFields) if (d.usedFields().contains(f.key) && f.key != 'date' && f.key != 'company') f.label];
    return LabGroup(
      title: widget.batch ? 'Batch' : 'Copies',
      trailing: StatusPill('$_totalLabels ${_totalLabels == 1 ? 'label' : 'labels'}', tone: MarketTone.brand),
      children: [
        if (widget.batch)
          for (final j in widget.jobs) InfoRow(j.title, '× ${j.copies}')
        else
          LabRow(label: 'Copies', child: LabStepper(value: _o.copies, min: 1, max: 999, onChanged: (v) => _set(() => _o.copies = v))),
        if (missing.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 10, top: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.warnBg, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(Icons.info_outline, size: 18, color: p.warn),
              const SizedBox(width: 8),
              Expanded(child: Text('No data source chosen — ${missing.join(', ')} print empty.', style: TextStyle(fontSize: 12, color: p.text))),
            ]),
          ),
      ],
    );
  }

  Widget _bluetoothGroup(MarketPalette p) {
    return LabGroup(title: 'Bluetooth thermal printer', children: [
      if (_printers.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Expanded(child: Text('No printers saved yet.', style: TextStyle(fontSize: 12.5, color: p.label))),
            TextButton(
              onPressed: () async {
                await Navigator.of(context).push(motionRoute<void>(const PrintersListPage()));
                final printers = await PrinterDevicesService().loadAll();
                if (!mounted) return;
                setState(() {
                  _printers = printers;
                  _o.printerId ??= printers.where((pr) => pr.isDefault).firstOrNull?.id ?? printers.firstOrNull?.id;
                });
              },
              child: const Text('Add printer'),
            ),
          ]),
        )
      else
        FormLabel(
          label: 'Printer',
          child: PickerField(
            value: _o.printerId,
            allowClear: false,
            icon: Icons.print_outlined,
            options: [for (final pr in _printers) PickOption(pr.id, pr.name, sub: '${pr.paperWidthMm} mm${pr.isDefault ? ' · default' : ''}')],
            onChanged: (v) {
              final pr = _printers.where((x) => x.id == v).firstOrNull;
              _set(() {
                _o.printerId = pr?.id;
                if (pr != null) _o.paperWidthMm = pr.paperWidthMm >= 80 ? 80 : 58;
              }, rerender: true);
            },
          ),
        ),
      LabChoice<int>(
        label: 'Paper width',
        value: _o.paperWidthMm,
        options: const [(58, '58 mm · 384 dots'), (80, '80 mm · 576 dots')],
        onChanged: (v) => _set(() => _o.paperWidthMm = v, rerender: true),
      ),
      LabSlider(
        label: 'Feed after each label',
        value: _o.feedMm,
        min: 0,
        max: 20,
        divisions: 40,
        format: (v) => '${v.toStringAsFixed(1)} mm',
        onChanged: (v) => setState(() => _o.feedMm = v),
        onChangeEnd: (v) => _set(() => _o.feedMm = v),
      ),
      LabChoice<LabelCutMode>(
        label: 'Cut',
        value: _o.cut,
        options: const [(LabelCutMode.none, 'No cut'), (LabelCutMode.each, 'After each'), (LabelCutMode.end, 'At the end')],
        onChanged: (v) => _set(() => _o.cut = v),
      ),
    ]);
  }

  Widget _pdfGroup(MarketPalette p) {
    final fits = _o.sheet.fits(d.widthMm, d.heightMm);
    return LabGroup(title: _o.method == LabelPrintMethod.system ? 'System print' : 'PDF', children: [
      LabChoice<LabelPdfLayout>(
        label: 'Layout',
        value: _o.pdfLayout,
        options: const [(LabelPdfLayout.labelPages, 'Label size pages'), (LabelPdfLayout.a4Sheet, 'A4 sheet')],
        onChanged: (v) => _set(() => _o.pdfLayout = v),
      ),
      LabSwitch(label: 'Monochrome', sub: 'Same 1-bit image as the preview', value: _o.monochromePdf, onChanged: (v) => _set(() => _o.monochromePdf = v)),
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: _o.pdfLayout != LabelPdfLayout.a4Sheet
            ? const SizedBox(width: double.infinity)
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                LabRow(label: 'Columns', child: LabStepper(value: _o.columns, min: 1, max: 20, onChanged: (v) => _set(() => _o.columns = v))),
                LabRow(label: 'Rows', child: LabStepper(value: _o.rows, min: 1, max: 40, onChanged: (v) => _set(() => _o.rows = v))),
                Row(children: [
                  Expanded(child: MmBox(key: const ValueKey('mt'), label: 'Top margin', value: _o.marginTopMm, onChanged: (v) => _set(() => _o.marginTopMm = v.clamp(0, 100).toDouble()))),
                  const SizedBox(width: 8),
                  Expanded(child: MmBox(key: const ValueKey('ml'), label: 'Left margin', value: _o.marginLeftMm, onChanged: (v) => _set(() => _o.marginLeftMm = v.clamp(0, 100).toDouble()))),
                  const SizedBox(width: 8),
                  Expanded(child: MmBox(key: const ValueKey('gx'), label: 'Gap across', value: _o.gapXMm, onChanged: (v) => _set(() => _o.gapXMm = v.clamp(0, 50).toDouble()))),
                  const SizedBox(width: 8),
                  Expanded(child: MmBox(key: const ValueKey('gy'), label: 'Gap down', value: _o.gapYMm, onChanged: (v) => _set(() => _o.gapYMm = v.clamp(0, 50).toDouble()))),
                ]),
                const SizedBox(height: 12),
                LabRow(
                  label: 'Start at position',
                  sub: 'Skip labels already used on the sheet',
                  child: LabStepper(value: _o.startPosition, min: 1, max: _o.columns * _o.rows, onChanged: (v) => _set(() => _o.startPosition = v)),
                ),
                Row(children: [
                  Expanded(
                    child: Text(
                      fits ? '${_o.columns * _o.rows} labels per A4 page' : 'This grid does not fit on A4',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fits ? p.label : p.error),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      final m = A4SheetLayout.maxFit(d.widthMm, d.heightMm, marginTop: _o.marginTopMm, marginLeft: _o.marginLeftMm, gapX: _o.gapXMm, gapY: _o.gapYMm);
                      _set(() {
                        _o.columns = m.columns;
                        _o.rows = m.rows;
                        _o.startPosition = _o.startPosition.clamp(1, m.columns * m.rows);
                      });
                    },
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: const Text('Fit to page'),
                  ),
                ]),
                const SizedBox(height: 6),
              ]),
      ),
    ]);
  }
}
