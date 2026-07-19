import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  String _label(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System',
      };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.slate400.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text('APPEARANCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: AppController.themeMode,
                builder: (context, mode, _) => Column(
                  children: ThemeMode.values.map((value) {
                    return RadioListTile<ThemeMode>(
                      value: value,
                      // ignore: deprecated_member_use
                      groupValue: mode,
                      title: Text(_label(value)),
                      activeColor: AppColors.brand,
                      // ignore: deprecated_member_use
                      onChanged: (selected) {
                        if (selected != null) AppController.setThemeMode(selected);
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}
