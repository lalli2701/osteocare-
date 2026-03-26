import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_service.dart';
import 'survey_sync_service.dart';

class ReminderConfig {
  const ReminderConfig({
    required this.ageGroup,
    required this.riskLevel,
    required this.reminderTime,
    required this.enabled,
    required this.reminderSlots,
  });

  final String ageGroup;
  final String riskLevel;
  final String reminderTime;
  final bool enabled;
  final List<String> reminderSlots;

  factory ReminderConfig.fromJson(Map<String, dynamic> json) {
    return ReminderConfig(
      ageGroup: (json['age_group']?.toString().trim().isNotEmpty ?? false)
          ? json['age_group'].toString().trim()
          : '18-50',
      riskLevel: (json['risk_level']?.toString().trim().isNotEmpty ?? false)
          ? json['risk_level'].toString().trim().toUpperCase()
          : 'MODERATE',
      reminderTime: (json['reminder_time']?.toString().trim().isNotEmpty ?? false)
          ? json['reminder_time'].toString().trim()
          : '08:00',
      enabled: json['enabled'] == true,
      reminderSlots: ((json['reminder_slots'] as List?) ?? const <dynamic>[])
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toList(),
    );
  }
}

class ReminderSyncService {
  ReminderSyncService._internal();

  static final ReminderSyncService instance = ReminderSyncService._internal();

  Future<String> _resolveUserId() async {
    return SurveySyncService.instance.resolveEffectiveUserId();
  }

  Future<Map<String, String>> _buildHeaders({required String userId}) async {
    return {
      'Content-Type': 'application/json',
      'X-User-Id': userId,
      'X-API-Key': 'dev-key',
    };
  }

  Future<ReminderConfig?> fetchConfig({String? userId}) async {
    final effectiveUserId = userId ?? await _resolveUserId();
    try {
      final headers = await _buildHeaders(userId: effectiveUserId);
      final uri = Uri.parse('${AuthService.baseUrl}/reminder/get')
          .replace(queryParameters: {'user_id': effectiveUserId});
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final data = Map<String, dynamic>.from(
        (jsonDecode(response.body) as Map?) ?? const <String, dynamic>{},
      );
      final config = data['config'];
      if (config is! Map) {
        return null;
      }
      return ReminderConfig.fromJson(Map<String, dynamic>.from(config));
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveConfig({
    String? userId,
    required String ageGroup,
    required String riskLevel,
    required String reminderTime,
    required bool enabled,
    required List<String> reminderSlots,
  }) async {
    final effectiveUserId = userId ?? await _resolveUserId();
    try {
      final headers = await _buildHeaders(userId: effectiveUserId);
      final response = await http
          .post(
            Uri.parse('${AuthService.baseUrl}/reminder/config'),
            headers: headers,
            body: jsonEncode({
              'user_id': effectiveUserId,
              'age_group': ageGroup,
              'risk_level': riskLevel,
              'reminder_time': reminderTime,
              'enabled': enabled,
              'reminder_slots': reminderSlots,
            }),
          )
          .timeout(const Duration(seconds: 12));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<void> logHabit({
    String? userId,
    required String tip,
    required bool completed,
    required DateTime date,
  }) async {
    final effectiveUserId = userId ?? await _resolveUserId();
    try {
      final headers = await _buildHeaders(userId: effectiveUserId);
      await http
          .post(
            Uri.parse('${AuthService.baseUrl}/reminder/habit'),
            headers: headers,
            body: jsonEncode({
              'tip': tip,
              'completed': completed,
              'date': date.toIso8601String().split('T').first,
            }),
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      // Ignore logging failures to avoid blocking UX.
    }
  }
}
