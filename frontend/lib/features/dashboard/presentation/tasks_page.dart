import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/daily_plan_service.dart';
import '../../chatbot/presentation/assistant_fab.dart';
import '../../survey/presentation/survey_page.dart';
import 'dashboard_wrapper.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.riskLevel, this.age});

  static const routePath = '/tasks';

  final String? riskLevel;
  final int? age;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  static const _taskStoreKey = 'daily_plan_tasks_v1';
  static const _taskNames = <String>[
    'Calcium intake (milk or equivalent)',
    '20 minutes sunlight',
    'Exercise / walk',
  ];

  bool _isLoading = true;
  bool _isSyncing = false;
  Map<String, Map<String, bool>> _taskHistoryByDate = <String, Map<String, bool>>{};
  Map<String, bool> _todayTasks = <String, bool>{};
  int _streakDays = 0;
  bool _streakBroken = false;
  double _todayProgress = 0;
  double _weeklyCompletionPercent = 0;

  int _surveyCount = 0;
  String _riskTrendText = 'Add more survey entries to view trend.';
  bool _hasSignificantImprovement = false;
  List<Map<String, dynamic>> _serverCompletionSeries = const [];
  List<Map<String, dynamic>> _serverRiskTrend = const [];

  @override
  void initState() {
    super.initState();
    _loadDailyPlan();
  }

  String _dateKey(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Map<String, bool> _defaultTaskState() {
    return {
      for (final task in _taskNames) task: false,
    };
  }

  Future<void> _loadDailyPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_taskStoreKey);

    final decoded = <String, Map<String, bool>>{};
    if (raw != null && raw.isNotEmpty) {
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        parsed.forEach((date, value) {
          if (value is Map<String, dynamic>) {
            final state = <String, bool>{};
            for (final task in _taskNames) {
              state[task] = value[task] == true;
            }
            decoded[date] = state;
          }
        });
      }
    }

    final todayKey = _dateKey(DateTime.now());
    decoded.putIfAbsent(todayKey, _defaultTaskState);

    if (!mounted) {
      return;
    }

    setState(() {
      _taskHistoryByDate = decoded;
      _todayTasks = Map<String, bool>.from(decoded[todayKey] ?? _defaultTaskState());
      _recomputeMetrics();
      _isLoading = false;
    });

    await _syncTasksFromServer();
    await _loadInsights();
  }

  Future<void> _saveDailyPlan() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_taskStoreKey, jsonEncode(_taskHistoryByDate));
  }

  bool _allTasksCompleted(Map<String, bool> state) {
    return _taskNames.every((task) => state[task] == true);
  }

  int _completedCount(Map<String, bool> state) {
    return _taskNames.where((task) => state[task] == true).length;
  }

  void _recomputeMetrics() {
    final now = DateTime.now();
    final todayKey = _dateKey(now);
    final todayState = _taskHistoryByDate[todayKey] ?? _defaultTaskState();

    _todayProgress = _completedCount(todayState) / _taskNames.length;

    var weeklyCompleted = 0;
    var weeklyTotal = 0;
    for (var i = 0; i < 7; i++) {
      final key = _dateKey(now.subtract(Duration(days: i)));
      final dayState = _taskHistoryByDate[key] ?? _defaultTaskState();
      weeklyCompleted += _completedCount(dayState);
      weeklyTotal += _taskNames.length;
    }
    _weeklyCompletionPercent =
        weeklyTotal == 0 ? 0 : (weeklyCompleted / weeklyTotal) * 100;

    var streak = 0;
    for (var i = 0; i < 365; i++) {
      final key = _dateKey(now.subtract(Duration(days: i)));
      final dayState = _taskHistoryByDate[key];
      if (dayState == null || !_allTasksCompleted(dayState)) {
        break;
      }
      streak++;
    }
    _streakDays = streak;

    final yesterdayKey = _dateKey(now.subtract(const Duration(days: 1)));
    final yesterday = _taskHistoryByDate[yesterdayKey];
    final hadAnyRecentComplete = List.generate(7, (i) => i + 1).any((d) {
      final state =
          _taskHistoryByDate[_dateKey(now.subtract(Duration(days: d)))];
      return state != null && _allTasksCompleted(state);
    });
    _streakBroken =
        yesterday != null && !_allTasksCompleted(yesterday) && hadAnyRecentComplete;
  }

  Future<void> _syncTasksFromServer() async {
    if (!mounted) {
      return;
    }
    setState(() => _isSyncing = true);

    try {
      final records = await DailyPlanService.instance.fetchTasks(days: 30);
      if (records.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() => _isSyncing = false);
        return;
      }

      final merged = Map<String, Map<String, bool>>.from(_taskHistoryByDate);
      for (final record in records) {
        final dateMap = merged.putIfAbsent(record.date, _defaultTaskState);
        if (dateMap.containsKey(record.taskName)) {
          dateMap[record.taskName] = record.completed;
        }
      }

      final todayKey = _dateKey(DateTime.now());
      merged.putIfAbsent(todayKey, _defaultTaskState);

      if (!mounted) {
        return;
      }
      setState(() {
        _taskHistoryByDate = merged;
        _todayTasks = Map<String, bool>.from(merged[todayKey] ?? _defaultTaskState());
        _recomputeMetrics();
        _isSyncing = false;
      });
      await _saveDailyPlan();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isSyncing = false);
    }
  }

  Future<void> _toggleTask(String task, bool done) async {
    final todayKey = _dateKey(DateTime.now());
    setState(() {
      _todayTasks[task] = done;
      _taskHistoryByDate[todayKey] = Map<String, bool>.from(_todayTasks);
      _recomputeMetrics();
    });
    await _saveDailyPlan();

    await DailyPlanService.instance.upsertTask(
      date: todayKey,
      taskName: task,
      completed: done,
    );

    await _loadInsights();
  }

  int _riskRank(String risk) {
    final normalized = risk.toLowerCase();
    if (normalized == 'high') return 3;
    if (normalized == 'moderate') return 2;
    if (normalized == 'low') return 1;
    return 0;
  }

  Future<void> _loadInsights() async {
    final insights = await DailyPlanService.instance.fetchInsights(days: 7);
    if (insights == null || !mounted) {
      return;
    }

    final riskTrend = insights.riskTrend;
    String trendText = 'Add more survey entries to view trend.';
    var hasImprovement = false;
    if (riskTrend.length >= 2) {
      final latest = riskTrend.last;
      final previous = riskTrend[riskTrend.length - 2];
      final latestLevel = (latest['risk_level'] ?? '').toString();
      final previousLevel = (previous['risk_level'] ?? '').toString();
      final latestScore = (latest['risk_score'] as num?)?.toDouble();
      final previousScore = (previous['risk_score'] as num?)?.toDouble();

      final levelImproved = _riskRank(latestLevel) < _riskRank(previousLevel);
      final scoreImproved = latestScore != null &&
          previousScore != null &&
          (previousScore - latestScore) >= 1.0;
      hasImprovement = levelImproved || scoreImproved;

      if (levelImproved) {
        trendText = 'Risk trend: Improved from $previousLevel to $latestLevel.';
      } else if (scoreImproved) {
        trendText =
            'Risk score improved by ${(previousScore - latestScore).toStringAsFixed(1)} points.';
      } else {
        trendText = 'Risk trend: Stable. Keep consistency to improve further.';
      }
    } else if (riskTrend.length == 1) {
      trendText = 'Complete one more survey to unlock trend insight.';
    }

    setState(() {
      _weeklyCompletionPercent = insights.weeklyCompletionPct;
      _streakDays = insights.streakDays;
      _serverCompletionSeries = insights.completionSeries;
      _serverRiskTrend = riskTrend;
      _surveyCount = riskTrend.length;
      _hasSignificantImprovement = hasImprovement;
      _riskTrendText = trendText;
    });
  }

  bool get _shouldPromptResurvey {
    return _streakDays >= 7 || _streakBroken || _hasSignificantImprovement;
  }

  String get _triggerMessage {
    if (_streakDays >= 7) {
      return 'You reached a 7-day consistency streak. Time to take survey again.';
    }
    if (_streakBroken) {
      return 'Your consistency dropped. Restart today.';
    }
    if (_hasSignificantImprovement) {
      return 'Great progress detected. Recheck your risk now.';
    }
    return 'Keep going. Re-survey trigger appears after 7 days, streak break, or strong improvement.';
  }

  List<FlSpot> _completionSpots() {
    final series = _serverCompletionSeries;
    if (series.isEmpty) {
      return List<FlSpot>.generate(7, (i) {
        final key = _dateKey(DateTime.now().subtract(Duration(days: 6 - i)));
        final state = _taskHistoryByDate[key] ?? _defaultTaskState();
        final pct = (_completedCount(state) / _taskNames.length) * 100;
        return FlSpot(i.toDouble(), pct);
      });
    }

    return List<FlSpot>.generate(series.length, (i) {
      final value = (series[i]['completion_pct'] as num?)?.toDouble() ?? 0;
      return FlSpot(i.toDouble(), value);
    });
  }

  List<FlSpot> _riskSpots() {
    if (_serverRiskTrend.isEmpty) {
      return const [];
    }
    return List<FlSpot>.generate(_serverRiskTrend.length, (i) {
      final score = (_serverRiskTrend[i]['risk_score'] as num?)?.toDouble() ?? 0;
      return FlSpot(i.toDouble(), score);
    });
  }

  Widget _buildChartCard({
    required String title,
    required List<FlSpot> points,
    required Color lineColor,
    required Color areaColor,
    required double maxY,
    String? emptyText,
  }) {
    if (points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(emptyText ?? 'No chart data yet.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 150,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY > 50 ? 20 : 5,
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  left: BorderSide(color: Colors.grey.shade300),
                  bottom: BorderSide(color: Colors.grey.shade300),
                  right: BorderSide.none,
                  top: BorderSide.none,
                ),
              ),
              titlesData: const FlTitlesData(
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: points,
                  isCurved: true,
                  barWidth: 3,
                  color: lineColor,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: areaColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(DashboardWrapper.routePath);
              }
            },
          ),
          title: const Text('Daily Plan'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(DashboardWrapper.routePath);
            }
          },
        ),
        title: const Text('Daily Plan'),
      ),
      floatingActionButton: const AssistantFab(
        contextHint: 'Get a 7-day plan based on your routine',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Today's Tasks",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      minHeight: 10,
                      value: _todayProgress,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('${(_todayProgress * 100).toStringAsFixed(0)}% completed today'),
                  const SizedBox(height: 14),
                  ..._taskNames.map((task) {
                    final completed = _todayTasks[task] == true;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(task),
                            value: completed,
                            onChanged: (value) => _toggleTask(task, value == true),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                          LinearProgressIndicator(
                            minHeight: 6,
                            value: completed ? 1 : 0,
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Text('🔥', style: TextStyle(fontSize: 22)),
              title: const Text(
                'Consistency Score',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('$_streakDays Day Streak'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Progress Trigger',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(_triggerMessage),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _shouldPromptResurvey
                        ? () => context.push(SurveyPage.routePath)
                        : null,
                    icon: const Icon(Icons.assignment_outlined),
                    label: const Text('Take Survey Again'),
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
                  const Text(
                    'Weekly Insight',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text('Task completion (7 days): ${_weeklyCompletionPercent.toStringAsFixed(1)}%'),
                  const SizedBox(height: 6),
                  Text('Risk trend: $_riskTrendText'),
                  const SizedBox(height: 6),
                  Text('Survey records used: $_surveyCount'),
                  const SizedBox(height: 14),
                  _buildChartCard(
                    title: 'Weekly Completion Trend',
                    points: _completionSpots(),
                    lineColor: const Color(0xFF2F80ED),
                    areaColor: const Color(0x332F80ED),
                    maxY: 100,
                  ),
                  const SizedBox(height: 16),
                  _buildChartCard(
                    title: 'Risk Score Trend',
                    points: _riskSpots(),
                    lineColor: const Color(0xFFE65100),
                    areaColor: const Color(0x33E65100),
                    maxY: 30,
                    emptyText: 'Complete more surveys to see risk trend chart.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
