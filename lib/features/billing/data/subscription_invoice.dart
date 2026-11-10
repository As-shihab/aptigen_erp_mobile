import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/storage/app_storage.dart';
import '../../sell/market/presentation/widgets/market_ui.dart';

/// Creates an invoice + its one line item, always `status: 'pending'` — a
/// port of erp/desktop's `module/market/shared/subscriptionInvoice.ts`
/// `createPendingInvoice`. A platform admin has to approve it before the
/// module's subscription activates (the backend then pushes
/// `billing:invoice-updated`, which reloads the paywall snapshot).
/// Returns the new invoice's id (opened next in the invoice page).
Future<int> createPendingInvoice(
  ApiClient client, {
  required int moduleId,
  required String moduleName,
  required double unitPrice,
  required int months,
  String paymentMethod = 'offline',
  int? paymentAccountId,
}) async {
  final total = (unitPrice * months * 100).round() / 100;
  final invoiceNo = 'INV-${DateTime.now().millisecondsSinceEpoch}';
  final user = await AppStorage.getUser();
  final userId = int.tryParse('${user?['id'] ?? ''}');

  final created = await client.post(
    'module_purchase_invoices',
    {
      'invoice_no': invoiceNo,
      'subtotal': total,
      'total': total,
      'currency': 'BDT',
      'payment_method': paymentMethod,
      'payment_account_id': paymentAccountId,
      'is_sandbox': false,
      'status': 'pending',
      'paid_at': null,
      'created_by': (userId != null && userId > 0) ? userId : null,
    },
    isV8: true,
  );
  final row = created is Map && created['value'] is Map ? created['value'] as Map : (created is Map ? created : const {});
  final invoiceId = int.tryParse('${row['id'] ?? ''}') ?? 0;
  if (invoiceId == 0) throw ApiException(0, 'Could not create invoice');

  await client.post(
    'module_purchase_invoice_items',
    {'invoice_id': invoiceId, 'module_id': moduleId, 'name': moduleName, 'price': unitPrice, 'quantity': months},
    isV8: true,
  );
  return invoiceId;
}

/// Workplaces already known to have a phone this session.
final Set<String> _knownPhoneWorkplaces = {};

/// Resolves true when the workplace has (or now has) a phone number, false
/// if the user cancelled — port of desktop's `ensureWorkplacePhone`, called
/// before creating a module invoice.
Future<bool> ensureWorkplacePhone(BuildContext context, ApiClient client) async {
  final user = await AppStorage.getUser();
  final workplace = user?['selectedWorkplace'] ?? user?['workplace'];
  final key = workplace is Map ? '${workplace['id'] ?? ''}' : '';
  if (key.isNotEmpty && _knownPhoneWorkplaces.contains(key)) return true;

  try {
    final res = await client.get('workplace/me', isV8: false);
    final phone = res is Map ? res['phone'] : null;
    if (phone is String && phone.trim().isNotEmpty) {
      if (key.isNotEmpty) _knownPhoneWorkplaces.add(key);
      return true;
    }
  } catch (_) {
    // Can't read the workplace — let the invoice call surface its own error.
    return true;
  }

  if (!context.mounted) return false;
  final saved = await showDialog<bool>(context: context, builder: (_) => _PhonePromptDialog(client: client));
  if (saved == true && key.isNotEmpty) _knownPhoneWorkplaces.add(key);
  return saved == true;
}

class _PhonePromptDialog extends StatefulWidget {
  final ApiClient client;
  const _PhonePromptDialog({required this.client});

  @override
  State<_PhonePromptDialog> createState() => _PhonePromptDialogState();
}

class _PhonePromptDialogState extends State<_PhonePromptDialog> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.client.put('workplace', 'me', {'phone': value}, isV8: false);
      if (!mounted) return;
      marketToast(context, 'Workplace phone saved');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      marketToast(context, e.message.isEmpty ? 'Failed to save phone number' : e.message, error: true);
      setState(() => _saving = false);
    } catch (_) {
      if (!mounted) return;
      marketToast(context, 'Failed to save phone number', error: true);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return AlertDialog(
      title: const Text('Workplace phone number', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your workplace has no phone number yet. Add one to create the invoice.', style: TextStyle(fontSize: 13, color: p.label)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.phone,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Phone number', hintText: 'e.g. +880 1700 000000'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving || _controller.text.trim().isEmpty ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save and continue'),
        ),
      ],
    );
  }
}
