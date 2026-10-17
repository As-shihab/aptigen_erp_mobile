import 'package:flutter/material.dart';
import '../../../sell/market/presentation/banners/form_kit.dart' show FieldBlock, OptionChip, marketInput;
import '../../../sell/presentation/widgets/sell_ui.dart' show dayLabel, parseLocal;
import '../../data/document_models.dart';
import '../widgets/store_ui.dart';

// Shared look for the Store document screens (MRR, MRR return, return, SR,
// SPR, PO): one list scaffold with KPIs, search, a status filter, day groups
// and skeletons, plus the form building blocks (section cards, dropdowns,
// status chips, a read-only field and a sticky save bar). Same SAP Horizon
// kit as Sales — every colour comes from [MarketPalette].

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "12 Oct" (this year) or "12 Oct 2025".
String docShortDate(DateTime d) => d.year == DateTime.now().year ? '${d.day} ${_months[d.month - 1]}' : '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Store status tone, plus MRR return's SHIPPED (done = positive).
MarketTone docStatusTone(String status) => status == 'SHIPPED' ? MarketTone.ok : storeStatusTone(status);

/// SPR status → label. PENDING reads "Pending approval" (matches desktop's
/// `SPR_STATUS_LABEL`), the rest use the shared store labels.
String sprStatusLabel(String status) => status == 'PENDING' ? 'Pending approval' : storeStatusLabel(status);

String _qty(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

/// "3 items · 12 units" for a set of document lines.
String docLineSummary(List<DocumentLine> lines) {
  if (lines.isEmpty) return 'No items yet';
  final units = lines.fold<double>(0, (s, l) => s + l.quantity);
  return '${lines.length} item${lines.length == 1 ? '' : 's'} · ${_qty(units)} unit${units == 1 ? '' : 's'}';
}

// ── List ────────────────────────────────────────────────────────────────

/// What a list row shows for one document.
class DocListItem {
  final String number;
  final String? date; // ISO string from the API, used for day groups
  final List<String?> meta; // warehouse, supplier, purpose … (blank ones skipped)
  final int? itemCount;
  final String status;
  final (String, MarketTone)? extraPill; // e.g. SPR approval progress
  const DocListItem({required this.number, this.date, this.meta = const [], this.itemCount, required this.status, this.extraPill});
}

/// KPI tile over the loaded rows: counts rows whose status is in [statuses]
/// (all rows when null). Tapping it applies that status as the filter.
class DocKpi {
  final IconData icon;
  final String label;
  final MarketTone tone;
  final Set<String>? statuses;
  const DocKpi({required this.icon, required this.label, this.tone = MarketTone.brand, this.statuses});
}

/// Generic Store document list. [onOpen] / [onCreate] resolve true when
/// something was saved, which reloads the list.
class StoreDocList<T> extends StatefulWidget {
  final String title;
  final IconData icon;
  final Future<List<T>> Function() load;
  final DocListItem Function(T row) describe;
  final List<String> statuses; // filter options; empty hides the filter
  final String Function(String status)? statusLabel;
  final List<DocKpi> kpis;
  final String emptyTitle;
  final String emptyMessage;
  final String searchHint;
  final String? createLabel;
  final Future<bool> Function()? onCreate;
  final Future<bool> Function(T row)? onOpen;
  final Widget Function(T row)? trailing;

  const StoreDocList({
    super.key,
    required this.title,
    required this.icon,
    required this.load,
    required this.describe,
    this.statuses = const [],
    this.statusLabel,
    this.kpis = const [],
    required this.emptyTitle,
    required this.emptyMessage,
    this.searchHint = 'Search number, warehouse or supplier',
    this.createLabel,
    this.onCreate,
    this.onOpen,
    this.trailing,
  });

  @override
  State<StoreDocList<T>> createState() => _StoreDocListState<T>();
}

class _StoreDocListState<T> extends State<StoreDocList<T>> {
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<T> _rows = [];
  String _status = 'ALL';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.load();
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (_) {
      if (!mounted) return;
      if (_rows.isEmpty) {
        setState(() => _error = 'Could not load ${widget.title.toLowerCase()}.');
      } else {
        marketToast(context, 'Could not refresh the list.', error: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _label(String s) => widget.statusLabel?.call(s) ?? storeStatusLabel(s);

  List<(T, DocListItem)> get _visible {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final r in _rows)
        if (widget.describe(r) case final d
            when (_status == 'ALL' || d.status == _status) &&
                (q.isEmpty || d.number.toLowerCase().contains(q) || d.meta.any((m) => (m ?? '').toLowerCase().contains(q))))
          (r, d),
    ];
  }

  Future<void> _open(Future<bool> Function() action) async {
    final saved = await action();
    if (saved && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final visible = _visible;
    final all = _rows.map(widget.describe).toList();

    return MarketScaffold(
      title: widget.title,
      subtitle: _loading && _rows.isEmpty ? 'Loading…' : '${visible.length} of ${_rows.length}',
      fab: widget.onCreate == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _open(widget.onCreate!),
              icon: const Icon(Icons.add),
              label: Text(widget.createLabel ?? 'New'),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (widget.kpis.isNotEmpty) ...[
                  _kpis(all),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 14, color: p.text),
                  decoration: marketInput(
                    context,
                    hint: widget.searchHint,
                    prefixIcon: Icon(Icons.search, size: 20, color: p.label),
                    suffix: _search.text.isEmpty
                        ? null
                        : IconButton(icon: Icon(Icons.close, size: 18, color: p.label), onPressed: () => setState(_search.clear)),
                  ).copyWith(fillColor: p.card),
                ),
                if (widget.statuses.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  MarketSegmented<String>(
                    value: _status,
                    onChanged: (v) => setState(() => _status = v),
                    options: [
                      (id: 'ALL', label: 'All', count: all.length),
                      for (final s in widget.statuses) (id: s, label: _label(s), count: all.where((d) => d.status == s).length),
                    ],
                  ),
                ],
              ]),
            ),
          ),
          ..._listSlivers(p, visible),
        ]),
      ),
    );
  }

  Widget _kpis(List<DocListItem> all) {
    final tiles = [
      for (final k in widget.kpis)
        KpiTile(
          icon: k.icon,
          label: k.label,
          tone: k.tone,
          value: k.statuses == null ? all.length : all.where((d) => k.statuses!.contains(d.status)).length,
          onTap: widget.statuses.isEmpty
              ? null
              : () => setState(() => _status = (k.statuses != null && k.statuses!.length == 1) ? k.statuses!.first : 'ALL'),
        ),
    ];
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 10));
      rows.add(Row(children: [
        Expanded(child: tiles[i]),
        const SizedBox(width: 10),
        Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
      ]));
    }
    return Column(children: rows);
  }

  List<Widget> _listSlivers(MarketPalette p, List<(T, DocListItem)> visible) {
    if (_loading && _rows.isEmpty) {
      return const [SliverFillRemaining(hasScrollBody: false, child: SkeletonList(count: 6, itemHeight: 70))];
    }
    if (_error != null) {
      return [SliverFillRemaining(hasScrollBody: false, child: MarketEmpty(icon: Icons.cloud_off_outlined, title: _error!, actionLabel: 'Try again', onAction: _load))];
    }
    if (visible.isEmpty) {
      final none = _rows.isEmpty;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: MarketEmpty(
            icon: widget.icon,
            title: none ? widget.emptyTitle : 'Nothing matches',
            message: none ? widget.emptyMessage : 'Try another search or status.',
            actionLabel: none && widget.onCreate != null ? widget.createLabel ?? 'New' : null,
            onAction: none && widget.onCreate != null ? () => _open(widget.onCreate!) : null,
          ),
        ),
      ];
    }

    // Group rows under day headers (Today / Yesterday / date).
    final items = <Object>[];
    String? lastDay;
    for (final entry in visible) {
      final d = parseLocal(entry.$2.date);
      final label = d == null ? 'Undated' : dayLabel(d);
      if (label != lastDay) {
        items.add(label);
        lastDay = label;
      }
      items.add(entry);
    }

    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, widget.onCreate == null ? 24 : 96),
        sliver: SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            if (item is String) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
                child: Text(item, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.label)),
              );
            }
            final (row, d) = item as (T, DocListItem);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FadeSlideIn(index: i, child: _row(p, row, d)),
            );
          },
        ),
      ),
    ];
  }

  Widget _row(MarketPalette p, T row, DocListItem d) {
    final tone = docStatusTone(d.status);
    final c = p.tone(tone);
    final date = parseLocal(d.date);
    final meta = [
      ...d.meta.where((m) => (m ?? '').trim().isNotEmpty).cast<String>(),
      if (d.itemCount != null) '${d.itemCount} item${d.itemCount == 1 ? '' : 's'}',
    ].join(' · ');
    return MarketCard(
      padding: const EdgeInsets.all(12),
      onTap: widget.onOpen == null ? null : () => _open(() => widget.onOpen!(row)),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10)),
          child: Icon(widget.icon, size: 20, color: c.fg),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.number.isEmpty ? 'No number' : d.number,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          StatusPill(_label(d.status), tone: tone),
          if (d.extraPill != null) ...[
            const SizedBox(height: 4),
            StatusPill(d.extraPill!.$1, tone: d.extraPill!.$2),
          ],
          if (date != null) ...[
            const SizedBox(height: 5),
            Text(docShortDate(date), style: TextStyle(fontSize: 11, color: p.label)),
          ],
        ]),
        if (widget.trailing != null) widget.trailing!(row),
      ]),
    );
  }
}

// ── Form ────────────────────────────────────────────────────────────────

/// Section title + card. With [card] false the children sit directly under
/// the header (used for the line items editor, whose rows are cards).
class DocSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final bool card;
  final int index;
  const DocSection({super.key, required this.title, this.subtitle, this.trailing, required this.children, this.card = true, this.index = 0});

  @override
  Widget build(BuildContext context) => FadeSlideIn(
        index: index,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader(title, subtitle: subtitle, trailing: trailing),
          if (card)
            MarketCard(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            )
          else
            ...children,
        ]),
      );
}

/// Labelled dropdown in the market input style. [options] are (value, label).
class DocDropdown<V> extends StatelessWidget {
  final String label;
  final V? value;
  final List<(V, String)> options;
  final ValueChanged<V?> onChanged;
  final String? hint;
  final IconData? icon;
  final bool required;
  final String? help;
  const DocDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint,
    this.icon,
    this.required = false,
    this.help,
  });

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return FieldBlock(
      label: label,
      required: required,
      help: help,
      child: DropdownButtonFormField<V>(
        initialValue: options.any((o) => o.$1 == value) ? value : null,
        isExpanded: true,
        dropdownColor: p.card,
        style: TextStyle(fontSize: 14, color: p.text),
        icon: Icon(Icons.expand_more, color: p.label),
        decoration: marketInput(
          context,
          hint: options.isEmpty ? 'Nothing to choose yet' : (hint ?? 'Choose'),
          prefixIcon: icon == null ? null : Icon(icon, size: 18, color: p.label),
        ),
        items: [
          for (final o in options) DropdownMenuItem<V>(value: o.$1, child: Text(o.$2, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// Status picker as sentence-case chips (no raw status codes).
class DocStatusPicker extends StatelessWidget {
  final List<String> statuses;
  final String value;
  final ValueChanged<String> onChanged;
  final String? help;
  const DocStatusPicker({super.key, required this.statuses, required this.value, required this.onChanged, this.help});

  @override
  Widget build(BuildContext context) => FieldBlock(
        label: 'Status',
        help: help,
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in statuses) OptionChip(label: storeStatusLabel(s), selected: s == value, onTap: () => onChanged(s)),
        ]),
      );
}

/// Read-only value shown in the field style, optionally as a status pill.
class DocReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final MarketTone? tone;
  final String? help;
  const DocReadOnlyField({super.key, required this.label, required this.value, required this.icon, this.tone, this.help});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return FieldBlock(
      label: label,
      help: help,
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
        child: Row(children: [
          Icon(icon, size: 18, color: p.label),
          const SizedBox(width: 10),
          Flexible(
            child: tone != null
                ? StatusPill(value, tone: tone!)
                : Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: p.text)),
          ),
        ]),
      ),
    );
  }
}

/// Sticky bottom save bar with an optional summary line.
class DocSaveBar extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;
  final String? summary;
  const DocSaveBar({super.key, required this.label, required this.icon, required this.busy, required this.onPressed, this.summary});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final button = SizedBox(
      height: 48,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon, size: 20),
        label: Text(label),
      ),
    );
    return Container(
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: summary == null
              ? SizedBox(width: double.infinity, child: button)
              : Row(children: [
                  Expanded(
                    child: Text(summary!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.label)),
                  ),
                  const SizedBox(width: 12),
                  button,
                ]),
        ),
      ),
    );
  }
}

/// Inline notice card (info / warn / error tone) for form banners.
class DocNotice extends StatelessWidget {
  final IconData icon;
  final String message;
  final MarketTone tone;
  const DocNotice({super.key, required this.icon, required this.message, this.tone = MarketTone.info});

  @override
  Widget build(BuildContext context) {
    final c = MarketPalette.of(context).tone(tone);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: c.fg),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: TextStyle(fontSize: 12.5, color: c.fg, height: 1.35))),
      ]),
    );
  }
}

/// Loading placeholder for a form: two section skeletons.
class DocFormSkeleton extends StatelessWidget {
  const DocFormSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: const [
          SkeletonBox(height: 16, width: 120),
          SizedBox(height: 12),
          SkeletonBox(height: 220, radius: 12),
          SizedBox(height: 22),
          SkeletonBox(height: 16, width: 90),
          SizedBox(height: 12),
          SkeletonBox(height: 84, radius: 12),
          SizedBox(height: 10),
          SkeletonBox(height: 84, radius: 12),
        ],
      );
}

/// Wraps a form body: tap outside a field to dismiss the keyboard.
class DocFormBody extends StatelessWidget {
  final List<Widget> children;
  const DocFormBody({super.key, required this.children});

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: children),
      );
}
