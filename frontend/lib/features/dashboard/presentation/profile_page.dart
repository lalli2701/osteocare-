import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/services/language_service.dart';
import 'dashboard_wrapper.dart';
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
  String _createdDate = 'Loading...';
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
          Uri.parse('http://172.201.252.146:5000/api/user/preferences'),
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
        Uri.parse('http://172.201.252.146:5000/api/user/profile'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _fullName = data['full_name'] ?? 'User';
          _phoneNumber = data['phone_number'] ?? '';
          _createdDate = data['created_at'] != null
              ? DateTime.parse(data['created_at'])
                  .toLocal()
                  .toString()
                  .split(' ')[0]
              : '';
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'account_info'.tr(),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _infoRow('full_name'.tr(), _fullName),
                  _infoRow('phone_number'.tr(), _phoneNumber),
                  _infoRow('profile_account_created'.tr(), _createdDate),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'settings_support'.tr(),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.language),
              title: Text('language'.tr()),
              subtitle: Text(_getCurrentLanguageName()),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _showLanguageSelector,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.mic),
              title: Text('voice_features'.tr()),
              subtitle: Text(
                _voiceEnabled
                    ? 'profile_voice_enabled_desc'.tr()
                    : 'voice_disabled'.tr(),
              ),
              trailing: Switch(
                value: _voiceEnabled,
                onChanged: _toggleVoicePreference,
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock),
              title: Text('privacy_policy'.tr()),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => context.push('/privacy'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.description),
              title: Text('terms_conditions'.tr()),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => context.push('/terms'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.orange),
              title: Text('logout'.tr()),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _logout,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text('delete_account'.tr()),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _deleteAccount,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('logout'.tr()),
        content: Text('logout_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () async {
              await _authService.logout();
              if (mounted) {
                context.go(LandingPage.routePath);
              }
            },
            child: Text('logout'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
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
            onPressed: () async {
              // TODO: Call backend delete endpoint
              Navigator.pop(context);
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
