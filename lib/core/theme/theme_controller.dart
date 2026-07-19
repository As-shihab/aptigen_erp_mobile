import 'package:flutter/material.dart';
import '../storage/app_storage.dart';

/// App-wide theme mode, mirrors the sibling app's bare ValueNotifier
/// controller (no state-management package in this codebase's convention).
class AppController {
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  static Future<void> init() async {
    final stored = await AppStorage.getThemeMode();
    themeMode.value = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    await AppStorage.setThemeMode(mode.name);
  }
}
