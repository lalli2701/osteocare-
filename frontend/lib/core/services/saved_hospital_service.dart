import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SavedHospitalService {
  static const String _savedHospitalsKey = 'saved_hospitals_v1';

  static Future<List<Map<String, dynamic>>> getSavedHospitals() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedHospitalsKey);
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
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<bool> saveHospital(Map<String, dynamic> hospital) async {
    final current = await getSavedHospitals();
    final name = (hospital['name'] ?? '').toString().trim().toLowerCase();
    final address = (hospital['address'] ?? '').toString().trim().toLowerCase();

    final alreadySaved = current.any((item) {
      final itemName = (item['name'] ?? '').toString().trim().toLowerCase();
      final itemAddress = (item['address'] ?? '').toString().trim().toLowerCase();
      return itemName == name && itemAddress == address;
    });

    if (alreadySaved) {
      return false;
    }

    current.insert(0, {
      ...hospital,
      'savedAt': DateTime.now().toIso8601String(),
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedHospitalsKey, jsonEncode(current));
    return true;
  }

  static Future<void> removeHospital(Map<String, dynamic> hospital) async {
    final current = await getSavedHospitals();
    final name = (hospital['name'] ?? '').toString().trim().toLowerCase();
    final address = (hospital['address'] ?? '').toString().trim().toLowerCase();

    current.removeWhere((item) {
      final itemName = (item['name'] ?? '').toString().trim().toLowerCase();
      final itemAddress = (item['address'] ?? '').toString().trim().toLowerCase();
      return itemName == name && itemAddress == address;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedHospitalsKey, jsonEncode(current));
  }
}
