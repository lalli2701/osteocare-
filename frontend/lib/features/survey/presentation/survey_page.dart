import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../presentation/result_page.dart';
import '../presentation/voice_question_widget.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/survey_service.dart';
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

  static const _riskLevelKey = 'risk_level';
  static const _nextReassessmentDateKey = 'next_reassessment_date';
  static const _reminderEnabledKey = 'reminder_enabled';
  static const _voiceEnabledKey = 'voice_enabled';

  @override
  void initState() {
    super.initState();
    _initializeSurvey();
  }

  Future<void> _initializeSurvey() async {
    try {
      // Initialize services
      _surveyService = SurveyService();
      await VoiceService().initialize();

      // Load voice preference
      final prefs = await SharedPreferences.getInstance();
      _voiceEnabled = prefs.getBool(_voiceEnabledKey) ?? true;

      // Load questions from SurveyService
      await _loadQuestions();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error initializing survey: ${e.toString()}';
        _isLoading = false;
      });
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
    // Validate current question if required
    final currentQ = _questions[_currentQuestionIndex];

    if (currentQ.required) {
      // Special handling for height_weight type that has sub_fields
      if (currentQ.fieldName == 'height_weight') {
        final feet = _formData['height_feet'];
        final inches = _formData['height_inches'];
        final weight = _formData['weight_kg'];
        if (feet == null || inches == null || weight == null || weight == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Please enter height (feet and inches) and weight')),
          );
          return;
        }
      } else {
        // Regular validation for other field types
        if (_formData[currentQ.fieldName] == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Please answer this question before continuing')),
          );
          return;
        }
      }
    }

    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() => _currentQuestionIndex++);
    } else {
      _submitSurvey();
    }
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
    setState(() {
      _formData[fieldName] = answer;
    });

    // Auto-advance to next question for yes_no answers
    final question =
        _questions.firstWhere((q) => q.fieldName == fieldName, orElse: () {
      return _questions[_currentQuestionIndex];
    });

    if (question.type == 'yes_no' && _isCurrentQuestionComplete()) {
      // Slight delay to show confirmation
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          _nextQuestion();
        }
      });
    }
  }

  Future<void> _submitSurvey() async {
    setState(() => _isSubmitting = true);

    try {
      // Prepare survey data for submission
      final Map<String, dynamic> surveyPayload = {
        'survey_data': _formData,
      };

      final userData = await AuthService.instance.getUserData();
      final userId = (userData?['id']?.toString().trim().isNotEmpty ?? false)
          ? userData!['id'].toString()
          : 'user_${DateTime.now().millisecondsSinceEpoch}';

      final response = await http.post(
        Uri.parse('http://localhost:5000/survey/submit'),
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
        final result = jsonDecode(response.body);
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
          SnackBar(content: Text('Error submitting survey: ${e.toString()}')),
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

    await NotificationService.instance.scheduleReassessmentReminder(
      when: DateTime(nextDate.year, nextDate.month, nextDate.day, 9, 0),
    );
  }

  Widget _buildQuestionInput(SurveyQuestion question) {
    final fieldName = question.fieldName;
    final type = question.type;
    final options = question.options;

    switch (type) {
      case 'number_input':
        return TextFormField(
          keyboardType:
              const TextInputType.numberWithOptions(decimal: false),
          decoration: InputDecoration(
            labelText: question.question,
            hintText: 'Enter a number',
            border: const OutlineInputBorder(),
            helperText: question.helpText,
          ),
          onChanged: (value) {
            setState(() {
              _formData[fieldName] =
                  value.isEmpty ? null : int.tryParse(value);
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
              question.helpText ?? '',
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question.question,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              question.helpText ?? '',
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
                });
              },
            ),
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
        appBar: AppBar(title: const Text('Bone Health Survey')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bone Health Survey')),
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
                  _loadQuestions();
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
        appBar: AppBar(title: const Text('Bone Health Survey')),
        body: const Center(child: Text('No questions available')),
      );
    }

    final currentQuestion = _questions[_currentQuestionIndex];
    final progress = (_currentQuestionIndex + 1) / _questions.length;

    return Scaffold(
      appBar: AppBar(
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
    VoiceService().stop();
    super.dispose();
  }
}

