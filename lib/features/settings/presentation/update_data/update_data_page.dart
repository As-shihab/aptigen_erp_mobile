import 'dart:io' show Platform;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import '../../../../core/config/app_config.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/printer_devices_service.dart';
import '../../data/settings_service.dart';
import '../widgets/settings_widgets.dart';

/// Settings → Update & data. Desktop shows the Electron auto-updater and the
/// on-disk cache. On a phone, updates come from the app store, so this page
/// shows the installed version and build channel, and manages what the app
/// keeps on the device: the image cache (safe to clear) and local
/// preferences (device settings, printers).
class UpdateDataPage extends StatefulWidget {
  const UpdateDataPage({super.key});

  @override
  State<UpdateDataPage> createState() => _UpdateDataPageState();
}

class _UpdateDataPageState extends State<UpdateDataPage> {
  int _memBytes = 0;
  int _memImages = 0;
  ({int keys, int bytes})? _prefs;
  int _printers = 0;
  bool _loading = true;
  bool _clearing = false;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cache = PaintingBinding.instance.imageCache;
    final prefs = await LocalPrefs.footprint();
    final printers = await PrinterDevicesService().loadAll();
    if (!mounted) return;
    setState(() {
      _memBytes = cache.currentSizeBytes;
      _memImages = cache.currentSize;
      _prefs = prefs;
      _printers = printers.length;
      _loading = false;
    });
  }

  String get _platform {
    if (kIsWeb) return 'Web';
    try {
      if (Platform.isAndroid) return 'Android';
      if (Platform.isIOS) return 'iOS';
      return Platform.operatingSystem;
    } catch (_) {
      return 'Unknown';
    }
  }

  Future<void> _clearCache() async {
    final ok = await confirmMarket(context,
        title: 'Clear image cache?', message: 'Cached product and profile images will download again the next time you see them.', confirm: 'Clear');
    if (!ok) return;
    setState(() => _clearing = true);
    try {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      await CachedNetworkImageProvider.defaultCacheManager.emptyCache();
      if (mounted) marketToast(context, 'Cache cleared');
    } catch (_) {
      if (mounted) marketToast(context, 'Could not clear the cache', error: true);
    } finally {
      if (mounted) setState(() => _clearing = false);
      _load();
    }
  }

  Future<void> _resetPrefs() async {
    final ok = await confirmMarket(context,
        title: 'Reset device settings?',
        message: 'Biometrics, sensors and switches settings on this phone go back to their defaults. Your session, theme and printers are kept.',
        confirm: 'Reset');
    if (!ok) return;
    setState(() => _resetting = true);
    await LocalPrefs.resetDevicePrefs();
    if (!mounted) return;
    setState(() => _resetting = false);
    marketToast(context, 'Device settings reset');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MotionScaffold(
      title: 'Update and data',
      subtitle: 'Version $kAppVersion · what this phone keeps',
      icon: Icons.sync_rounded,
      accent: Accent.teal,
      onRefresh: _load,
      slivers: [
        sliverBox(FadeSlideIn(
          child: GlowCard(
            gradient: Accent.ocean.gradient,
            child: Row(children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.system_update_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${AppConfig.appName} $kAppVersion', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('Build $kAppBuild · $_platform · ${kReleaseMode ? 'Release' : 'Debug'}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 12.5)),
                ]),
              ),
            ]),
          ),
        )),
        sliverBox(FadeSlideIn(
          index: 1,
          child: SettingsSection(
            icon: Icons.download_rounded,
            accent: Accent.ocean,
            title: 'App updates',
            subtitle: 'Check for and install the latest version',
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(Icons.verified_rounded, size: 20, color: p.ok),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You are on version $kAppVersion. New versions of the mobile app are installed from Google Play or the App Store, not from inside the app.',
                    style: TextStyle(fontSize: 12.5, height: 1.35, color: p.text),
                  ),
                ),
              ]),
            ),
          ),
        )),
        sliverBox(FadeSlideIn(
          index: 2,
          child: SettingsSection(
            icon: Icons.storage_rounded,
            accent: Accent.violet,
            title: 'Cache and local data',
            subtitle: 'Manage what this phone keeps',
            child: _loading
                ? const Column(children: [SkeletonBox(height: 64, radius: 14), SizedBox(height: 10), SkeletonBox(height: 64, radius: 14)])
                : Column(children: [
                    _DataRow(
                      title: 'Image cache',
                      sub: '$_memImages images in memory · cached images on disk. Safe to clear any time.',
                      value: formatBytes(_memBytes),
                      action: _clearing ? null : _clearCache,
                      busy: _clearing,
                      actionLabel: 'Clear',
                    ),
                    const SizedBox(height: 10),
                    _DataRow(
                      title: 'Device settings',
                      sub: 'Biometrics, sensors and switches preferences on this phone.',
                      value: '${LocalPrefs.allKeys.length} groups',
                      action: _resetting ? null : _resetPrefs,
                      busy: _resetting,
                      actionLabel: 'Reset',
                    ),
                    const SizedBox(height: 10),
                    _DataRow(
                      title: 'Local data',
                      sub: 'Session, theme, $_printers saved ${_printers == 1 ? 'printer' : 'printers'} and other preferences. Not cleared here so you stay signed in.',
                      value: formatBytes(_prefs?.bytes ?? 0),
                    ),
                  ]),
          ),
        )),
      ],
    );
  }
}

class _DataRow extends StatelessWidget {
  final String title;
  final String sub;
  final String value;
  final VoidCallback? action;
  final String? actionLabel;
  final bool busy;
  const _DataRow({required this.title, required this.sub, required this.value, this.action, this.actionLabel, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(fontSize: 11.5, height: 1.3, color: p.label)),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.text)),
          if (actionLabel != null) ...[
            const SizedBox(height: 6),
            PressScale(
              onTap: action,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: p.errorBg, borderRadius: BorderRadius.circular(10)),
                child: busy
                    ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: p.error))
                    : Text(actionLabel!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.error)),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}
