import 'package:flutter/material.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/label_model.dart';
import '../../data/label_templates.dart';
import 'lab_widgets.dart';

/// Template gallery — built-in starters and the user's saved templates with
/// live thumbnails. Pops with the chosen design (a fresh copy) and whether
/// it is a user template (so the designer saves back to it).
class TemplateGalleryPage extends StatefulWidget {
  final String company;
  const TemplateGalleryPage({super.key, this.company = ''});

  @override
  State<TemplateGalleryPage> createState() => _TemplateGalleryPageState();
}

class _TemplateGalleryPageState extends State<TemplateGalleryPage> {
  final _builtIns = builtInLabelTemplates();
  List<LabelDesign> _mine = [];
  String? _defaultId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Future.wait([LabelTemplateStore.loadUser(), LabelTemplateStore.getDefaultId()]);
    if (!mounted) return;
    setState(() {
      _mine = res[0] as List<LabelDesign>;
      _defaultId = res[1] as String?;
      _loading = false;
    });
  }

  void _use(LabelDesign t) => Navigator.pop(context, (design: t.clone(), userTemplate: !isBuiltInTemplate(t.id)));

  Future<void> _menu(LabelDesign t) async {
    final builtIn = isBuiltInTemplate(t.id);
    final key = await showActionSheet(context, title: t.name, actions: [
      (key: 'use', label: 'Use this template', icon: Icons.check_circle_outline, destructive: false),
      if (!builtIn) (key: 'rename', label: 'Rename', icon: Icons.drive_file_rename_outline, destructive: false),
      (key: 'duplicate', label: builtIn ? 'Copy to my templates' : 'Duplicate', icon: Icons.copy_all_outlined, destructive: false),
      if (_defaultId != t.id) (key: 'default', label: 'Set as default', icon: Icons.star_outline_rounded, destructive: false),
      if (_defaultId == t.id) (key: 'undefault', label: 'Remove as default', icon: Icons.star_rounded, destructive: false),
      if (!builtIn) (key: 'delete', label: 'Delete', icon: Icons.delete_outline, destructive: true),
    ]);
    if (!mounted || key == null) return;
    switch (key) {
      case 'use':
        _use(t);
      case 'rename':
        final name = await promptLabelName(context, title: 'Rename template', initial: t.name);
        if (name == null) return;
        t.name = name;
        await LabelTemplateStore.upsert(t);
      case 'duplicate':
        final copy = t.clone(newId: true)..name = builtIn ? t.name : '${t.name} copy';
        await LabelTemplateStore.upsert(copy);
        if (mounted) marketToast(context, 'Saved to my templates.');
      case 'default':
        await LabelTemplateStore.setDefaultId(t.id);
      case 'undefault':
        await LabelTemplateStore.setDefaultId(null);
      case 'delete':
        final ok = await confirmMarket(context, title: 'Delete template', message: 'Delete "${t.name}"? This can\'t be undone.');
        if (!ok) return;
        await LabelTemplateStore.delete(t.id);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final sample = sampleLabelData(company: widget.company);
    return MarketScaffold(
      title: 'Templates',
      subtitle: 'Start from a layout or reuse your own',
      body: _loading
          ? const SkeletonList(count: 4, itemHeight: 150)
          : CustomScrollView(slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: SectionHeader('My templates', subtitle: _mine.isEmpty ? 'Save a design from the designer to see it here' : '${_mine.length} saved on this device'),
                ),
              ),
              if (_mine.isNotEmpty) _grid(_mine, sample, 0),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: const SectionHeader('Starters', subtitle: 'Built-in layouts'),
                ),
              ),
              _grid(_builtIns, sample, _mine.length),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ]),
    );
  }

  Widget _grid(List<LabelDesign> list, Map<String, String> sample, int offset) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.86),
          delegate: SliverChildBuilderDelegate(
            (context, i) => FadeSlideIn(index: offset + i, child: _TemplateCard(design: list[i], data: sample, isDefault: _defaultId == list[i].id, onTap: () => _use(list[i]), onMenu: () => _menu(list[i]))),
            childCount: list.length,
          ),
        ),
      );
}

class _TemplateCard extends StatelessWidget {
  final LabelDesign design;
  final Map<String, String> data;
  final bool isDefault;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  const _TemplateCard({required this.design, required this.data, required this.isDefault, required this.onTap, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8)),
            child: LabelThumb(design: design, data: data, maxHeight: 96),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 2, 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(design.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text)),
                const SizedBox(height: 2),
                Row(children: [
                  Flexible(child: Text(design.sizeLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label))),
                  if (isDefault) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.star_rounded, size: 14, color: p.warn),
                  ],
                ]),
              ]),
            ),
            IconButton(visualDensity: VisualDensity.compact, onPressed: onMenu, icon: Icon(Icons.more_vert_rounded, size: 20, color: p.label)),
          ]),
        ),
      ]),
    );
  }
}
