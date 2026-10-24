import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../../../shared/ui/motion_wizard.dart';
import '../../../store/data/document_models.dart';
import '../../../store/data/store_product_model.dart';
import '../../../store/presentation/documents/mrr_form_page.dart';
import '../../../store/presentation/widgets/line_items_editor.dart';
import '../../data/approval_service.dart';
import '../../data/po_service.dart';
import '../../data/pr_service.dart';
import '../approvals/approval_widgets.dart';

// Purchase orders — mobile port of desktop purchase/PurchaseOrder.tsx:
// status tabs with counts, search, supplier / date filters, a detail page
// with lines, received progress, totals and the approval chain, status
// actions, and the create / edit wizard. With RFQ on, new orders come from
// the comparative study only (same as desktop), so "New" is hidden.

MarketTone poTone(String s) => switch (s) {
      'PENDING' => MarketTone.warn,
      'APPROVED' || 'RECEIVED' => MarketTone.ok,
      'REJECTED' || 'CANCELLED' => MarketTone.error,
      'SENT' || 'PARTIALLY_RECEIVED' => MarketTone.info,
      _ => MarketTone.neutral,
    };

String fmtQty(double v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

String _isoDay(DateTime d) => DateTime.utc(d.year, d.month, d.day).toIso8601String();

const _tabs = <({String id, String label, Set<String>? statuses})>[
  (id: 'all', label: 'All', statuses: null),
  (id: 'approved', label: 'Approved', statuses: {'APPROVED', 'SENT', 'PARTIALLY_RECEIVED'}),
  (id: 'pending', label: 'Pending', statuses: {'PENDING'}),
  (id: 'received', label: 'Received', statuses: {'RECEIVED'}),
  (id: 'cancelled', label: 'Cancelled', statuses: {'CANCELLED', 'REJECTED'}),
];

class PurchaseOrdersPage extends StatefulWidget {
  const PurchaseOrdersPage({super.key});

  @override
  State<PurchaseOrdersPage> createState() => _PurchaseOrdersPageState();
}

class _PurchaseOrdersPageState extends State<PurchaseOrdersPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<PurchaseOrder> _rows = [];
  PurchaseSettings _settings = const PurchaseSettings();
  List<Map<String, dynamic>> _suppliers = [];
  String _q = '';
  String _tab = 'all';
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
      final data = await purchaseBatch(_client, {
        'rows': PoService.listQuery,
        'settings': PurchaseSettings.query,
        'suppliers': PoService.suppliersQuery,
      }, required: {'rows'});
      if (!mounted) return;
      setState(() {
        _rows = (data['rows'] ?? []).map(PurchaseOrder.fromJson).toList();
        _settings = PurchaseSettings.fromRows(data['settings']);
        _suppliers = data['suppliers'] ?? [];
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load purchase orders'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? get _supplierFilterName {
    final id = _filter.partyId;
    if (id == null) return null;
    for (final s in _suppliers) {
      if (s['id'].toString() == id.toString()) return str(s['supplier_name']);
    }
    return null;
  }

  /// Search + filter, before the status tab (so tab counts stay honest).
  List<PurchaseOrder> get _base {
    final q = _q.trim().toLowerCase();
    return _rows.where((r) {
      if (_filter.partyId != null && r.supplierId?.toString() != _filter.partyId.toString()) return false;
      if (!_filter.matchesDate(r.orderDate)) return false;
      if (q.isEmpty) return true;
      return [r.poNo, r.supplierName ?? '', r.sprNo ?? ''].any((v) => v.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _openFilter() async {
    final f = await showListFilterSheet(
      context,
      current: _filter,
      partyLabel: 'Supplier',
      partyOptions: [for (final s in _suppliers) PickOption(s['id'], str(s['supplier_name']))],
      dateLabel: 'Order date',
    );
    if (f != null) setState(() => _filter = f);
  }

  Future<void> _create() async {
    final saved = await pushMotion<bool>(context, PurchaseOrderFormPage(settings: _settings));
    if (saved == true) _load();
  }

  Future<void> _open(PurchaseOrder po) async {
    await pushMotion(context, PurchaseOrderDetailPage(poId: po.id, initial: po));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final base = _base;
    final tab = _tabs.firstWhere((t) => t.id == _tab);
    final rows = tab.statuses == null ? base : base.where((r) => tab.statuses!.contains(r.status)).toList();
    final awaiting = base.where((r) => const {'APPROVED', 'SENT', 'PARTIALLY_RECEIVED'}.contains(r.status)).length;
    final pending = base.where((r) => r.status == 'PENDING').length;
    final value = rows.fold<double>(0, (s, r) => s + r.amount);
    final supplierName = _supplierFilterName;

    return MotionScaffold(
      title: 'Purchase orders',
      subtitle: _loading ? null : '${rows.length} ${rows.length == 1 ? 'order' : 'orders'}',
      icon: Icons.shopping_cart_outlined,
      onRefresh: _load,
      onFab: _settings.hasRfq ? null : _create,
      fabLabel: 'New order',
      actions: [
        IconButton(
          tooltip: 'Filter',
          onPressed: _openFilter,
          icon: Badge(isLabelVisible: !_filter.isEmpty, smallSize: 8, backgroundColor: p.brand, child: Icon(Icons.tune_rounded, color: p.text)),
        ),
      ],
      headerExtra: HeaderSearch(hint: 'Search PO, supplier or SPR', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        if (!_filter.isEmpty)
          sliverBox(
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (supplierName != null) _FilterChip(label: supplierName, onClear: () => setState(() => _filter = ListFilter(from: _filter.from, to: _filter.to))),
              if (_filter.from != null || _filter.to != null)
                _FilterChip(
                  label: [if (_filter.from != null) 'From ${fmtDate(_filter.from)}', if (_filter.to != null) 'to ${fmtDate(_filter.to)}'].join(' '),
                  onClear: () => setState(() => _filter = ListFilter(partyId: _filter.partyId)),
                ),
            ]),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: KpiStrip(height: 106, children: [
              GradientKpi(icon: Icons.payments_outlined, label: 'Value in view', value: value, format: (v) => money(v), accent: Accent.ocean),
              GradientKpi(icon: Icons.local_shipping_outlined, label: 'Awaiting goods', value: awaiting, accent: Accent.teal, onTap: () => setState(() => _tab = 'approved')),
              GradientKpi(icon: Icons.hourglass_empty_rounded, label: 'Pending', value: pending, accent: Accent.amber, onTap: () => setState(() => _tab = 'pending')),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 12),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _tab,
              options: [
                for (final t in _tabs) (id: t.id, label: t.label, count: t.statuses == null ? base.length : base.where((r) => t.statuses!.contains(r.status)).length),
              ],
              onChanged: (v) => setState(() => _tab = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton(height: 96)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.assignment_outlined,
            title: _rows.isEmpty ? 'No purchase orders yet' : 'No purchase orders',
            message: _rows.isEmpty
                ? (_settings.hasRfq ? 'Purchase orders are created from the comparative study.' : 'Tap new order to raise the first one.')
                : 'Try another tab, search or filter.',
          )
        else
          sliverStagger(count: rows.length, builder: (_, i) => _PoTile(po: rows[i], onTap: () => _open(rows[i]))),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onClear;
  const _FilterChip({required this.label, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.brand.withValues(alpha: 0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.brand)),
        IconButton(visualDensity: VisualDensity.compact, iconSize: 16, onPressed: onClear, icon: Icon(Icons.close_rounded, color: p.brand)),
      ]),
    );
  }
}

class _PoTile extends StatelessWidget {
  final PurchaseOrder po;
  final VoidCallback onTap;
  const _PoTile({required this.po, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final sub = [po.supplierName ?? 'No supplier', if (po.orderDate != null) fmtDate(po.orderDate)].join(' · ');
    return GlowCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const AccentIcon(Icons.assignment_outlined, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(po.poNo, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
              const SizedBox(height: 1),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
            ]),
          ),
          const SizedBox(width: 8),
          StatusPill(poStatusLabel(po.status), tone: poTone(po.status)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: ReceiptBar(pct: po.pct)),
          const SizedBox(width: 8),
          Text('${fmtQty(po.received)}/${fmtQty(po.ordered)}', style: TextStyle(fontSize: 11.5, color: p.label)),
          const SizedBox(width: 12),
          Text(money(po.amount), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
        ]),
        if (po.hasChain || po.sprNo != null) ...[
          const SizedBox(height: 6),
          Text(
            [if (po.sprNo != null) 'SPR ${po.sprNo}', if (po.hasChain) 'Approval ${approvalProgress(po.approvals)}', '${po.items.length} ${po.items.length == 1 ? 'line' : 'lines'}'].join(' · '),
            style: TextStyle(fontSize: 11.5, color: p.label),
          ),
        ],
      ]),
    );
  }
}

// ── Detail ──────────────────────────────────────────────────────────────

class PurchaseOrderDetailPage extends StatefulWidget {
  final int poId;
  final PurchaseOrder? initial;
  const PurchaseOrderDetailPage({super.key, required this.poId, this.initial});

  @override
  State<PurchaseOrderDetailPage> createState() => _PurchaseOrderDetailPageState();
}

class _PurchaseOrderDetailPageState extends State<PurchaseOrderDetailPage> {
  final _client = ApiClient();
  late PurchaseOrder? _po = widget.initial;
  PurchaseSettings _settings = const PurchaseSettings();
  CurrentApprover _me = CurrentApprover.none;
  bool _loading = true;
  String? _error;
  bool _busy = false;
  String _itemQ = '';

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
      final data = await purchaseBatch(_client, {
        'po': PoService.detailQuery(widget.poId),
        'settings': PurchaseSettings.query,
        ...ApprovalService.meQueries(userId),
      }, required: {'po'});
      if (!mounted) return;
      final rows = data['po'] ?? [];
      if (rows.isEmpty) throw ApiException(404, 'This purchase order no longer exists');
      setState(() {
        _po = PurchaseOrder.fromJson(rows.first);
        _settings = PurchaseSettings.fromRows(data['settings']);
        _me = ApprovalService.meFrom(userId, data);
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load this purchase order'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _approvalOn => _settings.hasPoApproval;

  /// Statuses a person may set by hand (desktop's statusOptions): any while
  /// approval is off; with approval on, nothing while the chain owns the
  /// order, then only the post-approval statuses.
  List<String> _statusTargets(PurchaseOrder po) {
    if (!_approvalOn) return poStatuses.where((s) => s != po.status).toList();
    if (poChainStatuses.contains(po.status)) return const [];
    return poStatuses.where((s) => !poChainStatuses.contains(s) && s != po.status).toList();
  }

  bool _canSubmit(PurchaseOrder po) => _approvalOn && (po.status == 'REJECTED' || (po.status == 'PENDING' && !po.hasChain));
  bool _canReceive(PurchaseOrder po) => const {'APPROVED', 'SENT', 'PARTIALLY_RECEIVED'}.contains(po.status);

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(PurchaseOrder po, String status) => _run(() async {
        try {
          await PoService(_client).setStatus(po.id, status);
          if (!mounted) return;
          marketToast(context, '${po.poNo} marked ${poStatusLabel(status).toLowerCase()}');
          await _load();
        } catch (e) {
          if (mounted) marketToast(context, errorMessage(e, 'Could not update the status'), error: true);
        }
      });

  Future<void> _pickStatus(PurchaseOrder po) async {
    final targets = _statusTargets(po);
    final key = await showActionSheet(context, title: 'Change status', actions: [
      for (final s in targets)
        (key: s, label: poStatusLabel(s), icon: s == 'CANCELLED' ? Icons.block_rounded : Icons.flag_outlined, destructive: s == 'CANCELLED' || s == 'REJECTED'),
    ]);
    if (key == null || !mounted) return;
    if (key == 'CANCELLED') {
      final ok = await confirmMarket(context, title: 'Cancel ${po.poNo}?', message: 'The order is marked cancelled and leaves the receiving queue.', confirm: 'Cancel order');
      if (!ok) return;
    }
    await _setStatus(po, key);
  }

  Future<void> _submit(PurchaseOrder po) => _run(() async {
        try {
          final steps = await ApprovalService(_client).start(ApprovalDoc.po, po.id, _settings.poApproverTypeId);
          if (!mounted) return;
          marketToast(context, steps > 0 ? '${po.poNo} submitted for approval' : 'No approvers are set up for purchase orders, change the status by hand');
          await _load();
        } catch (e) {
          if (mounted) marketToast(context, errorMessage(e, 'Could not submit for approval'), error: true);
        }
      });

  Future<void> _decide(PurchaseOrder po, bool approve) async {
    final changed = await runApprovalDecision(
      context,
      doc: ApprovalDoc.po,
      docId: po.id,
      docNo: po.poNo,
      currentSerial: po.currentSerial,
      steps: po.approvals,
      approve: approve,
      me: _me,
    );
    if (changed) _load();
  }

  Future<void> _receive(PurchaseOrder po) async {
    marketToast(context, 'Pick ${po.poNo} as the purchase order to load its lines');
    await pushMotion(context, const MrrFormPage(type: 'LOCAL'));
    if (mounted) _load();
  }

  Future<void> _edit(PurchaseOrder po) async {
    final saved = await pushMotion<bool>(context, PurchaseOrderFormPage(settings: _settings, existing: po));
    if (saved == true) _load();
  }

  Future<void> _delete(PurchaseOrder po) async {
    final ok = await confirmMarket(context, title: 'Delete ${po.poNo}?', message: 'Its ${po.items.length} item line${po.items.length == 1 ? '' : 's'} will be removed too.');
    if (!ok) return;
    await _run(() async {
      try {
        await PoService(_client).delete(po.id);
        if (!mounted) return;
        marketToast(context, 'Purchase order deleted');
        Navigator.of(context).pop(true);
      } catch (e) {
        if (mounted) marketToast(context, errorMessage(e, 'Could not delete the purchase order'), error: true);
      }
    });
  }

  Future<void> _more(PurchaseOrder po) async {
    final key = await showActionSheet(context, title: po.poNo, actions: [
      (key: 'edit', label: 'Edit', icon: Icons.edit_outlined, destructive: false),
      if (_statusTargets(po).isNotEmpty) (key: 'status', label: 'Change status', icon: Icons.flag_outlined, destructive: false),
      if (_canSubmit(po)) (key: 'submit', label: po.status == 'REJECTED' ? 'Resubmit for approval' : 'Submit for approval', icon: Icons.send_outlined, destructive: false),
      if (_canReceive(po)) (key: 'receive', label: 'Receive goods', icon: Icons.move_to_inbox_outlined, destructive: false),
      (key: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (key == null || !mounted) return;
    switch (key) {
      case 'edit':
        await _edit(po);
      case 'status':
        await _pickStatus(po);
      case 'submit':
        await _submit(po);
      case 'receive':
        await _receive(po);
      case 'delete':
        await _delete(po);
    }
  }

  Widget? _bottomBar(PurchaseOrder po) {
    final step = po.pendingStep;
    if (po.hasChain && canActOnStep(step, _me)) {
      return DetailActionBar(children: [
        OutlineAction(label: step!.isRequired ? 'Reject' : 'Skip step', icon: Icons.close_rounded, destructive: true, onTap: _busy ? null : () => _decide(po, false)),
        GradientButton(label: 'Approve', icon: Icons.check_rounded, busy: _busy, onTap: () => _decide(po, true)),
      ]);
    }
    if (_canSubmit(po)) {
      return DetailActionBar(children: [
        GradientButton(label: po.status == 'REJECTED' ? 'Resubmit for approval' : 'Submit for approval', icon: Icons.send_outlined, busy: _busy, onTap: () => _submit(po)),
      ]);
    }
    if (po.status == 'APPROVED' && _statusTargets(po).contains('SENT')) {
      return DetailActionBar(children: [
        OutlineAction(label: 'Receive goods', icon: Icons.move_to_inbox_outlined, onTap: _busy ? null : () => _receive(po)),
        GradientButton(label: 'Mark as sent', icon: Icons.send_outlined, busy: _busy, onTap: () => _setStatus(po, 'SENT')),
      ]);
    }
    if (_canReceive(po)) {
      return DetailActionBar(children: [
        GradientButton(label: 'Receive goods', icon: Icons.move_to_inbox_outlined, busy: _busy, onTap: () => _receive(po)),
      ]);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final po = _po;
    if (po == null) {
      return MotionScaffold(
        title: 'Purchase order',
        onRefresh: _load,
        slivers: [
          if (_loading) sliverSkeleton(count: 4, height: 110) else sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load),
        ],
      );
    }
    final q = _itemQ.trim().toLowerCase();
    final items = po.items.where((i) => q.isEmpty || i.productName.toLowerCase().contains(q)).toList();
    final step = po.pendingStep;

    return MotionScaffold(
      title: po.poNo,
      subtitle: 'Purchase order',
      onRefresh: _load,
      actions: [
        IconButton(tooltip: 'Edit', onPressed: _busy ? null : () => _edit(po), icon: Icon(Icons.edit_outlined, color: p.text)),
        IconButton(tooltip: 'More', onPressed: _busy ? null : () => _more(po), icon: Icon(Icons.more_vert_rounded, color: p.text)),
      ],
      bottomBar: _bottomBar(po),
      slivers: [
        if (_error != null)
          sliverBox(GlowCard(
            color: p.errorBg,
            child: Row(children: [
              Icon(Icons.error_outline_rounded, color: p.error, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(_error!, style: TextStyle(color: p.error, fontSize: 12.5))),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ]),
          )),
        sliverBox(FadeSlideIn(
          child: GlowCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                StatusPill(poStatusLabel(po.status), tone: poTone(po.status)),
                if (po.receiptLabel != null) StatusPill(po.receiptLabel!, tone: po.pct >= 100 ? MarketTone.ok : MarketTone.info),
                if (po.hasChain) StatusPill('Approval ${approvalProgress(po.approvals)}', tone: MarketTone.neutral),
              ]),
              const SizedBox(height: 12),
              Text(po.supplierName ?? 'No supplier', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
              const SizedBox(height: 2),
              Text('Order total ${money(po.amount)}', style: TextStyle(fontSize: 12.5, color: p.label)),
              if (step != null && !canActOnStep(step, _me)) ...[
                const SizedBox(height: 8),
                Text('Waiting on step ${po.currentSerial}: ${step.label}', style: TextStyle(fontSize: 12, color: p.warn)),
              ],
            ]),
          ),
        )),
        SliverPadding(
          padding: const EdgeInsets.only(top: 12),
          sliver: SliverToBoxAdapter(
            child: KpiStrip(height: 106, children: [
              GradientKpi(icon: Icons.payments_outlined, label: 'Total amount', value: po.amount, format: (v) => money(v)),
              GradientKpi(icon: Icons.format_list_bulleted_rounded, label: 'Items', value: po.items.length, accent: Accent.violet),
              GradientKpi(icon: Icons.inventory_outlined, label: 'Received', value: po.pct, format: (v) => '${v.round()}%', accent: Accent.teal),
            ]),
          ),
        ),
        sliverBox(GlowCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Receiving', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text))),
              Text('${fmtQty(po.received)} / ${fmtQty(po.ordered)}', style: TextStyle(fontSize: 12, color: p.label)),
            ]),
            const SizedBox(height: 10),
            ReceiptBar(pct: po.pct, height: 8),
            const SizedBox(height: 14),
            infoGrid([
              ('SPR', po.sprNo ?? ''),
              ('Goods receipts', po.mrrCount == 0 ? 'None yet' : '${po.mrrCount}'),
              ('Order date', fmtDate(po.orderDate)),
              ('Expected date', fmtDate(po.expectedDate)),
            ]),
          ]),
        )),
        if (po.remarks != null)
          sliverBox(GlowCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Note', style: TextStyle(fontSize: 12, color: p.label)),
              const SizedBox(height: 4),
              Text(po.remarks!, style: TextStyle(fontSize: 13.5, color: p.text, height: 1.35)),
            ]),
          )),
        if (po.hasChain) ...[
          sliverBox(SectionHeader('Approval chain', subtitle: '${approvalProgress(po.approvals)} steps done'), padding: const EdgeInsets.fromLTRB(16, 18, 16, 0)),
          sliverBox(GlowCard(child: ApprovalTimeline(steps: po.approvals, currentSerial: po.currentSerial, docStatus: po.status)), padding: const EdgeInsets.fromLTRB(16, 4, 16, 0)),
        ],
        sliverBox(SectionHeader('Items', subtitle: '${po.items.length} ${po.items.length == 1 ? 'line' : 'lines'}'), padding: const EdgeInsets.fromLTRB(16, 18, 16, 0)),
        if (po.items.length > 5)
          sliverBox(HeaderSearch(hint: 'Search items', onChanged: (v) => setState(() => _itemQ = v)), padding: const EdgeInsets.fromLTRB(16, 4, 16, 0)),
        if (po.items.isEmpty)
          sliverEmpty(icon: Icons.inventory_2_outlined, title: 'No item lines on this order')
        else if (items.isEmpty)
          sliverEmpty(icon: Icons.search_off_rounded, title: 'No matching items')
        else
          sliverStagger(count: items.length, gap: 8, padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), builder: (_, i) => _PoItemCard(po: po, item: items[i])),
        sliverBox(GlowCard(
          child: Column(children: [
            InfoRow('Lines', '${po.items.length}'),
            InfoRow('Ordered quantity', fmtQty(po.ordered)),
            InfoRow('Received quantity', fmtQty(po.received)),
            Divider(color: p.line, height: 16),
            InfoRow('Order total', money(po.amount), emphasize: true),
          ]),
        )),
      ],
    );
  }
}

class _PoItemCard extends StatelessWidget {
  final PurchaseOrder po;
  final PoItem item;
  const _PoItemCard({required this.po, required this.item});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final received = po.receivedFor(item);
    final remaining = (item.quantity - received).clamp(0, double.infinity).toDouble();
    String q(double n) => '${fmtQty(n)}${item.unit.isEmpty ? '' : ' ${item.unit}'}';
    Widget cell(String label, String value, {Color? color}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 11, color: p.label)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color ?? p.text)),
          ]),
        );
    return GlowCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(item.productName, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text))),
          const SizedBox(width: 8),
          Text(money(item.total), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
        ]),
        const SizedBox(height: 2),
        Text('${item.unitPrice != null ? money(item.unitPrice!) : '—'} each', style: TextStyle(fontSize: 11.5, color: p.label)),
        const SizedBox(height: 10),
        Row(children: [
          cell('Ordered', q(item.quantity)),
          cell('Received', q(received)),
          cell('Remaining', q(remaining), color: remaining > 0 ? p.warn : p.ok),
        ]),
        if (item.remarks != null) ...[
          const SizedBox(height: 8),
          Text(item.remarks!, style: TextStyle(fontSize: 12, color: p.label)),
        ],
      ]),
    );
  }
}

// ── Create / edit wizard ────────────────────────────────────────────────

class PurchaseOrderFormPage extends StatefulWidget {
  final PurchaseSettings settings;
  final PurchaseOrder? existing;

  /// Prefills the order from an approved requisition (desktop "Create PO").
  final PurchaseRequisition? fromSpr;
  const PurchaseOrderFormPage({super.key, required this.settings, this.existing, this.fromSpr});

  @override
  State<PurchaseOrderFormPage> createState() => _PurchaseOrderFormPageState();
}

class _PurchaseOrderFormPageState extends State<PurchaseOrderFormPage> {
  final _client = ApiClient();
  late final _service = PoService(_client);

  late final _poNo = TextEditingController(text: widget.existing?.poNo ?? '');
  late final _supplierName = TextEditingController(text: widget.existing?.supplierName ?? '');
  late final _remarks = TextEditingController(text: widget.existing?.remarks ?? '');
  late int? _supplierId = widget.existing?.supplierId;
  late int? _sprId = widget.existing?.purchaseRequisitionId ?? widget.fromSpr?.id;
  late String _status = widget.existing?.status ?? 'PENDING';
  late DateTime? _orderDate = widget.existing?.orderDate?.toLocal() ?? DateTime.now();
  late DateTime? _expectedDate = widget.existing?.expectedDate?.toLocal();

  bool _loading = true;
  bool _generating = false;
  bool _touched = false;
  List<StoreProduct> _products = [];
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _sprs = [];
  List<DocumentLine> _lines = [];
  List<int> _originalLineIds = [];

  bool get _isEdit => widget.existing != null;
  String get _originalStatus => widget.existing?.status ?? 'PENDING';
  bool get _approvalOn => widget.settings.hasPoApproval;
  bool get _statusLocked => _approvalOn && poChainStatuses.contains(_status);
  bool get _linesLocked => _isEdit && widget.settings.lockApprovedPo && !poChainStatuses.contains(_originalStatus);

  /// New order, a rejected one being resubmitted, or an old pending one
  /// without a chain — each (re)enters the approval chain on save.
  bool get _startsChain => _approvalOn && (!_isEdit || _originalStatus == 'REJECTED' || (_originalStatus == 'PENDING' && !widget.existing!.hasChain));

  List<String> get _statusOptions {
    if (!_approvalOn) return poStatuses;
    if (_statusLocked) return [_status];
    return poStatuses.where((s) => !poChainStatuses.contains(s)).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poNo.dispose();
    _supplierName.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await purchaseBatch(_client, {
        'products': PoService.productsQuery,
        'suppliers': PoService.suppliersQuery,
        'sprs': PoService.sprsQuery,
      });
      List<DocumentLine> lines = [];
      if (_isEdit) {
        lines = await _service.loadLines(widget.existing!.id);
      } else if (widget.fromSpr != null) {
        lines = [
          for (final i in widget.fromSpr!.items)
            DocumentLine(productId: i.productId, productName: i.productName, quantity: i.quantity, unitPrice: i.estimatedPrice, remarks: i.remarks),
        ];
      }
      if (!mounted) return;
      setState(() {
        _products = (data['products'] ?? []).map(StoreProduct.fromJson).toList();
        _suppliers = data['suppliers'] ?? [];
        _sprs = data['sprs'] ?? [];
        _lines = lines;
        _originalLineIds = lines.where((l) => l.id != null).map((l) => l.id!).toList();
      });
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Some lists could not be loaded'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!_isEdit && _poNo.text.isEmpty) _generate();
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    final code = await _service.generateCode();
    if (!mounted) return;
    setState(() {
      _generating = false;
      if (code != null) _poNo.text = code;
    });
  }

  void _touch(VoidCallback fn) => setState(() {
        _touched = true;
        fn();
      });

  String _supplierLabel() {
    if (_supplierId != null) {
      for (final s in _suppliers) {
        if (s['id'].toString() == _supplierId.toString()) return str(s['supplier_name']);
      }
    }
    return _supplierName.text.trim();
  }

  String _sprLabel() {
    if (_sprId == null) return '';
    if (widget.fromSpr != null && widget.fromSpr!.id == _sprId) return widget.fromSpr!.sprNo;
    for (final s in _sprs) {
      if (s['id'].toString() == _sprId.toString()) return str(s['spr_no']);
    }
    return widget.existing?.sprNo ?? '#$_sprId';
  }

  double get _total => _lines.fold(0, (s, l) => s + l.quantity * (l.unitPrice ?? 0));
  double get _qty => _lines.fold(0, (s, l) => s + l.quantity);

  Future<bool> _save() async {
    final header = <String, dynamic>{
      'purchase_requisition_id': _sprId,
      'supplier_id': _supplierId,
      'po_no': _poNo.text.trim(),
      'supplier_name': _supplierLabel().isEmpty ? null : _supplierLabel(),
      'status': _startsChain ? 'PENDING' : _status,
      'expected_date': _expectedDate == null ? null : _isoDay(_expectedDate!),
      'remarks': _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
      if (_orderDate != null) 'order_date': _isoDay(_orderDate!),
      // Same as desktop's "Create PO" from a requisition: the order follows
      // the requisition's warehouse (not a form field).
      if (widget.fromSpr?.warehouseId != null && !_isEdit) 'warehouse_id': widget.fromSpr!.warehouseId,
    };
    try {
      final id = await _service.save(
        id: widget.existing?.id,
        header: header,
        lines: _lines,
        originalLineIds: _originalLineIds,
        skipLines: _linesLocked,
      );

      var submitted = false;
      if (_startsChain) {
        try {
          submitted = await ApprovalService(_client).start(ApprovalDoc.po, id, widget.settings.poApproverTypeId) > 0;
        } catch (_) {
          if (mounted) marketToast(context, 'Saved, but the approval chain could not be started', error: true);
        }
      }

      final spr = widget.fromSpr;
      if (spr != null && spr.status != 'ORDERED') {
        try {
          await PrService(_client).setStatus(spr.id, 'ORDERED');
        } catch (_) {}
      }

      if (!mounted) return true;
      marketToast(
        context,
        submitted
            ? (spr != null ? 'Purchase order created from ${spr.sprNo} and submitted for approval' : 'Purchase order submitted for approval')
            : (_isEdit ? 'Purchase order updated' : (spr != null ? 'Purchase order created from ${spr.sprNo}' : 'Purchase order created')),
      );
      Navigator.of(context).pop(true);
      return true;
    } catch (e) {
      if (mounted) marketToast(context, describePoError(e, 'Could not save the purchase order'), error: true);
      return false;
    }
  }

  Widget _headerStep(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FormLabel(
        label: 'PO number',
        required: true,
        child: TextField(
          controller: _poNo,
          enabled: !_generating,
          onChanged: (_) => _touched = true,
          decoration: motionInput(
            context,
            hint: 'e.g. PO-2026-001',
            icon: Icons.tag_rounded,
            suffix: _generating
                ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                : (_isEdit ? null : IconButton(tooltip: 'Generate', onPressed: _generate, icon: Icon(Icons.autorenew_rounded, size: 19, color: p.label))),
          ),
        ),
      ),
      FormLabel(
        label: 'Supplier',
        required: widget.settings.requireSupplier,
        help: widget.settings.requireSupplier ? 'A supplier from the list is required on purchase orders.' : null,
        child: PickerField(
          value: _supplierId,
          hint: 'Select supplier',
          icon: Icons.storefront_outlined,
          options: [for (final s in _suppliers) PickOption(s['id'], str(s['supplier_name']))],
          onChanged: (v) => _touch(() {
            _supplierId = v == null ? null : int.tryParse(v.toString());
            if (_supplierId != null) _supplierName.text = _supplierLabel();
          }),
        ),
      ),
      if (_supplierId == null && !widget.settings.requireSupplier)
        FormLabel(
          label: 'Supplier name',
          help: 'Only when the supplier is not in the list.',
          child: TextField(controller: _supplierName, onChanged: (_) => _touched = true, decoration: motionInput(context, hint: 'Optional', icon: Icons.edit_outlined)),
        ),
      FormLabel(
        label: 'Source requisition',
        child: widget.fromSpr != null
            ? InputDecorator(decoration: motionInput(context, icon: Icons.link_rounded), child: Text(widget.fromSpr!.sprNo, style: TextStyle(fontSize: 14, color: p.text)))
            : PickerField(
                value: _sprId,
                hint: 'Optional, link to a requisition',
                icon: Icons.link_rounded,
                options: [for (final s in _sprs) PickOption(s['id'], str(s['spr_no']), sub: humanize(str(s['status'])))],
                onChanged: (v) => _touch(() => _sprId = v == null ? null : int.tryParse(v.toString())),
              ),
      ),
      FormLabel(
        label: 'Status',
        required: true,
        help: _statusLocked ? (_status == 'REJECTED' ? 'Saving resubmits it for approval.' : 'Set by the approval chain.') : null,
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in _statusOptions)
            ChoiceChip(
              label: Text(poStatusLabel(s)),
              selected: _status == s,
              onSelected: _statusLocked ? null : (_) => _touch(() => _status = s),
            ),
        ]),
      ),
      Row(children: [
        Expanded(child: FormLabel(label: 'Order date', child: DatePickField(value: _orderDate, onChanged: (d) => _touch(() => _orderDate = d)))),
        const SizedBox(width: 10),
        Expanded(child: FormLabel(label: 'Expected date', child: DatePickField(value: _expectedDate, hint: 'Optional', onChanged: (d) => _touch(() => _expectedDate = d)))),
      ]),
    ]);
  }

  Widget _linesStep(BuildContext context) {
    final p = MarketPalette.of(context);
    if (_linesLocked) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GlowCard(
          color: p.warnBg,
          child: Row(children: [
            Icon(Icons.lock_outline_rounded, color: p.warn, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text('This order is approved, so its lines are locked. Change this in purchase settings.', style: TextStyle(fontSize: 12.5, color: p.text))),
          ]),
        ),
        const SizedBox(height: 10),
        for (final l in _lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlowCard(
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.productName, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                    Text('${fmtQty(l.quantity)} × ${l.unitPrice != null ? money(l.unitPrice!) : '—'}', style: TextStyle(fontSize: 11.5, color: p.label)),
                  ]),
                ),
                Text(money(l.quantity * (l.unitPrice ?? 0)), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
              ]),
            ),
          ),
      ]);
    }
    return LineItemsEditor(
      lines: _lines,
      products: _products,
      fieldsConfig: const LineFieldsConfig(showUnitPrice: true, showRemarks: true),
      onChanged: (lines) => _touch(() => _lines = lines),
    );
  }

  Widget _notesStep(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FormLabel(
        label: 'Remarks',
        help: 'Delivery terms, payment terms or anything the supplier should know.',
        child: TextField(controller: _remarks, minLines: 4, maxLines: 8, onChanged: (_) => _touched = true, decoration: motionInput(context, hint: 'Optional')),
      ),
      if (_approvalOn)
        GlowCard(
          color: p.infoBg,
          child: Row(children: [
            Icon(Icons.info_outline_rounded, color: p.info, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _startsChain ? 'Saving submits this order to the approval chain.' : 'Approval is on. The chain decides pending and rejected orders.',
                style: TextStyle(fontSize: 12.5, color: p.text),
              ),
            ),
          ]),
        ),
    ]);
  }

  Widget _reviewStep(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      reviewGrid([
        ('PO number', _poNo.text.trim()),
        ('Supplier', _supplierLabel()),
        ('Requisition', _sprLabel()),
        ('Status', poStatusLabel(_startsChain ? 'PENDING' : _status)),
        ('Order date', fmtDate(_orderDate)),
        ('Expected date', fmtDate(_expectedDate)),
      ]),
      const SizedBox(height: 14),
      GlowCard(
        child: Column(children: [
          InfoRow('Lines', '${_lines.length}'),
          InfoRow('Total quantity', fmtQty(_qty)),
          Divider(color: p.line, height: 16),
          InfoRow('Order total', money(_total), emphasize: true),
        ]),
      ),
      if (_remarks.text.trim().isNotEmpty) ...[
        const SizedBox(height: 12),
        ReviewTile('Remarks', _remarks.text.trim()),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? 'Edit ${widget.existing!.poNo}' : (widget.fromSpr != null ? 'Purchase order from ${widget.fromSpr!.sprNo}' : 'New purchase order');
    if (_loading) {
      final p = MarketPalette.of(context);
      return MarketScaffold(
        title: title,
        body: ListView(padding: const EdgeInsets.all(16), children: [
          for (var i = 0; i < 5; i++) Padding(padding: const EdgeInsets.only(bottom: 12), child: SkeletonBox(height: i == 0 ? 58 : 48, radius: 10)),
          Text('Loading suppliers and products', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.label)),
        ]),
      );
    }
    return MotionWizardPage(
      title: title,
      submitLabel: _isEdit ? 'Save changes' : (_startsChain ? 'Submit for approval' : 'Create order'),
      isDirty: () => _touched || (!_isEdit && _lines.isNotEmpty),
      onSubmit: _save,
      steps: [
        WizardStep(
          title: 'Header',
          icon: Icons.receipt_long_outlined,
          caption: 'Number, supplier and dates',
          builder: _headerStep,
          validate: () {
            if (_poNo.text.trim().isEmpty) return 'Enter a PO number';
            if (widget.settings.requireSupplier && _supplierId == null) return 'Pick a supplier from the list, a supplier is required';
            return null;
          },
        ),
        WizardStep(
          title: 'Line items',
          icon: Icons.inventory_2_outlined,
          caption: _linesLocked ? 'Locked after approval' : 'Products, quantities and prices',
          builder: _linesStep,
          validate: () => _lines.isEmpty ? 'Add at least one product line' : null,
        ),
        WizardStep(title: 'Terms', icon: Icons.notes_rounded, caption: 'Remarks and approval', builder: _notesStep),
        WizardStep(title: 'Review', icon: Icons.fact_check_outlined, caption: 'Check the order before saving', builder: _reviewStep),
      ],
    );
  }
}
