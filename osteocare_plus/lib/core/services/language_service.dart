import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../auth/auth_service.dart';

enum AppLanguage {
  english('en', 'English', 'english'),
  hindi('hi', 'हिंदी (Hindi)', 'hindi'),
  telugu('te', 'తెలుగు (Telugu)', 'telugu');

  final String code;
  final String displayName;
  final String backendValue;

  const AppLanguage(this.code, this.displayName, this.backendValue);

  static AppLanguage fromCode(String code) {
    return AppLanguage.values.firstWhere(
      (lang) => lang.code == code,
      orElse: () => AppLanguage.english,
    );
  }

  static AppLanguage fromBackendValue(String value) {
    return AppLanguage.values.firstWhere(
      (lang) => lang.backendValue == value,
      orElse: () => AppLanguage.english,
    );
  }
}

class LanguageService {
  static const String _languageKey = 'preferred_language';
  static const String _backendUrl = 'http://localhost:5000';

  static Future<void> changeLanguage(
    BuildContext context,
    AppLanguage language,
  ) async {
    // Update app locale
    await context.setLocale(Locale(language.code));

    // Save locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, language.code);

    // Send to backend
    await _updateBackendLanguage(language.backendValue);
  }

  static Future<void> _updateBackendLanguage(String language) async {
    try {
      final token = await AuthService.instance.getToken();
      if (token == null) return;

      final response = await http.post(
        Uri.parse('$_backendUrl/api/user/preferences'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'preferred_language': language}),
      );

      if (response.statusCode != 200) {
        // Language update failed
      }
    } catch (e) {
      // Error updating language preference
    }
  }

  static Future<AppLanguage> getSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_languageKey) ?? 'en';
    return AppLanguage.fromCode(code);
  }

  static Future<void> loadLanguageFromBackend(BuildContext context) async {
    try {
      final token = await AuthService.instance.getToken();
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$_backendUrl/api/dashboard'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final preferredLanguage = data['preferred_language'] as String?;
        
        if (preferredLanguage != null) {
          final language = AppLanguage.fromBackendValue(preferredLanguage);
          await context.setLocale(Locale(language.code));
          
          // Save locally
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_languageKey, language.code);
        }
      }
    } catch (e) {
      // Error loading language from backend
    }
  }

  static String getTTSLanguageCode(AppLanguage language) {
    switch (language) {
      case AppLanguage.english:
        return 'en-IN';
      case AppLanguage.hindi:
        return 'hi-IN';
      case AppLanguage.telugu:
        return 'te-IN';
    }
  }
}
