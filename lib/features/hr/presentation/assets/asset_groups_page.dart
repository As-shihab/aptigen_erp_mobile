import 'package:flutter/material.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';

/// Asset groups — mirrors desktop AssetGroupList.tsx (asset_groups:
/// custom id, name, description, active).
class AssetGroupsPage extends StatelessWidget {
  const AssetGroupsPage({super.key});

  @override
  Widget build(BuildContext context) => EntityListPage(
        config: EntityConfig(
          title: 'Asset groups',
          endpoint: 'asset_groups',
          icon: Icons.inventory_2_outlined,
          accent: Accent.amber,
          select: 'id,custom_id,name,description,is_active',
          fields: const [
            EntityField('is_active', 'Active', kind: EField.toggle, defaultValue: true),
            EntityField('custom_id', 'Custom ID', hint: 'Optional', icon: Icons.tag_rounded),
            EntityField('name', 'Name', required: true, hint: 'Enter group name', icon: Icons.label_outline_rounded),
            EntityField('description', 'Description', kind: EField.multiline, hint: 'Optional description'),
          ],
          rowTitle: (r) => str(r['name']),
          rowSubtitle: (r, _) => str(r['description']),
          rowMeta: (r, _) => str(r['custom_id']).isEmpty ? null : 'ID ${r['custom_id']}',
          searchKeys: const ['name', 'custom_id', 'description'],
          beforeSave: (p, _) => {...p, 'name': str(p['name']).trim()},
        ),
      );
}
