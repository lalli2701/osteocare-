import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/language_service.dart';
import '../../onboarding/presentation/landing_page.dart';

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

  static const _nextReassessmentDateKey = 'next_reassessment_date';
  static const _reminderEnabledKey = 'reminder_enabled';

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
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
        Uri.parse('http://localhost:5000/api/user/dashboard'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Load and set language preference from backend
        final preferredLanguage = data['preferred_language'] as String?;
        if (preferredLanguage != null && mounted) {
          final language = AppLanguage.fromBackendValue(preferredLanguage);
          await context.setLocale(Locale(language.code));
        }
        
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

          _recommendationsPreview =
              List<String>.from(data['recommendations_preview'] ?? []);
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning';
    } else if (hour < 18) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
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
        Uri.parse('http://localhost:5000/api/user/reminders'),
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
            content: Text('Reminders ${_remindersEnabled ? 'enabled' : 'disabled'}'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
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
          title: const Text('Dashboard'),
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
        title: const Text('Dashboard'),
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
              'Quick Actions',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _quickActionCard(
                    icon: Icons.assignment,
                    title: 'Assessment',
                    subtitle: _riskLevel == null ? 'Start' : 'Retake',
                    onTap: () => context.push('/survey'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _quickActionCard(
                    icon: Icons.lightbulb,
                    title: 'Recommendations',
                    subtitle: 'View All',
                    onTap: () {
                      // Navigate to Tasks tab within wrapper
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _quickActionCard(
                    icon: Icons.download,
                    title: 'Report',
                    subtitle: 'Download',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Download feature coming soon'),
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
                'Personalized Tips',
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
                    // Navigate to Tasks tab
                  },
                  child: const Text('View All Tasks →'),
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
                          'Reminders',
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
                        'Next Reassessment: ${_formatDate(_nextReassignmentDate!.toLocal())}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    if (_isReassessmentOverdue()) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Reassessment overdue. Please retake survey.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Reminders: ${_remindersEnabled ? 'Enabled' : 'Disabled'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _remindersEnabled ? Colors.green : Colors.grey,
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
              'No Assessment Yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.blue[900],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You have not completed your osteoporosis risk assessment.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.blue[800],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.push('/survey'),
              child: const Text('Start Assessment'),
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
                          'Your Risk Level',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _riskLevel ?? 'Unknown',
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
                          'Risk Score',
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
                    'Last Assessment: ${_lastAssessmentDate!.toLocal().toString().split(' ')[0]}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Risk is based on provided lifestyle and medical factors.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => context.push('/survey'),
                  child: const Text('Retake Assessment'),
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
              title: const Text('Profile Settings'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Privacy Policy'),
              onTap: () {
                Navigator.pop(context);
                context.push('/privacy');
              },
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('Terms'),
              onTap: () {
                Navigator.pop(context);
                context.push('/terms');
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.orange),
              title: const Text('Logout'),
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
              title: const Text('Delete Account'),
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
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to permanently delete your account? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Call backend delete endpoint
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Account deleted')),
              );
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

