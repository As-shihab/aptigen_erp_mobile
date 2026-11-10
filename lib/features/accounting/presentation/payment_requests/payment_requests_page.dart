import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/utils/currency.dart';
import '../../../../shared/ui/motion_kit.dart' hide toInt, toDouble;
import '../../../purchase/presentation/approvals/approval_widgets.dart' show OutlineAction;
import '../../data/accounting_transactions_service.dart';

/// Payment requests — mobile port of desktop accounting/payment-requests/
/// PaymentRequests.tsx. Cross-module "please pay this" inbox: HR payroll
/// (and later other modules) drop a payment_requests row here and
/// accounting decides. Approve picks the bank/cash account + contra
/// account and runs the same posting sequence as a payment voucher, then
/// links the voucher back. Reject only records decision_remarks. Both
/// actions exist for PENDING rows only — a decided request is immutable.
class PaymentRequestsPage extends StatefulWidget {
  const PaymentRequestsPage({super.key});

  @override
  State<PaymentRequestsPage> createState() => _PaymentRequestsPageState();
}

class _PaymentRequestsPageState extends State<PaymentRequestsPage> {
  final _service = AccountingTransactionsService(ApiClient());
  bool _loading = true;
  String? _error;
  String _status = 'PENDING';
  String _query = '';
  List<PaymentRequestRow> _rows = [];
  RequestLookups _lookups = RequestLookups.empty;

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
      final rows = await _service.loadPaymentRequests();
      RequestLookups lookups;
      try {
        lookups = await _service.loadRequestLookups();
      } catch (_) {
        // Party names fall back to "—" and the approve pickers stay empty.
        lookups = RequestLookups.empty;
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _lookups = lookups;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load payment requests'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _count(String status) => status == 'ALL' ? _rows.length : _rows.where((r) => r.status == status).length;

  List<PaymentRequestRow> get _visible {
    final q = _query.trim().toLowerCase();
    return _rows.where((r) {
      if (_status != 'ALL' && r.status != _status) return false;
      if (q.isEmpty) return true;
      return [r.requestNo, r.sourceModule, r.referenceType, r.remarks, _lookups.partyName(r.partyType, r.partyId)]
          .any((s) => (s ?? '').toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _decide(PaymentRequestRow row, bool approve) async {
    final done = await showMotionSheet<bool>(
      context,
      (_) => _DecisionSheet(service: _service, lookups: _lookups, request: row, approve: approve, partyName: _lookups.partyName(row.partyType, row.partyId)),
    );
    if (done == true) {
      if (mounted) marketToast(context, approve ? 'Request approved and paid' : 'Request rejected');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    return MotionScaffold(
      title: 'Payment requests',
      icon: Icons.request_quote_outlined,
      onRefresh: _load,
      headerExtra: HeaderSearch(hint: 'Search requests', onChanged: (v) => setState(() => _query = v)),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 12),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _status,
              options: [
                (id: 'PENDING', label: 'Pending', count: _count('PENDING')),
                (id: 'APPROVED', label: 'Approved', count: _count('APPROVED')),
                (id: 'REJECTED', label: 'Rejected', count: _count('REJECTED')),
                (id: 'ALL', label: 'All', count: _count('ALL')),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton(count: 4, height: 150)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(
            icon: Icons.task_alt_rounded,
            title: _status == 'PENDING' && _query.isEmpty ? 'All caught up' : 'Nothing here',
            message: _status == 'PENDING' && _query.isEmpty ? 'No payment requests are waiting for a decision.' : 'No requests match this filter.',
          )
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final r = rows[i];
              return _RequestCard(
                request: r,
                partyName: _lookups.partyName(r.partyType, r.partyId),
                onApprove: () => _decide(r, true),
                onReject: () => _decide(r, false),
              );
            },
          ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  final PaymentRequestRow request;
  final String? partyName;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  const _RequestCard({required this.request, required this.partyName, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final r = request;
    final subtitle = [
      partyName ?? (r.partyType == null ? null : humanize(r.partyType)),
      '${humanize(r.sourceModule)} · ${humanize(r.referenceType)}',
      if (r.requestDate != null) fmtDate(r.requestDate),
    ].whereType<String>().join(' · ');

    return GlowCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.requestNo, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(formatMoney(r.amount), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 4),
            StatusPill(humanize(r.status), tone: toneForStatus(r.status)),
          ]),
        ]),
        if (r.remarks != null) ...[
          const SizedBox(height: 8),
          Text(r.remarks!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.label)),
        ],
        if (r.decisionRemarks != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8)),
            child: Text('Decision: ${r.decisionRemarks}', style: TextStyle(fontSize: 12, color: p.text)),
          ),
        ],
        if (r.isPending) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlineAction(label: 'Reject', icon: Icons.close_rounded, destructive: true, onTap: onReject)),
            const SizedBox(width: 10),
            Expanded(child: GradientButton(label: 'Approve', icon: Icons.check_rounded, onTap: onApprove)),
          ]),
        ],
      ]),
    );
  }
}

/// Approve (pick bank/cash + contra account, then post) or reject (record a
/// reason) a single PENDING request.
class _DecisionSheet extends StatefulWidget {
  final AccountingTransactionsService service;
  final RequestLookups lookups;
  final PaymentRequestRow request;
  final bool approve;
  final String? partyName;
  const _DecisionSheet({required this.service, required this.lookups, required this.request, required this.approve, this.partyName});

  @override
  State<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends State<_DecisionSheet> {
  final _remarksCtrl = TextEditingController();
  BankOption? _bank;
  int? _otherAccountId;
  bool _saving = false;

  @override
  void dispose() {
    _remarksCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit => !widget.approve || (_bank != null && _otherAccountId != null);

  String? get _remarks {
    final s = _remarksCtrl.text.trim();
    return s.isEmpty ? null : s;
  }

  Future<void> _submit() async {
    if (!_canSubmit || _saving) return;
    setState(() => _saving = true);
    final r = widget.request;
    try {
      if (widget.approve) {
        // A request is always money going out, so the bank/cash account is
        // the credit side — same direction as a PAYMENT voucher. Dated on
        // the request's own date, falling back to now.
        final voucherId = await widget.service.postPayment(
          number: r.requestNo,
          date: r.requestDate,
          debitAccountId: _otherAccountId!,
          bank: _bank!,
          amount: r.amount,
          partyType: r.partyType,
          partyId: r.partyId,
          remarks: r.remarks,
        );
        await widget.service.updatePaymentRequest(r.id, {
          'status': 'APPROVED',
          'payment_voucher_id': voucherId > 0 ? voucherId : null,
          'decision_remarks': _remarks,
        });
      } else {
        await widget.service.updatePaymentRequest(r.id, {'status': 'REJECTED', 'decision_remarks': _remarks});
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, widget.approve ? 'Failed to approve request' : 'Failed to reject request'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final r = widget.request;
    return FormSheet(
      title: widget.approve ? 'Approve ${r.requestNo}' : 'Reject ${r.requestNo}',
      submitLabel: widget.approve ? 'Approve and pay' : 'Reject',
      busy: _saving,
      onSubmit: _canSubmit ? _submit : null,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            InfoRow('Amount', formatMoney(r.amount), emphasize: true),
            if (widget.partyName != null || r.partyType != null) InfoRow('Pay to', widget.partyName ?? humanize(r.partyType)),
            InfoRow('From', '${humanize(r.sourceModule)} · ${humanize(r.referenceType)}'),
          ]),
        ),
        if (widget.approve) ...[
          FormLabel(
            label: 'Bank or cash account',
            required: true,
            child: PickerField(
              value: _bank?.id,
              hint: 'Select bank or cash account',
              icon: Icons.account_balance_outlined,
              options: [for (final b in widget.lookups.banks) PickOption(b.id, b.name, sub: 'Balance ${formatMoney(b.currentBalance)}')],
              onChanged: (v) => setState(() => _bank = widget.lookups.banks.where((b) => b.id.toString() == v?.toString()).firstOrNull),
            ),
          ),
          FormLabel(
            label: 'Expense or payable account',
            required: true,
            child: PickerField(
              value: _otherAccountId,
              hint: 'Select the expense account',
              icon: Icons.account_tree_outlined,
              options: [for (final a in widget.lookups.accounts) PickOption(a.id, a.label)],
              onChanged: (v) => setState(() => _otherAccountId = v == null ? null : int.tryParse(v.toString())),
            ),
          ),
        ],
        FormLabel(
          label: widget.approve ? 'Approval note' : 'Rejection reason',
          child: TextField(
            controller: _remarksCtrl,
            maxLines: 3,
            minLines: 2,
            style: TextStyle(color: p.text),
            decoration: motionInput(context, hint: 'Optional'),
          ),
        ),
      ],
    );
  }
}
