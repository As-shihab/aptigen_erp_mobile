import 'package:flutter/material.dart';
import '../../../../shared/ui/motion_kit.dart';
import 'targeted_post_list.dart';

/// HR notices — port of desktop NoticeList.tsx (hr_notices).
class NoticesPage extends StatelessWidget {
  const NoticesPage({super.key});

  @override
  Widget build(BuildContext context) => const TargetedPostList(
        endpoint: 'hr_notices',
        title: 'Notices',
        singular: 'notice',
        icon: Icons.campaign_rounded,
        accent: Accent.amber,
      );
}
