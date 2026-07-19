class AppConfig {
  static const String appName = 'Aptigen ERP';

  /// Same default the desktop app falls back to (VITE_API_URL).
  static const String apiBase = 'https://api.aptigen.net';

  /// OData-style base — GET/PUT/DELETE against Prisma model names directly.
  static const String v8Base = '$apiBase/aptigen/';

  /// Plain REST base — auth/*, hrm/*, and other custom routes.
  static const String apiPrefix = '$apiBase/api/';
}
