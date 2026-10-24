import 'package:flutter/material.dart';
import '../../../../core/config/app_config.dart';
import '../../../../shared/ui/motion_kit.dart';

// Helpers shared by the employee list, detail and form screens — mirrors the
// EmployeeRow shape of erp/desktop's EmployeeForm.tsx.

/// `$expand` used by desktop's EmployeeList (`employees?$expand=...`).
const employeeExpand = 'designation,department,employee_type,section,shift';

const employeeGenders = ['Male', 'Female', 'Other'];
const employeeReligions = ['Islam', 'Hinduism', 'Christianity', 'Buddhism', 'Other'];
const employeeBloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

String employeeName(Map<String, dynamic> e) {
  final n = [str(e['first_name']).trim(), str(e['last_name']).trim()].where((s) => s.isNotEmpty).join(' ');
  return n.isEmpty ? 'Unknown' : n;
}

/// Media URLs may be stored relative to the API host.
String? absMediaUrl(dynamic v) {
  final s = str(v).trim();
  if (s.isEmpty) return null;
  if (s.startsWith('http') || s.startsWith('data:')) return s;
  return '${AppConfig.apiBase}${s.startsWith('/') ? '' : '/'}$s';
}

/// Avatar with a hero tag so the list → detail transition morphs.
class EmployeeAvatar extends StatelessWidget {
  final Map<String, dynamic> employee;
  final double size;
  final bool showStatus;
  final bool hero;
  const EmployeeAvatar(this.employee, {super.key, this.size = 46, this.showStatus = true, this.hero = true});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final active = asBool(employee['is_active'], fallback: true);
    Widget avatar = InitialsAvatar(employeeName(employee), imageUrl: absMediaUrl(employee['profile_photo']), size: size);
    if (hero && employee['id'] != null) avatar = Hero(tag: 'employee-avatar-${employee['id']}', child: avatar);
    if (!showStatus) return avatar;
    final dot = size * 0.26;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? p.ok : p.neutral,
              border: Border.all(color: p.card, width: 2),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Small rounded info cell used in detail grids.
class FieldCell extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  const FieldCell(this.label, this.value, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.line.withValues(alpha: 0.7))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 13, color: p.label), const SizedBox(width: 4)],
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.label))),
        ]),
        const SizedBox(height: 4),
        Text(value.isEmpty ? '—' : value, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
      ]),
    );
  }
}

/// Two-column grid of [FieldCell]s that wraps naturally.
class FieldGrid extends StatelessWidget {
  final List<(String, String, IconData?)> fields;
  const FieldGrid(this.fields, {super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < fields.length; i++)
            SizedBox(
              width: w,
              child: FadeSlideIn(index: i, offsetY: 10, child: FieldCell(fields[i].$1, fields[i].$2, icon: fields[i].$3)),
            ),
        ]);
      });
}

/// Simple chip choice row for fixed string options (gender, religion…).
class StringChoice extends StatelessWidget {
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  const StringChoice({super.key, required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final o in options)
        PressScale(
          onTap: () => onChanged(value == o ? null : o),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: value == o ? p.brand : p.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: value == o ? p.brand : Colors.transparent),
            ),
            child: Text(o, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: value == o ? Colors.white : p.text)),
          ),
        ),
    ]);
  }
}
