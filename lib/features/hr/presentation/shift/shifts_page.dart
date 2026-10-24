import 'package:flutter/material.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'shift_common.dart';

/// Shift management — mirrors erp/desktop hrm/shift/Shift.tsx
/// (employee_shifts: name, start / end time, working hours, overtime,
/// colour, night shift, active, late grace minutes).
class ShiftsPage extends StatelessWidget {
  const ShiftsPage({super.key});

  @override
  Widget build(BuildContext context) => EntityListPage(
        config: EntityConfig(
          title: 'Shifts',
          endpoint: 'employee_shifts',
          icon: Icons.schedule_rounded,
          accent: Accent.ocean,
          select: 'id,custom_id,name,start_time,end_time,total_working_hours,overtime,color,is_night,is_active,late_start_minute',
          orderBy: 'id desc',
          fields: const [
            EntityField('name', 'Name', required: true, hint: 'Enter shift name', icon: Icons.badge_outlined),
            EntityField('custom_id', 'Custom id', hint: 'Optional', icon: Icons.tag_rounded),
            EntityField('start_time', 'Start time', kind: EField.time, required: true),
            EntityField('end_time', 'End time', kind: EField.time, required: true),
            EntityField('total_working_hours', 'Working hours', hint: 'e.g. 8h', icon: Icons.timelapse_rounded),
            EntityField('overtime', 'Overtime', hint: 'e.g. 2h', icon: Icons.more_time_rounded),
            EntityField('late_start_minute', 'Late grace period (minutes)', kind: EField.number, defaultValue: 10, hint: 'e.g. 10', icon: Icons.hourglass_bottom_rounded),
            EntityField('color', 'Color', kind: EField.color, defaultValue: '#3B82F6', hint: '#3B82F6', icon: Icons.palette_outlined),
            EntityField('is_night', 'Night shift', kind: EField.toggle, defaultValue: false, hint: 'Runs past midnight'),
            EntityField('is_active', 'Active', kind: EField.toggle, defaultValue: true),
          ],
          rowTitle: (r) => str(r['name']),
          rowSubtitle: (r, _) => '${clock(r['start_time'])} to ${clock(r['end_time'])}',
          rowMeta: (r, _) {
            final bits = <String>[
              if (str(r['total_working_hours']).isNotEmpty) 'Working ${r['total_working_hours']}',
              if (str(r['overtime']).isNotEmpty) 'Overtime ${r['overtime']}',
              'Late after ${r['late_start_minute'] ?? 10} min',
              if (str(r['custom_id']).isNotEmpty) 'Id ${r['custom_id']}',
            ];
            return bits.join(' · ');
          },
          rowLeading: (r) => _ShiftBadge(color: hexColor(r['color'], const Color(0xFF8396A8)), night: asBool(r['is_night'])),
          searchKeys: const ['name', 'custom_id'],
          chipFilters: {
            'Day': (r) => !asBool(r['is_night']),
            'Night': (r) => asBool(r['is_night']),
          },
          beforeSave: (p, _) {
            final late = p['late_start_minute'];
            final color = str(p['color']).trim();
            return {
              ...p,
              'late_start_minute': late is int && late >= 0 ? late : (late is int ? 0 : 10),
              'color': color.isEmpty ? null : (color.startsWith('#') ? color : '#$color'),
            };
          },
        ),
      );
}

class _ShiftBadge extends StatelessWidget {
  final Color color;
  final bool night;
  const _ShiftBadge({required this.color, required this.night});

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(night ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded, color: Colors.white, size: 20),
      );
}
