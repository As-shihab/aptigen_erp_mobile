import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'ai_voice_prefs.dart';

/// Voice input/output for Aptigen AI — the mobile counterpart to desktop's
/// browser `SpeechRecognition`/`speechSynthesis` (aiVoice.ts, HeaderAiPopover.tsx's
/// `toggleVoice`). Per-utterance voice/tone/style pickers from desktop's
/// settings aren't ported (a deliberate simplification — mute on/off is the
/// one control that actually matters day to day); rate/pitch stay at the
/// device's own defaults.
class AiVoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _speechAvailable = false;
  bool _initialized = false;

  bool get isListening => _speech.isListening;

  Future<bool> initSpeech({required void Function(String error) onError}) async {
    if (_initialized) return _speechAvailable;
    _initialized = true;
    try {
      _speechAvailable = await _speech.initialize(
        onError: (error) => onError(error.errorMsg),
        onStatus: (_) {},
      );
    } catch (_) {
      _speechAvailable = false;
    }
    return _speechAvailable;
  }

  /// Starts listening, calling [onResult] with the live transcript on every
  /// update (`isFinal` true once the platform is done) — mirrors desktop's
  /// `recog.onresult` handler, which both live-updates the input box and
  /// triggers `send()` the moment a final result lands.
  Future<bool> startListening({
    required void Function(String text, bool isFinal) onResult,
    required void Function(String error) onError,
  }) async {
    final available = await initSpeech(onError: onError);
    if (!available) {
      onError('Voice input isn\'t available on this device.');
      return false;
    }
    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) => onResult(result.recognizedWords, result.finalResult),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(seconds: 30),
        ),
      );
      return true;
    } catch (_) {
      onError('Could not start listening.');
      return false;
    }
  }

  Future<void> stopListening() async {
    if (_speech.isListening) await _speech.stop();
  }

  Future<bool> isMuted() => AiVoicePrefs.isMuted();

  Future<void> setMuted(bool muted) async {
    await AiVoicePrefs.setMuted(muted);
    if (muted) await _tts.stop();
  }

  /// Speaks [text] unless voice output is muted — always cancels whatever
  /// was playing first, same as desktop's `speechSynthesis.cancel()` before
  /// every `speak()`.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    if (await isMuted()) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() => _tts.stop();

  void dispose() {
    _speech.cancel();
    _tts.stop();
  }
}
