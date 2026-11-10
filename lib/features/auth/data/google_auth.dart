import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/http_client.dart';

/// Google sign-in the same way the website does it: the server's own Google
/// flow (`GET /api/auth/google`) opened in a secure browser tab. The server
/// sends the result back to the app through the `aptigenerp://` scheme as a
/// one-time code, which is exchanged together with a secret only this app
/// knows (PKCE-style) — no Android OAuth client / SHA-1 setup in Google
/// Cloud is needed, unlike native Google sign-in.
class GoogleAuth {
  static const _scheme = 'aptigenerp';
  static const _client = 'erp-app';

  static bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  /// Returns the login response (`{access_token, refresh_token, user}`, same
  /// as auth/login), or null when the user closed the sign-in page.
  static Future<Map<String, dynamic>?> signIn(ApiClient api) async {
    if (!isSupported) throw ApiException(0, 'Google sign-in is not available on this device.');
    final random = Random.secure();
    final verifier = _b64url(List<int>.generate(32, (_) => random.nextInt(256)));
    final challenge = _b64url(sha256.convert(utf8.encode(verifier)).bytes);
    final url = '${AppConfig.apiPrefix}auth/google?client=$_client&challenge=$challenge';

    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: _scheme);
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return null;
      throw ApiException(0, e.message?.isNotEmpty == true ? e.message! : 'Google sign-in failed. Please try again.');
    }

    final params = Uri.parse(result).queryParameters;
    final error = params['error'];
    if (error != null && error.isNotEmpty) throw ApiException(0, error);
    final code = params['code'];
    if (code == null || code.isEmpty) throw ApiException(0, 'Google sign-in failed. Please try again.');

    final data = await api.post('auth/google/app-exchange', {'code': code, 'verifier': verifier}, isV8: false);
    if (data is! Map) throw ApiException(0, 'Google sign-in failed. Please try again.');
    return Map<String, dynamic>.from(data);
  }
}
