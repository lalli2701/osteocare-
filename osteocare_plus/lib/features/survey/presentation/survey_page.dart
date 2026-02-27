import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../presentation/result_page.dart';
import '../../chatbot/presentation/assistant_fab.dart';

class SurveyPage extends StatefulWidget {
  const SurveyPage({super.key});

  static const routePath = '/survey';

  @override
  State<SurveyPage> createState() => _SurveyPageState();
}

class _SurveyPageState extends State<SurveyPage> {
  List<Map<String, dynamic>> _questions = [];
  final Map<String, dynamic> _formData = {};
  int _currentQuestionIndex = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    try {
      // Fetch questions from backend API
      final response = await http.get(
        Uri.parse('http://localhost:5000/survey/questions'),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Request timeout'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _questions = List<Map<String, dynamic>>.from(data['questions'] ?? []);
          _isLoading = false;
          // Initialize form data with empty values
          for (var q in _questions) {
            _formData[q['field_name']] = null;
          }
        });
      } else {
        throw Exception('Failed to load questions: ${response.statusCode}');
      }
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
    final fieldName = currentQ['field_name'];
    final isRequired = currentQ['required'] == true;
    
    if (isRequired) {
      // Special handling for height_weight type that has sub_fields
      if (fieldName == 'height_weight') {
        final heightCm = _formData['height_cm'];
        final weightKg = _formData['weight_kg'];
        if (heightCm == null || weightKg == null || heightCm == 0 || weightKg == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter both height and weight')),
          );
          return;
        }
      } else {
        // Regular validation for other field types
        if (_formData[fieldName] == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please answer this question before continuing')),
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

  Future<void> _submitSurvey() async {
    setState(() => _isSubmitting = true);

    try {
      // Prepare survey data for submission
      final Map<String, dynamic> surveyPayload = {
        'survey_data': _formData,
      };

      final response = await http.post(
        Uri.parse('http://localhost:5000/survey/submit'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-Id': 'user_${DateTime.now().millisecondsSinceEpoch}',
          'X-API-Key': 'dev-key',
        },
        body: jsonEncode(surveyPayload),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Request timeout'),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (mounted) {
          context.go(ResultPage.routePath, extra: result);
        }
      } else {
        throw Exception('Survey submission failed: ${response.statusCode}');
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

  Widget _buildQuestionInput(Map<String, dynamic> question) {
    final fieldName = question['field_name'];
    final type = question['type'];
    final options = question['options'] as List?;

    switch (type) {
      case 'number_input':
        return TextFormField(
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          decoration: InputDecoration(
            labelText: question['question'],
            hintText: 'Enter a number',
            border: const OutlineInputBorder(),
            helperText: question['help_text'],
          ),
          onChanged: (value) {
            setState(() {
              _formData[fieldName] = value.isEmpty ? null : int.tryParse(value);
            });
          },
        );

      case 'select':
        return DropdownButtonFormField<String>(
          initialValue: _formData[fieldName] as String?,
          decoration: InputDecoration(
            labelText: question['question'],
            border: const OutlineInputBorder(),
            helperText: question['help_text'],
          ),
          items: options
              ?.map((opt) => DropdownMenuItem<String>(
                    value: opt['value'],
                    child: Text(opt['label']),
                  ))
              .toList(),
          onChanged: (value) {
            setState(() => _formData[fieldName] = value);
          },
        );

      case 'yes_no':
        final currentValue = _formData[fieldName] as String?;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question['question'],
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Text(
              question['help_text'] ?? '',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _formData[fieldName] = 'Yes'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: currentValue == 'Yes' ? Colors.blue : null,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      'Yes',
                      style: TextStyle(
                        color: currentValue == 'Yes' ? Colors.white : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _formData[fieldName] = 'No'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: currentValue == 'No' ? Colors.blue : null,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      'No',
                      style: TextStyle(
                        color: currentValue == 'No' ? Colors.white : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

      case 'height_weight':
        final subFields = question['sub_fields'] as List?;
        return Column(
          children: [
            Text(
              question['question'],
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              question['help_text'] ?? '',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            if (subFields != null)
              ...subFields.map((subField) {
                final subFieldName = subField['field_name'];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: subField['label'],
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _formData[subFieldName] =
                            value.isEmpty ? null : double.tryParse(value);
                      });
                    },
                  ),
                );
              }),
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
      floatingActionButton: const AssistantFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
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
          // Question content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: _buildQuestionInput(currentQuestion),
            ),
          ),
          // Navigation buttons
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                if (_currentQuestionIndex > 0) ...[
                  OutlinedButton(
                    onPressed: _previousQuestion,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: 16),
                ] else ...[
                  const SizedBox(width: 0),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: _isSubmitting ? null : _nextQuestion,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isSubmitting
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
    );
  }
}

