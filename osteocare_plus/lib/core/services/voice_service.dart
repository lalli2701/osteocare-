import 'package:flutter_tts/flutter_tts.dart';

enum VoiceLanguage {
  english('en-IN', 'en'),
  hindi('hi-IN', 'hi'),
  telugu('te-IN', 'te');

  final String ttsCode;
  final String languageCode;

  const VoiceLanguage(this.ttsCode, this.languageCode);

  static VoiceLanguage fromLanguageCode(String code) {
    return VoiceLanguage.values.firstWhere(
      (lang) => lang.languageCode == code,
      orElse: () => VoiceLanguage.english,
    );
  }
}

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  
  factory VoiceService() {
    return _instance;
  }
  
  VoiceService._internal();

  final FlutterTts _tts = FlutterTts();
  VoiceLanguage _currentLanguage = VoiceLanguage.english;
  bool _isSpeaking = false;

  /// Initialize TTS engine
  Future<void> initialize() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      await setLanguage(VoiceLanguage.english);
    } catch (e) {
      // Error initializing TTS
    }
  }

  /// Set TTS language dynamically
  Future<void> setLanguage(VoiceLanguage language) async {
    try {
      _currentLanguage = language;
      await _tts.setLanguage(language.ttsCode);
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.5);
    } catch (e) {
      // Error setting TTS language
    }
  }

  /// Change language (e.g., when user switches in profile)
  Future<void> switchLanguage(String languageCode) async {
    await stop();
    final language = VoiceLanguage.fromLanguageCode(languageCode);
    await setLanguage(language);
  }

  /// Speak text dynamically
  Future<void> speak(String text) async {
    try {
      if (_isSpeaking) {
        await stop();
      }
      _isSpeaking = true;
      await _tts.speak(text);
    } catch (e) {
      _isSpeaking = false;
    }
  }

  /// Stop speaking
  Future<void> stop() async {
    try {
      await _tts.stop();
      _isSpeaking = false;
    } catch (e) {
      // Error stopping TTS
    }
  }

  /// Check if currently speaking
  bool get isSpeaking => _isSpeaking;

  /// Get current language
  VoiceLanguage get currentLanguage => _currentLanguage;

  /// Build voice script for question
  String buildQuestionVoiceScript(
    int currentIndex,
    int totalQuestions,
    String questionText,
    List<String> options,
  ) {
    final progressText = _getProgressText(currentIndex, totalQuestions);
    final optionsText = _getOptionsText(options);
    return "$progressText. $questionText $optionsText";
  }

  String _getProgressText(int current, int total) {
    switch (_currentLanguage) {
      case VoiceLanguage.english:
        return "Question $current of $total";
      case VoiceLanguage.hindi:
        return "$total में से ${_getHindiNumber(current)}वाँ प्रश्न";
      case VoiceLanguage.telugu:
        return "$total లో ${_getTeluguNumber(current)}వ ప్రశ్న";
    }
  }

  String _getOptionsText(List<String> options) {
    switch (_currentLanguage) {
      case VoiceLanguage.english:
        return "You may answer by saying ${options.join(' or ')}.";
      case VoiceLanguage.hindi:
        return "कृपया ${options.join(' या ')} कहें।";
      case VoiceLanguage.telugu:
        return "దయచేసి ${options.join(' లేదా ')} అని చెప్పండి.";
    }
  }

  String _getHindiNumber(int n) {
    const hindiNumbers = [
      "शून्य", "प्रथम", "द्वितीय", "तृतीय", "चतुर्थ", "पंचम",
      "षष्ठ", "सप्तम", "अष्टम", "नवम", "दशम", "एकादश",
      "द्वादश", "त्रयोदश", "चतुर्दश", "पंद्रह"
    ];
    return hindiNumbers.length > n ? hindiNumbers[n] : n.toString();
  }

  String _getTeluguNumber(int n) {
    const teluguNumbers = [
      "జీరో", "1వ", "2వ", "3వ", "4వ", "5వ",
      "6వ", "7వ", "8వ", "9వ", "10వ", "11వ",
      "12వ", "13వ", "14వ", "15వ"
    ];
    return teluguNumbers.length > n ? teluguNumbers[n] : n.toString();
  }

  /// Get number prompt for voice input
  String getNumberPrompt(String fieldName) {
    switch (_currentLanguage) {
      case VoiceLanguage.english:
        return "Please say your $fieldName as a number.";
      case VoiceLanguage.hindi:
        return "कृपया अपना $fieldName संख्या में बताएं।";
      case VoiceLanguage.telugu:
        return "దయచేసి మీ $fieldName సంఖ్యగా చెప్పండి.";
    }
  }

  /// Get confirmation prompt
  String getConfirmationPrompt(String userAnswer) {
    switch (_currentLanguage) {
      case VoiceLanguage.english:
        return "You said: $userAnswer. Is that correct?";
      case VoiceLanguage.hindi:
        return "आपने कहा: $userAnswer। क्या यह सही है?";
      case VoiceLanguage.telugu:
        return "మీరు చెప్పారు: $userAnswer. ఇది సరైనదేనా?";
    }
  }

  /// Get retry prompt
  String getRetryPrompt() {
    switch (_currentLanguage) {
      case VoiceLanguage.english:
        return "I could not understand. Please try again.";
      case VoiceLanguage.hindi:
        return "मुझे समझ नहीं आया। कृपया पुनः प्रयास करें।";
      case VoiceLanguage.telugu:
        return "నేను అర్థం చేసుకోలేకపోయాను. దయచేసి మళ్లీ ప్రయత్నించండి.";
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
    await _tts.stop();
  }
}
