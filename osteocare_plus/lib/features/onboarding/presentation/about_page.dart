import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dashboard/presentation/dashboard_page.dart';
import '../../chatbot/presentation/assistant_fab.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const routePath = '/about';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('About OssoPulse'),
      ),
      floatingActionButton: const AssistantFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome to OssoPulse',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This app helps you understand your osteoporosis risk early, learn how to protect your bones, and build daily healthy habits.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              'Important:',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '• OssoPulse is an educational tool, not a medical diagnosis.\n'
              '• Always talk to your doctor or healthcare provider about any concerns.\n'
              '• The risk level shown is an estimate based on your answers.',
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.go(DashboardPage.routePath),
                child: const Text('Continue to dashboard'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

