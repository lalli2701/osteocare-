import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/services/language_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadVoicePreference();
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
          Uri.parse('http://localhost:5000/api/user/preferences'),
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
              value ? 'Voice features enabled' : 'Voice features disabled',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating preference: $e')),
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
        Uri.parse('http://localhost:5000/api/user/profile'),
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
          SnackBar(content: Text('Error: $e')),
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
          title: const Text('Profile'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
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
                    'Account Information',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _infoRow('Full Name', _fullName),
                  _infoRow('Phone Number', _phoneNumber),
                  _infoRow('Account Created', _createdDate),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Settings & Support',
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
              title: const Text('Voice Features'),
              subtitle: Text(
                _voiceEnabled
                    ? 'Read questions aloud and speak answers'
                    : 'Voice features disabled',
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
              title: const Text('Privacy Policy'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => context.push('/privacy'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.description),
              title: const Text('Terms & Conditions'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => context.push('/terms'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.orange),
              title: const Text('Logout'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _logout,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Account'),
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
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('select_language'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppLanguage.values.map((language) {
            return RadioListTile<AppLanguage>(
              title: Text(language.displayName),
              value: language,
              groupValue: currentLanguage,
              onChanged: (AppLanguage? value) async {
                if (value != null && mounted) {
                  Navigator.pop(context);
                  await LanguageService.changeLanguage(context, value);
                  setState(() {}); // Refresh to show new language
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
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
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _authService.logout();
              if (mounted) {
                context.go(LandingPage.routePath);
              }
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
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
            onPressed: () async {
              // TODO: Call backend delete endpoint
              Navigator.pop(context);
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
