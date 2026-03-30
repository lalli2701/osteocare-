import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/services/daily_plan_service.dart';
import '../../onboarding/presentation/landing_page.dart';
import '../../survey/presentation/prescriptions_page.dart';
import '../../survey/presentation/saved_hospitals_page.dart';
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
  double? _riskScore;
  List<_FocusTask> _todayFocusTasks = const <_FocusTask>[];
  int _streakDays = 0;
  bool _isFirstVisit = true;

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

      // Check if this is the first visit
      final prefs = await SharedPreferences.getInstance();
      final hasVisitedDashboard =
          prefs.getBool('has_visited_dashboard') ?? false;
      final isFirstVisit = !hasVisitedDashboard;

      final response = await http
          .get(
            Uri.parse('${AuthService.baseUrl}/api/user/dashboard'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        String? riskLevel;
        double? riskScore;
        if (data['risk'] is Map<String, dynamic>) {
          riskLevel = data['risk']['risk_level']?.toString();
          riskScore = (data['risk']['risk_score'] as num?)?.toDouble();
        }
        if (!mounted) {
          return;
        }

        // Render critical dashboard identity/risk data first.
        // Secondary focus/streak data is fetched in the background.
        final fallbackTasks = _fallbackFocusTasksForRisk(riskLevel);

        setState(() {
          _fullName = data['full_name']?.toString().trim().isNotEmpty == true
              ? data['full_name'].toString().trim()
              : 'User';
          _riskLevel = riskLevel;
          _riskScore = riskScore;
          _todayFocusTasks = fallbackTasks;
          _streakDays = 0;
          _isLoading = false;
          _isFirstVisit = isFirstVisit;
        });

        // Mark that dashboard has been visited
        await prefs.setBool('has_visited_dashboard', true);

        _refreshFocusAndStreak(riskLevel);
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

  Future<void> _refreshFocusAndStreak(String? riskLevel) async {
    try {
      final focusAndStreak = await _loadFocusAndStreak(riskLevel);
      if (!mounted) {
        return;
      }
      setState(() {
        _todayFocusTasks = focusAndStreak.$1;
        _streakDays = focusAndStreak.$2;
      });
    } catch (e) {
      debugPrint('Dashboard secondary load failed: $e');
    }
  }

  Future<(List<_FocusTask>, int)> _loadFocusAndStreak(String? riskLevel) async {
    final insights = await DailyPlanService.instance.fetchInsights(days: 7);
    final records = await DailyPlanService.instance.fetchTasks(days: 7);

    final todayKey = _dateKey(DateTime.now());
    final todayRecords = records.where((r) => r.date == todayKey).toList();

    List<_FocusTask> tasks;
    if (todayRecords.isEmpty) {
      tasks = _fallbackFocusTasksForRisk(riskLevel);
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

  List<_FocusTask> _fallbackFocusTasksForRisk(String? riskLevel) {
    final level = (riskLevel ?? '').toLowerCase();
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

  String _riskInsight(String? level) {
    final risk = (level ?? '').toLowerCase();
    if (risk == 'high') return 'Immediate attention needed';
    if (risk == 'moderate') return 'Improve your habits';
    if (risk == 'low') return 'Keep maintaining';
    return 'Take assessment to get your risk status';
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
              // App Header with Logo and Tagline
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade600, Colors.blue.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          'assets/new_logo.jpeg',
                          width: 32,
                          height: 32,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'OsteoCare',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'AI-based osteoporosis risk screening',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Greeting based on first visit
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text(
                  _isFirstVisit ? 'Hi, $_fullName' : 'Welcome back, $_fullName',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.blueGrey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              Container(
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: riskColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: riskColor.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _riskText(_riskLevel),
                          style: TextStyle(
                            color: riskColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                        Text(
                          'Score: ${(_riskScore ?? 0).toStringAsFixed(0)}',
                          style: TextStyle(
                            color: Colors.blueGrey.shade800,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _riskInsight(_riskLevel),
                      style: TextStyle(
                        color: Colors.blueGrey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () => context.push(SurveyPage.routePath),
                      child: const Text('Recheck Risk'),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Actions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final maxWidth = constraints.maxWidth;
                        final crossAxisCount = maxWidth >= 980
                            ? 3
                            : maxWidth >= 640
                            ? 2
                            : 1;

                        final cardAspect = crossAxisCount == 1 ? 2.6 : 2.2;

                        return GridView.count(
                          crossAxisCount: crossAxisCount,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: cardAspect,
                          children: [
                            _QuickActionCard(
                              icon: Icons.badge_outlined,
                              title: 'Doctor Reports',
                              subtitle: 'View documents',
                              onTap: () =>
                                  context.push(PrescriptionsPage.routePath),
                            ),
                            _QuickActionCard(
                              icon: Icons.history,
                              title: 'Survey History',
                              subtitle: 'Past assessments',
                              onTap: () =>
                                  context.push(SurveyHistoryPage.routePath),
                            ),
                            _QuickActionCard(
                              icon: Icons.local_hospital_outlined,
                              title: 'Saved Hospitals',
                              subtitle: 'Nearby & bookmarked',
                              onTap: () =>
                                  context.push(SavedHospitalsPage.routePath),
                            ),
                          ],
                        );
                      },
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

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.blueGrey.shade100),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.blue.shade500, size: 28),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
