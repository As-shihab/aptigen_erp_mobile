import 'package:flutter/material.dart';
import '../../core/network/socket_client.dart';
import '../../core/theme/app_theme.dart';

/// Persistent header for the bottom-nav shell (Home/Profile/Settings/
/// Marketplace) — logo + brand on the left, workplace name centered,
/// Wi-Fi (socket status) + notifications on the right. SAP Business/Fiori
/// flat panel styling, same as AptigenAppBar (no filled color bar).
class AptigenShellHeader extends StatelessWidget implements PreferredSizeWidget {
  final String workplaceName;
  final VoidCallback onNotificationsTap;
  final int unreadNotifications;

  const AptigenShellHeader({
    super.key,
    required this.workplaceName,
    required this.onNotificationsTap,
    this.unreadNotifications = 0,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF12161F) : Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.slate400.withValues(alpha: 0.25))),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Image.asset('assets/icon/app_icon.png', width: 26, height: 26),
              const SizedBox(width: 8),
              const Text('Aptigen ERP', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              Expanded(
                child: Center(
                  child: Text(
                    workplaceName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: AppSocket.isConnected,
                builder: (context, connected, _) => Tooltip(
                  message: connected ? 'Realtime connected' : 'Realtime disconnected',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.wifi,
                      size: 18,
                      color: connected ? AppColors.success : AppColors.error,
                    ),
                  ),
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none, size: 22),
                    tooltip: 'Notifications',
                    onPressed: onNotificationsTap,
                  ),
                  if (unreadNotifications > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                        child: Text(
                          '$unreadNotifications',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
