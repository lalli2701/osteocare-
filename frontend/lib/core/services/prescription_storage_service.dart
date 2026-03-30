import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PrescriptionStorageService {
  static const String _reportsKey = 'prescription_reports_v1';

  static Future<List<Map<String, dynamic>>> getReports() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_reportsKey);
    if (raw == null || raw.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <Map<String, dynamic>>[];
      }
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> addReport({
    required String filePath,
    required String fileName,
    required String source,
  }) async {
    final current = await getReports();
    current.insert(0, {
      'filePath': filePath,
      'fileName': fileName,
      'source': source,
      'addedAt': DateTime.now().toIso8601String(),
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_reportsKey, jsonEncode(current));
  }

  static Future<List<Map<String, dynamic>>> getReportsBySources(
    Set<String> sources,
  ) async {
    final all = await getReports();
    if (sources.isEmpty) {
      return all;
    }

    return all.where((item) {
      final source = (item['source'] ?? '').toString();
      return sources.contains(source);
    }).toList();
  }
}
