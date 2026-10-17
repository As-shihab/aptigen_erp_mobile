import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_service.dart';
import '../models/workplace_model.dart';

/// Shown when activateWorkplace() fails with DEVICE_PENDING_APPROVAL — polls
/// the same workplace-token call every few seconds until a workplace admin
/// approves (Settings → Device Request) or rejects this device.
///
/// Polling rather than a socket push: a still-pending device has no
/// `selectedWorkplace` in storage yet (activateWorkplace hasn't succeeded),
/// and the existing AppSocket/resolveSocketContext helper requires exactly
/// that before it can connect — so there's no realtime channel available at
/// this point in the flow. auth/workplce_token is already an authenticated,
/// cheap endpoint to re-poll instead.
class DevicePendingPage extends StatefulWidget {
  final AuthService authService;
  final WorkplaceOption workplace;

  const DevicePendingPage({
    super.key,
    required this.authService,
    required this.workplace,
  });

  @override
  State<DevicePendingPage> createState() => _DevicePendingPageState();
}

class _DevicePendingPageState extends State<DevicePendingPage> {
  static const _pollInterval = Duration(seconds: 5);

  Timer? _timer;
  bool _rejected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_pollInterval, (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      await widget.authService.activateWorkplace(widget.workplace);
      _timer?.cancel();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/launcher');
    } catch (error) {
      if (error is ApiException && error.code == 'DEVICE_PENDING_APPROVAL') {
        return; // still waiting — keep polling
      }
      _timer?.cancel();
      if (!mounted) return;
      setState(() {
        _rejected = error is ApiException && error.code == 'DEVICE_REJECTED';
        _error = error is ApiException
            ? error.message
            : 'Could not verify device approval. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWaiting = _error == null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _rejected ? Icons.block_rounded : Icons.hourglass_top_rounded,
                    size: 56,
                    color: _rejected ? AppColors.error : Colors.orange,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _rejected ? 'Device Rejected' : 'Permission Under Pending',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error ??
                        'Waiting for a workplace admin to approve this device. '
                            'This screen will continue automatically once it\'s approved.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.slate400),
                  ),
                  const SizedBox(height: 28),
                  if (isWaiting) const CircularProgressIndicator(),
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.chevron_left, size: 18),
                    label: const Text('Back to Sign In'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
