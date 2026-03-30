import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_service.dart';

class DailyPlanTaskRecord {
  DailyPlanTaskRecord({
    required this.date,
    required this.taskName,
    required this.completed,
  });

  final String date;
  final String taskName;
  final bool completed;

  factory DailyPlanTaskRecord.fromJson(Map<String, dynamic> json) {
    return DailyPlanTaskRecord(
      date: (json['date'] ?? '').toString(),
      taskName: (json['task_name'] ?? '').toString(),
      completed: json['completed'] == true,
    );
  }
}

class DailyPlanInsights {
  DailyPlanInsights({
    required this.weeklyCompletionPct,
    required this.streakDays,
    required this.completionSeries,
    required this.riskTrend,
  });

  final double weeklyCompletionPct;
  final int streakDays;
  final List<Map<String, dynamic>> completionSeries;
  final List<Map<String, dynamic>> riskTrend;

  factory DailyPlanInsights.fromJson(Map<String, dynamic> json) {
    return DailyPlanInsights(
      weeklyCompletionPct: (json['weekly_completion_pct'] as num?)?.toDouble() ?? 0,
      streakDays: (json['streak_days'] as num?)?.toInt() ?? 0,
      completionSeries: List<Map<String, dynamic>>.from(
        json['completion_series'] ?? const <Map<String, dynamic>>[],
      ),
      riskTrend: List<Map<String, dynamic>>.from(
        json['risk_trend'] ?? const <Map<String, dynamic>>[],
      ),
    );
  }
}

class DailyPlanService {
  DailyPlanService._internal();

  static final DailyPlanService instance = DailyPlanService._internal();

  Future<Map<String, String>?> _headersWithAuth() async {
    final token = await AuthService.instance.getToken();
    if (token == null || token.isEmpty) {
      return null;
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<List<DailyPlanTaskRecord>> fetchTasks({int days = 30}) async {
    final headers = await _headersWithAuth();
    if (headers == null) {
      return const <DailyPlanTaskRecord>[];
    }

    final uri = Uri.parse('${AuthService.baseUrl}/api/user/tasks')
        .replace(queryParameters: {'days': '$days'});
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      return const <DailyPlanTaskRecord>[];
    }

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      return const <DailyPlanTaskRecord>[];
    }

    final records = body['records'];
    if (records is! List) {
      return const <DailyPlanTaskRecord>[];
    }

    return records
        .whereType<Map>()
        .map((e) => DailyPlanTaskRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> upsertTask({
    required String date,
    required String taskName,
    required bool completed,
  }) async {
    final headers = await _headersWithAuth();
    if (headers == null) {
      return;
    }

    await http.post(
      Uri.parse('${AuthService.baseUrl}/api/user/tasks/upsert'),
      headers: headers,
      body: jsonEncode({
        'date': date,
        'task_name': taskName,
        'completed': completed,
      }),
    );
  }

  Future<DailyPlanInsights?> fetchInsights({int days = 7}) async {
    final headers = await _headersWithAuth();
    if (headers == null) {
      return null;
    }

    final uri = Uri.parse('${AuthService.baseUrl}/api/user/tasks/insights')
        .replace(queryParameters: {'days': '$days'});
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      return null;
    }

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      return null;
    }

    return DailyPlanInsights.fromJson(body);
  }
}
