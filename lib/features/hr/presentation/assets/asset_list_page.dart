import 'package:flutter/material.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';

/// Asset list — mirrors desktop AssetsList.tsx (assets: custom id, name,
/// active), plus the optional asset group the schema carries
/// (assets.asset_group_id) so groups are usable from the phone.
class AssetListPage extends StatelessWidget {
  const AssetListPage({super.key});

  @override
  Widget build(BuildContext context) => EntityListPage(
        config: EntityConfig(
          title: 'Asset list',
          endpoint: 'assets',
          icon: Icons.devices_other_outlined,
          accent: Accent.ocean,
          select: 'id,custom_id,name,is_active,asset_group_id',
          expand: 'asset_group(\$select=id,name)',
          lookups: const {'groups': 'asset_groups?\$select=id,name&\$filter=is_active eq true&\$orderby=name asc&\$top=500'},
          fields: const [
            EntityField('is_active', 'Active', kind: EField.toggle, defaultValue: true),
            EntityField('custom_id', 'Custom ID', hint: 'Optional', icon: Icons.tag_rounded),
            EntityField('name', 'Name', required: true, hint: 'Enter asset name', icon: Icons.label_outline_rounded),
            EntityField('asset_group_id', 'Asset group', kind: EField.lookup, lookup: 'groups', icon: Icons.inventory_2_outlined),
          ],
          rowTitle: (r) => str(r['name']),
          rowSubtitle: (r, l) {
            final g = nested(r, 'asset_group');
            return g.isNotEmpty ? g : (lookupName(l['groups'], r['asset_group_id']).isNotEmpty ? lookupName(l['groups'], r['asset_group_id']) : 'Uncategorized');
          },
          rowMeta: (r, _) => str(r['custom_id']).isEmpty ? null : 'ID ${r['custom_id']}',
          searchKeys: const ['name', 'custom_id'],
          beforeSave: (p, _) => {...p, 'name': str(p['name']).trim()},
        ),
      );
}
