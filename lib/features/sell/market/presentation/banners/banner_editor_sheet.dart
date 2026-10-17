import 'package:flutter/material.dart';
import '../../data/market_seller_service.dart';
import '../widgets/market_ui.dart';
import 'banner_meta.dart';
import 'form_kit.dart';
import 'market_media.dart';

/// Opens the banner editor; resolves true when saved.
Future<bool> showBannerEditor(
  BuildContext context,
  MarketSellerService service, {
  Map<String, dynamic>? row,
  String placement = 'hero',
  int? creatorProfileId,
}) async {
  final saved = await showMarketSheet<bool>(
    context,
    builder: (_) => BannerEditorSheet(service: service, row: row, initialPlacement: placement, creatorProfileId: creatorProfileId),
  );
  return saved == true;
}

class BannerEditorSheet extends StatefulWidget {
  final MarketSellerService service;
  final Map<String, dynamic>? row;
  final String initialPlacement;
  final int? creatorProfileId;
  const BannerEditorSheet({super.key, required this.service, this.row, this.initialPlacement = 'hero', this.creatorProfileId});

  @override
  State<BannerEditorSheet> createState() => _BannerEditorSheetState();
}

class _BannerEditorSheetState extends State<BannerEditorSheet> {
  Map<String, dynamic> get _r => widget.row ?? const {};
  String _v(String k) => (_r[k] ?? '').toString();

  late String _placement = _r['placement']?.toString() ?? widget.initialPlacement;
  late final _title = TextEditingController(text: _v('title'));
  late final _subtitle = TextEditingController(text: _v('subtitle'));
  late final _cta = TextEditingController(text: _v('cta_label'));
  late final _link = TextEditingController(text: _v('link_url'));
  late String? _image = orNull(_v('image_url'));
  late String? _mobileImage = orNull(_v('mobile_image_url'));
  late String? _tone = orNull(_v('tone'));
  late int _sort = toInt(_r['sort_order']);
  late DateTime? _start = parseDate(_r['starts_at']);
  late DateTime? _end = parseDate(_r['ends_at']);
  late bool _active = widget.row == null ? true : _r['is_active'] == true;
  bool _saving = false;
  int _uploads = 0;

  bool get _isEdit => _r['id'] != null;

  @override
  void dispose() {
    for (final c in [_title, _subtitle, _cta, _link]) {
      c.dispose();
    }
    super.dispose();
  }

  void _busy(bool b) {
    if (mounted) setState(() => _uploads = (_uploads + (b ? 1 : -1)).clamp(0, 9));
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      marketToast(context, 'Title is required', error: true);
      return;
    }
    if (_start != null && _end != null && !_end!.isAfter(_start!)) {
      marketToast(context, 'End must be after the start', error: true);
      return;
    }
    if (!_isEdit && widget.creatorProfileId == null) {
      marketToast(context, "Couldn't set up your store profile, try again", error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final body = bannerBody({
        'placement': _placement,
        'title': _title.text,
        'subtitle': _subtitle.text,
        'cta_label': _cta.text,
        'link_url': _link.text,
        'image_url': _image,
        'mobile_image_url': _mobileImage,
        'tone': _tone,
        'sort_order': _sort,
        'is_active': _active,
        'starts_at': _start,
        'ends_at': _end,
      });
      if (_isEdit) {
        await widget.service.saveBanner(body, id: toInt(_r['id']));
      } else {
        await widget.service.saveBanner({...body, 'creator_profile_id': widget.creatorProfileId});
      }
      if (!mounted) return;
      marketToast(context, _isEdit ? 'Banner updated, sent for approval' : 'Banner created, sent for approval');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      marketToast(context, errorText(e, 'Could not save the banner'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final pl = bannerPlacement(_placement);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SheetHeader(title: _isEdit ? 'Edit banner' : 'New banner', subtitle: pl.desc),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: p.warnBg, borderRadius: BorderRadius.circular(10)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.verified_user_outlined, size: 17, color: p.warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Saved changes go to platform approval before the banner shows on the market.',
                        style: TextStyle(fontSize: 12, color: p.text, height: 1.35)),
                  ),
                ]),
              ),
              FieldBlock(
                label: 'Placement',
                required: true,
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final o in bannerPlacements)
                    OptionChip(label: o.label, icon: o.icon, selected: o.id == _placement, onTap: () => setState(() => _placement = o.id)),
                ]),
              ),
              FieldBlock(label: 'Title', required: true, child: MarketTextField(controller: _title, hint: 'e.g. Winter sale')),
              FieldBlock(label: 'Subtitle', child: MarketTextField(controller: _subtitle, maxLines: 3, hint: 'A short supporting line')),
              FieldBlock(
                label: 'Button label',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  MarketTextField(controller: _cta, hint: 'Shop now', onChanged: (_) => setState(() {})),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: bannerCtaLabels.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => OptionChip(
                        label: bannerCtaLabels[i],
                        selected: _cta.text.trim() == bannerCtaLabels[i],
                        onTap: () => setState(() => _cta.text = bannerCtaLabels[i]),
                      ),
                    ),
                  ),
                ]),
              ),
              FieldBlock(
                label: 'Link URL',
                help: 'Where the banner goes when tapped, e.g. a listing or category page.',
                child: MarketTextField(controller: _link, hint: 'https://', keyboardType: TextInputType.url, capitalization: TextCapitalization.none),
              ),
              FieldBlock(
                label: 'Image',
                help: _placement == 'hero' ? 'Wide 16:9 image works best.' : null,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  child: MediaPickTile(
                    service: widget.service,
                    url: _image,
                    aspectRatio: pl.aspect,
                    onBusy: _busy,
                    onChanged: (u) => setState(() => _image = u),
                  ),
                ),
              ),
              FieldBlock(
                label: 'Mobile image',
                help: 'Optional, shown on phones instead of the main image.',
                child: FractionallySizedBox(
                  widthFactor: 0.6,
                  alignment: Alignment.centerLeft,
                  child: MediaPickTile(
                    service: widget.service,
                    url: _mobileImage,
                    aspectRatio: 4 / 5,
                    emptyLabel: 'Add mobile image',
                    onBusy: _busy,
                    onChanged: (u) => setState(() => _mobileImage = u),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                alignment: Alignment.topCenter,
                child: _placement == 'promo_card'
                    ? FieldBlock(
                        label: 'Tone',
                        help: 'Background colour used when the card has no image.',
                        child: Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final t in bannerTones)
                            OptionChip(
                              label: sentence(t),
                              dot: bannerTone(context, t).fg,
                              selected: _tone == t,
                              onTap: () => setState(() => _tone = _tone == t ? null : t),
                            ),
                        ]),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              FieldBlock(
                label: 'Sort order',
                child: Row(children: [
                  StepperField(value: _sort, onChanged: (v) => setState(() => _sort = v)),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Lower numbers show first.', style: TextStyle(fontSize: 12, color: p.label))),
                ]),
              ),
              FieldBlock(label: 'Starts', child: DateTimeField(value: _start, hint: 'Right away', onChanged: (v) => setState(() => _start = v))),
              FieldBlock(label: 'Ends', child: DateTimeField(value: _end, hint: 'No end date', onChanged: (v) => setState(() => _end = v))),
              SwitchRow(
                title: 'Active',
                subtitle: _active ? 'Shows once approved' : 'Hidden from the market',
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ]),
          ),
        ),
        SheetFooter(
          label: _uploads > 0 ? 'Uploading…' : (_isEdit ? 'Save changes' : 'Create banner'),
          busy: _saving,
          onPressed: _uploads > 0 ? null : _save,
        ),
      ]),
    );
  }
}
