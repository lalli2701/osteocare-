import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/survey_sync_service.dart';
import '../../../core/services/dynamic_translation_service.dart';
import '../../onboarding/presentation/landing_page.dart';
import '../../survey/presentation/prescriptions_page.dart';
import '../../survey/presentation/survey_page.dart';
import 'tasks_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  static const routePath = '/dashboard';

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final AuthService _authService = AuthService.instance;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _isLoading = true;
  String _fullName = 'User';
  String _phoneNumber = 'Loading...';
  double? _riskScore;
  String? _riskLevel;
  DateTime? _lastAssessmentDate;
  DateTime? _nextReassignmentDate;
  List<String> _recommendationsPreview = [];
  bool _remindersEnabled = false;
  int _pendingSyncCount = 0;
  int _failedPermanentSyncCount = 0;
  DateTime? _lastSyncedAt;
  late Locale _currentLocale;
  bool _localeInitialized = false;

  static const _nextReassessmentDateKey = 'next_reassessment_date';
  static const _reminderEnabledKey = 'reminder_enabled';

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
      _loadDashboardData();
      return;
    }
    if (newLocale != _currentLocale) {
      _currentLocale = newLocale;
      _loadDashboardData();
    }
  }

  Future<void> _loadDashboardData() async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        // No token, redirect to login
        if (mounted) {
          context.go(LandingPage.routePath);
        }
        return;
      }

      final response = await http.get(
        Uri.parse('http://172.201.252.146:5000/api/user/dashboard'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawRecommendations =
            List<String>.from(data['recommendations_preview'] ?? []);

        // Keep current app language stable until the user changes it manually.
        final activeLangCode = context.locale.languageCode;

        final translatedRecommendations =
            await DynamicTranslationService.instance.translateMany(
          rawRecommendations,
          langCode: activeLangCode,
        );
        
        setState(() {
          _fullName = data['full_name'] ?? 'User';
          _phoneNumber = data['phone_number'] ?? '';

          if (data['risk'] != null) {
            _riskScore = (data['risk']['risk_score'] ?? 0).toDouble();
            _riskLevel = data['risk']['risk_level'];
            _lastAssessmentDate = data['risk']['last_assessment_date'] != null
                ? DateTime.parse(data['risk']['last_assessment_date'])
                : null;
            _nextReassignmentDate = data['risk']['next_reassessment_date'] != null
                ? DateTime.parse(data['risk']['next_reassessment_date'])
                : null;
          }

            _recommendationsPreview = translatedRecommendations;
          _remindersEnabled = data['reminders_enabled'] ?? true;

          _isLoading = false;
        });

        final localNextDate = await _storage.read(key: _nextReassessmentDateKey);
        final localRemindersEnabled = await _storage.read(key: _reminderEnabledKey);

        if (mounted) {
          setState(() {
            if (_nextReassignmentDate == null && localNextDate != null && localNextDate.isNotEmpty) {
              _nextReassignmentDate = DateTime.tryParse(localNextDate);
            }
            if (localRemindersEnabled != null) {
              _remindersEnabled = localRemindersEnabled.toLowerCase() == 'true';
            }
          });
        }

        await _refreshSyncStatus();
      } else if (response.statusCode == 401) {
        // Unauthorized, redirect to login
        if (mounted) {
          context.go(LandingPage.routePath);
        }
      } else {
        throw Exception('Failed to load dashboard data');
      }
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
      setState(() {
        _isLoading = false;
      });
      await _refreshSyncStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('error_loading'.tr())),
        );
      }
    }
  }

  Future<void> _refreshSyncStatus() async {
    try {
      final status = await SurveySyncService.instance.getSyncStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingSyncCount = (status['pending_count'] as num?)?.toInt() ?? 0;
        _failedPermanentSyncCount = (status['failed_permanent_count'] as num?)?.toInt() ?? 0;
        _lastSyncedAt = status['last_synced_at'] as DateTime?;
      });
    } catch (_) {
      // Ignore sync status rendering errors.
    }
  }

  String _formatRelative(DateTime value) {
    final diff = DateTime.now().difference(value.toLocal());
    if (diff.inSeconds < 60) {
      return 'dashboard_just_now'.tr();
    }
    if (diff.inMinutes < 60) {
      return 'dashboard_minutes_ago'.tr(args: ['${diff.inMinutes}']);
    }
    if (diff.inHours < 24) {
      return 'dashboard_hours_ago'.tr(args: ['${diff.inHours}']);
    }
    return 'dashboard_days_ago'.tr(args: ['${diff.inDays}']);
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'dashboard_greeting_morning'.tr();
    } else if (hour < 18) {
      return 'dashboard_greeting_afternoon'.tr();
    } else {
      return 'dashboard_greeting_evening'.tr();
    }
  }

  Color _getRiskColor() {
    final level = (_riskLevel ?? '').toLowerCase();
    if (level == 'low') return Colors.green;
    if (level == 'high') return Colors.red;
    return Colors.orange;
  }

  Future<void> _toggleReminders() async {
    try {
      final token = await _authService.getToken();
      if (token == null) return;

      final response = await http.post(
        Uri.parse('http://172.201.252.146:5000/api/user/reminders'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'enabled': !_remindersEnabled}),
      );

      if (response.statusCode == 200) {
        final updatedValue = !_remindersEnabled;
        setState(() {
          _remindersEnabled = updatedValue;
        });

        await _storage.write(
          key: _reminderEnabledKey,
          value: updatedValue.toString(),
        );

        if (!updatedValue) {
          await NotificationService.instance.cancelReassessmentReminder();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _remindersEnabled
                  ? 'dashboard_reminders_enabled'.tr()
                  : 'dashboard_reminders_disabled'.tr(),
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('error_loading'.tr())),
      );
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  bool _isReassessmentOverdue() {
    if (_nextReassignmentDate == null) {
      return false;
    }
    final today = DateTime.now();
    final dueDate = DateTime(
      _nextReassignmentDate!.year,
      _nextReassignmentDate!.month,
      _nextReassignmentDate!.day,
    );
    final nowDate = DateTime(today.year, today.month, today.day);
    return dueDate.isBefore(nowDate);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(LandingPage.routePath);
              }
            },
          ),
          title: Text('dashboard'.tr()),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showSettingsMenu,
            ),
          ],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(LandingPage.routePath);
            }
          },
        ),
        title: Text('dashboard'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsMenu,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getGreeting(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _fullName,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_phoneNumber.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _phoneNumber,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Risk Status Card
            if (_riskLevel == null) ...[
              _noAssessmentCard(theme),
            ] else ...[
              _riskStatusCard(theme),
            ],
            const SizedBox(height: 20),

            // Quick Actions Section
            Text(
              'dashboard_quick_actions'.tr(),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _quickActionCard(
                    icon: Icons.folder_shared_outlined,
                    title: 'Prescriptions',
                    subtitle: 'Reports',
                    onTap: () => context.push(PrescriptionsPage.routePath),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _quickActionCard(
                    icon: Icons.lightbulb,
                    title: 'recommendations'.tr(),
                    subtitle: 'dashboard_view_all'.tr(),
                    onTap: () {
                      context.push(
                        TasksPage.routePath,
                        extra: {
                          'risk_level': _riskLevel,
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _quickActionCard(
                    icon: Icons.download,
                    title: 'dashboard_report'.tr(),
                    subtitle: 'dashboard_download'.tr(),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('dashboard_download_soon'.tr()),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Personalized Tips Preview
            if (_recommendationsPreview.isNotEmpty) ...[
              Text(
                'dashboard_personalized_tips'.tr(),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ..._recommendationsPreview.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text('${entry.key + 1}'),
                      ),
                      title: Text(entry.value),
                    ),
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    context.push(
                      TasksPage.routePath,
                      extra: {
                        'risk_level': _riskLevel,
                      },
                    );
                  },
                  child: Text('dashboard_view_all_tasks'.tr()),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Reminder Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'reminders'.tr(),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Switch(
                          value: _remindersEnabled,
                          onChanged: (_) => _toggleReminders(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_nextReassignmentDate != null)
                      Text(
                        'dashboard_next_reassessment'.tr(args: [_formatDate(_nextReassignmentDate!.toLocal())]),
                        style: theme.textTheme.bodyMedium,
                      ),
                    if (_isReassessmentOverdue()) ...[
                      const SizedBox(height: 8),
                      Text(
                        'dashboard_reassessment_overdue'.tr(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'dashboard_reminders_status'.tr(
                        args: [_remindersEnabled ? 'enabled'.tr() : 'disabled'.tr()],
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _remindersEnabled ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'sync_status'.tr(),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'dashboard_pending_records'.tr(args: ['$_pendingSyncCount']),
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (_failedPermanentSyncCount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'dashboard_permanent_failures'.tr(args: ['$_failedPermanentSyncCount']),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.red[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _lastSyncedAt == null
                          ? 'dashboard_last_synced_never'.tr()
                          : 'dashboard_last_synced'.tr(args: [_formatRelative(_lastSyncedAt!)]),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _noAssessmentCard(ThemeData theme) {
    return Card(
      elevation: 4,
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'dashboard_no_assessment_title'.tr(),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.blue[900],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'dashboard_no_assessment_desc'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.blue[800],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.push(SurveyPage.routePath),
              child: Text('take_assessment'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _riskStatusCard(ThemeData theme) {
    return Card(
      elevation: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 8,
            color: _getRiskColor(),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'your_risk_level'.tr(),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _riskLevel ?? 'dashboard_unknown'.tr(),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _getRiskColor(),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'risk_score'.tr(),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_riskScore?.toStringAsFixed(1) ?? '0'}',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _getRiskColor(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_lastAssessmentDate != null)
                  Text(
                    'dashboard_last_assessment'.tr(
                      args: [_lastAssessmentDate!.toLocal().toString().split(' ')[0]],
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'dashboard_risk_based_note'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => context.push(SurveyPage.routePath),
                  child: Text('retake_assessment'.tr()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon, size: 32, color: Colors.blue),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettingsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: Text('profile'.tr()),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.lock),
              title: Text('privacy_policy'.tr()),
              onTap: () {
                Navigator.pop(context);
                context.push('/privacy');
              },
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: Text('terms'.tr()),
              onTap: () {
                Navigator.pop(context);
                context.push('/terms');
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.orange),
              title: Text('logout'.tr()),
              onTap: () async {
                Navigator.pop(context);
                await _authService.logout();
                if (mounted) {
                  context.go(LandingPage.routePath);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text('delete_account'.tr()),
              onTap: () {
                Navigator.pop(context);
                _showDeleteAccountDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('delete_account'.tr()),
        content: Text('delete_account_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Call backend delete endpoint
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('account_deleted'.tr())),
              );
            },
            child: Text('delete'.tr(), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

