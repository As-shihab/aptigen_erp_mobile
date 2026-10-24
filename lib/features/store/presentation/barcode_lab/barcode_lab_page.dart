import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/storage/app_storage.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../../../shared/widgets/media_library_dialog.dart';
import '../../data/label_model.dart';
import '../../data/label_render.dart';
import '../../data/label_templates.dart';
import '../../data/store_product_model.dart';
import 'data_source_sheet.dart';
import 'element_panel.dart';
import 'label_canvas.dart';
import 'label_print_page.dart';
import 'label_settings_sheet.dart';
import 'lab_widgets.dart';
import 'template_gallery_page.dart';

/// Barcode lab — a label designer. Lay out barcodes, 2D codes, text with
/// merge fields, prices, images, shapes and date stamps on a label of any
/// size, fill it from products (or a batch of products), save templates,
/// and print it as an exact monochrome image (Bluetooth thermal, system
/// print or PDF). Mirrors desktop's packaging "Lab" but as a full designer.
class BarcodeLabPage extends StatefulWidget {
  /// Prefills `{barcode}` (e.g. opened from a packaging's print sheet).
  final String? initialCode;

  /// Prefills the data source with this product.
  final StoreProduct? initialProduct;

  /// Extra merge-field values (`name`, `price`, `unit`, ...).
  final Map<String, String>? initialFields;

  const BarcodeLabPage({super.key, this.initialCode, this.initialProduct, this.initialFields});

  @override
  State<BarcodeLabPage> createState() => _BarcodeLabPageState();
}

class _BarcodeLabPageState extends State<BarcodeLabPage> {
  LabelDesign? _design;
  String? _templateId; // user template being edited, if any
  final List<String> _history = [];
  int _hIndex = -1;
  Timer? _debounce;
  Timer? _draftTimer;
  bool _dirty = false;

  String? _selectedId;
  bool _showGrid = true;
  bool _snap = true;
  double _gridMm = 1;

  final _source = LabDataSource();
  String _company = '';

  static const _panelInitial = 0.46;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _draftTimer?.cancel();
    final d = _design;
    if (d != null) LabelTemplateStore.saveDraft(d, _templateId);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final user = await AppStorage.getUser();
      final wp = (user?['selectedWorkplace'] ?? user?['workplace']);
      if (wp is Map) _company = (wp['name'] ?? '').toString();
    } catch (_) {}

    final prefilled = widget.initialCode != null || widget.initialProduct != null || (widget.initialFields?.isNotEmpty ?? false);
    LabelDesign design;
    String? templateId;
    if (prefilled) {
      design = await LabelTemplateStore.loadDefault();
      templateId = isBuiltInTemplate(design.id) ? null : design.id;
      if (widget.initialProduct != null) {
        _source
          ..mode = LabDataMode.product
          ..product = widget.initialProduct;
      }
      widget.initialFields?.forEach((k, v) {
        if (v.trim().isNotEmpty) _source.manual[k] = v;
      });
      if ((widget.initialCode ?? '').isNotEmpty) _source.manual['barcode'] = widget.initialCode!;
    } else {
      final draft = await LabelTemplateStore.loadDraft();
      if (draft != null) {
        design = draft.design;
        templateId = draft.templateId;
      } else {
        design = await LabelTemplateStore.loadDefault();
        templateId = isBuiltInTemplate(design.id) ? null : design.id;
      }
    }
    if (isBuiltInTemplate(design.id)) design.id = newLabelId();
    if (!mounted) return;
    setState(() {
      _design = design;
      _templateId = templateId;
      _history
        ..clear()
        ..add(jsonEncode(design.toJson()));
      _hIndex = 0;
    });
  }

  LabelDesign get d => _design!;
  LabelElement? get _selected => _design?.byId(_selectedId);
  Map<String, String> get _data => _source.previewData(_company);

  // ── History ───────────────────────────────────────────────────────────

  void _commit() {
    _debounce?.cancel();
    _debounce = null;
    final snap = jsonEncode(d.toJson());
    if (_hIndex >= 0 && _history[_hIndex] == snap) return;
    if (_hIndex < _history.length - 1) _history.removeRange(_hIndex + 1, _history.length);
    _history.add(snap);
    if (_history.length > 80) _history.removeAt(0);
    _hIndex = _history.length - 1;
    _dirty = true;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 700), () => LabelTemplateStore.saveDraft(d, _templateId));
    if (mounted) setState(() {});
  }

  void _edit(VoidCallback mutate, {bool debounce = false}) {
    mutate();
    setState(() {});
    if (debounce) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 450), _commit);
    } else {
      _commit();
    }
  }

  void _restore(int index) {
    _hIndex = index;
    final next = LabelDesign.fromJson(jsonDecode(_history[index]) as Map);
    setState(() {
      _design = next;
      if (next.byId(_selectedId) == null) _selectedId = null;
      _dirty = true;
    });
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 700), () => LabelTemplateStore.saveDraft(d, _templateId));
  }

  void _undo() {
    if (_debounce != null) _commit();
    if (_hIndex > 0) _restore(_hIndex - 1);
  }

  void _redo() {
    if (_hIndex < _history.length - 1) _restore(_hIndex + 1);
  }

  void _resetHistory() {
    _history
      ..clear()
      ..add(jsonEncode(d.toJson()));
    _hIndex = 0;
  }

  // ── Element actions ───────────────────────────────────────────────────

  void _add(LabelElementType type) {
    final e = LabelElement.create(type, d.widthMm, d.heightMm);
    if (type == LabelElementType.text && d.elements.any((x) => x.type == LabelElementType.text && x.content == '{name}')) e.content = 'Text';
    _edit(() => d.elements.add(e));
    setState(() => _selectedId = e.id);
  }

  void _action(String key) {
    final e = _selected;
    if (e == null) return;
    final list = d.elements;
    final i = list.indexOf(e);
    switch (key) {
      case 'duplicate':
        final c = e.clone(newId: true)
          ..x = e.x + 2
          ..y = e.y + 2
          ..locked = false;
        _edit(() => list.insert(i + 1, c));
        setState(() => _selectedId = c.id);
      case 'delete':
        _edit(() => list.removeAt(i));
        setState(() => _selectedId = null);
      case 'forward':
        if (i < list.length - 1) {
          _edit(() {
            list.removeAt(i);
            list.insert(i + 1, e);
          });
        } else {
          marketToast(context, 'Already in front.');
        }
      case 'backward':
        if (i > 0) {
          _edit(() {
            list.removeAt(i);
            list.insert(i - 1, e);
          });
        } else {
          marketToast(context, 'Already at the back.');
        }
      case 'lock':
        _edit(() => e.locked = !e.locked);
      case 'rotate':
        _edit(() {
          final cx = e.cx, cy = e.cy;
          // A line just flips direction; everything else rotates its content.
          if (e.type == LabelElementType.line) {
            e.vertical = !e.vertical;
          } else {
            e.rotation = (e.rotation + 90) % 360;
          }
          final w = e.w;
          e
            ..w = e.h
            ..h = w
            ..x = cx - e.h / 2
            ..y = cy - w / 2;
        });
      case 'align_left':
        _edit(() => e.x = 0);
      case 'align_hcenter':
        _edit(() => e.x = (d.widthMm - e.w) / 2);
      case 'align_right':
        _edit(() => e.x = d.widthMm - e.w);
      case 'align_top':
        _edit(() => e.y = 0);
      case 'align_vcenter':
        _edit(() => e.y = (d.heightMm - e.h) / 2);
      case 'align_bottom':
        _edit(() => e.y = d.heightMm - e.h);
    }
  }

  Future<void> _pickImage(String source) async {
    final e = _selected;
    if (e == null) return;
    if (source == 'clear') {
      _edit(() => e.imageB64 = null);
      return;
    }
    try {
      Uint8List? bytes;
      if (source == 'media') {
        final items = await showMediaLibraryDialog(context, title: 'Choose image');
        final item = items?.firstOrNull;
        if (item == null) return;
        final url = item.fileUrl.isNotEmpty ? item.fileUrl : item.previewUrl;
        final data = await NetworkAssetBundle(Uri.parse(url)).load(url);
        bytes = await _shrink(data.buffer.asUint8List());
      } else {
        final file = await ImagePicker().pickImage(
          source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 1000,
          maxHeight: 1000,
          imageQuality: 88,
        );
        if (file == null) return;
        bytes = await file.readAsBytes();
      }
      final b64 = base64Encode(bytes);
      _edit(() => e.imageB64 = b64);
    } catch (_) {
      if (mounted) marketToast(context, 'Could not load that image.', error: true);
    }
  }

  /// Keeps templates small — large library images are re-encoded at 800 px.
  Future<Uint8List> _shrink(Uint8List bytes) async {
    if (bytes.length < 400 * 1024) return bytes;
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 800);
    final frame = await codec.getNextFrame();
    final png = await imageToPng(frame.image);
    frame.image.dispose();
    return png.length < bytes.length ? png : bytes;
  }

  // ── Sheets / pages ────────────────────────────────────────────────────

  Future<void> _openSettings() => showLabelSettingsSheet(
        context,
        design: d,
        onEdit: _edit,
        gridMm: _gridMm,
        onGridMm: (v) => setState(() => _gridMm = v),
      );

  Future<void> _openData() => showDataSourceSheet(context, source: _source, usedFields: d.usedFields(), onChanged: () => setState(() {}));

  Future<void> _openTemplates() async {
    final res = await Navigator.of(context).push<({LabelDesign design, bool userTemplate})>(motionRoute(TemplateGalleryPage(company: _company)));
    if (res == null || !mounted) return;
    final next = res.design;
    if (!res.userTemplate) next.id = newLabelId();
    setState(() {
      _design = next;
      _templateId = res.userTemplate ? next.id : null;
      _selectedId = null;
      _dirty = false;
      _resetHistory();
    });
    LabelTemplateStore.saveDraft(next, _templateId);
  }

  Future<void> _save({bool asNew = false}) async {
    if (_debounce != null) _commit();
    if (_templateId == null || asNew) {
      final name = await promptLabelName(context, title: asNew ? 'Save as new template' : 'Save template', initial: asNew ? '${d.name} copy' : d.name);
      if (name == null) return;
      final copy = d.clone(newId: true)..name = name;
      await LabelTemplateStore.upsert(copy);
      setState(() {
        d
          ..id = copy.id
          ..name = name;
        _templateId = copy.id;
        _dirty = false;
      });
    } else {
      await LabelTemplateStore.upsert(d);
      setState(() => _dirty = false);
    }
    LabelTemplateStore.saveDraft(d, _templateId);
    if (mounted) marketToast(context, 'Template saved.');
  }

  Future<void> _more() async {
    final key = await showActionSheet(context, title: d.name, actions: [
      (key: 'templates', label: 'Templates', icon: Icons.dashboard_customize_outlined, destructive: false),
      (key: 'save', label: _templateId == null ? 'Save as template' : 'Save template', icon: Icons.save_outlined, destructive: false),
      if (_templateId != null) (key: 'saveas', label: 'Save as new template', icon: Icons.save_as_outlined, destructive: false),
      (key: 'settings', label: 'Label settings', icon: Icons.straighten_outlined, destructive: false),
      (key: 'data', label: 'Data source', icon: Icons.dataset_outlined, destructive: false),
      (key: 'blank', label: 'New blank label', icon: Icons.note_add_outlined, destructive: false),
      (key: 'clear', label: 'Clear all elements', icon: Icons.layers_clear_outlined, destructive: true),
    ]);
    if (!mounted || key == null) return;
    switch (key) {
      case 'templates':
        await _openTemplates();
      case 'save':
        await _save();
      case 'saveas':
        await _save(asNew: true);
      case 'settings':
        await _openSettings();
      case 'data':
        await _openData();
      case 'blank':
        setState(() {
          _design = LabelDesign(id: newLabelId(), presetId: d.presetId, widthMm: d.widthMm, heightMm: d.heightMm, dpi: d.dpi, gapMm: d.gapMm);
          _templateId = null;
          _selectedId = null;
          _resetHistory();
        });
        LabelTemplateStore.saveDraft(d, null);
      case 'clear':
        final ok = await confirmMarket(context, title: 'Clear label', message: 'Remove every element from this label? You can undo this.', confirm: 'Clear');
        if (!ok) return;
        _edit(() => d.elements.clear());
        setState(() => _selectedId = null);
    }
  }

  Future<void> _print() async {
    if (_debounce != null) _commit();
    final jobs = _source.jobs(_company, 1);
    if (jobs.isEmpty) {
      marketToast(context, 'Add at least one product with copies.', error: true);
      return;
    }
    if (d.elements.isEmpty) {
      marketToast(context, 'The label is empty — add an element first.', error: true);
      return;
    }
    final bad = jobs.where((j) => d.elements.any((e) => e.codeError(j.data) != null)).length;
    if (bad > 0 && _source.hasAny) {
      final ok = await confirmMarket(
        context,
        title: 'Invalid code data',
        message: bad == 1 && jobs.length == 1 ? 'A barcode on this label can\'t be encoded and will print blank. Print anyway?' : '$bad of ${jobs.length} labels have code data that can\'t be encoded; those codes print blank. Print anyway?',
        confirm: 'Print anyway',
        destructive: false,
      );
      if (!ok || !mounted) return;
    }
    await Navigator.of(context).push(motionRoute<void>(LabelPrintPage(
      design: d.clone(),
      jobs: jobs,
      batch: _source.mode == LabDataMode.batch && _source.batch.isNotEmpty,
      hasDataSource: _source.hasAny,
    )));
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final design = _design;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: p.line)),
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Barcode lab', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
          if (design != null)
            Row(children: [
              Flexible(child: Text(design.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label))),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _dirty && _templateId != null ? 1 : 0,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Container(width: 6, height: 6, decoration: BoxDecoration(color: p.warn, shape: BoxShape.circle)),
                ),
              ),
            ]),
        ]),
        actions: [
          IconButton(tooltip: 'Undo', onPressed: _hIndex > 0 || _debounce != null ? _undo : null, icon: const Icon(Icons.undo_rounded)),
          IconButton(tooltip: 'Redo', onPressed: _hIndex < _history.length - 1 ? _redo : null, icon: const Icon(Icons.redo_rounded)),
          IconButton(tooltip: 'More', onPressed: design == null ? null : _more, icon: const Icon(Icons.more_vert_rounded)),
        ],
      ),
      bottomNavigationBar: design == null ? null : _bottomBar(p),
      body: design == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              _topStrip(p),
              Expanded(
                child: LayoutBuilder(builder: (context, cons) {
                  final sel = _selected;
                  return Stack(children: [
                    Positioned.fill(
                      child: LabelCanvas(
                        design: design,
                        data: _data,
                        selectedId: _selectedId,
                        showGrid: _showGrid,
                        snap: _snap,
                        gridMm: _gridMm,
                        bottomInset: sel == null ? 0 : cons.maxHeight * _panelInitial,
                        onSelect: (id) => setState(() => _selectedId = id),
                        onLiveChange: () => setState(() {}),
                        onCommit: _commit,
                      ),
                    ),
                    Positioned.fill(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, a) => SlideTransition(
                          position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
                          child: FadeTransition(opacity: a, child: child),
                        ),
                        child: sel == null
                            ? const SizedBox.shrink(key: ValueKey('no-panel'))
                            : DraggableScrollableSheet(
                                key: const ValueKey('panel'),
                                initialChildSize: _panelInitial,
                                minChildSize: 0.18,
                                maxChildSize: 0.94,
                                snap: true,
                                snapSizes: const [_panelInitial],
                                builder: (context, sc) => Container(
                                  decoration: BoxDecoration(
                                    color: p.bg,
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                                    border: Border(top: BorderSide(color: p.line)),
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: p.dark ? 0.4 : 0.08), blurRadius: 16, offset: const Offset(0, -4))],
                                  ),
                                  child: ElementPanel(
                                    element: sel,
                                    design: design,
                                    data: _data,
                                    scrollController: sc,
                                    onEdit: _edit,
                                    onAction: _action,
                                    onPickImage: _pickImage,
                                    onClose: () => setState(() => _selectedId = null),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ]);
                }),
              ),
            ]),
    );
  }

  Widget _topStrip(MarketPalette p) => Container(
        height: 50,
        decoration: BoxDecoration(color: p.card, border: Border(bottom: BorderSide(color: p.line))),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            LabChip(icon: Icons.straighten_outlined, label: '${d.sizeLabel} · ${d.dpi} dpi', onTap: _openSettings),
            const SizedBox(width: 8),
            LabChip(icon: Icons.dataset_outlined, label: _source.summary, active: _source.hasAny, onTap: _openData),
            const SizedBox(width: 8),
            LabChip(icon: Icons.grid_4x4_rounded, label: 'Grid', active: _showGrid, onTap: () => setState(() => _showGrid = !_showGrid)),
            const SizedBox(width: 8),
            LabChip(icon: Icons.near_me_outlined, label: 'Snap', active: _snap, onTap: () => setState(() => _snap = !_snap)),
            const SizedBox(width: 8),
            LabChip(icon: Icons.dashboard_customize_outlined, label: 'Templates', onTap: _openTemplates),
          ],
        ),
      );

  Widget _bottomBar(MarketPalette p) {
    final tools = [
      (LabelElementType.barcode, 'Barcode'),
      (LabelElementType.qr, 'QR code'),
      (LabelElementType.text, 'Text'),
      (LabelElementType.price, 'Price'),
      (LabelElementType.image, 'Image'),
      (LabelElementType.line, 'Line'),
      (LabelElementType.rect, 'Box'),
      (LabelElementType.ellipse, 'Ellipse'),
      (LabelElementType.date, 'Date'),
    ];
    final total = _source.jobs(_company, 1).fold<int>(0, (a, j) => a + j.copies);
    final batch = _source.mode == LabDataMode.batch && _source.batch.isNotEmpty;
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: _selectedId != null
          ? const SizedBox(width: double.infinity)
          : Container(
              decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
              child: SafeArea(
                top: false,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    height: 64,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      children: [
                        for (var i = 0; i < tools.length; i++)
                          FadeSlideIn(index: i, offsetY: 6, child: LabTool(icon: labelElementIcon(tools[i].$1), label: tools[i].$2, onTap: () => _add(tools[i].$1))),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                    child: GradientButton(
                      label: batch ? 'Print $total labels' : 'Print',
                      icon: Icons.print_outlined,
                      onTap: _print,
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}
