import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/approval_service.dart';
import '../../data/po_service.dart';
import '../../data/pr_service.dart';
import '../orders/purchase_orders_page.dart';
import '../requisitions/purchase_requisitions_page.dart';
import 'approval_widgets.dart';

// One inbox for both purchase approval chains — mobile port of desktop
// purchase/approvals/PurchaseApprovals.tsx + SprApprovalList.tsx:
// requisitions (first step of the purchase flow, approving unlocks RFQ) and
// purchase orders, each split into "awaiting me" and "all pending".

enum _Doc { spr, po }

class PurchaseApprovalsPage extends StatefulWidget {
  const PurchaseApprovalsPage({super.key});

  @override
  State<PurchaseApprovalsPage> createState() => _PurchaseApprovalsPageState();
}

class _PurchaseApprovalsPageState extends State<PurchaseApprovalsPage> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  CurrentApprover _me = CurrentApprover.none;
  List<PurchaseRequisition> _sprs = [];
  List<PurchaseOrder> _pos = [];
  _Doc _doc = _Doc.spr;
  bool _mine = true;
  final Set<int> _acting = {};

  static const _sprQuery = "store_purchase_requisitions?\$filter=status eq 'PENDING' and approve_type_id ne null"
      r"&$expand=warehouse($select=name),requester($select=name,email),items($expand=product($select=id,name)),approvals($expand=actor($select=id,name,email))"
      r"&$orderby=id desc&$top=200";
  static const _poQuery = "purchase_orders?\$filter=status eq 'PENDING' and approve_type_id ne null"
      r"&$expand=items($expand=product($select=id,name)),approvals($expand=actor($select=id,name,email))"
      r"&$orderby=id desc&$top=200";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _sprs.isEmpty && _pos.isEmpty;
      _error = null;
    });
    try {
      final userId = await ApprovalService.currentUserId();
      final data = await purchaseBatch(_client, {
        'sprs': _sprQuery,
        'pos': _poQuery,
        ...ApprovalService.meQueries(userId),
      }, required: {'sprs', 'pos'});
      if (!mounted) return;
      setState(() {
        _me = ApprovalService.meFrom(userId, data);
        _sprs = (data['sprs'] ?? []).map(PurchaseRequisition.fromJson).where((r) => r.inChain).toList();
        _pos = (data['pos'] ?? []).map(PurchaseOrder.fromJson).where((r) => r.hasChain).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load approvals'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _canActSpr(PurchaseRequisition r) => canActOnStep(currentStep(r.approvals, r.currentSerial), _me);
  bool _canActPo(PurchaseOrder r) => canActOnStep(currentStep(r.approvals, r.currentSerial), _me);

  Future<void> _decide({required ApprovalDoc doc, required int id, required String no, required int serial, required List<ApprovalStep> steps, required bool approve}) async {
    setState(() => _acting.add(id));
    final changed = await runApprovalDecision(context, doc: doc, docId: id, docNo: no, currentSerial: serial, steps: steps, approve: approve, me: _me);
    if (!mounted) return;
    setState(() => _acting.remove(id));
    if (changed) _load();
  }

  @override
  Widget build(BuildContext context) {
    final mineSpr = _sprs.where(_canActSpr).toList();
    final minePo = _pos.where(_canActPo).toList();
    final sprList = _mine ? mineSpr : _sprs;
    final poList = _mine ? minePo : _pos;
    final count = _doc == _Doc.spr ? sprList.length : poList.length;

    return MotionScaffold(
      title: 'Approvals',
      subtitle: _loading ? null : '${mineSpr.length + minePo.length} awaiting you',
      icon: Icons.fact_check_outlined,
      onRefresh: _load,
      headerExtra: MarketSegmented<_Doc>(
        value: _doc,
        options: [
          (id: _Doc.spr, label: 'Requisitions', count: mineSpr.length),
          (id: _Doc.po, label: 'Purchase orders', count: minePo.length),
        ],
        onChanged: (v) => setState(() => _doc = v),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 12),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<bool>(
              value: _mine,
              options: [
                (id: true, label: 'Awaiting me', count: _doc == _Doc.spr ? mineSpr.length : minePo.length),
                (id: false, label: 'All pending', count: _doc == _Doc.spr ? _sprs.length : _pos.length),
              ],
              onChanged: (v) => setState(() => _mine = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton(count: 4, height: 170)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (count == 0)
          sliverEmpty(
            icon: Icons.task_alt_rounded,
            title: _mine ? 'All caught up' : 'Nothing pending',
            message: _doc == _Doc.spr
                ? (_mine ? 'No requisitions need your approval right now.' : 'No requisitions are waiting for approval.')
                : (_mine ? 'Nothing needs your approval right now.' : 'No purchase orders are waiting for approval.'),
          )
        else if (_doc == _Doc.spr)
          sliverStagger(
            count: sprList.length,
            builder: (_, i) {
              final r = sprList[i];
              final est = r.estimate;
              return _ApprovalCard(
                number: r.sprNo,
                subtitle: [r.warehouseName, r.requesterName, if (r.requestedDate != null) fmtDate(r.requestedDate)].whereType<String>().join(' · '),
                amount: est > 0 ? money(est) : '—',
                amountCaption: '${r.items.length} ${r.items.length == 1 ? 'line' : 'lines'}${est > 0 ? ', estimated' : ''}',
                steps: r.approvals,
                currentSerial: r.currentSerial,
                lines: [for (final it in r.items) (it.productName, '${fmtQty(it.quantity)}${it.estimatedPrice != null ? ' × ${money(it.estimatedPrice!)}' : ''}')],
                note: [r.purpose, r.remarks].whereType<String>().join(' — '),
                actionable: _canActSpr(r),
                busy: _acting.contains(r.id),
                onOpen: () async {
                  await pushMotion(context, PurchaseRequisitionDetailPage(sprId: r.id, initial: r));
                  if (mounted) _load();
                },
                onDecide: (approve) => _decide(doc: ApprovalDoc.spr, id: r.id, no: r.sprNo, serial: r.currentSerial, steps: r.approvals, approve: approve),
              );
            },
          )
        else
          sliverStagger(
            count: poList.length,
            builder: (_, i) {
              final r = poList[i];
              return _ApprovalCard(
                number: r.poNo,
                subtitle: [r.supplierName ?? 'No supplier', if (r.orderDate != null) fmtDate(r.orderDate)].join(' · '),
                amount: money(r.amount),
                amountCaption: '${r.items.length} ${r.items.length == 1 ? 'line' : 'lines'}',
                steps: r.approvals,
                currentSerial: r.currentSerial,
                lines: [for (final it in r.items) (it.productName, '${fmtQty(it.quantity)} × ${it.unitPrice != null ? money(it.unitPrice!) : '—'}')],
                note: r.remarks ?? '',
                actionable: _canActPo(r),
                busy: _acting.contains(r.id),
                onOpen: () async {
                  await pushMotion(context, PurchaseOrderDetailPage(poId: r.id, initial: r));
                  if (mounted) _load();
                },
                onDecide: (approve) => _decide(doc: ApprovalDoc.po, id: r.id, no: r.poNo, serial: r.currentSerial, steps: r.approvals, approve: approve),
              );
            },
          ),
      ],
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final String number;
  final String subtitle;
  final String amount;
  final String amountCaption;
  final List<ApprovalStep> steps;
  final int currentSerial;
  final List<(String, String)> lines;
  final String note;
  final bool actionable;
  final bool busy;
  final VoidCallback onOpen;
  final ValueChanged<bool> onDecide;

  const _ApprovalCard({
    required this.number,
    required this.subtitle,
    required this.amount,
    required this.amountCaption,
    required this.steps,
    required this.currentSerial,
    required this.lines,
    required this.note,
    required this.actionable,
    required this.busy,
    required this.onOpen,
    required this.onDecide,
  });

  void _chain(BuildContext context) {
    showMotionSheet<void>(context, (ctx) {
      final p = MarketPalette.of(ctx);
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetGrabber(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Approval chain', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('$number · ${approvalProgress(steps)} steps done', style: TextStyle(fontSize: 12.5, color: p.label)),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: ApprovalTimeline(steps: steps, currentSerial: currentSerial, docStatus: 'PENDING'),
              ),
            ),
          ]),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final step = currentStep(steps, currentSerial);
    return GlowCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(number, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
              const SizedBox(height: 2),
              Text(subtitle.isEmpty ? '—' : subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(amount, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
            Text(amountCaption, style: TextStyle(fontSize: 11.5, color: p.label)),
          ]),
        ]),
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _chain(context),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: ApprovalChips(steps: steps, currentSerial: currentSerial)),
        ),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              for (var i = 0; i < lines.length && i < 5; i++) ...[
                if (i > 0) Divider(height: 1, color: p.line),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Row(children: [
                    Expanded(child: Text(lines[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.text))),
                    const SizedBox(width: 8),
                    Text(lines[i].$2, style: TextStyle(fontSize: 12, color: p.label)),
                  ]),
                ),
              ],
              if (lines.length > 5)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 7),
                  child: Align(alignment: Alignment.centerLeft, child: Text('+${lines.length - 5} more', style: TextStyle(fontSize: 12, color: p.label))),
                ),
            ]),
          ),
        ],
        if (note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(note, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
        ],
        const SizedBox(height: 12),
        if (actionable)
          Row(children: [
            Expanded(
              child: OutlineAction(
                label: step?.isRequired == false ? 'Skip step' : 'Reject',
                icon: Icons.close_rounded,
                destructive: true,
                onTap: busy ? null : () => onDecide(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: GradientButton(label: 'Approve', icon: Icons.check_rounded, busy: busy, onTap: () => onDecide(true))),
          ])
        else
          Row(children: [
            Icon(Icons.schedule_rounded, size: 15, color: p.label),
            const SizedBox(width: 6),
            Expanded(child: Text('Waiting on step $currentSerial: ${step?.label ?? '—'}', style: TextStyle(fontSize: 12, color: p.label))),
          ]),
      ]),
    );
  }
}
