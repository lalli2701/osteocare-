import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/user_session.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/reminder_service.dart';
import '../../../core/services/reminder_sync_service.dart';
import '../../../core/services/tts_service.dart';
import '../../chatbot/presentation/assistant_fab.dart';
import 'dashboard_wrapper.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.riskLevel, this.age});

  static const routePath = '/tasks';

  final String? riskLevel;
  final int? age;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  TimeOfDay _selectedTime = const TimeOfDay(hour: 8, minute: 0);
  bool _isScheduling = false;
  bool _isLoadingTips = true;
  List<String> _tips = const [];
  String _ageGroup = '18-50';
  String _riskKey = 'MODERATE';
  List<String> _activeSlots = const ['morning', 'afternoon', 'evening'];
  late Locale _currentLocale;
  bool _localeInitialized = false;

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

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newLocale = context.locale;
    if (!_localeInitialized) {
      _currentLocale = newLocale;
      _localeInitialized = true;
      _loadTips();
      return;
    }
    if (newLocale != _currentLocale) {
      _currentLocale = newLocale;
      _loadTips();
    }
  }

  Future<void> _loadTips() async {
    var risk = ReminderService.normalizeRisk(widget.riskLevel ?? 'moderate');
    var ageGroup = ReminderService.ageGroupFromAge(widget.age);
    var reminderTime = _selectedTime;
    var slots = <String>['morning', 'afternoon', 'evening'];

    final remoteConfig = await ReminderSyncService.instance.fetchConfig();
    if (remoteConfig != null) {
      risk = ReminderService.normalizeRisk(remoteConfig.riskLevel);
      ageGroup = remoteConfig.ageGroup;
      slots = remoteConfig.reminderSlots.isEmpty
          ? _defaultSlotsForRisk(risk)
          : remoteConfig.reminderSlots;

      final parts = remoteConfig.reminderTime.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          reminderTime = TimeOfDay(hour: hour, minute: minute);
        }
      }
    }
    if (remoteConfig == null) {
      slots = _defaultSlotsForRisk(risk);
    }

    var tips = await ReminderService.getTips(
      ageGroup: ageGroup,
      risk: risk,
      slots: slots,
    );
    if (tips.isEmpty) {
      tips = await ReminderService.getTips(
        ageGroup: '18-50',
        risk: risk,
        slots: slots,
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _riskKey = risk;
      _ageGroup = ageGroup;
      _tips = tips;
      _activeSlots = slots;
      _selectedTime = reminderTime;
      _isLoadingTips = false;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _scheduleReminder() async {
    setState(() => _isScheduling = true);

    final slotsToSchedule = _activeSlots.isEmpty
        ? _defaultSlotsForRisk(_riskKey)
        : _activeSlots;

    final ids = slotsToSchedule.map(_notificationIdForSlot).toList();
    await NotificationService.instance.cancelTipsByIds(ids);

    String firstTip = '';
    for (final slot in slotsToSchedule) {
      final slotTime = _timeForSlot(slot, _selectedTime);
      final tip = await ReminderService.getOrCreateTodayTip(
        _tips,
        slotTag: slot,
      );
      firstTip = firstTip.isEmpty ? tip : firstTip;

      await NotificationService.instance.scheduleDailyTip(
        hour: slotTime.hour,
        minute: slotTime.minute,
        message: tip,
        notificationId: _notificationIdForSlot(slot),
      );
    }

    final formattedTime =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';
    await ReminderSyncService.instance.saveConfig(
      ageGroup: _ageGroup,
      riskLevel: _riskKey,
      reminderTime: formattedTime,
      enabled: true,
      reminderSlots: _activeSlots,
    );
    await ReminderSyncService.instance.logHabit(
      tip: firstTip,
      completed: false,
      date: DateTime.now(),
    );

    if (mounted) {
      setState(() => _isScheduling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'tasks_reminder_set'.tr(args: [_selectedTime.format(context)]),
          ),
        ),
      );
    }
  }

  Future<void> _playVoiceTip() async {
    final slot = (_activeSlots.isEmpty ? ['morning'] : _activeSlots).first;
    final message = await ReminderService.getOrCreateTodayTip(
      _tips,
      slotTag: slot,
    );
    await TtsService.instance.speakTip(message);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? _buildHistoryStream() {
    final uid = UserSession.instance.userId;
    if (uid == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('surveys')
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final riskLabel = (widget.riskLevel ?? 'unknown').toLowerCase();

    final historyStream = _buildHistoryStream();

    String riskText;
    if (riskLabel == 'low') {
      riskText = 'risk_low'.tr();
    } else if (riskLabel == 'high') {
      riskText = 'risk_high'.tr();
    } else if (riskLabel == 'moderate') {
      riskText = 'risk_moderate'.tr();
    } else {
      riskText = 'tasks_no_recent_result'.tr();
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(DashboardWrapper.routePath);
            }
          },
        ),
        title: Text('tasks_history_title'.tr()),
      ),
      floatingActionButton: const AssistantFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: Text('tasks_latest_risk'.tr()),
              subtitle: Text(riskText),
            ),
          ),
          const SizedBox(height: 8),
          if (historyStream != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'tasks_saved_results'.tr(),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: historyStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text(
                            'tasks_saved_results_error'.tr(),
                            style: theme.textTheme.bodyMedium,
                          );
                        }
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        if (!snapshot.hasData ||
                            snapshot.data!.docs.isEmpty) {
                          return Text(
                            'tasks_no_saved_surveys'.tr(),
                          );
                        }

                        final docs = snapshot.data!.docs;
                        return Column(
                          children: docs.map((doc) {
                            final data = doc.data();
                            final risk = (data['riskLevel'] as String? ?? '')
                                .toLowerCase();
                            final age = data['age'];
                            final weight = data['weight'];
                            final createdAt = data['createdAt'];
                            DateTime? created;
                            if (createdAt is Timestamp) {
                              created = createdAt.toDate();
                            }
                            final dateText = created != null
                                ? '${created.day}/${created.month}/${created.year}'
                                : 'Date not available';

                            String label;
                            if (risk == 'low') {
                              label = 'risk_low'.tr();
                            } else if (risk == 'high') {
                              label = 'risk_high'.tr();
                            } else if (risk == 'moderate') {
                              label = 'risk_moderate'.tr();
                            } else {
                              label = 'tasks_unknown_level'.tr();
                            }

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(label),
                              subtitle: Text(
                                "${'tasks_age_weight'.tr(args: ['${age ?? '-'}', '${weight ?? '-'}'])}\n$dateText",
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'tasks_signin_to_save'.tr(),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'tasks_daily_precautions'.tr(),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'tasks_age_group_risk'.tr(args: [_ageGroup, _riskKey]),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (_isLoadingTips)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_tips.isEmpty)
                    Text(
                      'tasks_no_personalized_tips'.tr(),
                      style: theme.textTheme.bodyMedium,
                    )
                  else
                    ..._tips.map(
                    (t) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• '),
                          Expanded(child: Text(t)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'tasks_daily_voice_reminder'.tr(),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'tasks_daily_voice_reminder_desc'.tr(),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'tasks_reminder_time'.tr(args: [_selectedTime.format(context)]),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _pickTime,
                        child: Text('tasks_change'.tr()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _isScheduling ? null : _scheduleReminder,
                    icon: _isScheduling
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.notifications_active_outlined),
                    label: Text('tasks_save_daily_reminder'.tr()),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _playVoiceTip,
                    icon: const Icon(Icons.volume_up_outlined),
                    label: Text('tasks_play_today_tip'.tr()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


