import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/auth/user_session.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/tts_service.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.riskLevel});

  static const routePath = '/tasks';

  final String? riskLevel;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  TimeOfDay _selectedTime = const TimeOfDay(hour: 8, minute: 0);
  bool _isScheduling = false;

  List<String> _tasksForRisk(String? level) {
    final risk = (level ?? '').toLowerCase();
    if (risk == 'low') {
      return const [
        'Walk or do light weight‑bearing exercise for at least 20–30 minutes most days.',
        'Include calcium‑rich foods (milk, curd, ragi, leafy greens) in your meals.',
        'Spend a few minutes in morning sunlight for natural vitamin D.',
      ];
    } else if (risk == 'high') {
      return const [
        'Talk to your doctor about a full bone health check and medication if needed.',
        'Avoid smoking and limit alcohol as much as possible.',
        'Keep your home safe to prevent falls (good lighting, no loose rugs, handrails).',
        'Do only joint‑friendly, supervised exercises as advised by a physiotherapist or doctor.',
      ];
    } else {
      // Moderate or unknown.
      return const [
        'Aim for at least 30 minutes of weight‑bearing activity (walking, stair‑climbing) most days.',
        'Add 2–3 days of strength training with light weights or resistance bands.',
        'Eat vitamin C and vitamin D rich foods (citrus fruits, guava, sprouts, eggs, fortified milk).',
        'Avoid long periods of sitting; stand up and move every hour.',
      ];
    }
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

    final risk = (widget.riskLevel ?? 'moderate').toLowerCase();
    String message;
    if (risk == 'low') {
      message =
          'Take a short walk and include calcium and vitamin D rich foods today to keep your bones strong.';
    } else if (risk == 'high') {
      message =
          'Move safely, avoid falls, and follow your doctor’s advice. A few gentle exercises now can still support your bones.';
    } else {
      message =
          'Do a few minutes of weight‑bearing exercise and eat vitamin C and vitamin D rich foods to protect your bones.';
    }

    await NotificationService.instance.scheduleDailyTip(
      hour: _selectedTime.hour,
      minute: _selectedTime.minute,
      message: message,
    );

    if (mounted) {
      setState(() => _isScheduling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Daily reminder set for ${_selectedTime.format(context)}.',
          ),
        ),
      );
    }
  }

  Future<void> _playVoiceTip() async {
    final risk = (widget.riskLevel ?? 'moderate').toLowerCase();
    String message;
    if (risk == 'low') {
      message =
          'Great job keeping your risk low. Take a brisk walk, do simple strength exercises, and enjoy calcium rich foods today.';
    } else if (risk == 'high') {
      message =
          'Your bone health needs extra care. Move carefully, avoid falls, follow your doctor’s plan, and take only safe, gentle exercises.';
    } else {
      message =
          'To protect your bones, spend a few minutes walking, do light strength exercises, and include vitamin C and D rich foods in your meals today.';
    }
    await TtsService.instance.speakTip(message);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? _buildHistoryStream() {
    final uid = UserSession.instance.uid;
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
    final tasks = _tasksForRisk(widget.riskLevel);
    final riskLabel = (widget.riskLevel ?? 'unknown').toLowerCase();

    final historyStream = _buildHistoryStream();

    String riskText;
    if (riskLabel == 'low') {
      riskText = 'Low risk';
    } else if (riskLabel == 'high') {
      riskText = 'High risk';
    } else if (riskLabel == 'moderate') {
      riskText = 'Moderate risk';
    } else {
      riskText = 'No recent survey result';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your tasks & history'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('Latest risk level'),
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
                      'Saved survey results',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: historyStream,
                      builder: (context, snapshot) {
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
                          return const Text(
                            'No saved surveys yet. Complete a survey to see it here.',
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
                              label = 'Low risk';
                            } else if (risk == 'high') {
                              label = 'High risk';
                            } else if (risk == 'moderate') {
                              label = 'Moderate risk';
                            } else {
                              label = 'Unknown level';
                            }

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(label),
                              subtitle: Text(
                                'Age: ${age ?? '-'}, Weight: ${weight ?? '-'} kg\n$dateText',
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
                  'Sign in with your phone number so we can save and show your survey history here.',
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
                    'Daily precautions to protect your bones',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...tasks.map(
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
                    'Daily voice tip reminder',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose a time, and the app will send a notification with a short tip like “exercise a few minutes and eat vitamin C & D rich foods” to remind you.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'Reminder time: ${_selectedTime.format(context)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _pickTime,
                        child: const Text('Change'),
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
                    label: const Text('Save daily reminder'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _playVoiceTip,
                    icon: const Icon(Icons.volume_up_outlined),
                    label: const Text('Play today’s tip now'),
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


