import 'package:shared_preferences/shared_preferences.dart';

import 'dynamic_translation_service.dart';

/// Ensures consistent language handling across chatbot conversations.
/// Prevents double translation and semantic drift.
class ChatbotLanguagePipeline {
  static const String _conversationLangKey = 'chatbot_conversation_lang';
  static const String _userPreferredLangKey = 'chatbot_user_preferred_lang';

  /// Initialize conversation language consistency.
  /// Must be called before processing chatbot messages.
  static Future<void> initializeConversation() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Get the user's preferred language
    final userLang = prefs.getString(_userPreferredLangKey) ?? 'en';
    
    // Set conversation language to user's preferred language
    await prefs.setString(_conversationLangKey, userLang);
  }

  /// Get the language for the current conversation
  static Future<String> getConversationLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_conversationLangKey) ?? 'en';
  }

  /// Set the conversation language explicitly
  static Future<void> setConversationLanguage(String langCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_conversationLangKey, langCode.toLowerCase());
  }

  /// Process user input in the chatbot conversation.
  /// Ensures consistent language handling from user → backend.
  static Future<String> processUserInput(String userMessage) async {
    if (userMessage.trim().isEmpty) {
      return userMessage;
    }

    final prefs = await SharedPreferences.getInstance();
    final conversationLang =
        prefs.getString(_conversationLangKey) ?? 'en';

    // If conversation is in English, send as-is
    if (conversationLang == 'en') {
      return userMessage;
    }

    // User message is in their local language.
    // For now, we assume backend expects English for processing.
    // If the backend can handle the user's language, send as-is.
    // Otherwise, translate the user message to English before sending.

    return userMessage; // Backend will handle the user's language
  }

  /// Process chatbot response for consistent language output.
  /// Translates backend response to conversation language if needed.
  static Future<String> processChatbotResponse(
    String response, {
    String? sourceLang,
  }) async {
    if (response.trim().isEmpty) {
      return response;
    }

    final prefs = await SharedPreferences.getInstance();
    final conversationLang =
        prefs.getString(_conversationLangKey) ?? 'en';

    // If conversation is in English, return as-is (assuming backend returns English)
    if (conversationLang == 'en') {
      return response;
    }

    // Source language defaults to English (backend response language)
    final source = sourceLang?.toLowerCase() ?? 'en';

    // If response is already in the conversation language, return as-is
    if (source == conversationLang) {
      return response;
    }

    // Translate response to conversation language
    try {
      final translated = await DynamicTranslationService.instance.translate(
        response,
        langCode: conversationLang,
      );
      return translated;
    } catch (_) {
      // If translation fails, return original response
      return response;
    }
  }

  /// Process a batch of chatbot responses
  static Future<List<String>> processChatbotResponses(
    List<String> responses, {
    String? sourceLang,
  }) async {
    if (responses.isEmpty) {
      return responses;
    }

    final prefs = await SharedPreferences.getInstance();
    final conversationLang =
        prefs.getString(_conversationLangKey) ?? 'en';

    // If conversation is in English, return as-is
    if (conversationLang == 'en') {
      return responses;
    }

    final source = sourceLang?.toLowerCase() ?? 'en';

    // If responses are already in the conversation language, return as-is
    if (source == conversationLang) {
      return responses;
    }

    // Batch translate responses to conversation language
    try {
      final translated = await DynamicTranslationService.instance.translateMany(
        responses,
        langCode: conversationLang,
      );
      return translated;
    } catch (_) {
      // If translation fails, return original responses
      return responses;
    }
  }

  /// Ensure message consistency across sessions
  /// Validates that the conversation language hasn't changed unexpectedly
  static Future<bool> validateLanguageConsistency() async {
    final prefs = await SharedPreferences.getInstance();
    
    final conversationLang =
        prefs.getString(_conversationLangKey) ?? 'en';
    final userPreferredLang =
        prefs.getString(_userPreferredLangKey) ?? 'en';

    // If user's preferred language changed, update conversation language
    if (userPreferredLang != conversationLang) {
      await setConversationLanguage(userPreferredLang);
      return false; // Indicates a language change
    }

    return true; // Consistent
  }

  /// Reset conversation language (useful when starting a new chat)
  static Future<void> resetConversationLanguage() async {
    await initializeConversation();
  }

  /// Get diagnostics information for debugging language issues
  static Future<Map<String, String>> getDiagnostics() async {
    final prefs = await SharedPreferences.getInstance();
    
    return {
      'conversation_language': prefs.getString(_conversationLangKey) ?? 'en',
      'user_preferred_language': prefs.getString(_userPreferredLangKey) ?? 'en',
    };
  }
}
