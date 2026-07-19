import 'package:flutter/material.dart';
import '../core/network/http_client.dart';
import '../core/storage/app_storage.dart';
import '../core/theme/theme_controller.dart';
import 'app.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppController.init();

  ApiClient.onUnauthorized = () async {
    await AppStorage.clearSession();
    navigatorKey.currentState?.pushNamedAndRemoveUntil('/welcome', (route) => false);
  };

  runApp(const AptigenApp());
}
