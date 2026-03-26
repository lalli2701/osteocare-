import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TtsService {
  TtsService._internal();

  static final TtsService instance = TtsService._internal();

  final FlutterTts _tts = FlutterTts();

  String _mapToTtsLocale(String code) {
    switch (code.toLowerCase()) {
      case 'hi':
        return 'hi-IN';
      case 'te':
        return 'te-IN';
      case 'en':
      default:
        return 'en-IN';
    }
  }

  Future<String> _getTtsLanguageCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = (prefs.getString('preferred_language') ?? 'en');
    return _mapToTtsLocale(code);
  }

  Future<void> configure({String? langCode}) async {
    final ttsLanguage = langCode == null
        ? await _getTtsLanguageCode()
        : _mapToTtsLocale(langCode);
    await _tts.setLanguage(ttsLanguage);
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
  }

  Future<void> speakTip(String text, {String? langCode}) async {
    await configure(langCode: langCode);
    await _tts.speak(text);
  }
}

