import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../dashboard/presentation/tasks_page.dart';
import 'nearby_hospitals_page.dart';
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

  String _getOneLineSummary(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'low':
        return 'You are doing well. Maintain your habits.';
      case 'high':
        return 'You are at high risk of bone loss.';
      case 'moderate':
      default:
        return 'You have moderate risk. Take preventive steps.';
    }
  }

  String _humanizeFactor(String factor) {
    const map = {
      'smoking': 'Smoking habit',
      'calcium_low': 'Low calcium intake',
      'exercise_low': 'Low physical activity',
      'sunlight_low': 'Lack of sunlight',
      'sleep_poor': 'Poor sleep quality',
    };
    final key = factor.trim().toLowerCase();
    if (map.containsKey(key)) {
      return map[key]!;
    }
    return factor.replaceAll('_', ' ');
  }

  List<Map<String, dynamic>> _parseFactorWeights(Map<String, dynamic> payload) {
    final raw = payload['top_factors_with_weight'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map(
          (item) => {
            'factor': item['factor']?.toString() ?? '',
            'impact': (item['impact'] as num?)?.toDouble() ?? 0.0,
            'normalized': (item['normalized'] as num?)?.toDouble() ?? 0.0,
          },
        )
        .where((item) => (item['factor'] as String).isNotEmpty)
        .toList();
  }

  Map<String, List<String>> _parseTimeGroups(Map<String, dynamic> payload) {
    final raw = payload['time_groups'];
    if (raw is! Map) {
      return {};
    }

    final groups = <String, List<String>>{};
    for (final entry in raw.entries) {
      if (entry.value is! List) {
        continue;
      }
      final items = (entry.value as List)
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (items.isNotEmpty) {
        groups[entry.key.toString()] = items;
      }
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    String riskLevel = 'unknown';
    double probability = 0.0;
    double confidence = 0.0;
    String confidenceLabel = 'Low';
    String confidenceBand = 'Low';
    String confidenceReason = '';
    String primaryAction = '';
    List<String> tasks = [];
    List<String> topFactors = [];
    List<Map<String, dynamic>> factorWeights = [];
    Map<String, List<String>> timeGroups = {};

    if (widget.result is Map<String, dynamic>) {
      riskLevel = widget.result['risk_level'] ?? 'Unknown';
      probability = (widget.result['probability'] ?? 0.0).toDouble();
      confidence = (widget.result['confidence'] ?? 0.0).toDouble();
      confidenceLabel = widget.result['confidence_label']?.toString() ?? confidenceLabel;
      confidenceBand = widget.result['confidence_band']?.toString() ?? confidenceBand;
      confidenceReason = widget.result['confidence_reason']?.toString() ?? '';
      primaryAction = widget.result['primary_action']?.toString() ?? '';
      tasks = List<String>.from(widget.result['recommended_tasks'] ?? []);
      topFactors = List<String>.from(widget.result['top_factors'] ?? const <String>[]);
      factorWeights = _parseFactorWeights(widget.result);
      timeGroups = _parseTimeGroups(widget.result);
    }

    if (factorWeights.isEmpty && topFactors.isNotEmpty) {
      factorWeights = topFactors
          .take(5)
          .toList()
          .asMap()
          .entries
          .map(
            (entry) => {
              'factor': entry.value,
              'normalized': (0.9 - (entry.key * 0.1)).clamp(0.4, 0.9),
            },
          )
          .toList();
    }

    if (primaryAction.isEmpty && tasks.isNotEmpty) {
      primaryAction = tasks.first;
    }

    if (timeGroups.isEmpty && tasks.isNotEmpty) {
      timeGroups = {'any': tasks};
    }

    final isHighRisk = riskLevel.toLowerCase() == 'high';
    final isModerateRisk = riskLevel.toLowerCase() == 'moderate';
    final showHospitalButton = isHighRisk || isModerateRisk;

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
        title: const Text('Your Risk Assessment'),
        elevation: 0,
      ),
      floatingActionButton: AssistantFab(
        contextHint: isHighRisk
            ? 'Ask how to reduce your risk'
            : 'Ask anything about your bone health',
        emphasize: isHighRisk,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _colorForRisk(riskLevel).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.health_and_safety,
                    color: _colorForRisk(riskLevel),
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _labelForRisk(riskLevel).toUpperCase(),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _colorForRisk(riskLevel),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('${(probability * 100).toInt()}% probability'),
                        const SizedBox(height: 6),
                        Text(
                          _getOneLineSummary(riskLevel),
                          style: TextStyle(color: Colors.blueGrey.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confidence • $confidenceBand',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: confidence.clamp(0, 1),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 8),
                    Text('${(confidence * 100).toInt()}% • $confidenceLabel'),
                    const SizedBox(height: 6),
                    Text(
                      confidenceReason,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),

            if (factorWeights.isNotEmpty) ...[
              Text(
                'Why this result?',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...factorWeights.map((f) {
                final factor = _humanizeFactor(f['factor']?.toString() ?? '');
                final normalized = (f['normalized'] as num?)?.toDouble() ?? 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(factor),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: normalized.clamp(0, 1),
                        minHeight: 6,
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 6),
            ],

            if (primaryAction.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 16, top: 6),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.priority_high, color: Colors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        primaryAction,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

            ...timeGroups.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    ...entry.value.map(
                      (task) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.check_circle_outline),
                        title: Text(task),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
            if (showHospitalButton)
              FilledButton.icon(
                onPressed: () => context.push(NearbyHospitalsPage.routePath),
                icon: const Icon(Icons.local_hospital_outlined),
                label: const Text('Find Nearby Specialists'),
              ),

            const SizedBox(height: 8),
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
              child: const Text('View Daily Plan'),
            ),

            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go(SurveyPage.routePath),
              child: const Text('Retake Assessment'),
            ),
          ],
        ),
      ),
    );
  }
}
