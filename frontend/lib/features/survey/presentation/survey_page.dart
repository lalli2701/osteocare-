import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../presentation/result_page.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/user_session.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/local_survey_store.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/speech_recognition_service.dart';
import '../../../core/services/survey_service.dart';
import '../../../core/services/survey_sync_service.dart';
import '../../../core/services/voice_service.dart';

class SurveyPage extends StatefulWidget {
  const SurveyPage({super.key});

  static const routePath = '/survey';

  @override
  State<SurveyPage> createState() => _SurveyPageState();
}

class _SurveyPageState extends State<SurveyPage> {
  late SurveyService _surveyService;
  List<SurveyQuestion> _questions = [];
  final Map<String, dynamic> _formData = {};
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  int _currentQuestionIndex = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _voiceEnabled = true;
  bool _isListening = false;
  bool _isSpeakingQuestion = false;
  String? _voiceStatusMessage;
  Timer? _autoNextTimer;
  String? _questionValidationError;
  late Locale _currentLocale;
  bool _localeInitialized = false;
  late SpeechRecognitionService _speechService;
  late PermissionService _permissionService;

  static const _riskLevelKey = 'risk_level';
  static const _nextReassessmentDateKey = 'next_reassessment_date';
  static const _reminderEnabledKey = 'reminder_enabled';
  static const _voiceEnabledKey = 'voice_enabled';

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newLocale = context.locale;
    if (!_localeInitialized) {
      _currentLocale = newLocale;
      _localeInitialized = true;
      _initializeSurvey();
      return;
    }
    if (newLocale != _currentLocale) {
      _currentLocale = newLocale;
      unawaited(_speechService.setLanguage(newLocale.languageCode));
      _loadQuestions();
    }
  }

  Future<void> _initializeSurvey() async {
    try {
      // Initialize core service and load survey questions first.
      // Voice and sync should not block form rendering on mobile.
      _surveyService = SurveyService();
      _speechService = SpeechRecognitionService();
      _permissionService = PermissionService();

      // Load voice preference
      final prefs = await SharedPreferences.getInstance();
      _voiceEnabled = prefs.getBool(_voiceEnabledKey) ?? true;

      await _speechService.initialize();
      await _speechService.setLanguage(context.locale.languageCode);

      // Load questions from SurveyService
      await _loadQuestions();

      // Background initialization should not keep survey in loading state.
      unawaited(_initializeBackgroundServices());
    } catch (e) {
      setState(() {
        _errorMessage = 'Error initializing survey: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeBackgroundServices() async {
    try {
      await VoiceService().initialize().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Voice features remain optional if initialization fails.
    }

    try {
      final userId = await SurveySyncService.instance.resolveEffectiveUserId();
      await SurveySyncService.instance
          .syncPendingSurveys(userId: userId)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Sync can be retried later and should not block survey usage.
    }
  }

  Future<void> _loadQuestions() async {
    try {
      // Get questions from SurveyService (which handles master + translations)
      final questions = await _surveyService.getQuestions();

      setState(() {
        _questions = questions;
        _isLoading = false;

        // Initialize form data with empty values
        for (var q in _questions) {
          _formData[q.fieldName] = null;
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading survey: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _nextQuestion() {
    final currentQ = _questions[_currentQuestionIndex];
    final validationError = _validateCurrentQuestion(currentQ);

    if (validationError != null) {
      setState(() {
        _questionValidationError = validationError;
      });
      return;
    }

    setState(() {
      _questionValidationError = null;
    });

    _autoNextTimer?.cancel();

    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() => _currentQuestionIndex++);
    } else {
      _submitSurvey();
    }
  }

  String? _validateCurrentQuestion(SurveyQuestion question) {
    if (question.fieldName == 'height_weight') {
      final feet = (_formData['height_feet'] as num?)?.toDouble();
      final inches = (_formData['height_inches'] as num?)?.toDouble();
      final weight = (_formData['weight_kg'] as num?)?.toDouble();

      if (question.required &&
          (feet == null || inches == null || weight == null || weight <= 0)) {
        return 'Please enter height (feet and inches) and weight';
      }

      if (feet != null && inches != null && weight != null && weight > 0) {
        final heightCm = (feet * 30.48) + (inches * 2.54);
        final heightM = heightCm / 100;
        final bmi = heightM > 0 ? weight / (heightM * heightM) : 0;
        if (bmi < 10 || bmi > 60) {
          return 'Please enter valid height/weight (BMI must be between 10 and 60)';
        }
      }
      return null;
    }

    final value = _formData[question.fieldName];
    final hasValue = value != null && value.toString().trim().isNotEmpty;

    if (question.required && !hasValue) {
      return 'Please answer this question before continuing';
    }

    if (question.fieldName == 'age' && hasValue) {
      final age = (value is num)
          ? value.toDouble()
          : double.tryParse(value.toString());
      if (age == null || age < 18 || age > 100) {
        return 'Age must be between 18 and 100';
      }
    }

    return null;
  }

  String? _ageValidationMessage(dynamic value) {
    if (value == null) {
      return null;
    }
    final age = (value is num)
        ? value.toDouble()
        : double.tryParse(value.toString());
    if (age == null) {
      return 'Please enter a valid age';
    }
    if (age < 18 || age > 100) {
      return 'Age must be between 18 and 100';
    }
    return null;
  }

  String? _heightWeightValidationMessage() {
    final feet = (_formData['height_feet'] as num?)?.toDouble();
    final inches = (_formData['height_inches'] as num?)?.toDouble();
    final weight = (_formData['weight_kg'] as num?)?.toDouble();

    if (feet == null || inches == null || weight == null || weight <= 0) {
      return null;
    }

    final heightCm = (feet * 30.48) + (inches * 2.54);
    final heightM = heightCm / 100;
    final bmi = heightM > 0 ? weight / (heightM * heightM) : 0;
    if (bmi < 10 || bmi > 60) {
      return 'Please enter valid height/weight (BMI must be between 10 and 60)';
    }
    return null;
  }

  void _scheduleAutoNextIfOptional(SurveyQuestion question) {
    if (question.required) {
      return;
    }
    if (_currentQuestionIndex >= _questions.length - 1) {
      return;
    }

    _autoNextTimer?.cancel();
    _autoNextTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) {
        return;
      }
      if (_questions[_currentQuestionIndex].fieldName != question.fieldName) {
        return;
      }
      if (_validateCurrentQuestion(question) == null) {
        _nextQuestion();
      }
    });
  }

  void _previousQuestion() {
    if (_currentQuestionIndex > 0) {
      setState(() => _currentQuestionIndex--);
    }
  }

  bool _isCurrentQuestionComplete() {
    final currentQ = _questions[_currentQuestionIndex];

    if (!currentQ.required) {
      return true;
    }

    if (currentQ.fieldName == 'height_weight') {
      final feet = _formData['height_feet'];
      final inches = _formData['height_inches'];
      final weight = _formData['weight_kg'];
      return feet != null && inches != null && weight != null && weight > 0;
    }

    return _formData[currentQ.fieldName] != null;
  }

  dynamic _normalizeYesNoForField(String fieldName, dynamic value) {
    if (value == null) {
      return '';
    }

    if (value is bool) {
      return fieldName == 'arthritis' ? value : (value ? 'Yes' : 'No');
    }

    if (value is num) {
      if (value == 1) {
        return fieldName == 'arthritis' ? true : 'Yes';
      }
      if (value == 0) {
        return fieldName == 'arthritis' ? false : 'No';
      }
    }

    final raw = value.toString().trim().toLowerCase();
    if (raw.isEmpty ||
        raw == 'null' ||
        raw == 'none' ||
        raw == 'recognitionresult.unknown') {
      return '';
    }

    const yesValues = {
      'yes',
      'y',
      'true',
      '1',
      'recognitionresult.yes',
      'affirmative',
      'correct',
      'right',
    };
    const noValues = {
      'no',
      'n',
      'false',
      '0',
      'recognitionresult.no',
      'negative',
    };

    if (yesValues.contains(raw)) {
      return fieldName == 'arthritis' ? true : 'Yes';
    }
    if (noValues.contains(raw)) {
      return fieldName == 'arthritis' ? false : 'No';
    }

    return fieldName == 'arthritis' ? false : '';
  }

  Map<String, dynamic> _buildNormalizedSurveyData() {
    final normalized = Map<String, dynamic>.from(_formData);

    const yesNoFields = [
      'memory_issue',
      'mobility_climb',
      'stand_long',
      'activity_limited',
      'arthritis',
      'thyroid',
      'lung_disease',
      'heart_failure',
      'smoking',
    ];

    for (final field in yesNoFields) {
      normalized[field] = _normalizeYesNoForField(field, normalized[field]);
    }

    const optionalSelectFields = [
      'alcohol',
      'general_health',
      'calcium_frequency',
    ];

    for (final field in optionalSelectFields) {
      final value = normalized[field];
      if (value == null) {
        normalized[field] = '';
      }
    }

    return normalized;
  }

  Future<void> _submitSurvey() async {
    setState(() => _isSubmitting = true);

    final userId = await SurveySyncService.instance.resolveEffectiveUserId();
    final normalizedSurveyData = _buildNormalizedSurveyData();

    try {
      final localRecord = await LocalSurveyStore.instance.insertSurvey(
        userId: userId,
        surveyData: normalizedSurveyData,
      );
      final localRecordId = (localRecord['id'] as num).toInt();
      final localId = localRecord['local_id']?.toString() ?? '';

      // Prepare survey data for submission
      final Map<String, dynamic> surveyPayload = {
        'local_id': localId,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'survey_data': normalizedSurveyData,
      };

      final response = await http
          .post(
            Uri.parse('${AuthService.baseUrl}/survey/submit'),
            headers: {
              'Content-Type': 'application/json',
              'X-User-Id': userId,
              'X-API-Key': 'dev-key',
            },
            body: jsonEncode(surveyPayload),
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Request timeout'),
          );

      if (response.statusCode == 200) {
        final result = Map<String, dynamic>.from(jsonDecode(response.body));
        await LocalSurveyStore.instance.markSynced(
          id: localRecordId,
          result: result,
        );

        // Do not block result navigation on non-critical background work.
        unawaited(
          SurveySyncService.instance.syncPendingSurveys(userId: userId),
        );
        unawaited(_persistAndScheduleReassessment(result));

        if (mounted) {
          setState(() => _isSubmitting = false);
          context.go(ResultPage.routePath, extra: result);
        }
      } else {
        String backendError =
            'Survey submission failed: ${response.statusCode}';
        try {
          final errJson = jsonDecode(response.body);
          backendError = errJson['error']?.toString() ?? backendError;
        } catch (_) {
          // Keep default error message
        }
        throw Exception(backendError);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved offline. Data will sync automatically when internet is available. (${e.toString()})',
            ),
          ),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  int _getReassessmentDays(String riskLevel) {
    switch (riskLevel) {
      case 'Low':
        return 180;
      case 'Moderate':
        return 90;
      case 'High':
        return 30;
      default:
        return 90;
    }
  }

  Future<void> _persistAndScheduleReassessment(
    Map<String, dynamic> result,
  ) async {
    final riskLevel = (result['risk_level']?.toString() ?? 'Moderate').trim();
    final normalizedRisk = riskLevel.toLowerCase();
    final backendNextDate = result['next_reassessment_date']?.toString();

    DateTime nextDate;
    if (backendNextDate != null && backendNextDate.isNotEmpty) {
      nextDate = DateTime.parse(backendNextDate);
    } else {
      nextDate = DateTime.now().add(
        Duration(days: _getReassessmentDays(riskLevel)),
      );
    }

    await _storage.write(key: _riskLevelKey, value: riskLevel);
    await _storage.write(
      key: _nextReassessmentDateKey,
      value: nextDate.toIso8601String(),
    );
    await _storage.write(key: _reminderEnabledKey, value: 'true');

    // Save survey history to Firestore
    try {
      String? uid = UserSession.instance.userId?.trim();
      if (uid == null || uid.isEmpty) {
        final userData = await AuthService.instance.getUserData();
        uid = userData?['id']?.toString().trim();
        if (uid != null && uid.isNotEmpty) {
          UserSession.instance.userId = uid;
        }
      }

      if (uid != null && uid.isNotEmpty) {
        final riskScore = (result['risk_score'] as num?)?.toDouble() ?? 0.0;
        final probability = ((result['probability'] as num?)?.toDouble() ??
                (riskScore / 100))
            .clamp(0.0, 1.0);
        final topFactors = List<String>.from(
          result['top_factors'] ?? result['factors'] ?? const <String>[],
        );
        final recommendedTasks = List<String>.from(
          result['recommended_tasks'] ??
              result['recommendations'] ??
              result['tasks'] ??
              const <String>[],
        );
        final timeGroups = Map<String, dynamic>.from(
          result['time_groups'] ?? const <String, dynamic>{},
        );
        final topFactorsWithWeight = List<Map<String, dynamic>>.from(
          result['top_factors_with_weight'] ?? const <Map<String, dynamic>>[],
        );
        
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('surveys')
            .add({
              'riskLevel': riskLevel,
              'riskScore': riskScore,
              'probability': probability,
              'confidence': (result['confidence'] as num?)?.toDouble() ?? 0.5,
              'confidenceLabel': result['confidence_label'] ?? 'Medium',
              'confidenceBand': result['confidence_band'] ?? 'Medium',
              'confidenceReason': result['confidence_reason'] ?? '',
              'primaryAction': result['primary_action'] ?? '',
              'topFactors': topFactors,
              'recommendedTasks': recommendedTasks,
              'topFactorsWithWeight': topFactorsWithWeight,
              'timeGroups': timeGroups,
              // Backward-compatible mirrors for older readers.
              'tasks': recommendedTasks,
              'factors': topFactors,
              'recommendations': recommendedTasks,
              // Preserve complete payload for detail/result screen reuse.
              'result': result,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
      }
    } catch (e) {
      debugPrint('Failed to save survey history to Firestore: $e');
      // Don't block execution if Firestore save fails
    }

    try {
      await NotificationService.instance.scheduleReassessmentReminder(
        when: DateTime(nextDate.year, nextDate.month, nextDate.day, 9, 0),
      );

      if (normalizedRisk == 'high') {
        final doctorReminderAt = DateTime.now().add(const Duration(days: 1));
        await NotificationService.instance.scheduleDoctorConsultReminder(
          when: DateTime(
            doctorReminderAt.year,
            doctorReminderAt.month,
            doctorReminderAt.day,
            10,
            0,
          ),
          title: 'doctor_consult_reminder_title'.tr(),
          body: 'doctor_consult_reminder_body'.tr(),
        );
      } else {
        await NotificationService.instance.cancelDoctorConsultReminder();
      }
    } catch (_) {
      // Reminder failures should never block survey completion/results display.
    }
  }

  Future<void> _speakCurrentQuestion(SurveyQuestion question) async {
    if (!_voiceEnabled || _isSpeakingQuestion) {
      return;
    }

    final script = VoiceService().buildQuestionVoiceScript(
      question.question,
      _currentQuestionIndex + 1,
      _questions.length,
      options: _getAnswerOptions(question),
    );

    setState(() {
      _isSpeakingQuestion = true;
      _voiceStatusMessage = null;
    });

    try {
      await VoiceService().speak(script);
    } catch (_) {
      if (mounted) {
        setState(() {
          _voiceStatusMessage = 'Unable to read this question right now';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSpeakingQuestion = false;
        });
      }
    }
  }

  Future<void> _captureVoiceAnswer(SurveyQuestion question) async {
    if (!_voiceEnabled || _isListening) {
      return;
    }

    final hasPermission = await _permissionService.ensureMicrophonePermission();
    if (!hasPermission) {
      if (mounted) {
        setState(() {
          _voiceStatusMessage =
              'Microphone permission is required to capture voice answers';
        });
      }
      return;
    }

    setState(() {
      _isListening = true;
      _voiceStatusMessage = 'Listening...';
    });

    try {
      await _speechService.startListening(
        onResult: (transcript) async {
          final normalized = transcript.trim();
          if (normalized.isEmpty) {
            return;
          }

          await _speechService.stopListening();
          if (!mounted) {
            return;
          }

          setState(() {
            _isListening = false;
          });

          _applyVoiceTranscript(question, normalized);
        },
        onError: () {
          if (!mounted) {
            return;
          }
          setState(() {
            _isListening = false;
            _voiceStatusMessage = 'Could not understand. Please try again';
          });
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _voiceStatusMessage = 'Voice capture failed. Try again';
        });
      }
    }
  }

  void _applyVoiceTranscript(SurveyQuestion question, String transcript) {
    dynamic value;
    final lowerTranscript = transcript.toLowerCase();

    if (question.type == 'yes_no') {
      final parsed = _speechService.parseYesNoAnswer(transcript);
      if (parsed == RecognitionResult.yes) {
        value = _normalizeYesNoForField(question.fieldName, 'Yes');
      } else if (parsed == RecognitionResult.no) {
        value = _normalizeYesNoForField(question.fieldName, 'No');
      }
    } else if (question.type == 'number_input') {
      value = _speechService.extractNumber(transcript);
    } else if (question.type == 'select' && question.options != null) {
      for (final option in question.options!) {
        final optionValue = option['value']?.toString() ?? '';
        final optionLabel = option['label']?.toString() ?? optionValue;
        final labelLower = optionLabel.toLowerCase();
        final valueLower = optionValue.toLowerCase();
        if (lowerTranscript.contains(labelLower) ||
            (valueLower.isNotEmpty && lowerTranscript.contains(valueLower))) {
          value = optionValue;
          break;
        }
      }
    } else if (question.type == 'height_weight') {
      final spokenWeight = _speechService.extractNumber(transcript);
      if (spokenWeight != null && spokenWeight >= 25 && spokenWeight <= 220) {
        setState(() {
          _formData['weight_kg'] = spokenWeight.toDouble();
          _voiceStatusMessage = 'Weight updated from voice';
          _questionValidationError = _heightWeightValidationMessage();
        });
      } else {
        setState(() {
          _voiceStatusMessage =
              'Say a valid weight in kilograms between 25 and 220';
        });
      }
      return;
    }

    if (value == null) {
      setState(() {
        _voiceStatusMessage = 'Try speaking a clearer answer';
      });
      return;
    }

    setState(() {
      _formData[question.fieldName] = value;
      _questionValidationError = null;
      _voiceStatusMessage = 'Answer captured: $transcript';
    });

    if (question.type == 'yes_no' && _isCurrentQuestionComplete()) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          _nextQuestion();
        }
      });
    }
  }

  String? _continueHint(SurveyQuestion question) {
    if (_isSubmitting) {
      return null;
    }
    if (_questionValidationError != null) {
      return _questionValidationError;
    }
    if (question.required && !_isCurrentQuestionComplete()) {
      return 'Answer this step to continue';
    }
    return _validateCurrentQuestion(question);
  }

  bool _canContinue(SurveyQuestion question) {
    return !_isSubmitting && _continueHint(question) == null;
  }

  Widget _buildQuestionInput(SurveyQuestion question) {
    final fieldName = question.fieldName;
    final type = question.type;
    final options = question.options;

    switch (type) {
      case 'number_input':
        final ageError = fieldName == 'age'
            ? (_questionValidationError ??
                  _ageValidationMessage(_formData[fieldName]))
            : null;
        return TextFormField(
          key: ValueKey('${fieldName}_input'),
          initialValue: _formData[fieldName]?.toString() ?? '',
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: 'Enter your age here',
            suffixText: fieldName == 'age' ? 'years' : null,
            filled: true,
            fillColor: Colors.blue.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: Colors.blue.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: Colors.blue.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: Colors.blue.shade500, width: 2),
            ),
            errorText: ageError,
          ),
          onChanged: (value) {
            setState(() {
              final parsed = value.isEmpty ? null : int.tryParse(value);
              _formData[fieldName] = parsed;
              _questionValidationError = fieldName == 'age'
                  ? _ageValidationMessage(parsed)
                  : null;
            });
          },
        );

      case 'select':
        final selected = _formData[fieldName] as String?;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final option in options ?? <Map<String, dynamic>>[])
              ChoiceChip(
                label: Text(option['label'] ?? option['value']),
                selected: selected == option['value'],
                labelStyle: TextStyle(
                  color: selected == option['value']
                      ? Colors.white
                      : Colors.blueGrey.shade900,
                  fontWeight: FontWeight.w600,
                ),
                selectedColor: Colors.blue.shade700,
                backgroundColor: Colors.blue.shade50,
                side: BorderSide(color: Colors.blue.shade200),
                onSelected: (_) {
                  setState(() {
                    _formData[fieldName] = option['value'];
                    _questionValidationError = null;
                  });
                  _scheduleAutoNextIfOptional(question);
                },
              ),
          ],
        );

      case 'yes_no':
        final currentValue = _formData[fieldName];

        // For arthritis, we store boolean; for others, we store string for backward compatibility
        final isArthritis = fieldName == 'arthritis';
        final isYesSelected = isArthritis
            ? (currentValue == true)
            : (currentValue == 'Yes');
        final isNoSelected = isArthritis
            ? (currentValue == false)
            : (currentValue == 'No');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        _formData[fieldName] = isArthritis ? true : 'Yes';
                        _questionValidationError = null;
                      });
                      _scheduleAutoNextIfOptional(question);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: isYesSelected
                          ? Colors.blue.shade700
                          : Colors.blue.shade100,
                      foregroundColor: isYesSelected
                          ? Colors.white
                          : Colors.blueGrey.shade900,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Yes'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        _formData[fieldName] = isArthritis ? false : 'No';
                        _questionValidationError = null;
                      });
                      _scheduleAutoNextIfOptional(question);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: isNoSelected
                          ? Colors.blue.shade700
                          : Colors.blue.shade100,
                      foregroundColor: isNoSelected
                          ? Colors.white
                          : Colors.blueGrey.shade900,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('No'),
                  ),
                ),
              ],
            ),
          ],
        );

      case 'height_weight':
        final feet = _formData['height_feet'] as int?;
        final inches = _formData['height_inches'] as int?;
        final weight = _formData['weight_kg'] as double?;

        // Calculate BMI
        double? bmi;
        String? bmiStatus;

        if (feet != null && inches != null && weight != null && weight > 0) {
          // height_cm = (feet * 30.48) + (inches * 2.54)
          final heightCm = (feet * 30.48) + (inches * 2.54);
          final heightM = heightCm / 100;
          bmi = weight / (heightM * heightM);

          if (bmi < 18.5) {
            bmiStatus = 'Your BMI: ${bmi.toStringAsFixed(1)} (Underweight)';
          } else if (bmi < 25) {
            bmiStatus = 'Your BMI: ${bmi.toStringAsFixed(1)} (Normal range)';
          } else if (bmi < 30) {
            bmiStatus = 'Your BMI: ${bmi.toStringAsFixed(1)} (Overweight)';
          } else {
            bmiStatus = 'Your BMI: ${bmi.toStringAsFixed(1)} (Obese)';
          }
        }

        final isComplete = feet != null && inches != null && weight != null;
        final heightWeightError =
            _questionValidationError ?? _heightWeightValidationMessage();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: feet,
                    decoration: InputDecoration(
                      labelText: 'Feet',
                      filled: true,
                      fillColor: Colors.blue.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.blue.shade200),
                      ),
                    ),
                    items: List.generate(4, (i) => i + 4)
                        .map(
                          (value) => DropdownMenuItem<int>(
                            value: value,
                            child: Text('$value ft'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _formData['height_feet'] = value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: inches,
                    decoration: InputDecoration(
                      labelText: 'Inches',
                      filled: true,
                      fillColor: Colors.blue.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.blue.shade200),
                      ),
                    ),
                    items: List.generate(12, (i) => i)
                        .map(
                          (value) => DropdownMenuItem<int>(
                            value: value,
                            child: Text('$value in'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _formData['height_inches'] = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Weight: ${weight?.toStringAsFixed(1) ?? '--'} kg',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            Slider(
              value: (weight ?? 60).clamp(25, 220),
              min: 25,
              max: 220,
              divisions: 195,
              label: '${(weight ?? 60).toStringAsFixed(1)} kg',
              onChanged: (value) {
                setState(() {
                  _formData['weight_kg'] = double.parse(
                    value.toStringAsFixed(1),
                  );
                  _questionValidationError = _heightWeightValidationMessage();
                });
              },
            ),
            if (heightWeightError != null) ...[
              const SizedBox(height: 8),
              Text(
                heightWeightError,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 16),
            // BMI Display
            if (isComplete && bmiStatus != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  border: Border.all(color: Colors.blue[300] ?? Colors.blue),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bmiStatus,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'BMI is calculated for general health reference and is not a diagnostic measurement.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              )
            else if (feet == null || inches == null || weight == null)
              Text(
                'Fill all fields to see BMI',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        );

      default:
        return Text('Unknown question type: $type');
    }
  }

  Widget _buildGuidedQuestionStep(SurveyQuestion question) {
    final explanatoryText =
        (question.infoText?.trim().isNotEmpty ?? false)
            ? question.infoText!.trim()
            : ((question.noteText?.trim().isNotEmpty ?? false)
                  ? question.noteText!.trim()
                  : '');

    return Column(
      key: ValueKey('${question.fieldName}_step_$_currentQuestionIndex'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Text(
          'Let\'s get to know you',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.blueGrey.shade700,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                question.question,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 30,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Read question',
              onPressed: _isListening
                  ? null
                  : () => _speakCurrentQuestion(question),
              icon: Icon(
                _isSpeakingQuestion
                    ? Icons.volume_up_rounded
                    : Icons.volume_up_outlined,
                color: Colors.blue.shade700,
              ),
            ),
          ],
        ),
        // Keep explanatory text between heading and input for every question.
        if (explanatoryText.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border.all(color: Colors.blue.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              explanatoryText.replaceAll('\\n', '\n'),
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 12,
                color: Colors.blueGrey.shade700,
                height: 1.5,
              ),
            ),
          ),
        ],
        if (question.helpText.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            question.helpText,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.blueGrey.shade500),
          ),
        ],
        const Spacer(),
        _buildQuestionInput(question),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isSpeakingQuestion
              ? null
              : () => _captureVoiceAnswer(question),
          icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
          label: Text(_isListening ? 'Listening...' : 'Speak your answer'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: BorderSide(color: Colors.blue.shade300),
          ),
        ),
        if (_voiceStatusMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _voiceStatusMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
          ),
        ],
        const Spacer(),
      ],
    );
  }

  void _navigateBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _navigateBack,
          ),
          title: const Text('Bone Health Survey'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _navigateBack,
          ),
          title: const Text('Bone Health Survey'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                  _initializeSurvey();
                },
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _navigateBack,
          ),
          title: const Text('Bone Health Survey'),
        ),
        body: const Center(child: Text('No questions available')),
      );
    }

    final currentQuestion = _questions[_currentQuestionIndex];
    final progress = (_currentQuestionIndex + 1) / _questions.length;

    final continueHint = _continueHint(currentQuestion);
    final canContinue = _canContinue(currentQuestion);

    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }

          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (canContinue) {
              _nextQuestion();
            }
            return KeyEventResult.handled;
          }

          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _previousQuestion();
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _navigateBack,
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    ),
                    Expanded(
                      child: Text(
                        'Step ${_currentQuestionIndex + 1} of ${_questions.length}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.blueGrey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 12,
                    backgroundColor: Colors.blue.shade100,
                    color: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) {
                      final slide = Tween<Offset>(
                        begin: const Offset(0.08, 0),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
                    child: _buildGuidedQuestionStep(currentQuestion),
                  ),
                ),
                if (continueHint != null) ...[
                  Text(
                    continueHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.blueGrey.shade600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton(
                  onPressed: canContinue ? _nextQuestion : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: canContinue
                        ? Colors.blue.shade700
                        : Colors.blueGrey.shade300,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          _currentQuestionIndex == _questions.length - 1
                              ? 'Submit'
                              : 'Continue ->',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Get answer options for voice recognition
  List<String>? _getAnswerOptions(SurveyQuestion question) {
    if (question.type == 'yes_no') {
      return ['Yes', 'No'];
    }
    if (question.type == 'select' && question.options != null) {
      return question.options!
          .map((opt) => opt['label'] ?? opt['value'])
          .cast<String>()
          .toList();
    }
    return null;
  }

  @override
  void dispose() {
    _autoNextTimer?.cancel();
    unawaited(_speechService.dispose());
    VoiceService().stop();
    super.dispose();
  }
}
