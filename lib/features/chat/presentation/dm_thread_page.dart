import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'widgets/chat_thread_view.dart';

class DmThreadPage extends StatelessWidget {
  final int roomId;
  final int workplaceId;
  final int memberId;
  final String peerName;
  final int peerMemberId;

  const DmThreadPage({
    super.key,
    required this.roomId,
    required this.workplaceId,
    required this.memberId,
    required this.peerName,
    required this.peerMemberId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.brand.withValues(alpha: 0.15),
              child: Text(peerName.isNotEmpty ? peerName[0].toUpperCase() : '?', style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(peerName, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: ChatThreadView(roomId: roomId, workplaceId: workplaceId, memberId: memberId, placeholderName: peerName, isGroup: false),
    );
  }
}
