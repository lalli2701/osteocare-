/// Service to protect critical medical terms from being auto-translated.
/// Medical context requires accuracy — these terms should remain consistent
/// across all languages to prevent semantic drift.
class MedicalTermsService {
  /// Protected medical terms that should NOT be auto-translated.
  /// These terms are kept standard to ensure medical accuracy.
  static const Map<String, List<String>> _protectedTerms = {
    'en': [
      'bone density',
      'osteoporosis',
      'osteopenia',
      'fracture risk',
      'calcium',
      'vitamin D',
      'BMD',
      'DEXA scan',
      'T-score',
      'Z-score',
      'osteoblast',
      'osteoclast',
      'mineralisation',
      'trabecular bone',
      'cortical bone',
      'remodeling',
      'PTH',
      'estrogen',
      'bisphosphonate',
      'HRT',
    ],
    'hi': [
      'bone density',
      'osteoporosis',
      'osteopenia',
      'fracture risk',
      'DEXA scan',
      'BMD',
      'T-score',
      'Z-score',
    ],
    'te': [
      'bone density',
      'osteoporosis',
      'osteopenia',
      'fracture risk',
      'DEXA scan',
      'BMD',
      'T-score',
      'Z-score',
    ],
  };

  /// Preserves protected medical terms in translated text.
  /// Replaces protected terms with placeholders, translates, then restores.
  static String preserveProtectedTerms(
    String text,
    String targetLang,
  ) {
    if (text.isEmpty) return text;

    String result = text;
    final terms = _protectedTerms[targetLang] ?? [];

    // Replace protected terms with placeholders
    final Map<String, String> placeholders = {};
    for (int i = 0; i < terms.length; i++) {
      final term = terms[i];
      final placeholder = '<<<MEDICAL_TERM_$i>>>';
      if (result.toLowerCase().contains(term.toLowerCase())) {
        // Case-insensitive replacement
        result = result.replaceAll(
          RegExp(term, caseSensitive: false),
          placeholder,
        );
        placeholders[placeholder] = term;
      }
    }

    return _encodeForTransport(result, placeholders);
  }

  /// Restore protected medical terms after translation.
  static String restoreProtectedTerms(
    String translatedText,
    Map<String, String> placeholders,
  ) {
    if (placeholders.isEmpty) return translatedText;

    String result = translatedText;
    placeholders.forEach((placeholder, term) {
      result = result.replaceAll(placeholder, term);
    });

    return result;
  }

  /// Encode placeholders map for transport through translation API
  static String _encodeForTransport(
    String text,
    Map<String, String> placeholders,
  ) {
    return '$text\n<<<MEDICAL_PROTECTED:${placeholders.keys.join(',')}>>';
  }

  /// Returns a mapping of medical terms for the given language
  static List<String> getTermsForLanguage(String langCode) {
    return _protectedTerms[langCode.toLowerCase()] ?? [];
  }

  /// Check if text contains any protected medical terms
  static bool hasProtectedTerms(String text, String langCode) {
    final terms = _protectedTerms[langCode.toLowerCase()] ?? [];
    return terms.any(
      (term) => text.toLowerCase().contains(term.toLowerCase()),
    );
  }

  /// Extract protected terms that appear in the given text
  static List<String> extractProtectedTerms(String text, String langCode) {
    final terms = _protectedTerms[langCode.toLowerCase()] ?? [];
    return terms.where((term) {
      return text.toLowerCase().contains(term.toLowerCase());
    }).toList();
  }
}
