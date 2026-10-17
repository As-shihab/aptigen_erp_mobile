import 'package:flutter/material.dart';
import '../../data/market_seller_service.dart';
import '../banners/form_kit.dart';
import '../widgets/market_ui.dart';
import 'gateway_methods.dart';

/// Opens the add / edit sheet; resolves true when something was saved.
Future<bool> showGatewayEditor(BuildContext context, MarketSellerService service, {Map<String, dynamic>? row, String method = 'mobile'}) async {
  final saved = await showMarketSheet<bool>(
    context,
    builder: (_) => GatewayEditorSheet(service: service, row: row, initialMethod: method),
  );
  return saved == true;
}

class GatewayEditorSheet extends StatefulWidget {
  final MarketSellerService service;
  final Map<String, dynamic>? row;
  final String initialMethod;
  const GatewayEditorSheet({super.key, required this.service, this.row, this.initialMethod = 'mobile'});

  @override
  State<GatewayEditorSheet> createState() => _GatewayEditorSheetState();
}

class _GatewayEditorSheetState extends State<GatewayEditorSheet> {
  late String _method = widget.row?['method']?.toString() ?? widget.initialMethod;
  late final _provider = TextEditingController(text: widget.row?['provider']?.toString() ?? '');
  late final _label = TextEditingController(text: widget.row?['label']?.toString() ?? '');
  late final _accountName = TextEditingController(text: widget.row?['account_name']?.toString() ?? '');
  late final _accountNumber = TextEditingController(text: widget.row?['account_number']?.toString() ?? '');
  late final _instructions = TextEditingController(text: widget.row?['instructions']?.toString() ?? '');
  late int _sort = toInt(widget.row?['sort_order']);
  late bool _active = widget.row == null ? true : widget.row!['is_active'] == true;
  bool _saving = false;

  bool get _isEdit => widget.row?['id'] != null;
  GatewayMethod get _m => gatewayMethod(_method);

  @override
  void dispose() {
    for (final c in [_provider, _label, _accountName, _accountNumber, _instructions]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_m.needsAccount && _accountNumber.text.trim().isEmpty) {
      marketToast(context, 'Account number is required for ${_m.label.toLowerCase()}', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final body = gatewayBody({
        'method': _method,
        'provider': _method == 'cash' ? '' : _provider.text,
        'label': _label.text,
        'account_name': _m.needsAccount ? _accountName.text : '',
        'account_number': _m.needsAccount ? _accountNumber.text : '',
        'instructions': _instructions.text,
        'sort_order': _sort,
        'is_active': _active,
      });
      await widget.service.saveGateway(body, id: _isEdit ? toInt(widget.row!['id']) : null);
      if (!mounted) return;
      marketToast(context, _isEdit ? 'Payment method updated' : 'Payment method added');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      marketToast(context, errorText(e, 'Could not save the payment method'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final m = _m;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SheetHeader(title: _isEdit ? 'Edit payment method' : 'New payment method', subtitle: m.hint),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FieldBlock(
                label: 'Method',
                required: true,
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final g in gatewayMethods)
                    OptionChip(label: g.label, icon: g.icon, selected: g.id == _method, onTap: () => setState(() => _method = g.id)),
                ]),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (_method != 'cash')
                    FieldBlock(
                      label: _method == 'bank' ? 'Bank name' : 'Provider',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        MarketTextField(
                          controller: _provider,
                          hint: _method == 'bank' ? 'e.g. City Bank' : (m.providers.isEmpty ? null : 'e.g. ${m.providers.first}'),
                          onChanged: (_) => setState(() {}),
                        ),
                        if (m.providers.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final s in m.providers)
                              OptionChip(
                                label: s,
                                selected: _provider.text.trim().toLowerCase() == s.toLowerCase(),
                                onTap: () => setState(() => _provider.text = s),
                              ),
                          ]),
                        ],
                      ]),
                    ),
                  FieldBlock(
                    label: 'Label',
                    help: 'Shown to buyers at checkout.',
                    child: MarketTextField(controller: _label, hint: _method == 'mobile' ? 'bKash personal' : 'Shown to buyers at checkout'),
                  ),
                  if (m.needsAccount) ...[
                    FieldBlock(label: 'Account name', child: MarketTextField(controller: _accountName, capitalization: TextCapitalization.words)),
                    FieldBlock(
                      label: _method == 'mobile' ? 'Wallet number' : 'Account number',
                      required: true,
                      child: MarketTextField(
                        controller: _accountNumber,
                        keyboardType: _method == 'mobile' ? TextInputType.phone : TextInputType.text,
                        hint: _method == 'mobile' ? '01XXXXXXXXX' : null,
                      ),
                    ),
                  ],
                ]),
              ),
              FieldBlock(
                label: 'Instructions',
                help: 'Optional note for buyers, e.g. "Send money, then enter the transaction ID".',
                child: MarketTextField(controller: _instructions, maxLines: 4),
              ),
              FieldBlock(
                label: 'Sort order',
                child: Row(children: [
                  StepperField(value: _sort, onChanged: (v) => setState(() => _sort = v)),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Lower numbers show first.', style: TextStyle(fontSize: 12, color: p.label))),
                ]),
              ),
              SwitchRow(
                title: 'Active',
                subtitle: _active ? 'Buyers can pay this way' : 'Hidden at checkout',
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ]),
          ),
        ),
        SheetFooter(label: _isEdit ? 'Save changes' : 'Add method', busy: _saving, onPressed: _save),
      ]),
    );
  }
}
