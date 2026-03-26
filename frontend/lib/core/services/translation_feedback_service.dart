import 'package:flutter/material.dart';

class TranslationFeedbackService {
  TranslationFeedbackService._internal();

  static final TranslationFeedbackService instance =
      TranslationFeedbackService._internal();

  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  DateTime? _lastFallbackNoticeAt;

  void notifyFallback() {
    final now = DateTime.now();
    final last = _lastFallbackNoticeAt;
    if (last != null && now.difference(last).inSeconds < 30) {
      return;
    }
    _lastFallbackNoticeAt = now;

    final messenger = messengerKey.currentState;
    if (messenger == null) {
      return;
    }

    messenger.showSnackBar(
      const SnackBar(
        content: Text('Translation unavailable, showing default language.'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}
