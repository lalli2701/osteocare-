import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dashboard/presentation/tasks_page.dart';
import 'survey_page.dart';

class ResultPage extends StatelessWidget {
  const ResultPage({super.key, this.riskLevel});

  static const routePath = '/results';

  final String? riskLevel;

  Color _colorForRisk(String level, ThemeData theme) {
    switch (level.toLowerCase()) {
      case 'low':
        return Colors.green;
      case 'high':
        return Colors.red;
      case 'moderate':
      default:
        return theme.colorScheme.secondary;
    }
  }

  String _labelForRisk(String level) {
    switch (level.toLowerCase()) {
      case 'low':
        return 'Low risk';
      case 'high':
        return 'High risk';
      case 'moderate':
      default:
        return 'Moderate risk';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = riskLevel ?? 'unknown';

    String advice;
    switch (level.toLowerCase()) {
      case 'low':
        advice =
            'Your current answers suggest a low risk. Keep up regular weight‑bearing exercise, a balanced diet rich in calcium and vitamin D, and avoid smoking and heavy alcohol use.';
        break;
      case 'high':
        advice =
            'Your answers suggest a higher risk. Try to see a doctor for a full check‑up, take extra care to prevent falls, avoid smoking and heavy alcohol, and follow an exercise plan that is safe for your joints.';
        break;
      case 'moderate':
        advice =
            'Your answers suggest a moderate risk. Improving daily movement, strengthening exercises, and bone‑friendly food choices can help lower your risk over time.';
        break;
      default:
        advice =
            'Complete the survey to get a personalised overview of your bone health risk.';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your result'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimated osteoporosis risk',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (level == 'unknown')
                      const Text(
                        'Complete a survey to see your risk level.',
                      )
                    else
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color:
                                  _colorForRisk(level, theme).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _labelForRisk(level),
                              style: TextStyle(
                                color: _colorForRisk(level, theme),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'This level is calculated from your answers and is for education only.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What this means',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(advice),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                title: const Text('See my recommended precautions'),
                subtitle: const Text(
                  'Exercise, nutrition and lifestyle tips based on your level.',
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => context.go(
                  TasksPage.routePath,
                  extra: level == 'unknown' ? null : level,
                ),
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => context.go(SurveyPage.routePath),
              child: const Text('Retake survey'),
            ),
          ],
        ),
      ),
    );
  }
}

