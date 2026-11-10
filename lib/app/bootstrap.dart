import 'package:flutter/material.dart';
import '../core/billing/paywall_state.dart';
import '../core/network/http_client.dart';
import '../core/storage/app_storage.dart';
import '../core/theme/theme_controller.dart';
import '../features/billing/presentation/paywall_sheet.dart';
import 'app.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppController.init();

  ApiClient.onUnauthorized = () async {
    await AppStorage.clearSession();
    navigatorKey.currentState?.pushNamedAndRemoveUntil('/welcome', (route) => false);
  };

  // A blocked OData write opens the subscription wall over whatever screen
  // is on top — desktop's GlobalPaywallDialog mounted in App.tsx.
  PaywallState.onBlocked = (block) {
    final context = navigatorKey.currentState?.overlay?.context;
    if (context != null) showPaywallSheet(context, block);
  };

  runApp(const AptigenApp());
}
