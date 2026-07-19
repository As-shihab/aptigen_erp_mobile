import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Shared loading/error/empty/data switch — the same shape every screen in
/// the sibling Flutter app follows (see stays_page.dart's _load pattern).
class AsyncStateView extends StatelessWidget {
  final bool loading;
  final String? error;
  final bool isEmpty;
  final String emptyMessage;
  final IconData emptyIcon;
  final Future<void> Function()? onRetry;
  final WidgetBuilder builder;

  const AsyncStateView({
    super.key,
    required this.loading,
    required this.error,
    required this.isEmpty,
    required this.builder,
    this.emptyMessage = 'Nothing here yet.',
    this.emptyIcon = Icons.inbox_outlined,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: AppColors.brand)));
    }
    if (error != null) {
      return ListView(
        children: [
          const SizedBox(height: 64),
          Icon(Icons.error_outline, size: 36, color: AppColors.slate400),
          const SizedBox(height: 12),
          Center(child: Text(error!, style: TextStyle(color: AppColors.slate600))),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            Center(child: TextButton(onPressed: onRetry, child: const Text('Retry'))),
          ],
        ],
      );
    }
    if (isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 64),
          Icon(emptyIcon, size: 36, color: AppColors.slate400),
          const SizedBox(height: 12),
          Center(child: Text(emptyMessage, style: TextStyle(color: AppColors.slate600))),
        ],
      );
    }
    return builder(context);
  }
}

/// A small rounded status/category chip, reused across tabs (leave status,
/// payroll status, asset assigned/returned, ...).
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const StatusChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
