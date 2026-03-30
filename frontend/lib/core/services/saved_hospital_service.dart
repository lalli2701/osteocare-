import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_service.dart';
import '../auth/user_session.dart';

class SavedHospitalService {
  static const String _savedHospitalsKeyPrefix = 'saved_hospitals_v2';
  static const String _legacySavedHospitalsKey = 'saved_hospitals_v1';
  static const String _anonymousHospitalsKey = '${_savedHospitalsKeyPrefix}_anon';

  static Future<String> _resolveStorageKey() async {
    final sessionUid = UserSession.instance.userId?.trim();
    if (sessionUid != null && sessionUid.isNotEmpty) {
      return '${_savedHospitalsKeyPrefix}_$sessionUid';
    }

    final userData = await AuthService.instance.getUserData();
    final authUid = userData?['id']?.toString().trim();
    if (authUid != null && authUid.isNotEmpty) {
      UserSession.instance.userId = authUid;
      return '${_savedHospitalsKeyPrefix}_$authUid';
    }

    return _anonymousHospitalsKey;
  }

  static Future<void> _migrateLegacyIfNeeded({
    required SharedPreferences prefs,
    required String key,
  }) async {
    if (prefs.containsKey(key)) {
      return;
    }

    final legacyRaw = prefs.getString(_legacySavedHospitalsKey);
    if (legacyRaw == null || legacyRaw.isEmpty) {
      return;
    }

    await prefs.setString(key, legacyRaw);
  }

  static Future<List<Map<String, dynamic>>> getSavedHospitals() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _resolveStorageKey();
    await _migrateLegacyIfNeeded(prefs: prefs, key: key);

    final raw = prefs.getString(key);
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
    final key = await _resolveStorageKey();
    await _migrateLegacyIfNeeded(prefs: prefs, key: key);
    await prefs.setString(key, jsonEncode(current));
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
    final key = await _resolveStorageKey();
    await _migrateLegacyIfNeeded(prefs: prefs, key: key);
    await prefs.setString(key, jsonEncode(current));
  }
}
