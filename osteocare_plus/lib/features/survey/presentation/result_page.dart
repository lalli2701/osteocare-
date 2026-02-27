import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dashboard/presentation/tasks_page.dart';
import 'survey_page.dart';
import '../../chatbot/presentation/assistant_fab.dart';

class ResultPage extends StatelessWidget {
  const ResultPage({super.key, this.result});

  static const routePath = '/results';

  final dynamic result; // Map<String, dynamic> from API

  Color _colorForRisk(String level) {
    switch (level.toLowerCase()) {
      case 'low':
        return Colors.green;
      case 'high':
        return Colors.red;
      case 'moderate':
      default:
        return Colors.orange;
    }
  }

  String _labelForRisk(String level) {
    switch (level.toLowerCase()) {
      case 'low':
        return 'Low Risk';
      case 'high':
        return 'High Risk';
      case 'moderate':
      default:
        return 'Moderate Risk';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Extract data from result
    String riskLevel = 'Unknown';
    String message = 'Complete the survey to get a personalised assessment.';
    double probability = 0.0;
    List<String> tasks = [];
    List<String> alerts = [];

    if (result is Map<String, dynamic>) {
      riskLevel = result['risk_level'] ?? 'Unknown';
      message = result['message'] ?? message;
      probability = (result['probability'] ?? 0.0).toDouble();
      tasks = List<String>.from(result['recommended_tasks'] ?? []);
      alerts = List<String>.from(result['medical_alerts'] ?? []);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Risk Assessment'),
      ),
      floatingActionButton: const AssistantFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Risk Level Card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Bone Health Risk Level',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: _colorForRisk(riskLevel).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _colorForRisk(riskLevel),
                          width: 2,
                        ),
                      ),
                      child: Text(
                        _labelForRisk(riskLevel),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _colorForRisk(riskLevel),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Risk Probability: ${(probability * 100).toStringAsFixed(1)}%',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Message Card
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assessment Summary',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Recommended Tasks
            if (tasks.isNotEmpty) ...[
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recommended Actions',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      ...tasks.asMap().entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: _colorForRisk(riskLevel).withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${entry.key + 1}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _colorForRisk(riskLevel),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  entry.value,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Medical Alerts
            if (alerts.isNotEmpty) ...[
              Card(
                elevation: 1,
                color: Colors.orange[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange[700],
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Important Notes',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.orange[900],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...alerts.map((alert) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '• $alert',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.orange[900],
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Info Text
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'This assessment is for educational purposes only. Please consult with a healthcare professional for medical advice.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            FilledButton(
              onPressed: () => context.go(TasksPage.routePath, extra: riskLevel),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('View Health Tips'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go(SurveyPage.routePath),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Retake Survey'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

