import 'package:flutter/material.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'payroll_common.dart';

const _components = ['basic', 'house_rent', 'medical_allowance', 'transport_allowance', 'other_allowance'];

double _total(Map<String, dynamic> r) => _components.fold<double>(0, (a, k) => a + n(r[k]));

String _empLabel(Map<String, dynamic> e) => employeeName(e) + (str(e['employee_no']).isEmpty ? '' : ' (${e['employee_no']})');

/// Salary structure — mirrors desktop SalaryTypeList.tsx (employee_salaries):
/// one row per employee with basic + allowances; employee is fixed once
/// created (desktop disables it in edit mode), amounts default to 0.
class SalaryStructurePage extends StatelessWidget {
  const SalaryStructurePage({super.key});

  @override
  Widget build(BuildContext context) => EntityListPage(
        config: EntityConfig(
          title: 'Salary structure',
          endpoint: 'employee_salaries',
          icon: Icons.tune_rounded,
          accent: Accent.ocean,
          expand: 'employee',
          lookups: const {'employees': 'employees?\$select=id,first_name,last_name,employee_no&\$filter=is_active eq true&\$top=500'},
          fields: [
            const EntityField('is_active', 'Active', kind: EField.toggle, defaultValue: true),
            EntityField('employee_id', 'Employee', kind: EField.lookup, lookup: 'employees', required: true, icon: Icons.person_outline_rounded, lookupLabel: _empLabel),
            const EntityField('basic', 'Basic salary', kind: EField.decimal, required: true, icon: Icons.payments_outlined),
            const EntityField('house_rent', 'House rent', kind: EField.decimal, icon: Icons.home_outlined),
            const EntityField('medical_allowance', 'Medical allowance', kind: EField.decimal, icon: Icons.medical_services_outlined),
            const EntityField('transport_allowance', 'Transport allowance', kind: EField.decimal, icon: Icons.directions_bus_outlined),
            const EntityField('other_allowance', 'Other allowance', kind: EField.decimal, icon: Icons.add_card_outlined),
          ],
          rowTitle: (r) => employeeName(asMap(r['employee']), r['employee_id']),
          rowLeading: (r) => InitialsAvatar(employeeName(asMap(r['employee']), r['employee_id']), size: 42),
          rowSubtitle: (r, _) => 'Total salary ${money(_total(r))}',
          rowMeta: (r, _) => 'Basic ${plain(n(r['basic']))} · house ${plain(n(r['house_rent']))} · medical ${plain(n(r['medical_allowance']))} · '
              'transport ${plain(n(r['transport_allowance']))} · other ${plain(n(r['other_allowance']))}',
          searchKeys: const ['basic'],
          beforeSave: (payload, existing) {
            final body = {...payload};
            for (final k in _components) {
              body[k] = (body[k] as num?) ?? 0;
            }
            // Employee can't be changed after creation (unique per employee).
            if (existing != null) body.remove('employee_id');
            return body;
          },
        ),
      );
}
