import 'package:shared_preferences/shared_preferences.dart';

/// Same idea as desktop's `AI_VOICE_MUTED_KEY` (aiVoice.ts) — a purely
/// client-local preference, not synced to the backend.
class AiVoicePrefs {
  static const _mutedKey = 'aptigen_ai_voice_muted';

  static Future<bool> isMuted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_mutedKey) ?? false;
  }

  static Future<void> setMuted(bool muted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mutedKey, muted);
  }
}
