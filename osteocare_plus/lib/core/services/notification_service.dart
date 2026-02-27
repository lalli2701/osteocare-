import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._internal();

  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  static const int reassessmentReminderId = 1001;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      settings: initSettings,
    );
    _initialized = true;
  }

  Future<void> scheduleDailyTip({
    required int hour,
    required int minute,
    String? message,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'bone_health_tips',
        'Bone health voice tips',
        channelDescription:
            'Daily reminders with tips to support bone health and prevent osteoporosis.',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id: 0,
      title: 'OssoPulse daily tip',
      body:
          message ?? 'Take a few minutes to move and protect your bones today.',
      scheduledDate: scheduled,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> scheduleReassessmentReminder({
    required DateTime when,
    String title = 'Bone Health Reminder',
    String body = 'It’s time to reassess your osteoporosis risk in OssoPulse.',
  }) async {
    if (!_initialized) {
      await initialize();
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'bone_health_reassessment',
        'Bone health reassessment reminders',
        channelDescription:
            'Scheduled reminders for osteoporosis risk reassessment.',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    final scheduled = tz.TZDateTime.from(when, tz.local);
    final now = tz.TZDateTime.now(tz.local);

    if (!scheduled.isAfter(now)) {
      return;
    }

    await _plugin.zonedSchedule(
      id: reassessmentReminderId,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelReassessmentReminder() async {
    if (!_initialized) {
      await initialize();
    }
    await _plugin.cancel(id: reassessmentReminderId);
  }
}

