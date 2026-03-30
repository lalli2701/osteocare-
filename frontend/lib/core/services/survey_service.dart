import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SurveyQuestion {
  final int id;
  final String fieldName;
  final String type;
  final String question;
  final String helpText;
  final List<Map<String, dynamic>>? options; // Changed to support option metadata
  final bool required;
  final Map<String, dynamic>? subFields;
  final String? noteText;
  final String? infoText;

  SurveyQuestion({
    required this.id,
    required this.fieldName,
    required this.type,
    required this.question,
    required this.helpText,
    this.options,
    this.required = false,
    this.subFields,
    this.noteText,
    this.infoText,
  });
}

class SurveyService {
  static final SurveyService _instance = SurveyService._internal();
  
  factory SurveyService() {
    return _instance;
  }
  
  SurveyService._internal();

  String _humanizeFieldName(String fieldName) {
    final spaced = fieldName.replaceAll('_', ' ').trim();
    if (spaced.isEmpty) {
      return 'Question';
    }
    return spaced
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  List<dynamic>? _masterQuestions;
  Map<String, dynamic>? _englishQuestions;
  Map<String, dynamic>? _currentLanguageQuestions;
  String? _lastLoadedLanguage;

  String _normalizeLanguageCode(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'en';
    }

    final parts = normalized.split(RegExp('[-_]'));
    final code = parts.first;
    if (code == 'en' || code == 'hi' || code == 'te') {
      return code;
    }
    return 'en';
  }

  Future<Map<String, dynamic>> _loadEnglishQuestions() async {
    if (_englishQuestions != null) {
      return _englishQuestions!;
    }

    try {
      final String jsonString = await rootBundle.loadString(
        'assets/survey/survey_questions/en.json',
      );
      final decoded = jsonDecode(jsonString);
      if (decoded is Map<String, dynamic>) {
        _englishQuestions = decoded;
        return _englishQuestions!;
      }
    } catch (_) {
      // Keep graceful fallback behavior when bundled assets are unavailable.
    }

    _englishQuestions = <String, dynamic>{};
    return _englishQuestions!;
  }

  /// Load master questions from survey_master.json
  Future<List<dynamic>> _loadMasterQuestions() async {
    if (_masterQuestions != null) return _masterQuestions!;
    
    final String jsonString = await rootBundle.loadString('assets/survey/survey_master.json');
    final decoded = jsonDecode(jsonString);
    if (decoded is! List) {
      throw const FormatException('survey_master.json must contain a JSON array');
    }
    _masterQuestions = decoded;
    return _masterQuestions!;
  }

  /// Load language-specific questions
  Future<Map<String, dynamic>> _loadLanguageQuestions(String languageCode) async {
    if (_currentLanguageQuestions != null && _lastLoadedLanguage == languageCode) {
      return _currentLanguageQuestions!;
    }

    try {
      final String jsonString = await rootBundle.loadString(
        'assets/survey/survey_questions/$languageCode.json',
      );
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Language survey file must contain a JSON object');
      }
      _currentLanguageQuestions = decoded;
      _lastLoadedLanguage = languageCode;
      return _currentLanguageQuestions!;
    } catch (e) {
      // Fallback to English if language not found
      if (languageCode == 'en') {
        _currentLanguageQuestions = <String, dynamic>{};
        _lastLoadedLanguage = 'en';
        return _currentLanguageQuestions!;
      }
      return _loadLanguageQuestions('en');
    }
  }

  /// Get language code from SharedPreferences or default to 'en'
  Future<String> _getLanguageCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _normalizeLanguageCode(prefs.getString('preferred_language') ?? 'en');
    } catch (e) {
      return 'en';
    }
  }

  /// Merge master questions with language-specific text
  Future<List<SurveyQuestion>> getQuestions() async {
    final masterQuestions = await _loadMasterQuestions();
    final englishQuestions = await _loadEnglishQuestions();
    final languageCode = await _getLanguageCode();
    final languageQuestions = languageCode == 'en'
        ? englishQuestions
        : await _loadLanguageQuestions(languageCode);

    List<SurveyQuestion> questions = [];

    for (final masterRaw in masterQuestions) {
      if (masterRaw is! Map<String, dynamic>) {
        continue;
      }

      final fieldName = masterRaw['field_name']?.toString();
      if (fieldName == null || fieldName.isEmpty) {
        continue;
      }

      final enDataRaw = englishQuestions[fieldName];
      final enData = enDataRaw is Map<String, dynamic>
          ? enDataRaw
          : <String, dynamic>{};

      final langDataRaw = languageQuestions[fieldName];
      final langData = langDataRaw is Map<String, dynamic>
          ? langDataRaw
          : <String, dynamic>{};
      
      // Parse options with language translations
      List<Map<String, dynamic>>? options;
      if (masterRaw['options'] is List) {
        options = [];
        final masterOptions = masterRaw['options'] as List;
        final langOptions = (langData['options'] as Map<String, dynamic>?) ?? {};
        final enOptions = (enData['options'] as Map<String, dynamic>?) ?? {};
        
        for (var optValue in masterOptions) {
          options.add({
            'value': optValue,
            'label': langOptions[optValue] ?? enOptions[optValue] ?? optValue,
          });
        }
      }

      // Parse sub_fields for height_weight
      Map<String, dynamic>? subFields;
      if (masterRaw['sub_fields'] is List && langData['sub_fields'] is Map) {
        subFields = {};
        for (final subField in (masterRaw['sub_fields'] as List)) {
          if (subField is! Map<String, dynamic>) {
            continue;
          }
          final subFieldName = subField['field_name']?.toString();
          if (subFieldName == null || subFieldName.isEmpty) {
            continue;
          }
          final localizedSubFields = langData['sub_fields'] as Map;
          final englishSubFields = (enData['sub_fields'] is Map)
              ? enData['sub_fields'] as Map
              : const {};
          final subFieldLabel = localizedSubFields[subFieldName] ??
              englishSubFields[subFieldName] ??
              subFieldName;
          subFields[subFieldName] = {
            ...subField,
            'label': subFieldLabel,
          };
        }
      } else if (masterRaw['sub_fields'] is List && enData['sub_fields'] is Map) {
        subFields = {};
        final englishSubFields = enData['sub_fields'] as Map;
        for (final subField in (masterRaw['sub_fields'] as List)) {
          if (subField is! Map<String, dynamic>) {
            continue;
          }
          final subFieldName = subField['field_name']?.toString();
          if (subFieldName == null || subFieldName.isEmpty) {
            continue;
          }
          final subFieldLabel = englishSubFields[subFieldName] ?? subFieldName;
          subFields[subFieldName] = {
            ...subField,
            'label': subFieldLabel,
          };
        }
      }

      final question = SurveyQuestion(
        id: (masterRaw['id'] is num)
            ? (masterRaw['id'] as num).toInt()
            : (questions.length + 1),
        fieldName: fieldName,
        type: masterRaw['type']?.toString() ?? 'text',
        question: (langData['question'] ?? enData['question'])?.toString() ??
          _humanizeFieldName(fieldName),
        helpText: (langData['help_text'] ?? enData['help_text'])?.toString() ?? '',
        options: options,
        required: masterRaw['required'] == true,
        subFields: subFields,
        noteText: (langData['note_text'] ?? enData['note_text'])?.toString(),
        infoText: (langData['info_text'] ?? enData['info_text'])?.toString(),
      );

      questions.add(question);
    }

    return questions;
  }

  /// Get a specific question by field name
  Future<SurveyQuestion?> getQuestionByFieldName(String fieldName) async {
    final questions = await getQuestions();
    try {
      return questions.firstWhere((q) => q.fieldName == fieldName);
    } catch (e) {
      return null;
    }
  }

  /// Get translated option label for a given value
  String getOptionLabel(String fieldName, String value) {
    final langQuestions = _currentLanguageQuestions;
    if (langQuestions == null) return value;

    try {
      final fieldData = langQuestions[fieldName] as Map<String, dynamic>?;
      if (fieldData == null) return value;

      final options = fieldData['options'] as Map<String, dynamic>?;
      if (options == null) return value;

      return options[value] as String? ?? value;
    } catch (e) {
      return value;
    }
  }

  /// Reload questions for new language
  Future<void> reloadForLanguage(String languageCode) async {
    _currentLanguageQuestions = null;
    _lastLoadedLanguage = null;
    await _loadLanguageQuestions(languageCode);
  }

  /// Clear cache
  void clearCache() {
    _masterQuestions = null;
    _englishQuestions = null;
    _currentLanguageQuestions = null;
    _lastLoadedLanguage = null;
  }
}
