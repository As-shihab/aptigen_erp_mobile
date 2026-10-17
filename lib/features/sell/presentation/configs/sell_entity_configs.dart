import 'package:flutter/material.dart';
import '../../../store/presentation/widgets/field_spec.dart';

/// Reuses Store's generic config-driven CRUD scaffold
/// (`SimpleCrudConfig`/`SimpleEntityListPage`/`SimpleEntityFormPage`,
/// field_spec.dart) — `client_groups` is exactly the same "flat record, a
/// few typed fields" shape those were built for, no need for a bespoke
/// list/form pair.
SimpleCrudConfig clientGroupsConfig() => SimpleCrudConfig(
      title: 'Client Groups',
      endpoint: 'client_groups',
      icon: Icons.groups_outlined,
      rowTitle: (r) => (r['name'] ?? '').toString(),
      rowSubtitle: (r) => r['code']?.toString(),
      fields: const [
        FieldSpec(key: 'code', label: 'Code', kind: FieldKind.text, required: true),
        FieldSpec(key: 'name', label: 'Name', kind: FieldKind.text, required: true),
        FieldSpec(key: 'discount_rate', label: 'Discount rate (%)', kind: FieldKind.decimal, hint: 'Optional'),
        FieldSpec(key: 'credit_limit', label: 'Credit limit', kind: FieldKind.decimal, hint: 'Optional'),
        FieldSpec(key: 'is_active', label: 'Active', kind: FieldKind.boolSwitch, defaultValue: true),
      ],
    );
