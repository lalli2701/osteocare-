import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dynamic_translation_service.dart';

class ReminderService {
  static const String _assetPath = 'assets/reminders_master.json';
  static const String _languageKey = 'preferred_language';
  static const String _todayTipKeyPrefix = 'today_tip_';
  static const String _todayTipDateKeyPrefix = 'today_tip_date_';
  static const String _translatedTipsKeyPrefix = 'translated_tips_';
  static const List<String> _fallbackTips = [
    'Stay active and eat healthy.',
    'Take a short walk and keep your bones moving.',
    'Choose calcium-rich foods and hydrate well.',
  ];

  static Future<Map<String, dynamic>> loadReminders() async {
    try {
      final data = await rootBundle.loadString(_assetPath);
      final decoded = json.decode(data);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  static String normalizeRisk(String risk) {
    final value = risk.trim().toUpperCase();
    if (value == 'LOW' || value == 'MODERATE' || value == 'HIGH') {
      return value;
    }
    return 'MODERATE';
  }

  static String ageGroupFromAge(dynamic age) {
    final parsed = int.tryParse(age?.toString() ?? '');
    if (parsed == null) {
      return '18-50';
    }
    if (parsed <= 50) {
      return '18-50';
    }
    return '51+';
  }

  static Future<List<String>> getTips({
    required String ageGroup,
    required String risk,
    List<String>? slots,
    String? langCode,
  }) async {
    try {
      final data = await loadReminders();
      final normalizedRisk = normalizeRisk(risk);

      final byAge = data[ageGroup];
      if (byAge is! Map) {
        return _translateTipsForPreferredLanguage(
          _fallbackTips,
          ageGroup: ageGroup,
          risk: normalizedRisk,
          slots: const ['default'],
          langCode: langCode,
        );
      }

      final byRisk = byAge[normalizedRisk];
      if (byRisk is! Map) {
        return _translateTipsForPreferredLanguage(
          _fallbackTips,
          ageGroup: ageGroup,
          risk: normalizedRisk,
          slots: const ['default'],
          langCode: langCode,
        );
      }

      final preferredSlots = (slots == null || slots.isEmpty)
          ? const ['morning', 'afternoon', 'evening']
          : slots.map((s) => s.trim().toLowerCase()).toList();

      final tips = <String>[];
      for (final slot in preferredSlots) {
        final slotTips = byRisk[slot];
        if (slotTips is List) {
          tips.addAll(slotTips.map((item) => item.toString()));
        }
      }

      if (tips.isEmpty) {
        return _translateTipsForPreferredLanguage(
          _fallbackTips,
          ageGroup: ageGroup,
          risk: normalizedRisk,
          slots: preferredSlots,
          langCode: langCode,
        );
      }

      return _translateTipsForPreferredLanguage(
        tips,
        ageGroup: ageGroup,
        risk: normalizedRisk,
        slots: preferredSlots,
        langCode: langCode,
      );
    } catch (_) {
      return _translateTipsForPreferredLanguage(
        _fallbackTips,
        ageGroup: ageGroup,
        risk: normalizeRisk(risk),
        slots: const ['default'],
        langCode: langCode,
      );
    }
  }

  static String _buildTipsCacheKey({
    required String langCode,
    required String ageGroup,
    required String risk,
    required List<String> slots,
  }) {
    final normalizedSlots = slots.map((s) => s.trim().toLowerCase()).join(',');
    return '$_translatedTipsKeyPrefix$langCode|$ageGroup|$risk|$normalizedSlots';
  }

  static Future<List<String>?> _readTranslatedTipsCache(String cacheKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return null;
      }
      final values = decoded.map((item) => item.toString()).toList();
      if (values.isEmpty) {
        return null;
      }
      return values;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeTranslatedTipsCache(
    String cacheKey,
    List<String> tips,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode(tips));
    } catch (_) {
      // Ignore cache write failures.
    }
  }

  static Future<List<String>> _translateTipsForPreferredLanguage(
    List<String> tips, {
    required String ageGroup,
    required String risk,
    required List<String> slots,
    String? langCode,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final effectiveLangCode =
          (langCode ?? prefs.getString(_languageKey) ?? 'en').toLowerCase();
      if (effectiveLangCode == 'en') {
        return tips;
      }

      final cacheKey = _buildTipsCacheKey(
        langCode: effectiveLangCode,
        ageGroup: ageGroup,
        risk: risk,
        slots: slots,
      );
      final cached = await _readTranslatedTipsCache(cacheKey);
      if (cached != null) {
        return cached;
      }

      final translated = await DynamicTranslationService.instance.translateMany(
        tips,
        langCode: effectiveLangCode,
      );
      await _writeTranslatedTipsCache(cacheKey, translated);
      return translated;
    } catch (_) {
      return tips;
    }
  }

  static Future<void> preTranslateForLanguage(String langCode) async {
    final normalizedLang = langCode.trim().toLowerCase();
    if (normalizedLang.isEmpty || normalizedLang == 'en') {
      return;
    }

    final data = await loadReminders();
    if (data.isEmpty) {
      return;
    }

    for (final ageEntry in data.entries) {
      final ageGroup = ageEntry.key;
      final byRisk = ageEntry.value;
      if (byRisk is! Map) {
        continue;
      }

      for (final riskEntry in byRisk.entries) {
        final risk = riskEntry.key.toString();
        final bySlot = riskEntry.value;
        if (bySlot is! Map) {
          continue;
        }

        final slots = bySlot.keys.map((k) => k.toString()).toList();
        await getTips(
          ageGroup: ageGroup,
          risk: risk,
          slots: slots,
          langCode: normalizedLang,
        );
      }
    }
  }

  static String getRandomTip(List<String> tips) {
    if (tips.isEmpty) {
      return 'Take a few minutes to move and protect your bones today.';
    }
    final random = Random();
    return tips[random.nextInt(tips.length)];
  }

  static Future<String> getOrCreateTodayTip(
    List<String> tips, {
    String slotTag = 'default',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T').first;
    final tipKey = '$_todayTipKeyPrefix$slotTag';
    final dateKey = '$_todayTipDateKeyPrefix$slotTag';
    final savedDate = prefs.getString(dateKey);
    final savedTip = prefs.getString(tipKey);

    if (savedDate == today && savedTip != null && savedTip.isNotEmpty) {
      return savedTip;
    }

    final tip = getRandomTip(tips.isEmpty ? _fallbackTips : tips);
    await prefs.setString(dateKey, today);
    await prefs.setString(tipKey, tip);
    return tip;
  }
}
