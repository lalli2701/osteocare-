import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/dynamic_translation_service.dart';

class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key});

  static const routePath = '/privacy';

  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  List<_SectionData> _sections = _englishSections;
  String _lastLangCode = 'en';
  bool _isTranslating = false;

  static const String _pageTitle = 'OsteoCare+ Privacy Policy';
  static const String _privacyCardTitle = 'Your Privacy Matters';
  static const String _privacyCardBody =
      'We are committed to protecting your personal and health information. Your data is encrypted, securely stored, and never sold to third parties.';
  static const String _lastUpdated = 'Last Updated: February 2026';

  static const List<_SectionData> _englishSections = [
    _SectionData(
      '1. Introduction',
      'OsteoCare+ ("we", "our", or "us") is committed to protecting your privacy and handling your personal health information with care. This Privacy Policy explains how we collect, use, store, and protect your information when you use our application.',
    ),
    _SectionData(
      '2. Information We Collect',
      'We collect the following types of information:\n\n'
          'Account Information:\n'
          '• Full name\n'
          '• Phone number\n'
          '• Account creation date\n\n'
          'Health Information:\n'
          '• Age and gender\n'
          '• Height and weight (BMI calculation)\n'
          '• Medical history (conditions, medications)\n'
          '• Lifestyle factors (smoking, alcohol, exercise)\n'
          '• Dietary habits (calcium intake)\n'
          '• Family history of osteoporosis\n'
          '• Previous bone health assessments\n\n'
          'Usage Information:\n'
          '• Assessment history and results\n'
          '• App usage patterns\n'
          '• Notification preferences\n'
          '• Device information (for technical support)',
    ),
    _SectionData(
      '3. How We Use Your Information',
      'We use your information for the following purposes:\n\n'
          '• Risk Assessment: To calculate your personalized osteoporosis risk score using AI-based algorithms\n\n'
          '• Health Recommendations: To provide tailored health tips and prevention strategies\n\n'
          '• Notifications: To send health reminders, reassessment alerts, and educational content\n\n'
          '• Service Improvement: To enhance our risk assessment models and application features\n\n'
          '• Research: To conduct anonymized population health studies (with your consent)\n\n'
          '• Support: To respond to your questions and provide technical assistance',
    ),
    _SectionData(
      '4. Data Security',
      'We implement industry-standard security measures to protect your information:\n\n'
          '• Encryption: All data transmitted between your device and our servers is encrypted using SSL/TLS\n\n'
          '• Secure Storage: Your personal and health information is stored in encrypted databases\n\n'
          '• Access Control: Only authorized personnel have access to user data, and only when necessary\n\n'
          '• Password Protection: Your account is protected by a secure password that only you know\n\n'
          '• Regular Audits: We conduct regular security audits and updates to maintain data protection',
    ),
    _SectionData(
      '5. Data Sharing and Disclosure',
      'We do NOT sell your personal information to third parties.\n\n'
          'We may share your information only in the following circumstances:\n\n'
          '• Healthcare Providers: If you explicitly request us to share your assessment results with your doctor\n\n'
          '• Legal Requirements: When required by law, court order, or government regulations\n\n'
          '• Emergency Situations: To prevent imminent harm to health or safety\n\n'
          '• Service Providers: With trusted third-party service providers who assist in operating our application (under strict confidentiality agreements)\n\n'
          '• Aggregated Data: We may share anonymized, aggregated data for research purposes (cannot identify individuals)',
    ),
    _SectionData(
      '6. Your Rights and Choices',
      'You have the following rights regarding your personal information:\n\n'
          '• Access: You can access your personal and health information at any time through the app\n\n'
          '• Correction: You can update or correct your information in your account settings\n\n'
          '• Deletion: You can request deletion of your account and all associated data\n\n'
          '• Export: You can request a copy of your data in a portable format\n\n'
          '• Notification Control: You can manage your notification preferences\n\n'
          '• Withdrawal of Consent: You can withdraw consent for data processing at any time',
    ),
    _SectionData(
      '7. Data Retention',
      'We retain your information as follows:\n\n'
          '• Active Accounts: We retain your data while your account remains active\n\n'
          '• Deleted Accounts: After account deletion, we retain data for 30 days for recovery purposes, then permanently delete it\n\n'
          '• Legal Requirements: We may retain certain information longer if required by law or for legitimate business purposes\n\n'
          '• Anonymized Research Data: Anonymized data used for research may be retained indefinitely',
    ),
    _SectionData(
      '8. Children\'s Privacy',
      'OsteoCare+ is intended for users aged 18 and older. If you are under 18, you should use this application only under parental or guardian supervision.\n\n'
          'If we discover that we have collected information from a child under 13 without proper consent, we will delete that information immediately.',
    ),
    _SectionData(
      '9. Health Information Privacy (HIPAA Considerations)',
      'While OsteoCare+ handles sensitive health information, please note:\n\n'
          '• We are not a covered entity under HIPAA as we do not provide medical treatment or services\n\n'
          '• Our service is informational and educational, not diagnostic or therapeutic\n\n'
          '• We follow industry best practices for health data protection\n\n'
          '• For formal medical records, always consult your licensed healthcare provider',
    ),
    _SectionData(
      '10. International Data Transfers',
      'Your information may be transferred to and processed in countries other than your country of residence. We ensure appropriate safeguards are in place to protect your data in accordance with this Privacy Policy.',
    ),
    _SectionData(
      '11. Cookies and Tracking',
      'OsteoCare+ mobile application does not use cookies. However, we may collect:\n\n'
          '• Device identifiers for authentication\n'
          '• Analytics data to improve app performance\n'
          '• Session information to maintain your logged-in state\n\n'
          'You can control some of these features through your device settings.',
    ),
    _SectionData(
      '12. Changes to This Privacy Policy',
      'We may update this Privacy Policy from time to time to reflect changes in:\n\n'
          '• Our practices\n'
          '• Legal requirements\n'
          '• Application features\n\n'
          'We will notify you of significant changes through the app or via your registered phone number. Continued use of the app after changes constitutes acceptance of the updated policy.',
    ),
    _SectionData(
      '13. Contact Us',
      'If you have questions or concerns about this Privacy Policy or how we handle your data, please contact us:\n\n'
          '• Through the app support section\n'
          '• Via the feedback form in settings\n\n'
          'We will respond to privacy inquiries within 30 days.',
    ),
    _SectionData(
      '14. Your Consent',
      'By using OsteoCare+, you consent to:\n\n'
          '• This Privacy Policy\n'
          '• Collection and processing of your information as described\n'
          '• Use of your data for risk assessment and health recommendations\n'
          '• Receiving notifications and health alerts\n\n'
          'You can withdraw your consent at any time by deleting your account.',
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final langCode = context.locale.languageCode.toLowerCase();
    if (langCode != _lastLangCode) {
      _lastLangCode = langCode;
      _loadLocalizedContent(langCode);
    }
  }

  Future<void> _loadLocalizedContent(String langCode) async {
    if (langCode == 'en') {
      if (!mounted) {
        return;
      }
      setState(() {
        _isTranslating = false;
        _sections = _englishSections;
      });
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _isTranslating = true;
    });

    final titleInputs = _englishSections.map((e) => e.title).toList();
    final bodyInputs = _englishSections.map((e) => e.content).toList();

    final translatedTitles = await DynamicTranslationService.instance.translateMany(
      titleInputs,
      langCode: langCode,
    );
    final translatedBodies = await DynamicTranslationService.instance.translateMany(
      bodyInputs,
      langCode: langCode,
    );

    if (!mounted || _lastLangCode != langCode) {
      return;
    }

    setState(() {
      _sections = List.generate(
        _englishSections.length,
        (i) => _SectionData(translatedTitles[i], translatedBodies[i]),
      );
      _isTranslating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final langCode = context.locale.languageCode.toLowerCase();
    final Future<String> localizedTitle = langCode == 'en'
      ? Future<String>.value(_pageTitle)
      : DynamicTranslationService.instance.translate(_pageTitle, langCode: langCode);
    final Future<String> localizedCardTitle = langCode == 'en'
      ? Future<String>.value(_privacyCardTitle)
      : DynamicTranslationService.instance.translate(_privacyCardTitle, langCode: langCode);
    final Future<String> localizedCardBody = langCode == 'en'
      ? Future<String>.value(_privacyCardBody)
      : DynamicTranslationService.instance.translate(_privacyCardBody, langCode: langCode);
    final Future<String> localizedLastUpdated = langCode == 'en'
      ? Future<String>.value(_lastUpdated)
      : DynamicTranslationService.instance.translate(_lastUpdated, langCode: langCode);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: Text('privacy_policy'.tr()),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<String>(
              future: localizedTitle,
              builder: (context, snapshot) {
                return Text(
                  snapshot.data ?? _pageTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                );
              },
            ),
            if (_isTranslating)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'chatbot_thinking'.tr(),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 20),
            ..._sections.map((section) => _buildSection(theme, section.title, section.content)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.security,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      FutureBuilder<String>(
                        future: localizedCardTitle,
                        builder: (context, snapshot) {
                          return Text(
                            snapshot.data ?? _privacyCardTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<String>(
                    future: localizedCardBody,
                    builder: (context, snapshot) {
                      return Text(
                        snapshot.data ?? _privacyCardBody,
                        style: theme.textTheme.bodyMedium,
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            FutureBuilder<String>(
              future: localizedLastUpdated,
              builder: (context, snapshot) {
                return Text(
                  snapshot.data ?? _lastUpdated,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600],
                  ),
                );
              },
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(ThemeData theme, String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionData {
  const _SectionData(this.title, this.content);

  final String title;
  final String content;
}
