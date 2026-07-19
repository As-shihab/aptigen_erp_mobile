import 'package:flutter/material.dart';
import '../../core/network/socket_client.dart';
import '../../core/theme/app_theme.dart';

/// SAP Business/Fiori-standard header: flat, light panel background with a
/// hairline bottom border (no filled/colored AppBar, no heavy shadow —
/// matches erp/desktop's AppHeaderBar.tsx), bold left-aligned title, and a
/// Wi-Fi icon reflecting live socket connection state (green = connected,
/// red = disconnected) — same 3-state color convention as AppHeaderBar.tsx's
/// `networkStatus` (there also gated on internet reachability; this app only
/// tracks the socket itself since there's no separate connectivity check).
class AptigenAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBack;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  const AptigenAppBar({super.key, required this.title, this.showBack = false, this.actions, this.bottom});

  @override
  Size get preferredSize => Size.fromHeight(56 + (bottom?.preferredSize.height ?? 0));

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  if (showBack)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  else
                    const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: AppSocket.isConnected,
                    builder: (context, connected, _) => Tooltip(
                      message: connected ? 'Realtime connected' : 'Realtime disconnected',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.wifi,
                          size: 18,
                          color: connected ? AppColors.success : AppColors.error,
                        ),
                      ),
                    ),
                  ),
                  ...?actions,
                  const SizedBox(width: 8),
                ],
              ),
            ),
            ?bottom,
          ],
        ),
      ),
    );
  }
}
