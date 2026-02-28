import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SurveyQuestion {
  final int id;
  final String fieldName;
  final String type;
  final String question;
  final String helpText;
  final List<String> options;
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
    this.options = const [],
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

  List<dynamic>? _masterQuestions;
  Map<String, dynamic>? _currentLanguageQuestions;
  String? _lastLoadedLanguage;

  /// Load master questions from survey_master.json
  Future<List<dynamic>> _loadMasterQuestions() async {
    if (_masterQuestions != null) return _masterQuestions!;
    
    final String jsonString = await rootBundle.loadString('assets/survey/survey_master.json');
    _masterQuestions = jsonDecode(jsonString);
    return _masterQuestions!;
  }

  /// Load language-specific questions
  Future<Map<String, dynamic>> _loadLanguageQuestions(String languageCode) async {
    if (_currentLanguageQuestions != null && _lastLoadedLanguage == languageCode) {
      return _currentLanguageQuestions!;
    }

    try {
      final String jsonString = await rootBundle.loadString(
        'assets/translations/survey_questions/$languageCode.json',
      );
      _currentLanguageQuestions = jsonDecode(jsonString);
      _lastLoadedLanguage = languageCode;
      return _currentLanguageQuestions!;
    } catch (e) {
      // Fallback to English if language not found
      return _loadLanguageQuestions('en');
    }
  }

  /// Get language code from SharedPreferences or default to 'en'
  Future<String> _getLanguageCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('preferred_language') ?? 'en';
    } catch (e) {
      return 'en';
    }
  }

  /// Merge master questions with language-specific text
  Future<List<SurveyQuestion>> getQuestions() async {
    final masterQuestions = await _loadMasterQuestions();
    final languageCode = await _getLanguageCode();
    final languageQuestions = await _loadLanguageQuestions(languageCode);

    List<SurveyQuestion> questions = [];

    for (var master in masterQuestions) {
      final fieldName = master['field_name'] as String;
      final langData = languageQuestions[fieldName] as Map<String, dynamic>? ?? {};
      
      // Parse options
      List<String> options = [];
      if (master['options'] != null) {
        options = List<String>.from(master['options']);
      }

      // Parse sub_fields for height_weight
      Map<String, dynamic>? subFields;
      if (master['sub_fields'] != null && langData['sub_fields'] != null) {
        subFields = {};
        for (var subField in master['sub_fields']) {
          final subFieldName = subField['field_name'] as String;
          final subFieldLabel = langData['sub_fields'][subFieldName] ?? subFieldName;
          subFields[subFieldName] = {
            ...subField,
            'label': subFieldLabel,
          };
        }
      }

      final question = SurveyQuestion(
        id: master['id'] as int,
        fieldName: fieldName,
        type: master['type'] as String,
        question: langData['question'] as String? ?? master['field_name'],
        helpText: langData['help_text'] as String? ?? '',
        options: options,
        required: master['required'] as bool? ?? false,
        subFields: subFields,
        noteText: langData['note_text'] as String?,
        infoText: langData['info_text'] as String?,
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
    _currentLanguageQuestions = null;
    _lastLoadedLanguage = null;
  }
}
