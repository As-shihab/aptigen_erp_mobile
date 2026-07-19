import 'package:flutter/foundation.dart' show kReleaseMode;

class AppConfig {
  static const String appName = 'Aptigen ERP';

  /// Same dev/prod split as erp/desktop's env.config.ts
  /// (`import.meta.env.PROD ? env.apiBase : env.apiLocal`) — release builds
  /// hit the real API, debug/profile builds hit this same hosted API too
  /// (no separate local/LAN backend right now).
  static const String _prodApiBase = 'https://api.aptigen.net';
  static const String _localApiBase = 'https://api.aptigen.net';

  static const String apiBase = kReleaseMode ? _prodApiBase : _localApiBase;

  /// OData-style base — GET/PUT/DELETE against Prisma model names directly.
  static const String v8Base = '$apiBase/aptigen/';

  /// Plain REST base — auth/*, hrm/*, and other custom routes.
  static const String apiPrefix = '$apiBase/api/';
}
