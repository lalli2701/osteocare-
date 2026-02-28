import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechKeywordMapping {
  final List<String> yesKeywords;
  final List<String> noKeywords;
  final List<String> alternativeKeywords;

  SpeechKeywordMapping({
    required this.yesKeywords,
    required this.noKeywords,
    this.alternativeKeywords = const [],
  });
}

class MultilingualKeywordMap {
  static final Map<String, SpeechKeywordMapping> mapping = {
    'en': SpeechKeywordMapping(
      yesKeywords: ['yes', 'yeah', 'yup', 'sure', 'okay', 'ok', 'correct', 'right', 'affirmative'],
      noKeywords: ['no', 'nope', 'nah', 'negative', 'never', 'not', 'false'],
      alternativeKeywords: ['maybe', 'perhaps', 'possibly'],
    ),
    'hi': SpeechKeywordMapping(
      yesKeywords: ['haan', 'haa', 'ham', 'bilkul', 'theek', 'sahi', 'haan beta', 'bilwul'],
      noKeywords: ['nahi', 'nahin', 'na', 'bilkul nahi', 'kabhi nahi', 'mat', 'naa'],
      alternativeKeywords: ['shayad', 'sambhav', 'ho sakta hai'],
    ),
    'te': SpeechKeywordMapping(
      yesKeywords: ['avunu', 'aavanu', 'oka', 'kosu', 'kottukunnanu', 'tanmaya', 'thelusu'],
      noKeywords: ['kaadu', 'kadu', 'ledu', 'lenu', 'enduku', 'akada', 'vyatireka'],
      alternativeKeywords: ['sambhavamga', 'chala', 'vantava'],
    ),
  };

  static SpeechKeywordMapping getMapping(String languageCode) {
    return mapping[languageCode] ?? mapping['en']!;
  }
}

enum RecognitionResult {
  yes,
  no,
  alternative,
  unknown,
}

class SpeechRecognitionService {
  static final SpeechRecognitionService _instance = SpeechRecognitionService._internal();
  
  factory SpeechRecognitionService() {
    return _instance;
  }
  
  SpeechRecognitionService._internal();

  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isListening = false;
  String _currentLanguageCode = 'en';
  String _recognizedTranscript = '';

  /// Initialize speech recognition
  Future<bool> initialize() async {
    try {
      final available = await _speechToText.initialize(
        onError: (error) {
          // Speech recognition error
        },
        onStatus: (status) {
          // Speech recognition status changed
        },
      );
      return available;
    } catch (e) {
      return false;
    }
  }

  /// Set current language for recognition
  Future<void> setLanguage(String languageCode) async {
    _currentLanguageCode = languageCode;
    try {
      // Map app language codes to speech recognition locales
      _mapToSpeechLocale(languageCode);
    } catch (e) {
      // Error setting speech language
    }
  }

  /// Map app language code to speech recognition locale
  String _mapToSpeechLocale(String languageCode) {
    switch (languageCode) {
      case 'en':
        return 'en_IN';
      case 'hi':
        return 'hi_IN';
      case 'te':
        return 'te_IN';
      default:
        return 'en_IN';
    }
  }

  /// Start listening for speech input
  Future<void> startListening({
    required Function(String transcript) onResult,
    required Function() onError,
  }) async {
    if (_isListening) return;

    try {
      _isListening = true;
      final localeId = _mapToSpeechLocale(_currentLanguageCode);
      
      await _speechToText.listen(
        localeId: localeId,
        onSoundLevelChange: (level) {
          // Can be used for audio visualization
        },
        onResult: (result) {
          _recognizedTranscript = result.recognizedWords.toLowerCase();
          onResult(_recognizedTranscript);
          
          if (result.finalResult) {
            _isListening = false;
          }
        },
      );
    } catch (e) {
      _isListening = false;
      onError();
    }
  }

  /// Stop listening
  Future<void> stopListening() async {
    try {
      await _speechToText.stop();
      _isListening = false;
    } catch (e) {
      // Error stopping speech recognition
    }
  }

  /// Process transcript and extract answer
  RecognitionResult parseYesNoAnswer(String transcript) {
    final normalizedTranscript = transcript.toLowerCase().trim();
    final mapping = MultilingualKeywordMap.getMapping(_currentLanguageCode);

    // Check yes keywords
    for (final keyword in mapping.yesKeywords) {
      if (normalizedTranscript.contains(keyword)) {
        return RecognitionResult.yes;
      }
    }

    // Check no keywords
    for (final keyword in mapping.noKeywords) {
      if (normalizedTranscript.contains(keyword)) {
        return RecognitionResult.no;
      }
    }

    // Check alternative keywords (for select fields)
    for (final keyword in mapping.alternativeKeywords) {
      if (normalizedTranscript.contains(keyword)) {
        return RecognitionResult.alternative;
      }
    }

    return RecognitionResult.unknown;
  }

  /// Extract number from transcript
  /// Returns null if no number found
  int? extractNumber(String transcript) {
    // Match numbers: 1, 2, three, teen, twenty, etc.
    final numberPattern = RegExp(r'\d+');
    final match = numberPattern.firstMatch(transcript);
    
    if (match != null) {
      return int.tryParse(match.group(0)!);
    }

    // For Hindi numbers (basic support)
    if (_currentLanguageCode == 'hi') {
      return _parseHindiNumber(transcript);
    }

    // For Telugu numbers (basic support)
    if (_currentLanguageCode == 'te') {
      return _parseTeluguNumber(transcript);
    }

    return null;
  }

  /// Parse written Hindi numbers
  int? _parseHindiNumber(String transcript) {
    const hindiNumberMap = {
      'ek': 1, 'do': 2, 'teen': 3, 'char': 4, 'paanch': 5,
      'chhah': 6, 'saat': 7, 'aath': 8, 'nau': 9, 'das': 10,
    };
    
    for (final entry in hindiNumberMap.entries) {
      if (transcript.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Parse written Telugu numbers (basic)
  int? _parseTeluguNumber(String transcript) {
    const teluguNumberMap = {
      'oka': 1, 'rendo': 2, 'moodu': 3, 'nalu': 4, 'idi': 5,
      'aaru': 6, 'eadu': 7, 'enimidhi': 8, 'tommidi': 9, 'padi': 10,
    };
    
    for (final entry in teluguNumberMap.entries) {
      if (transcript.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Get user-friendly display text for recognized answer
  String getDisplayText(String transcript, RecognitionResult result) {
    switch (result) {
      case RecognitionResult.yes:
        switch (_currentLanguageCode) {
          case 'en':
            return 'Yes';
          case 'hi':
            return 'हाँ';
          case 'te':
            return 'అవును';
          default:
            return 'Yes';
        }
      case RecognitionResult.no:
        switch (_currentLanguageCode) {
          case 'en':
            return 'No';
          case 'hi':
            return 'नहीं';
          case 'te':
            return 'లేదు';
          default:
            return 'No';
        }
      case RecognitionResult.alternative:
        return transcript;
      case RecognitionResult.unknown:
        return transcript;
    }
  }

  /// Check if ready to listen
  bool get isAvailable => _speechToText.isAvailable;
  bool get isListening => _isListening;
  String get lastTranscript => _recognizedTranscript;
  String get currentLanguageCode => _currentLanguageCode;

  /// Dispose resources
  Future<void> dispose() async {
    await stopListening();
  }
}
