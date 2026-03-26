import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/services/dynamic_translation_service.dart';

import '../../dashboard/presentation/tasks_page.dart';
import 'survey_page.dart';
import '../../chatbot/presentation/assistant_fab.dart';

class ResultPage extends StatefulWidget {
  const ResultPage({super.key, this.result});

  static const routePath = '/results';

  final dynamic result; // Map<String, dynamic> from API

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  late Locale _currentLocale;
  bool _localeInitialized = false;
  String? _translatedMessage;
  List<String> _translatedTasks = const [];
  List<String> _translatedAlerts = const [];

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
      _translateDynamicContent();
      return;
    }
    if (newLocale != _currentLocale) {
      _currentLocale = newLocale;
      _translateDynamicContent();
    }
  }

  Future<void> _translateDynamicContent() async {
    if (widget.result is! Map<String, dynamic>) {
      return;
    }
    final payload = widget.result as Map<String, dynamic>;
    final langCode = context.locale.languageCode;

    final message = (payload['message'] ?? '').toString();
    final tasks = List<String>.from(payload['recommended_tasks'] ?? const []);
    final alerts = List<String>.from(payload['medical_alerts'] ?? const []);

    final translatedMessage = message.isEmpty
        ? ''
        : await DynamicTranslationService.instance.translate(
            message,
            langCode: langCode,
          );
    final translatedTasks = tasks.isEmpty
        ? const <String>[]
        : await DynamicTranslationService.instance.translateMany(
            tasks,
            langCode: langCode,
          );
    final translatedAlerts = alerts.isEmpty
        ? const <String>[]
        : await DynamicTranslationService.instance.translateMany(
            alerts,
            langCode: langCode,
          );

    if (!mounted) return;
    setState(() {
      _translatedMessage = translatedMessage.isEmpty ? null : translatedMessage;
      _translatedTasks = translatedTasks;
      _translatedAlerts = translatedAlerts;
    });
  }

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
        return 'risk_low'.tr();
      case 'high':
        return 'risk_high'.tr();
      case 'moderate':
      default:
        return 'risk_moderate'.tr();
    }
  }

  int? _extractAgeFromResult(dynamic payload) {
    if (payload is! Map<String, dynamic>) {
      return null;
    }

    final directAge = payload['age'];
    final parsedDirect = int.tryParse(directAge?.toString() ?? '');
    if (parsedDirect != null) {
      return parsedDirect;
    }

    final inputs = payload['inputs'];
    if (inputs is Map<String, dynamic>) {
      final age = inputs['age'];
      return int.tryParse(age?.toString() ?? '');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Extract data from result
    String riskLevel = 'Unknown';
    String message = 'result_survey_incomplete'.tr();
    double probability = 0.0;
    List<String> tasks = [];
    List<String> alerts = [];

    if (widget.result is Map<String, dynamic>) {
      riskLevel = widget.result['risk_level'] ?? 'Unknown';
      message = widget.result['message'] ?? message;
      probability = (widget.result['probability'] ?? 0.0).toDouble();
      tasks = List<String>.from(widget.result['recommended_tasks'] ?? []);
      alerts = List<String>.from(widget.result['medical_alerts'] ?? []);
    }

    final shownMessage = _translatedMessage ?? message;
    final shownTasks = _translatedTasks.isEmpty ? tasks : _translatedTasks;
    final shownAlerts = _translatedAlerts.isEmpty ? alerts : _translatedAlerts;

    return Scaffold(
      appBar: AppBar(
        title: Text('result_title'.tr()),
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
                      'result_risk_level'.tr(),
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
                        color: _colorForRisk(riskLevel).withValues(alpha: 0.1),
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
                      'result_probability'.tr(args: [(probability * 100).toStringAsFixed(1)]),
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
                      'result_summary'.tr(),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      shownMessage,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Recommended Tasks
            if (shownTasks.isNotEmpty) ...[
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'result_recommendations'.tr(),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      ...shownTasks.asMap().entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: _colorForRisk(riskLevel).withValues(alpha: 0.2),
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
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Medical Alerts
            if (shownAlerts.isNotEmpty) ...[
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
                            'result_alerts'.tr(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.orange[900],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...shownAlerts.map((alert) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '• $alert',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.orange[900],
                            ),
                          ),
                        );
                      }),
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
                'result_disclaimer'.tr(),
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
              onPressed: () {
                final age = _extractAgeFromResult(widget.result);
                context.go(
                  TasksPage.routePath,
                  extra: {
                    'risk_level': riskLevel,
                    'age': age,
                  },
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('view_health_tips'.tr()),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go(SurveyPage.routePath),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('retake_survey'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
