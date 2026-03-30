import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/services/language_service.dart';
import 'help_feedback_page.dart';
import 'dashboard_wrapper.dart';
import '../../onboarding/presentation/about_page.dart';
import '../../onboarding/presentation/landing_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  static const routePath = '/profile';

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final AuthService _authService = AuthService.instance;
  String _fullName = 'Loading...';
  String _phoneNumber = 'Loading...';
  bool _isLoading = true;
  bool _voiceEnabled = true;
  late Locale _currentLocale;
  bool _localeInitialized = false;

  @override
  void initState() {
    super.initState();
    _loadVoicePreference();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newLocale = context.locale;
    if (!_localeInitialized) {
      _currentLocale = newLocale;
      _localeInitialized = true;
      _loadUserData();
      return;
    }
    if (newLocale != _currentLocale) {
      _currentLocale = newLocale;
      _loadUserData();
    }
  }

  Future<void> _loadVoicePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _voiceEnabled = prefs.getBool('voice_enabled') ?? true;
      });
    } catch (e) {
      // Silently fail - voice_enabled defaults to true
    }
  }

  Future<void> _toggleVoicePreference(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('voice_enabled', value);
      
      // Optionally sync to backend
      final token = await _authService.getToken();
      if (token != null) {
        await http.put(
          Uri.parse('${AuthService.baseUrl}/api/user/preferences'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'voice_enabled': value}),
        ).timeout(const Duration(seconds: 10));
      }
      
      setState(() => _voiceEnabled = value);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value ? 'voice_enabled'.tr() : 'voice_disabled'.tr(),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('error_loading'.tr())),
        );
      }
    }
  }

  Future<void> _loadUserData() async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        if (mounted) {
          context.go(LandingPage.routePath);
        }
        return;
      }

      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/api/user/profile'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _fullName = data['full_name'] ?? 'User';
          _phoneNumber = data['phone_number'] ?? '';
          _isLoading = false;
        });
      } else if (response.statusCode == 401) {
        if (mounted) {
          context.go(LandingPage.routePath);
        }
      } else {
        throw Exception('Failed to load profile');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('error_loading'.tr())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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
          title: Text('profile'.tr()),
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
              context.go(DashboardWrapper.routePath);
            }
          },
        ),
        title: Text('profile'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1) Profile Header (compact)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFFEFF6FF),
                  child: Icon(Icons.person, color: Colors.blue.shade700),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fullName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _phoneNumber,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2) Health Preferences
          const Text(
            'Health Preferences',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.volume_up_outlined),
                  title: const Text('Voice Assistance'),
                  subtitle: const Text('Read & answer via voice'),
                  trailing: Switch(
                    value: _voiceEnabled,
                    onChanged: _toggleVoicePreference,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: const Text('Language'),
                  subtitle: Text(_getCurrentLanguageName()),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showLanguageSelector,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 3) App Settings
          Text(
            'App Settings',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => context.push('/privacy'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms & Conditions'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => context.push('/terms'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 4) Support
          const Text(
            'Support',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: const Text('Help & Feedback'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => context.push(HelpFeedbackPage.routePath),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About App'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => context.push(AboutPage.routePath),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 5) Danger Zone
          const Text(
            'Danger Zone',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB42318),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withValues(alpha: 0.18)),
            ),
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, color: Colors.orange),
                  title: const Text('Logout'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _logout,
                ),
                Divider(
                  height: 1,
                  color: Colors.red.withValues(alpha: 0.2),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Delete Account'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _deleteAccount,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getCurrentLanguageName() {
    final currentLocale = context.locale;
    final language = AppLanguage.fromCode(currentLocale.languageCode);
    return language.displayName;
  }

  Future<void> _showLanguageSelector() async {
    final currentLanguage = AppLanguage.fromCode(context.locale.languageCode);
    final pageContext = context; // Capture parent context before dialog
    
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('select_language'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppLanguage.values.map((language) {
            return RadioListTile<AppLanguage>(
              title: Text(language.displayName),
              value: language,
              // ignore: deprecated_member_use
              groupValue: currentLanguage,
              // ignore: deprecated_member_use
              onChanged: (AppLanguage? value) async {
                if (value != null && mounted) {
                  Navigator.pop(dialogContext);
                  // Use parent context (pageContext) not dialog context
                  await LanguageService.changeLanguage(pageContext, value);
                  setState(() {}); // Refresh to show new language
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('cancel'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final pageContext = context;
    showDialog(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        title: Text('logout'.tr()),
        content: Text('logout_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _authService.logout();
              if (mounted) {
                pageContext.go(LandingPage.routePath);
              }
            },
            child: Text('logout'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final pageContext = context;
    showDialog(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        title: Text('delete_account'.tr()),
        content: Text('delete_account_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final result = await _authService.deleteAccount();
              if (!mounted) {
                return;
              }
              if (result['success'] == true) {
                ScaffoldMessenger.of(pageContext).showSnackBar(
                  SnackBar(content: Text('account_deleted'.tr())),
                );
                pageContext.go(LandingPage.routePath);
              } else {
                final err = result['error']?.toString() ?? 'Unable to delete account';
                ScaffoldMessenger.of(pageContext).showSnackBar(
                  SnackBar(content: Text(err)),
                );
              }
            },
            child: Text('delete'.tr(), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
