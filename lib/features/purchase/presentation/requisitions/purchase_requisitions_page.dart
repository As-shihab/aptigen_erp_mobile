import '../comparative/comparative_study_page.dart';
import '../rfq/rfqs_page.dart';
import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../../../shared/ui/motion_wizard.dart';
import '../../../store/data/document_models.dart';
import '../../../store/data/store_product_model.dart';
import '../../../store/presentation/widgets/line_items_editor.dart';
import '../../data/approval_service.dart';
import '../../data/po_service.dart';
import '../../data/pr_service.dart';
import '../approvals/approval_widgets.dart';
import '../orders/purchase_orders_page.dart';

// Purchase requisitions (SPR) — mobile port of desktop
// purchase/PurchaseRequisitions.tsx: status tabs with counts, search, date
// filter, the flow stage of each requisition, a detail page with lines,
// estimate, approval chain and linked orders, manual approve / reject (only
// for requisitions outside an approval chain), chain decisions, "Create PO"
// (only while RFQ is off), plus the store-side create / edit wizard.
// No destination warehouse field on the form.

MarketTone sprTone(String s) => switch (s) {
  'PENDING' => MarketTone.warn,
  'APPROVED' => MarketTone.info,
  'ORDERED' => MarketTone.ok,
  'REJECTED' => MarketTone.error,
  _ => MarketTone.neutral,
};

Color _stageColor(MarketPalette p, SprStageTone t) => switch (t) {
  SprStageTone.error => p.error,
  SprStageTone.ok => p.ok,
  SprStageTone.warn => p.warn,
  SprStageTone.info => p.info,
  SprStageTone.violet => const Color(0xFF7858FF),
};

class PurchaseRequisitionsPage extends StatefulWidget {
  const PurchaseRequisitionsPage({super.key});

  @override
  State<PurchaseRequisitionsPage> createState() => _PurchaseRequisitionsPageState();
}

class _PurchaseRequisitionsPageState extends State<PurchaseRequisitionsPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<PurchaseRequisition> _rows = [];
  PurchaseSettings _settings = const PurchaseSettings();
  String _q = '';
  String _tab = 'ALL';
  ListFilter _filter = const ListFilter();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    try {
      final data = await purchaseBatch(_client, {'rows': PrService.listQuery, 'settings': PurchaseSettings.query}, required: {'rows'});
      if (!mounted) return;
      setState(() {
        _rows = (data['rows'] ?? []).map(PurchaseRequisition.fromJson).toList();
        _settings = PurchaseSettings.fromRows(data['settings']);
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load purchase requisitions'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<PurchaseRequisition> get _base {
    final q = _q.trim().toLowerCase();
    return _rows.where((r) {
      if (!_filter.matchesDate(r.requestedDate)) return false;
      if (q.isEmpty) return true;
      return [r.sprNo, r.purpose ?? '', r.warehouseName ?? '', r.requesterName ?? ''].any((v) => v.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _openFilter() async {
    final f = await showListFilterSheet(context, current: _filter, dateLabel: 'Requested');
    if (f != null) setState(() => _filter = f);
  }

  Future<void> _create() async {
    final saved = await pushMotion<bool>(context, const PurchaseRequisitionFormPage());
    if (saved == true) _load();
  }

  Future<void> _open(PurchaseRequisition r) async {
    await pushMotion(context, PurchaseRequisitionDetailPage(sprId: r.id, initial: r));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final base = _base;
    final rows = _tab == 'ALL' ? base : base.where((r) => r.status == _tab).toList();
    final ready = base.where((r) => r.status == 'APPROVED' && !r.isOrdered).length;
    final pending = base.where((r) => r.status == 'PENDING').length;
    final estimate = rows.fold<double>(0, (s, r) => s + r.estimate);

    return MotionScaffold(
      title: 'Purchase requisitions',
      subtitle: _loading ? null : '${rows.length} ${rows.length == 1 ? 'requisition' : 'requisitions'}',
      icon: Icons.request_page_outlined,
      onRefresh: _load,
      onFab: _create,
      fabLabel: 'New SPR',
      actions: [
        IconButton(
          tooltip: 'Filter',
          onPressed: _openFilter,
          icon: Badge(
            isLabelVisible: !_filter.isEmpty,
            smallSize: 8,
            backgroundColor: p.brand,
            child: Icon(Icons.tune_rounded, color: p.text),
          ),
        ),
      ],
      headerExtra: HeaderSearch(hint: 'Search number, purpose or warehouse', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        if (!_filter.isEmpty)
          sliverBox(
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                label: Text([if (_filter.from != null) 'From ${fmtDate(_filter.from)}', if (_filter.to != null) 'to ${fmtDate(_filter.to)}'].join(' ')),
                onDeleted: () => setState(() => _filter = const ListFilter()),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: KpiStrip(
              height: 106,
              children: [
                GradientKpi(
                  icon: Icons.hourglass_empty_rounded,
                  label: 'Awaiting approval',
                  value: pending,
                  accent: Accent.amber,
                  onTap: () => setState(() => _tab = 'PENDING'),
                ),
                GradientKpi(
                  icon: Icons.verified_outlined,
                  label: _settings.hasRfq ? 'Ready for RFQ' : 'Ready for PO',
                  value: ready,
                  accent: Accent.teal,
                  onTap: () => setState(() => _tab = 'APPROVED'),
                ),
                GradientKpi(icon: Icons.payments_outlined, label: 'Estimate in view', value: estimate, format: (v) => money(v)),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 12),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _tab,
              options: [
                (id: 'ALL', label: 'All', count: base.length),
                for (final s in sprStatuses) (id: s, label: sprStatusText(s), count: base.where((r) => r.status == s).length),
              ],
              onChanged: (v) => setState(() => _tab = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton(height: 92)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.request_page_outlined,
            title: _rows.isEmpty ? 'No purchase requisitions yet' : 'No requisitions',
            message: _rows.isEmpty ? 'Requests to buy stock go here, then through approval to purchasing.' : 'Try another tab, search or filter.',
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) => _SprTile(spr: rows[i], onTap: () => _open(rows[i])),
          ),
      ],
    );
  }
}

class _SprTile extends StatelessWidget {
  final PurchaseRequisition spr;
  final VoidCallback onTap;
  const _SprTile({required this.spr, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final stage = spr.stage;
    final sub = [
      if (spr.purpose != null) spr.purpose!,
      if (spr.warehouseName != null) spr.warehouseName!,
      if (spr.requestedDate != null) fmtDate(spr.requestedDate),
    ].join(' · ');
    return GlowCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AccentIcon(Icons.request_page_outlined, accent: Accent.violet, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spr.sprNo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.label),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(sprStatusText(spr.status), tone: sprTone(spr.status)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: _stageColor(p, stage.tone), shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  stage.label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _stageColor(p, stage.tone)),
                ),
              ),
              Text('${spr.items.length} ${spr.items.length == 1 ? 'item' : 'items'}', style: TextStyle(fontSize: 11.5, color: p.label)),
              if (spr.estimate > 0) ...[
                const SizedBox(width: 10),
                Text(
                  money(spr.estimate),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Detail ──────────────────────────────────────────────────────────────

class PurchaseRequisitionDetailPage extends StatefulWidget {
  final int sprId;
  final PurchaseRequisition? initial;
  const PurchaseRequisitionDetailPage({super.key, required this.sprId, this.initial});

  @override
  State<PurchaseRequisitionDetailPage> createState() => _PurchaseRequisitionDetailPageState();
}

class _PurchaseRequisitionDetailPageState extends State<PurchaseRequisitionDetailPage> {
  final _client = ApiClient();
  late PurchaseRequisition? _spr = widget.initial;
  PurchaseSettings _settings = const PurchaseSettings();
  CurrentApprover _me = CurrentApprover.none;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = await ApprovalService.currentUserId();
      final data = await purchaseBatch(
        _client,
        {'spr': PrService.detailQuery(widget.sprId), 'settings': PurchaseSettings.query, ...ApprovalService.meQueries(userId)},
        required: {'spr'},
      );
      if (!mounted) return;
      final rows = data['spr'] ?? [];
      if (rows.isEmpty) throw ApiException(404, 'This requisition no longer exists');
      setState(() {
        _spr = PurchaseRequisition.fromJson(rows.first);
        _settings = PurchaseSettings.fromRows(data['settings']);
        _me = ApprovalService.meFrom(userId, data);
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load this requisition'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _rfqOn => _settings.hasRfq;
  bool _canApprove(PurchaseRequisition r) => r.status == 'PENDING' && !r.inChain;

  // Once quotations are out it's past rejecting — cancel the RFQ first.
  bool _canReject(PurchaseRequisition r) => ['PENDING', 'APPROVED'].contains(r.status) && !r.hasRfq && !(r.status == 'PENDING' && r.inChain);
  bool _canCreatePo(PurchaseRequisition r) => !_rfqOn && r.status == 'APPROVED';

  Future<void> _manual(PurchaseRequisition r, bool approve) async {
    final ok = await confirmMarket(
      context,
      title: approve ? 'Approve ${r.sprNo}?' : 'Reject ${r.sprNo}?',
      message: approve
          ? (_rfqOn ? 'It can then go out for quotation.' : 'A purchase order can then be created from it.')
          : 'The store will see it as rejected and it leaves the purchase flow.',
      confirm: approve ? 'Approve' : 'Reject',
      destructive: !approve,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await PrService(_client).setStatus(r.id, approve ? 'APPROVED' : 'REJECTED');
      if (!mounted) return;
      marketToast(context, approve ? '${r.sprNo} approved' : '${r.sprNo} rejected');
      await _load();
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not update the requisition'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(PurchaseRequisition r, bool approve) async {
    final changed = await runApprovalDecision(
      context,
      doc: ApprovalDoc.spr,
      docId: r.id,
      docNo: r.sprNo,
      currentSerial: r.currentSerial,
      steps: r.approvals,
      approve: approve,
      me: _me,
    );
    if (changed) _load();
  }

  Future<void> _createPo(PurchaseRequisition r) async {
    final saved = await pushMotion<bool>(context, PurchaseOrderFormPage(settings: _settings, fromSpr: r));
    if (saved == true) _load();
  }

  Future<void> _edit(PurchaseRequisition r) async {
    if (!r.isEditable) {
      marketToast(context, '${r.sprNo} is ${sprStatusText(r.status).toLowerCase()} and can no longer be changed');
      return;
    }
    final saved = await pushMotion<bool>(context, PurchaseRequisitionFormPage(existing: r));
    if (saved == true) _load();
  }

  Future<void> _delete(PurchaseRequisition r) async {
    if (!r.isEditable) {
      marketToast(context, '${r.sprNo} is already ${sprStatusText(r.status).toLowerCase()} and can\'t be deleted');
      return;
    }
    final ok = await confirmMarket(
      context,
      title: 'Delete ${r.sprNo}?',
      message: 'Its ${r.items.length} item line${r.items.length == 1 ? '' : 's'} will be removed too.',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await PrService(_client).delete(r.id);
      if (!mounted) return;
      marketToast(context, 'Purchase requisition deleted');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(e, 'Could not delete the requisition'), error: true);
      }
    }
  }

  Future<void> _rfqHint(PurchaseRequisition r) async {
    if (r.hasQuotes) {
      await pushMotion(context, ComparativeStudyPage(sprId: r.id));
    } else {
      await pushMotion<bool>(context, RfqFormPage(presetSprId: r.id));
    }
    if (mounted) _load();
  }

  Future<void> _more(PurchaseRequisition r) async {
    final key = await showActionSheet(
      context,
      title: r.sprNo,
      actions: [
        if (r.isEditable) (key: 'edit', label: 'Edit', icon: Icons.edit_outlined, destructive: false),
        if (_canApprove(r)) (key: 'approve', label: 'Approve', icon: Icons.check_circle_outline_rounded, destructive: false),
        if (_canCreatePo(r)) (key: 'po', label: 'Create purchase order', icon: Icons.assignment_outlined, destructive: false),
        if (_rfqOn && r.status == 'APPROVED' && !r.hasRfq) (key: 'rfq', label: 'Create RFQ', icon: Icons.request_quote_outlined, destructive: false),
        if (_rfqOn && !r.isOrdered && r.hasQuotes) (key: 'rfq', label: 'Compare quotes', icon: Icons.compare_arrows_rounded, destructive: false),
        if (_canReject(r)) (key: 'reject', label: 'Reject', icon: Icons.block_rounded, destructive: true),
        if (r.isEditable) (key: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
      ],
    );
    if (key == null || !mounted) return;
    switch (key) {
      case 'edit':
        await _edit(r);
      case 'approve':
        await _manual(r, true);
      case 'reject':
        await _manual(r, false);
      case 'po':
        await _createPo(r);
      case 'rfq':
        _rfqHint(r);
      case 'delete':
        await _delete(r);
    }
  }

  Widget? _bottomBar(PurchaseRequisition r) {
    final step = r.pendingStep;
    if (r.inChain && canActOnStep(step, _me)) {
      return DetailActionBar(
        children: [
          OutlineAction(
            label: step!.isRequired ? 'Reject' : 'Skip step',
            icon: Icons.close_rounded,
            destructive: true,
            onTap: _busy ? null : () => _decide(r, false),
          ),
          GradientButton(label: 'Approve', icon: Icons.check_rounded, busy: _busy, onTap: () => _decide(r, true)),
        ],
      );
    }
    if (_canApprove(r)) {
      return DetailActionBar(
        children: [
          OutlineAction(label: 'Reject', icon: Icons.close_rounded, destructive: true, onTap: _busy ? null : () => _manual(r, false)),
          GradientButton(label: 'Approve', icon: Icons.check_rounded, busy: _busy, onTap: () => _manual(r, true)),
        ],
      );
    }
    if (_canCreatePo(r)) {
      return DetailActionBar(
        children: [GradientButton(label: 'Create purchase order', icon: Icons.assignment_outlined, busy: _busy, onTap: () => _createPo(r))],
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final r = _spr;
    if (r == null) {
      return MotionScaffold(
        title: 'Purchase requisition',
        onRefresh: _load,
        slivers: [
          if (_loading)
            sliverSkeleton(count: 4, height: 110)
          else
            sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load),
        ],
      );
    }
    final stage = r.stage;
    final step = r.pendingStep;

    return MotionScaffold(
      title: r.sprNo,
      subtitle: 'Purchase requisition',
      onRefresh: _load,
      actions: [
        if (r.isEditable)
          IconButton(
            tooltip: 'Edit',
            onPressed: _busy ? null : () => _edit(r),
            icon: Icon(Icons.edit_outlined, color: p.text),
          ),
        IconButton(
          tooltip: 'More',
          onPressed: _busy ? null : () => _more(r),
          icon: Icon(Icons.more_vert_rounded, color: p.text),
        ),
      ],
      bottomBar: _bottomBar(r),
      slivers: [
        if (_error != null)
          sliverBox(
            GlowCard(
              color: p.errorBg,
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: p.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!, style: TextStyle(color: p.error, fontSize: 12.5)),
                  ),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        sliverBox(
          FadeSlideIn(
            child: GlowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StatusPill(sprStatusText(r.status), tone: sprTone(r.status)),
                      if (r.inChain) StatusPill('Approval ${approvalProgress(r.approvals)}', tone: MarketTone.neutral),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: _stageColor(p, stage.tone), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          stage.label,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r.estimate > 0
                        ? 'Estimated ${money(r.estimate)} for ${r.items.length} ${r.items.length == 1 ? 'item' : 'items'}'
                        : '${r.items.length} ${r.items.length == 1 ? 'item' : 'items'}',
                    style: TextStyle(fontSize: 12.5, color: p.label),
                  ),
                  if (step != null && !canActOnStep(step, _me)) ...[
                    const SizedBox(height: 8),
                    Text('Waiting on step ${r.currentSerial}: ${step.label}', style: TextStyle(fontSize: 12, color: p.warn)),
                  ],
                  if (_rfqOn && r.status == 'APPROVED' && !r.isOrdered) ...[
                    const SizedBox(height: 8),
                    Text(
                      r.hasQuotes
                          ? 'Quotes are in. Compare them in the comparative study.'
                          : (r.hasRfq ? 'Out for quotation.' : 'Next step: send it out for quotation from RFQs.'),
                      style: TextStyle(fontSize: 12, color: p.info),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        sliverBox(
          GlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                infoGrid([
                  ('Requested', fmtDate(r.requestedDate)),
                  ('Requested by', r.requesterName ?? ''),
                  ('Warehouse', r.warehouseName ?? ''),
                  ('Purpose', r.purpose ?? ''),
                ]),
                if (r.remarks != null) ...[
                  const SizedBox(height: 12),
                  Text('Remarks', style: TextStyle(fontSize: 11.5, color: p.label)),
                  const SizedBox(height: 2),
                  Text(r.remarks!, style: TextStyle(fontSize: 13.5, color: p.text, height: 1.35)),
                ],
              ],
            ),
          ),
        ),
        if (r.inChain) ...[
          sliverBox(
            SectionHeader('Approval chain', subtitle: '${approvalProgress(r.approvals)} steps done'),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          ),
          sliverBox(
            GlowCard(
              child: ApprovalTimeline(steps: r.approvals, currentSerial: r.currentSerial, docStatus: r.status),
            ),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          ),
        ],
        if (r.purchaseOrders.isNotEmpty || r.rfqs.isNotEmpty) ...[
          sliverBox(const SectionHeader('Linked documents'), padding: const EdgeInsets.fromLTRB(16, 18, 16, 0)),
          sliverBox(
            GlowCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final po in r.purchaseOrders)
                    ListTile(
                      leading: const AccentIcon(Icons.assignment_outlined, size: 34),
                      title: Text(
                        po.poNo,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text),
                      ),
                      subtitle: Text('Purchase order', style: TextStyle(fontSize: 12, color: p.label)),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.label),
                      onTap: () => pushMotion(context, PurchaseOrderDetailPage(poId: po.id)),
                    ),
                  for (final rfq in r.rfqs)
                    ListTile(
                      leading: const AccentIcon(Icons.request_quote_outlined, accent: Accent.violet, size: 34),
                      title: Text(
                        'RFQ #${rfq.id}',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text),
                      ),
                      subtitle: Text(
                        '${humanize(rfq.status)} · ${rfq.quotes} ${rfq.quotes == 1 ? 'quote' : 'quotes'}',
                        style: TextStyle(fontSize: 12, color: p.label),
                      ),
                    ),
                ],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          ),
        ],
        sliverBox(
          SectionHeader('Product lines', subtitle: '${r.items.length} ${r.items.length == 1 ? 'line' : 'lines'}'),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        ),
        if (r.items.isEmpty)
          sliverEmpty(icon: Icons.inventory_2_outlined, title: 'No line items')
        else
          sliverStagger(
            count: r.items.length,
            gap: 8,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            builder: (_, i) {
              final it = r.items[i];
              return GlowCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            it.productName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${fmtQty(it.quantity)} × ${it.estimatedPrice != null ? money(it.estimatedPrice!) : 'no estimate'}',
                            style: TextStyle(fontSize: 11.5, color: p.label),
                          ),
                          if (it.remarks != null) Text(it.remarks!, style: TextStyle(fontSize: 11.5, color: p.label)),
                        ],
                      ),
                    ),
                    if (it.estimatedPrice != null)
                      Text(
                        money(it.total),
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text),
                      ),
                  ],
                ),
              );
            },
          ),
        if (r.items.isNotEmpty)
          sliverBox(
            GlowCard(
              child: Column(
                children: [
                  InfoRow('Lines', '${r.items.length}'),
                  InfoRow('Total quantity', fmtQty(r.items.fold(0, (s, i) => s + i.quantity))),
                  Divider(color: p.line, height: 16),
                  InfoRow('Estimated total', money(r.estimate), emphasize: true),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Create / edit wizard ────────────────────────────────────────────────

/// Store-side create / edit of an SPR. Every save sends it (back) as
/// PENDING and, when the store's SPR approval is on, (re)starts the chain.
/// No warehouse field: the destination is decided later in purchasing.
class PurchaseRequisitionFormPage extends StatefulWidget {
  final PurchaseRequisition? existing;
  const PurchaseRequisitionFormPage({super.key, this.existing});

  @override
  State<PurchaseRequisitionFormPage> createState() => _PurchaseRequisitionFormPageState();
}

class _PurchaseRequisitionFormPageState extends State<PurchaseRequisitionFormPage> {
  final _client = ApiClient();
  late final _service = PrService(_client);

  late final _sprNo = TextEditingController(text: widget.existing?.sprNo ?? '');
  late final _purpose = TextEditingController(text: widget.existing?.purpose ?? '');
  late final _remarks = TextEditingController(text: widget.existing?.remarks ?? '');
  late DateTime? _requested = widget.existing?.requestedDate?.toLocal() ?? DateTime.now();

  bool _loading = true;
  bool _generating = false;
  bool _touched = false;
  List<StoreProduct> _products = [];
  List<DocumentLine> _lines = [];
  List<int> _originalLineIds = [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sprNo.dispose();
    _purpose.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await purchaseBatch(_client, {'products': PrService.productsQuery});
      final lines = _isEdit ? await _service.loadLines(widget.existing!.id) : <DocumentLine>[];
      if (!mounted) return;
      setState(() {
        _products = (data['products'] ?? []).map(StoreProduct.fromJson).toList();
        _lines = lines;
        _originalLineIds = lines.where((l) => l.id != null).map((l) => l.id!).toList();
      });
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Some lists could not be loaded'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!_isEdit && _sprNo.text.isEmpty) _generate();
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    final code = await _service.generateCode();
    if (!mounted) return;
    setState(() {
      _generating = false;
      if (code != null) _sprNo.text = code;
    });
  }

  double get _estimate => _lines.fold(0, (s, l) => s + l.quantity * (l.estimatedPrice ?? 0));

  Future<bool> _save() async {
    final header = <String, dynamic>{
      'spr_no': _sprNo.text.trim(),
      'purpose': _purpose.text.trim().isEmpty ? null : _purpose.text.trim(),
      // Every save (new, edited while pending, or a rejected one resent)
      // goes (back) for approval.
      'status': 'PENDING',
      'remarks': _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
      // requested_date is NOT NULL with a now() default — omit when blank.
      if (_requested != null) 'requested_date': DateTime.utc(_requested!.year, _requested!.month, _requested!.day).toIso8601String(),
    };
    try {
      final id = await _service.save(id: widget.existing?.id, header: header, lines: _lines, originalLineIds: _originalLineIds);
      final steps = await _service.startApproval(id);
      if (!mounted) return true;
      final no = _sprNo.text.trim();
      marketToast(context, steps > 0 ? '$no sent for approval ($steps step${steps == 1 ? '' : 's'})' : '$no sent to purchasing for approval');
      Navigator.of(context).pop(true);
      return true;
    } catch (e) {
      if (mounted) marketToast(context, describeSprError(e, 'Could not save the purchase requisition'), error: true);
      return false;
    }
  }

  Widget _detailsStep(BuildContext context) {
    final p = MarketPalette.of(context);
    final spr = widget.existing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormLabel(
          label: 'SPR number',
          required: true,
          child: TextField(
            controller: _sprNo,
            enabled: !_generating,
            onChanged: (_) => _touched = true,
            decoration: motionInput(
              context,
              hint: 'e.g. SPR-2026-0001',
              icon: Icons.tag_rounded,
              suffix: _generating
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : (_isEdit
                        ? null
                        : IconButton(
                            tooltip: 'Generate',
                            onPressed: _generate,
                            icon: Icon(Icons.autorenew_rounded, size: 19, color: p.label),
                          )),
            ),
          ),
        ),
        FormLabel(
          label: 'Purpose',
          child: TextField(
            controller: _purpose,
            onChanged: (_) => _touched = true,
            decoration: motionInput(context, hint: 'What it is for', icon: Icons.flag_outlined),
          ),
        ),
        FormLabel(
          label: 'Requested date',
          child: DatePickField(
            value: _requested,
            onChanged: (d) => setState(() {
              _touched = true;
              _requested = d;
            }),
          ),
        ),
        GlowCard(
          color: p.infoBg,
          child: Row(
            children: [
              Icon(Icons.send_outlined, color: p.info, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  spr == null
                      ? 'Sent for approval on save. Approvers, or purchasing when no chain is set up, decide.'
                      : (spr.status == 'REJECTED'
                            ? 'Saving sends it for approval again.'
                            : (spr.inChain
                                  ? 'Approval ${approvalProgress(spr.approvals)} done. Saving restarts the approval.'
                                  : 'Saving sends it to purchasing for approval.')),
                  style: TextStyle(fontSize: 12.5, color: p.text),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _linesStep(BuildContext context) => LineItemsEditor(
    lines: _lines,
    products: _products,
    fieldsConfig: const LineFieldsConfig(showEstimatedPrice: true, showRemarks: true),
    onChanged: (lines) => setState(() {
      _touched = true;
      _lines = lines;
    }),
  );

  Widget _notesStep(BuildContext context) => FormLabel(
    label: 'Remarks',
    help: 'Anything purchasing should know, like preferred brands or urgency.',
    child: TextField(
      controller: _remarks,
      minLines: 4,
      maxLines: 8,
      onChanged: (_) => _touched = true,
      decoration: motionInput(context, hint: 'Optional'),
    ),
  );

  Widget _reviewStep(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        reviewGrid([('SPR number', _sprNo.text.trim()), ('Requested date', fmtDate(_requested)), ('Purpose', _purpose.text.trim()), ('Status', 'Pending')]),
        const SizedBox(height: 14),
        GlowCard(
          child: Column(
            children: [
              InfoRow('Lines', '${_lines.length}'),
              InfoRow('Total quantity', fmtQty(_lines.fold(0, (s, l) => s + l.quantity))),
              Divider(color: p.line, height: 16),
              InfoRow('Estimated total', money(_estimate), emphasize: true),
            ],
          ),
        ),
        if (_remarks.text.trim().isNotEmpty) ...[const SizedBox(height: 12), ReviewTile('Remarks', _remarks.text.trim())],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? 'Edit ${widget.existing!.sprNo}' : 'New purchase requisition';
    if (_loading) {
      return MarketScaffold(
        title: title,
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SkeletonBox(height: i == 0 ? 58 : 48, radius: 10),
              ),
          ],
        ),
      );
    }
    return MotionWizardPage(
      title: title,
      submitLabel: _isEdit ? 'Save and send' : 'Send for approval',
      isDirty: () => _touched || (!_isEdit && _lines.isNotEmpty),
      onSubmit: _save,
      steps: [
        WizardStep(
          title: 'Details',
          icon: Icons.request_page_outlined,
          caption: 'Number, purpose and date',
          builder: _detailsStep,
          validate: () => _sprNo.text.trim().isEmpty ? 'Enter an SPR number' : null,
        ),
        WizardStep(
          title: 'Line items',
          icon: Icons.inventory_2_outlined,
          caption: 'Products, quantities and estimates',
          builder: _linesStep,
          validate: () => _lines.isEmpty ? 'Add at least one product line' : null,
        ),
        WizardStep(title: 'Notes', icon: Icons.notes_rounded, caption: 'Remarks for purchasing', builder: _notesStep),
        WizardStep(title: 'Review', icon: Icons.fact_check_outlined, caption: 'Check before sending', builder: _reviewStep),
      ],
    );
  }
}
