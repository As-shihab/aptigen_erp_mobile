import 'package:flutter/material.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';

/// Bonus types — mirrors desktop BonusType.tsx (bonus_types: name,
/// description, active).
class BonusTypesPage extends StatelessWidget {
  const BonusTypesPage({super.key});

  @override
  Widget build(BuildContext context) => EntityListPage(
        config: EntityConfig(
          title: 'Bonus types',
          endpoint: 'bonus_types',
          icon: Icons.card_giftcard_outlined,
          accent: Accent.amber,
          select: 'id,name,description,is_active',
          fields: const [
            EntityField('is_active', 'Active', kind: EField.toggle, defaultValue: true),
            EntityField('name', 'Name', required: true, hint: 'e.g. Festival bonus', icon: Icons.label_outline_rounded),
            EntityField('description', 'Description', kind: EField.multiline, hint: 'Enter description'),
          ],
          rowTitle: (r) => str(r['name']),
          rowSubtitle: (r, _) => str(r['description']),
          searchKeys: const ['name', 'description'],
          beforeSave: (p, _) => {...p, 'name': str(p['name']).trim()},
        ),
      );
}
