import 'package:flutter/material.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'targeted_post_list.dart';

/// HR policies — port of desktop PolicyList.tsx (hr_policies).
class PoliciesPage extends StatelessWidget {
  const PoliciesPage({super.key});

  @override
  Widget build(BuildContext context) => const TargetedPostList(
        endpoint: 'hr_policies',
        title: 'Policies',
        singular: 'policy',
        icon: Icons.policy_rounded,
        accent: Accent.ocean,
      );
}
