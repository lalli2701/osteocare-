import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../../core/auth/auth_service.dart';
import '../../../core/services/daily_plan_service.dart';
import '../../onboarding/presentation/landing_page.dart';
import '../../survey/presentation/nearby_hospitals_page.dart';
import '../../survey/presentation/saved_reports_page.dart';
import '../../survey/presentation/survey_page.dart';
import 'survey_history_page.dart';
import 'tasks_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  static const routePath = '/dashboard';

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final AuthService _authService = AuthService.instance;

  bool _isLoading = true;
  String _fullName = 'User';
  String? _riskLevel;
  List<_FocusTask> _todayFocusTasks = const <_FocusTask>[];
  int _streakDays = 0;

  late Locale _currentLocale;
  bool _localeInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newLocale = context.locale;
    if (!_localeInitialized) {
      _currentLocale = newLocale;
      _localeInitialized = true;
      _loadDashboardData();
      return;
    }
    if (newLocale != _currentLocale) {
      _currentLocale = newLocale;
      _loadDashboardData();
    }
  }

  Future<void> _loadDashboardData() async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        if (mounted) {
          context.go(LandingPage.routePath);
        }
        return;
      }

      final response = await http
          .get(
            Uri.parse('${AuthService.baseUrl}/api/user/dashboard'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        String? riskLevel;
        if (data['risk'] is Map<String, dynamic>) {
          riskLevel = data['risk']['risk_level']?.toString();
        }

        final focusAndStreak = await _loadFocusAndStreak();
        if (!mounted) {
          return;
        }

        setState(() {
          _fullName = data['full_name']?.toString().trim().isNotEmpty == true
              ? data['full_name'].toString().trim()
              : 'User';
          _riskLevel = riskLevel;
          _todayFocusTasks = focusAndStreak.$1;
          _streakDays = focusAndStreak.$2;
          _isLoading = false;
        });
        return;
      }

      if (response.statusCode == 401 && mounted) {
        context.go(LandingPage.routePath);
        return;
      }

      throw Exception('Failed to load dashboard data');
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('error_loading'.tr())));
    }
  }

  Future<(List<_FocusTask>, int)> _loadFocusAndStreak() async {
    final insights = await DailyPlanService.instance.fetchInsights(days: 7);
    final records = await DailyPlanService.instance.fetchTasks(days: 7);

    final todayKey = _dateKey(DateTime.now());
    final todayRecords = records.where((r) => r.date == todayKey).toList();

    List<_FocusTask> tasks;
    if (todayRecords.isEmpty) {
      tasks = _fallbackFocusTasks();
    } else {
      final incomplete = <_FocusTask>[];
      final completed = <_FocusTask>[];
      for (final record in todayRecords) {
        final item = _FocusTask(
          task: record.taskName,
          completed: record.completed,
        );
        if (record.completed) {
          completed.add(item);
        } else {
          incomplete.add(item);
        }
      }
      tasks = <_FocusTask>[...incomplete, ...completed];
    }

    return (tasks.take(3).toList(), insights?.streakDays ?? 0);
  }

  List<_FocusTask> _fallbackFocusTasks() {
    final level = (_riskLevel ?? '').toLowerCase();
    if (level == 'high') {
      return const <_FocusTask>[
        _FocusTask(task: 'Stop smoking', completed: false),
        _FocusTask(task: 'Take calcium + vitamin D', completed: false),
        _FocusTask(task: 'Light guided exercise', completed: false),
      ];
    }
    if (level == 'moderate') {
      return const <_FocusTask>[
        _FocusTask(task: '20 minutes sunlight', completed: false),
        _FocusTask(task: 'Calcium-rich meals', completed: false),
        _FocusTask(task: '30 minutes walking', completed: false),
      ];
    }
    return const <_FocusTask>[
      _FocusTask(task: 'Walk 30 minutes', completed: false),
      _FocusTask(task: 'Hydrate well today', completed: false),
      _FocusTask(task: 'Maintain routine', completed: false),
    ];
  }

  String _dateKey(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Color _riskColor(String? level) {
    final risk = (level ?? '').toLowerCase();
    if (risk == 'high') return Colors.red;
    if (risk == 'moderate') return Colors.orange;
    if (risk == 'low') return Colors.green;
    return Colors.blueGrey;
  }

  String _riskText(String? level) {
    final risk = (level ?? '').toLowerCase();
    if (risk == 'high') return 'HIGH RISK';
    if (risk == 'moderate') return 'MODERATE RISK';
    if (risk == 'low') return 'LOW RISK';
    return 'NO ASSESSMENT';
  }

  Future<void> _toggleFocusTask(_FocusTask task, bool checked) async {
    setState(() {
      _todayFocusTasks = _todayFocusTasks
          .map(
            (t) => t.task == task.task
                ? _FocusTask(task: t.task, completed: checked)
                : t,
          )
          .toList();
    });

    await DailyPlanService.instance.upsertTask(
      date: _dateKey(DateTime.now()),
      taskName: task.task,
      completed: checked,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    final riskColor = _riskColor(_riskLevel);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: riskColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person, color: riskColor),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hi, $_fullName',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _riskText(_riskLevel),
                          style: TextStyle(
                            color: riskColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Today's Focus",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ..._todayFocusTasks
                          .take(3)
                          .map(
                            (task) => CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: task.completed,
                              onChanged: (v) =>
                                  _toggleFocusTask(task, v == true),
                              title: Text(task.task),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => context.push(TasksPage.routePath),
                          child: const Text('View Full Plan ->'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_fire_department,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$_streakDays Day Streak',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.9,
                  children: [
                    _QuickAction(
                      icon: Icons.description,
                      label: 'Reports',
                      onTap: () => context.push(SavedReportsPage.routePath),
                    ),
                    _QuickAction(
                      icon: Icons.history,
                      label: 'History',
                      onTap: () => context.push(SurveyHistoryPage.routePath),
                    ),
                    _QuickAction(
                      icon: Icons.local_hospital,
                      label: 'Hospitals',
                      onTap: () => context.push(NearbyHospitalsPage.routePath),
                    ),
                    _QuickAction(
                      icon: Icons.assignment,
                      label: 'Survey',
                      onTap: () => context.push(SurveyPage.routePath),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusTask {
  const _FocusTask({required this.task, required this.completed});

  final String task;
  final bool completed;
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          CircleAvatar(radius: 24, child: Icon(icon)),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
