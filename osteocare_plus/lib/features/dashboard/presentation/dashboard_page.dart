import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/user_session.dart';
import '../../survey/presentation/survey_page.dart';
import '../../survey/presentation/result_page.dart';
import '../../dashboard/presentation/tasks_page.dart';
import '../../chatbot/presentation/chatbot_page.dart';
import '../../chatbot/presentation/assistant_fab.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  static const routePath = '/dashboard';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastRisk = UserSession.instance.lastRiskLevel;

    String latestSubtitle;
    if (lastRisk == null) {
      latestSubtitle = 'No survey completed yet';
    } else {
      switch (lastRisk.toLowerCase()) {
        case 'low':
          latestSubtitle = 'Last result: Low risk';
          break;
        case 'high':
          latestSubtitle = 'Last result: High risk';
          break;
        case 'moderate':
        default:
          latestSubtitle = 'Last result: Moderate risk';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('OsteoCare+ Dashboard'),
      ),
      floatingActionButton: const AssistantFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your bone health overview',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Complete a quick survey to estimate your osteoporosis risk and get personalised tips.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => context.go(SurveyPage.routePath),
                    child: const Text('Take survey'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Latest result'),
              subtitle: Text(latestSubtitle),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                context.go(
                  ResultPage.routePath,
                  extra: lastRisk,
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Your tasks & history'),
              subtitle: const Text('View your previous surveys and tasks'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => context.go(
                TasksPage.routePath,
                extra: lastRisk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

