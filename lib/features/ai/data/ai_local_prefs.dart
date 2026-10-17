import 'package:shared_preferences/shared_preferences.dart';

/// Same idea as desktop's `localStorage['aptigen_ai_last_session_id']` —
/// resume the last chat on reopen instead of always starting fresh.
class AiLocalPrefs {
  static const _lastSessionKey = 'aptigen_ai_last_session_id';

  static Future<int?> getLastSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_lastSessionKey);
    return (id != null && id > 0) ? id : null;
  }

  static Future<void> setLastSessionId(int? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_lastSessionKey);
    } else {
      await prefs.setInt(_lastSessionKey, id);
    }
  }
}
