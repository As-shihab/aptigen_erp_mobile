import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../core/utils/currency.dart';
import '../../../../shared/ui/motion_kit.dart' hide toInt, toDouble;
import '../../data/accounting_transactions_service.dart';
import '../../models/accounting_models.dart';

/// Party statement — mobile port of desktop accounting/party-statement/
/// PartyStatement.tsx. Pick one client or supplier and see every
/// transaction tied to them with a running net. Not a full AR/AP
/// sub-ledger: a supplier's statement only has vouchers tagged to them,
/// since purchase orders / MRRs carry a free-text supplier name with no
/// supplier_id to follow.
class PartyStatementPage extends StatefulWidget {
  const PartyStatementPage({super.key});

  @override
  State<PartyStatementPage> createState() => _PartyStatementPageState();
}

class _PartyStatementPageState extends State<PartyStatementPage> {
  final _service = AccountingTransactionsService(ApiClient());
  bool _loadingParties = true;
  bool _loading = false;
  String? _error;
  String _partyType = 'CLIENT';
  int? _partyId;
  List<PartyOption> _clients = [];
  List<PartyOption> _suppliers = [];
  List<StatementLine> _lines = [];

  /// Guards against an older statement request landing after a newer
  /// party was picked.
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _loadParties();
  }

  Future<void> _loadParties() async {
    try {
      final parties = await _service.loadStatementParties();
      if (!mounted) return;
      setState(() {
        _clients = parties.clients;
        _suppliers = parties.suppliers;
      });
    } catch (_) {
      // Empty picker — pull to refresh retries.
    } finally {
      if (mounted) setState(() => _loadingParties = false);
    }
  }

  Future<void> _loadStatement() async {
    final partyId = _partyId;
    final seq = ++_requestSeq;
    if (partyId == null) {
      setState(() {
        _lines = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lines = await _service.loadPartyStatement(_partyType, partyId);
      if (!mounted || seq != _requestSeq) return;
      setState(() => _lines = lines);
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _lines = [];
        _error = errorMessage(e, 'Could not load statement');
      });
    } finally {
      if (mounted && seq == _requestSeq) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (_clients.isEmpty && _suppliers.isEmpty) await _loadParties();
    await _loadStatement();
  }

  List<PartyOption> get _parties => _partyType == 'CLIENT' ? _clients : _suppliers;

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final isClient = _partyType == 'CLIENT';
    final totalDebit = _lines.fold<double>(0, (s, l) => s + l.debit);
    final totalCredit = _lines.fold<double>(0, (s, l) => s + l.credit);
    final net = totalDebit - totalCredit;
    final netCaption = net > 0 ? (isClient ? 'Net, owed to us' : 'Net, owed by us') : 'Net, settled';

    return MotionScaffold(
      title: 'Party statement',
      icon: Icons.contact_page_outlined,
      onRefresh: _refresh,
      headerExtra: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MarketSegmented<String>(
          value: _partyType,
          options: const [
            (id: 'CLIENT', label: 'Client', count: null),
            (id: 'SUPPLIER', label: 'Supplier', count: null),
          ],
          onChanged: (v) {
            if (v == _partyType) return;
            setState(() {
              _partyType = v;
              _partyId = null;
            });
            _loadStatement();
          },
        ),
        const SizedBox(height: 10),
        PickerField(
          value: _partyId,
          hint: _loadingParties ? 'Loading…' : (isClient ? 'Select a client' : 'Select a supplier'),
          icon: isClient ? Icons.person_outline_rounded : Icons.local_shipping_outlined,
          options: [for (final party in _parties) PickOption(party.id, party.name)],
          onChanged: (v) {
            setState(() => _partyId = v == null ? null : int.tryParse(v.toString()));
            _loadStatement();
          },
        ),
        if (!isClient) ...[
          const SizedBox(height: 8),
          Text(
            'Purchase orders and MRRs aren\'t linked to a supplier record yet (supplier name is free text), so only payment vouchers tagged to this supplier appear here.',
            style: TextStyle(fontSize: 11.5, color: p.label),
          ),
        ],
      ]),
      slivers: [
        if (_partyId == null)
          sliverEmpty(
            icon: Icons.contact_page_outlined,
            title: isClient ? 'Pick a client' : 'Pick a supplier',
            message: 'Their transactions and running balance show up here.',
          )
        else if (_loading && _lines.isEmpty)
          sliverSkeleton(count: 5, height: 64)
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _loadStatement)
        else ...[
          SliverPadding(
            padding: const EdgeInsets.only(top: 14),
            sliver: SliverToBoxAdapter(
              child: KpiStrip(children: [
                GradientKpi(icon: Icons.arrow_upward_rounded, label: 'Debit', value: totalDebit, format: (v) => formatMoney(v), accent: Accent.sunset),
                GradientKpi(icon: Icons.arrow_downward_rounded, label: 'Credit', value: totalCredit, format: (v) => formatMoney(v), accent: Accent.emerald),
                GradientKpi(
                  icon: Icons.balance_rounded,
                  label: netCaption,
                  value: net,
                  format: (v) => formatMoney(v),
                  accent: net > 0 ? Accent.rose : Accent.emerald,
                ),
              ]),
            ),
          ),
          if (_lines.isEmpty)
            sliverEmpty(icon: Icons.receipt_long_outlined, title: 'No transactions', message: 'Nothing is tied to this party yet.')
          else ...[
            sliverBox(SectionHeader('Transactions', subtitle: '${_lines.length} ${_lines.length == 1 ? 'entry' : 'entries'}, oldest first'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0)),
            sliverStagger(
              count: _lines.length,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              gap: 8,
              builder: (_, i) => _StatementTile(line: _lines[i]),
            ),
          ],
        ],
      ],
    );
  }
}

class _StatementTile extends StatelessWidget {
  final StatementLine line;
  const _StatementTile({required this.line});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final isDebit = line.debit > 0;
    return GlowCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(children: [
        AccentIcon(isDebit ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, accent: isDebit ? Accent.sunset : Accent.emerald, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(line.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(height: 2),
            Text(line.date == null ? 'No date' : fmtDate(line.date), style: TextStyle(fontSize: 11.5, color: p.label)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '${isDebit ? 'Dr' : 'Cr'} ${formatMoney(isDebit ? line.debit : line.credit)}',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: isDebit ? p.warn : p.ok),
          ),
          const SizedBox(height: 2),
          Text('Balance ${formatMoney(line.balance)}', style: TextStyle(fontSize: 11.5, color: p.label)),
        ]),
      ]),
    );
  }
}
