import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';

import 'core/router/app_router.dart';
import 'core/services/chatbot_language_pipeline.dart';
import 'core/services/language_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/reminder_service.dart';
import 'core/services/reminder_sync_service.dart';
import 'core/services/survey_sync_coordinator.dart';
import 'core/services/translation_feedback_service.dart';
import 'core/services/translation_system_initializer.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize translation system (cache cleanup, pre-warming)
  await TranslationSystemInitializer.initialize();

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
        Locale('te'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      saveLocale: true,
      child: const ProviderScope(child: OsteoCareApp()),
    ),
  );
}

class OsteoCareApp extends ConsumerStatefulWidget {
  const OsteoCareApp({super.key});

  @override
  ConsumerState<OsteoCareApp> createState() => _OsteoCareAppState();
}

class _OsteoCareAppState extends ConsumerState<OsteoCareApp> {
  List<String> _defaultSlotsForRisk(String risk) {
    switch (risk.toUpperCase()) {
      case 'LOW':
        return const ['morning'];
      case 'HIGH':
        return const ['morning', 'afternoon', 'evening'];
      case 'MODERATE':
      default:
        return const ['morning', 'evening'];
    }
  }

  TimeOfDay _timeForSlot(String slot, TimeOfDay baseTime) {
    final normalized = slot.toLowerCase();
    if (normalized == 'morning') {
      return baseTime;
    }
    if (normalized == 'afternoon') {
      return const TimeOfDay(hour: 14, minute: 0);
    }
    if (normalized == 'evening') {
      return const TimeOfDay(hour: 19, minute: 0);
    }
    return baseTime;
  }

  int _notificationIdForSlot(String slot) {
    switch (slot.toLowerCase()) {
      case 'morning':
        return 21001;
      case 'afternoon':
        return 21002;
      case 'evening':
        return 21003;
      default:
        return 21999;
    }
  }

  Future<void> _rescheduleRemindersOnLaunch() async {
    try {
      final config = await ReminderSyncService.instance.fetchConfig();
      if (config == null || !config.enabled) {
        return;
      }

      final parts = config.reminderTime.split(':');
      final hour = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
      final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
      final baseTime = (hour != null && minute != null)
          ? TimeOfDay(hour: hour, minute: minute)
          : const TimeOfDay(hour: 8, minute: 0);

      final slots = config.reminderSlots.isEmpty
          ? _defaultSlotsForRisk(config.riskLevel)
          : config.reminderSlots;

      final tips = await ReminderService.getTips(
        ageGroup: config.ageGroup,
        risk: config.riskLevel,
        slots: slots,
      );

      final ids = slots.map(_notificationIdForSlot).toList();
      await NotificationService.instance.cancelTipsByIds(ids);

      for (final slot in slots) {
        final tip = await ReminderService.getOrCreateTodayTip(
          tips,
          slotTag: slot,
        );
        final when = _timeForSlot(slot, baseTime);
        await NotificationService.instance.scheduleDailyTip(
          hour: when.hour,
          minute: when.minute,
          message: tip,
          notificationId: _notificationIdForSlot(slot),
        );
      }
    } catch (_) {
      // Non-blocking: app should still boot even if reminder reschedule fails.
    }
  }

  @override
  void initState() {
    super.initState();
    SurveySyncCoordinator.instance.start();
    // Fire language init in background without awaiting
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeStartupLanguage();
    });
    _rescheduleRemindersOnLaunch();
  }

  Future<void> _initializeStartupLanguage() async {
    try {
      await LanguageService.applySavedLanguage(context);
      // Initialize chatbot language pipeline for consistency
      await ChatbotLanguagePipeline.initializeConversation();
    } catch (_) {
      // Keep app boot resilient even if language initialization fails.
    }
  }

  @override
  void dispose() {
    SurveySyncCoordinator.instance.stop();
    // Cleanup translation system on app shutdown
    TranslationSystemInitializer.shutdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'OsteoCare+',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      routerConfig: router,
      scaffoldMessengerKey: TranslationFeedbackService.messengerKey,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
    );
  }
}

