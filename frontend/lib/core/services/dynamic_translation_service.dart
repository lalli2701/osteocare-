import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_service.dart';
import 'medical_terms_service.dart';
import 'translation_cache_service.dart';
import 'translation_feedback_service.dart';

class DynamicTranslationService {
  DynamicTranslationService._internal();

  static final DynamicTranslationService instance =
      DynamicTranslationService._internal();

  static const String _languageKey = 'preferred_language';
  static const String _versionKey = 'translation_cache_version';
  static const int _maxCacheEntries = 2000;
  static const int _batchRetries = 1;

  final LinkedHashMap<String, String> _sessionCache =
      LinkedHashMap<String, String>();

  Future<String> _getCacheVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_versionKey) ?? '1.0.0';
  }

  Future<String> _getPreferredLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_languageKey) ?? 'en').toLowerCase();
  }

  String? _sessionCacheGet(String key) {
    final val = _sessionCache[key];
    if (val == null) {
      return null;
    }
    _sessionCache.remove(key);
    _sessionCache[key] = val;
    return val;
  }

  void _sessionCacheSet(String key, String value) {
    if (_sessionCache.length >= _maxCacheEntries) {
      _sessionCache.remove(_sessionCache.keys.first);
    }
    _sessionCache[key] = value;
  }

  Future<String> translate(
    String text, {
    String? langCode,
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return text;
    }

    final targetLang = (langCode ?? await _getPreferredLanguage()).toLowerCase();
    if (targetLang == 'en') {
      return text;
    }

    final sessionKey = '$targetLang|$normalizedText';
    final sessionCached = _sessionCacheGet(sessionKey);
    if (sessionCached != null) {
      return sessionCached;
    }

    final cacheVersion = await _getCacheVersion();
    final dbCached = await TranslationCacheService.instance.get(
      langCode: targetLang,
      version: cacheVersion,
      originalText: normalizedText,
    );
    if (dbCached != null) {
      _sessionCacheSet(sessionKey, dbCached);
      return dbCached;
    }

    try {
      // Protect medical terms before translation
      String textForTranslation = normalizedText;
      final protectedTermsMap = <String, String>{};
      
      if (MedicalTermsService.hasProtectedTerms(normalizedText, targetLang)) {
        final terms =
            MedicalTermsService.extractProtectedTerms(normalizedText, targetLang);
        for (int i = 0; i < terms.length; i++) {
          final term = terms[i];
          final placeholder = '<<<MEDICAL_${i}>>>';
          textForTranslation = textForTranslation.replaceAll(
            RegExp(term, caseSensitive: false),
            placeholder,
          );
          protectedTermsMap[placeholder] = term;
        }
      }

      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/translate'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': 'dev-key',
        },
        body: jsonEncode({
          'text': textForTranslation,
          'lang': targetLang,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        var body = jsonDecode(response.body);
        var translated = (body is Map<String, dynamic>)
            ? (body['translated']?.toString() ?? normalizedText)
            : normalizedText;
        final usedFallback = body is Map<String, dynamic> && body['fallback'] == true;
        if (usedFallback) {
          TranslationFeedbackService.instance.notifyFallback();
        }

        // Restore protected medical terms
        if (protectedTermsMap.isNotEmpty) {
          protectedTermsMap.forEach((placeholder, term) {
            translated = translated.replaceAll(placeholder, term);
          });
        }

        final finalText = translated.isNotEmpty ? translated : normalizedText;
        _sessionCacheSet(sessionKey, finalText);
        await TranslationCacheService.instance.set(
          langCode: targetLang,
          version: cacheVersion,
          originalText: normalizedText,
          translatedText: finalText,
        );
        return finalText;
      }
    } catch (_) {
      // Fallback to original text gracefully.
    }

    TranslationFeedbackService.instance.notifyFallback();
    _sessionCacheSet(sessionKey, text);
    return text;
  }

  Future<List<String>> translateMany(
    List<String> items, {
    String? langCode,
  }) async {
    if (items.isEmpty) {
      return items;
    }

    final targetLang = (langCode ?? await _getPreferredLanguage()).toLowerCase();
    if (targetLang == 'en') {
      return items;
    }

    final cacheVersion = await _getCacheVersion();
    final results = List<String>.filled(items.length, '');
    final missingTexts = <String>[];
    final missingIndexesByText = <String, List<int>>{};

    for (var i = 0; i < items.length; i++) {
      final normalized = items[i].trim();
      if (normalized.isEmpty) {
        results[i] = items[i];
        continue;
      }

      final sessionKey = '$targetLang|$normalized';
      final sessionCached = _sessionCacheGet(sessionKey);
      if (sessionCached != null) {
        results[i] = sessionCached;
        continue;
      }

      final dbCached = await TranslationCacheService.instance.get(
        langCode: targetLang,
        version: cacheVersion,
        originalText: normalized,
      );
      if (dbCached != null) {
        results[i] = dbCached;
        _sessionCacheSet(sessionKey, dbCached);
        continue;
      }

      missingIndexesByText.putIfAbsent(normalized, () {
        missingTexts.add(normalized);
        return <int>[];
      }).add(i);
    }

    if (missingTexts.isEmpty) {
      return results;
    }

    try {
      // Protect medical terms before translation
      final textsForTranslation = <String>[];
      final protectedTermsMaps = <Map<String, String>>[];

      for (final text in missingTexts) {
        var textToSend = text;
        final protectedMap = <String, String>{};
        
        if (MedicalTermsService.hasProtectedTerms(text, targetLang)) {
          final terms = MedicalTermsService.extractProtectedTerms(text, targetLang);
          for (int i = 0; i < terms.length; i++) {
            final term = terms[i];
            final placeholder = '<<<MEDICAL_${i}>>>';
            textToSend = textToSend.replaceAll(
              RegExp(term, caseSensitive: false),
              placeholder,
            );
            protectedMap[placeholder] = term;
          }
        }
        
        textsForTranslation.add(textToSend);
        protectedTermsMaps.add(protectedMap);
      }

      var batchResponse = await http.post(
        Uri.parse('${AuthService.baseUrl}/translate'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': 'dev-key',
        },
        body: jsonEncode({
          'texts': textsForTranslation,
          'lang': targetLang,
        }),
      );

      if (batchResponse.statusCode >= 400 && batchResponse.statusCode < 500) {
        if (_batchRetries > 0) {
          await Future.delayed(const Duration(milliseconds: 500));
          batchResponse = await http.post(
            Uri.parse('${AuthService.baseUrl}/translate'),
            headers: {
              'Content-Type': 'application/json',
              'X-API-Key': 'dev-key',
            },
            body: jsonEncode({
              'texts': textsForTranslation,
              'lang': targetLang,
            }),
          );
        }
      }

      if (batchResponse.statusCode >= 200 && batchResponse.statusCode < 300) {
        final body = jsonDecode(batchResponse.body);
        final translatedByText = <String, String>{};
        var usedFallback = false;

        if (body is Map<String, dynamic>) {
          final translations = body['translations'];
          if (translations is List) {
            for (var idx = 0; idx < translations.length; idx++) {
              final entry = translations[idx];
              if (entry is! Map) {
                continue;
              }
              var sourceText = entry['text']?.toString() ?? '';
              if (sourceText.isEmpty) {
                continue;
              }
              var translated = entry['translated']?.toString() ?? sourceText;
              
              // Restore protected medical terms for this translation
              if (idx < protectedTermsMaps.length) {
                final protectedMap = protectedTermsMaps[idx];
                protectedMap.forEach((placeholder, term) {
                  translated = translated.replaceAll(placeholder, term);
                  sourceText = sourceText.replaceAll(placeholder, term);
                });
              }
              
              translatedByText[missingTexts[idx]] =
                  translated.isNotEmpty ? translated : missingTexts[idx];
              usedFallback = usedFallback || entry['fallback'] == true;
            }
          }
        }

        for (final sourceText in missingTexts) {
          final translated = translatedByText[sourceText] ?? sourceText;
          _sessionCacheSet('$targetLang|$sourceText', translated);
          await TranslationCacheService.instance.set(
            langCode: targetLang,
            version: cacheVersion,
            originalText: sourceText,
            translatedText: translated,
          );
          final indexes = missingIndexesByText[sourceText] ?? const <int>[];
          for (final index in indexes) {
            results[index] = translated;
          }
        }

        if (usedFallback) {
          TranslationFeedbackService.instance.notifyFallback();
        }
        return results;
      }
    } catch (_) {
      // Fall back to per-item translation if batch fails.
    }

    final fallbackTranslated = await Future.wait(
      missingTexts.map((text) => translate(text, langCode: targetLang)),
    );

    for (var i = 0; i < missingTexts.length; i++) {
      final sourceText = missingTexts[i];
      final translated = fallbackTranslated[i];
      final indexes = missingIndexesByText[sourceText] ?? const <int>[];
      for (final index in indexes) {
        results[index] = translated;
      }
    }

    return results;
  }
}
