import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';

String _name(Map<String, dynamic>? e) =>
    e == null ? '' : [str(e['first_name']), str(e['last_name'])].where((s) => s.isNotEmpty).join(' ');

String _empLabel(Map<String, dynamic> e) => _name(e) + (str(e['employee_no']).isEmpty ? '' : ' (${e['employee_no']})');

MarketTone _tone(String s) => switch (s.toUpperCase()) {
      'PAID' => MarketTone.ok,
      'CANCELLED' => MarketTone.error,
      _ => MarketTone.warn,
    };

Future<bool> _setStatus(BuildContext context, Map<String, dynamic> row, String status) async {
  try {
    await ApiClient().put('bonus_list', row['id'], {'status': status});
    if (context.mounted) marketToast(context, 'Bonus marked ${humanize(status).toLowerCase()}');
    return true;
  } catch (e) {
    if (context.mounted) marketToast(context, errorMessage(e, 'Failed to update bonus'), error: true);
    return false;
  }
}

/// Bonus list — mirrors desktop BonusList.tsx (bonus_list scoped to
/// code 'hrm'): employee, bonus type, amount, date, status
/// (pending / paid / cancelled) and remarks.
class BonusListPage extends StatelessWidget {
  const BonusListPage({super.key});

  @override
  Widget build(BuildContext context) => EntityListPage(
        config: EntityConfig(
          title: 'Bonus list',
          endpoint: 'bonus_list',
          icon: Icons.redeem_outlined,
          accent: Accent.sunset,
          expand: 'employee,bonus_type',
          filter: "code eq 'hrm'",
          lookups: const {
            'employees': 'employees?\$select=id,first_name,last_name,employee_no&\$filter=is_active eq true&\$top=500',
            'types': 'bonus_types?\$select=id,name&\$filter=is_active eq true&\$top=200',
          },
          fields: [
            EntityField('employee_id', 'Employee', kind: EField.lookup, lookup: 'employees', required: true, icon: Icons.person_outline_rounded, lookupLabel: _empLabel),
            const EntityField('bonus_type_id', 'Bonus type', kind: EField.lookup, lookup: 'types', required: true, icon: Icons.card_giftcard_outlined),
            const EntityField('amount', 'Amount', kind: EField.decimal, required: true, icon: Icons.payments_outlined),
            const EntityField('bonus_date', 'Date', kind: EField.date, required: true),
            const EntityField('status', 'Status', kind: EField.choice, defaultValue: 'PENDING', choices: [('PENDING', 'Pending'), ('PAID', 'Paid'), ('CANCELLED', 'Cancelled')]),
            const EntityField('remarks', 'Remarks', kind: EField.multiline, hint: 'Optional remarks'),
          ],
          rowTitle: (r) {
            final s = _name(r['employee'] is Map ? (r['employee'] as Map).cast<String, dynamic>() : null);
            return s.isEmpty ? 'Employee #${r['employee_id']}' : s;
          },
          rowLeading: (r) => InitialsAvatar(_name(r['employee'] is Map ? (r['employee'] as Map).cast<String, dynamic>() : null), size: 42),
          rowSubtitle: (r, _) => '${nested(r, 'bonus_type').isEmpty ? 'Bonus' : nested(r, 'bonus_type')} · ${money(toDouble(r['amount']))}',
          rowMeta: (r, _) => [fmtDate(parseDate(r['bonus_date'])), str(r['remarks'])].where((s) => s.isNotEmpty).join(' · '),
          rowPill: (r) {
            final s = str(r['status']).isEmpty ? 'PENDING' : str(r['status']);
            return (label: humanize(s), tone: _tone(s));
          },
          searchKeys: const ['status', 'remarks', 'amount'],
          chipFilters: {
            'Pending': (r) => (str(r['status']).isEmpty ? 'PENDING' : str(r['status']).toUpperCase()) == 'PENDING',
            'Paid': (r) => str(r['status']).toUpperCase() == 'PAID',
            'Cancelled': (r) => str(r['status']).toUpperCase() == 'CANCELLED',
          },
          rowActions: [
            RowAction('Mark as paid', Icons.check_circle_outline_rounded, (ctx, r) => _setStatus(ctx, r, 'PAID')),
            RowAction('Mark as pending', Icons.schedule_rounded, (ctx, r) => _setStatus(ctx, r, 'PENDING')),
            RowAction('Cancel bonus', Icons.block_rounded, (ctx, r) => _setStatus(ctx, r, 'CANCELLED'), destructive: true),
          ],
          beforeSave: (p, _) => {
            ...p,
            'status': p['status'] ?? 'PENDING',
            'remarks': str(p['remarks']).trim().isEmpty ? null : str(p['remarks']).trim(),
          },
        ),
      );
}
