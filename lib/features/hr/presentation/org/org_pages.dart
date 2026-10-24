import 'package:flutter/material.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';

// Org structure lookups — ports of erp/desktop's hrm/department,
// designation, employee-type and employee-section pages. All four are flat
// OData entities, so each page is an [EntityListPage] config carrying the
// same fields, list columns and toggles desktop has.

String? _textOrNull(dynamic v) {
  final s = str(v).trim();
  return s.isEmpty ? null : s;
}

/// Trims text fields like desktop (`name.trim()`, empty → null).
Map<String, dynamic> _trimmed(Map<String, dynamic> body, List<String> keys) => {
      ...body,
      for (final k in keys) k: k == 'name' ? str(body[k]).trim() : _textOrNull(body[k]),
    };

class DepartmentsPage extends StatelessWidget {
  const DepartmentsPage({super.key});

  @override
  Widget build(BuildContext context) => EntityListPage(
        config: EntityConfig(
          title: 'Departments',
          endpoint: 'departments',
          icon: Icons.account_tree_outlined,
          accent: Accent.ocean,
          select: 'id,name,description',
          orderBy: 'name asc',
          searchKeys: const ['name', 'description'],
          rowTitle: (r) => str(r['name']),
          rowSubtitle: (r, _) => _textOrNull(r['description']) ?? 'No description',
          fields: const [
            EntityField('name', 'Name', required: true, hint: 'e.g. Human resources', icon: Icons.account_tree_outlined),
            EntityField('description', 'Description', kind: EField.multiline, hint: 'Optional description'),
          ],
          beforeSave: (body, _) => _trimmed(body, ['name', 'description']),
        ),
      );
}

class DesignationsPage extends StatelessWidget {
  const DesignationsPage({super.key});

  @override
  Widget build(BuildContext context) => EntityListPage(
        config: EntityConfig(
          title: 'Designations',
          endpoint: 'designations',
          icon: Icons.workspace_premium_outlined,
          accent: Accent.ocean,
          select: 'id,name,description,is_active',
          orderBy: 'name asc',
          searchKeys: const ['name', 'description'],
          rowTitle: (r) => str(r['name']),
          rowSubtitle: (r, _) => _textOrNull(r['description']) ?? 'No description',
          fields: const [
            EntityField('is_active', 'Active', kind: EField.toggle, defaultValue: true),
            EntityField('name', 'Name', required: true, hint: 'Enter designation name', icon: Icons.workspace_premium_outlined),
            EntityField('description', 'Description', kind: EField.multiline, hint: 'Enter description'),
          ],
          beforeSave: (body, _) => _trimmed(body, ['name', 'description']),
        ),
      );
}

class EmployeeTypesPage extends StatelessWidget {
  const EmployeeTypesPage({super.key});

  @override
  Widget build(BuildContext context) => EntityListPage(
        config: EntityConfig(
          title: 'Employee types',
          endpoint: 'employee_types',
          icon: Icons.category_outlined,
          accent: Accent.ocean,
          select: 'id,custom_id,name,is_active,is_officer_staff',
          orderBy: 'name asc',
          searchKeys: const ['name', 'custom_id'],
          rowTitle: (r) => str(r['name']),
          rowSubtitle: (r, _) => [
            if (_textOrNull(r['custom_id']) != null) 'ID ${r['custom_id']}',
            asBool(r['is_officer_staff']) ? 'Officer staff' : 'General staff',
          ].join(' · '),
          chipFilters: {
            'Officer staff': (r) => asBool(r['is_officer_staff']),
          },
          fields: const [
            EntityField('is_active', 'Active', kind: EField.toggle, defaultValue: true),
            EntityField('is_officer_staff', 'Officer staff', kind: EField.toggle, defaultValue: false, hint: 'Counts as officer level staff'),
            EntityField('custom_id', 'Custom ID', hint: 'Enter custom ID (optional)', icon: Icons.tag_rounded),
            EntityField('name', 'Name', required: true, hint: 'Enter employee type name', icon: Icons.category_outlined),
          ],
          beforeSave: (body, _) => _trimmed(body, ['name', 'custom_id']),
        ),
      );
}

class EmployeeSectionsPage extends StatelessWidget {
  const EmployeeSectionsPage({super.key});

  @override
  Widget build(BuildContext context) => EntityListPage(
        config: EntityConfig(
          title: 'Employee sections',
          endpoint: 'employee_sections',
          icon: Icons.view_module_outlined,
          accent: Accent.emerald,
          select: 'id,custom_id,name,is_active,is_attendance_bonus,is_overtime_bonus',
          orderBy: 'name asc',
          searchKeys: const ['name', 'custom_id'],
          rowTitle: (r) => str(r['name']),
          rowSubtitle: (r, _) => [
            if (_textOrNull(r['custom_id']) != null) 'ID ${r['custom_id']}',
            'Attendance bonus ${asBool(r['is_attendance_bonus']) ? 'on' : 'off'}',
            'Overtime bonus ${asBool(r['is_overtime_bonus']) ? 'on' : 'off'}',
          ].join(' · '),
          chipFilters: {
            'Attendance bonus': (r) => asBool(r['is_attendance_bonus']),
            'Overtime bonus': (r) => asBool(r['is_overtime_bonus']),
          },
          fields: const [
            EntityField('is_active', 'Active', kind: EField.toggle, defaultValue: true),
            EntityField('is_attendance_bonus', 'Attendance bonus', kind: EField.toggle, defaultValue: false),
            EntityField('is_overtime_bonus', 'Overtime bonus', kind: EField.toggle, defaultValue: false),
            EntityField('custom_id', 'Custom ID', hint: 'Enter custom ID (optional)', icon: Icons.tag_rounded),
            EntityField('name', 'Name', required: true, hint: 'Enter section name', icon: Icons.view_module_outlined),
          ],
          beforeSave: (body, _) => _trimmed(body, ['name', 'custom_id']),
        ),
      );
}
