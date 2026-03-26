import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../presentation/result_page.dart';
import '../presentation/voice_question_widget.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/local_survey_store.dart';
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
  Timer? _autoNextTimer;
  String? _questionValidationError;
  late Locale _currentLocale;
  bool _localeInitialized = false;

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
      _loadQuestions();
    }
  }

  Future<void> _initializeSurvey() async {
    try {
      // Initialize core service and load survey questions first.
      // Voice and sync should not block form rendering on mobile.
      _surveyService = SurveyService();

      // Load voice preference
      final prefs = await SharedPreferences.getInstance();
      _voiceEnabled = prefs.getBool(_voiceEnabledKey) ?? true;

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
      final age = (value is num) ? value.toDouble() : double.tryParse(value.toString());
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
    final age = (value is num) ? value.toDouble() : double.tryParse(value.toString());
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

  /// Handle voice answer confirmation
  void _handleVoiceAnswer(String fieldName, dynamic answer) {
    final question =
        _questions.firstWhere((q) => q.fieldName == fieldName, orElse: () {
      return _questions[_currentQuestionIndex];
    });

    dynamic normalized = answer;
    if (question.type == 'yes_no') {
      normalized = _normalizeYesNoForField(fieldName, answer);
    }

    setState(() {
      _formData[fieldName] = normalized;
    });

    // Auto-advance to next question for yes_no answers
    if (question.type == 'yes_no' && _isCurrentQuestionComplete()) {
      // Slight delay to show confirmation
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          _nextQuestion();
        }
      });
    }
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
    if (raw.isEmpty || raw == 'null' || raw == 'none' || raw == 'recognitionresult.unknown') {
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

      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/survey/submit'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-Id': userId,
          'X-API-Key': 'dev-key',
        },
        body: jsonEncode(surveyPayload),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Request timeout'),
      );

      if (response.statusCode == 200) {
        final result = Map<String, dynamic>.from(jsonDecode(response.body));
        await LocalSurveyStore.instance.markSynced(
          id: localRecordId,
          result: result,
        );
        await SurveySyncService.instance.syncPendingSurveys(userId: userId);
        await _persistAndScheduleReassessment(result);
        if (mounted) {
          context.go(ResultPage.routePath, extra: result);
        }
      } else {
        String backendError = 'Survey submission failed: ${response.statusCode}';
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

  Future<void> _persistAndScheduleReassessment(Map<String, dynamic> result) async {
    final riskLevel = (result['risk_level']?.toString() ?? 'Moderate').trim();
    final normalizedRisk = riskLevel.toLowerCase();
    final backendNextDate = result['next_reassessment_date']?.toString();

    DateTime nextDate;
    if (backendNextDate != null && backendNextDate.isNotEmpty) {
      nextDate = DateTime.parse(backendNextDate);
    } else {
      nextDate = DateTime.now().add(Duration(days: _getReassessmentDays(riskLevel)));
    }

    await _storage.write(key: _riskLevelKey, value: riskLevel);
    await _storage.write(
      key: _nextReassessmentDateKey,
      value: nextDate.toIso8601String(),
    );
    await _storage.write(key: _reminderEnabledKey, value: 'true');

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

  Widget _buildQuestionInput(SurveyQuestion question) {
    final fieldName = question.fieldName;
    final type = question.type;
    final options = question.options;

    switch (type) {
      case 'number_input':
        final ageError = fieldName == 'age'
            ? (_questionValidationError ?? _ageValidationMessage(_formData[fieldName]))
            : null;
        return TextFormField(
          keyboardType:
              const TextInputType.numberWithOptions(decimal: false),
          decoration: InputDecoration(
            labelText: question.question,
            hintText: 'Enter a number',
            border: const OutlineInputBorder(),
            helperText: question.helpText,
            errorText: ageError,
          ),
          onChanged: (value) {
            setState(() {
              final parsed = value.isEmpty ? null : int.tryParse(value);
              _formData[fieldName] = parsed;
              if (fieldName == 'age') {
                _questionValidationError = _ageValidationMessage(parsed);
              }
            });
          },
        );

      case 'select':
        return DropdownButtonFormField<String>(
          initialValue: _formData[fieldName] as String?,
          decoration: InputDecoration(
            labelText: question.question,
            border: const OutlineInputBorder(),
            helperText: question.helpText,
          ),
          items: options
              ?.map((opt) => DropdownMenuItem<String>(
                    value: opt['value'],
                    child: Text(opt['label'] ?? opt['value']),
                  ))
              .toList(),
          onChanged: (value) {
            setState(() => _formData[fieldName] = value);
            if (value != null) {
              _scheduleAutoNextIfOptional(question);
            }
          },
        );

      case 'yes_no':
        final currentValue = _formData[fieldName];
        final infoText = question.infoText;
        final noteText = question.noteText;

        // For arthritis, we store boolean; for others, we store string for backward compatibility
        final isArthritis = fieldName == 'arthritis';
        final isYesSelected = isArthritis
            ? (currentValue == true)
            : (currentValue == 'Yes');
        final isNoSelected = isArthritis
            ? (currentValue == false)
            : (currentValue == 'No');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    question.question,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
                if (infoText != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.info_outline, size: 20),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('What is ${question.fieldName}?'),
                          content: Text(
                            infoText.replaceAll('\\n', '\n'),
                            style: const TextStyle(fontSize: 14),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Got it'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              question.helpText,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            if (noteText != null) ...[
              const SizedBox(height: 8),
              Text(
                noteText,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _formData[fieldName] = isArthritis ? true : 'Yes';
                      _scheduleAutoNextIfOptional(question);
                    }),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: isYesSelected ? Colors.blue : null,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      'Yes',
                      style: TextStyle(
                        color: isYesSelected ? Colors.white : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _formData[fieldName] = isArthritis ? false : 'No';
                      _scheduleAutoNextIfOptional(question);
                    }),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: isNoSelected ? Colors.blue : null,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      'No',
                      style: TextStyle(
                        color: isNoSelected ? Colors.white : null,
                      ),
                    ),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question.question,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              question.helpText,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            // Height - Feet dropdown
            DropdownButtonFormField<int>(
              initialValue: feet,
              decoration: InputDecoration(
                labelText: 'Height (Feet)',
                border: const OutlineInputBorder(),
              ),
              items: List.generate(4, (i) => i + 4)
                  .map((value) => DropdownMenuItem<int>(
                        value: value,
                        child: Text('$value ft'),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() => _formData['height_feet'] = value);
              },
            ),
            const SizedBox(height: 12),
            // Height - Inches dropdown
            DropdownButtonFormField<int>(
              initialValue: inches,
              decoration: InputDecoration(
                labelText: 'Height (Inches)',
                border: const OutlineInputBorder(),
              ),
              items: List.generate(12, (i) => i)
                  .map((value) => DropdownMenuItem<int>(
                        value: value,
                        child: Text('$value in'),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() => _formData['height_inches'] = value);
              },
            ),
            const SizedBox(height: 12),
            // Weight input
            TextFormField(
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Weight (kg)',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _formData['weight_kg'] = value.isEmpty ? null : double.tryParse(value);
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/dashboard');
              }
            },
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
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/dashboard');
              }
            },
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
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/dashboard');
              }
            },
          ),
          title: const Text('Bone Health Survey'),
        ),
        body: const Center(child: Text('No questions available')),
      );
    }

    final currentQuestion = _questions[_currentQuestionIndex];
    final progress = (_currentQuestionIndex + 1) / _questions.length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: const Text('Bone Health Survey'),
        elevation: 0,
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }

          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (!_isSubmitting && _isCurrentQuestionComplete()) {
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
        child: Column(
          children: [
            // Progress bar
            LinearProgressIndicator(value: progress),
            // Question number
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Question ${_currentQuestionIndex + 1} of ${_questions.length}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ),
            // Question content with voice wrapper
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: VoiceQuestionWidget(
                  questionWidget: _buildQuestionInput(currentQuestion),
                  questionText: currentQuestion.question,
                  fieldName: currentQuestion.fieldName,
                  questionType: currentQuestion.type,
                  currentIndex: _currentQuestionIndex,
                  totalQuestions: _questions.length,
                  enableVoice: _voiceEnabled,
                  answerOptions: _getAnswerOptions(currentQuestion),
                  onVoiceAnswerConfirmed: _handleVoiceAnswer,
                ),
              ),
            ),
            // Navigation buttons
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (_currentQuestionIndex > 0) ...[
                    OutlinedButton.icon(
                      onPressed: _previousQuestion,
                      icon: const Icon(Icons.arrow_back),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                      label: const Text('Back'),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_isSubmitting || !_isCurrentQuestionComplete()) ? null : _nextQuestion,
                      icon: Icon(
                        _currentQuestionIndex == _questions.length - 1
                            ? Icons.check
                            : Icons.arrow_forward,
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      label: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              _currentQuestionIndex == _questions.length - 1
                                  ? 'Submit'
                                  : 'Next',
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
    VoiceService().stop();
    super.dispose();
  }
}

