import 'package:flutter/material.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  static const routePath = '/terms';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms & Conditions'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OssoPulse Terms & Conditions',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            
            _buildSection(
              theme,
              '1. Acceptance of Terms',
              'By accessing and using OssoPulse, you agree to be bound by these Terms & Conditions. If you do not agree to these terms, please do not use this application.',
            ),
            
            _buildSection(
              theme,
              '2. User Consent and Acknowledgment',
              'By using OssoPulse, you confirm and agree to the following:\n\n'
              '• I confirm that the information I provide is true and accurate to the best of my knowledge.\n\n'
              '• I understand that this application provides an AI-based osteoporosis risk assessment for informational and educational purposes only.\n\n'
              '• I understand that this application does not replace consultation, diagnosis, or treatment by a licensed medical professional.\n\n'
              '• I consent to the use of my submitted data for the purpose of calculating my personalized osteoporosis risk score.\n\n'
              '• I agree to receive health-related reminders, reassessment notifications, and educational alerts from the application.\n\n'
              '• I confirm that I am voluntarily choosing to use this application.\n\n'
              '• If I am under 18 years of age, I confirm that I am using this application under parental or legal guardian supervision.',
            ),
            
            _buildSection(
              theme,
              '3. Medical Disclaimer',
              'OssoPulse is designed to provide general health information and risk assessment only. It is NOT intended to:\n\n'
              '• Diagnose any medical condition\n'
              '• Provide medical advice or treatment\n'
              '• Replace professional medical consultation\n\n'
              'Always consult with a qualified healthcare provider before making any health-related decisions. If you experience severe symptoms or health concerns, seek immediate medical attention.',
            ),
            
            _buildSection(
              theme,
              '4. Data Accuracy',
              'While we strive to provide accurate risk assessments based on validated models, results may vary. The accuracy of your risk assessment depends on:\n\n'
              '• The accuracy of information you provide\n'
              '• Current medical research and guidelines\n'
              '• Individual health factors not captured in the assessment\n\n'
              'We do not guarantee the accuracy, completeness, or reliability of any risk assessment or health information provided.',
            ),
            
            _buildSection(
              theme,
              '5. User Responsibilities',
              'As a user, you agree to:\n\n'
              '• Provide accurate and truthful health information\n'
              '• Use the application for lawful purposes only\n'
              '• Not misuse or attempt to manipulate the risk assessment system\n'
              '• Keep your account credentials secure and confidential\n'
              '• Notify us immediately of any unauthorized access to your account',
            ),
            
            _buildSection(
              theme,
              '6. Age Restrictions',
              'OssoPulse is intended for users aged 18 years and older. Users under 18 must have parental or guardian consent and supervision when using this application.',
            ),
            
            _buildSection(
              theme,
              '7. Data Usage and Privacy',
              'Your privacy is important to us. By using OssoPulse, you consent to:\n\n'
              '• Collection and storage of your health information\n'
              '• Processing of your data for risk assessment purposes\n'
              '• Receiving notifications and health alerts\n\n'
              'For detailed information about how we handle your data, please review our Privacy Policy.',
            ),
            
            _buildSection(
              theme,
              '8. Notifications and Alerts',
              'By using OssoPulse, you agree to receive:\n\n'
              '• Health-related reminders and tips\n'
              '• Reassessment notifications\n'
              '• Educational content about bone health\n'
              '• System updates and important announcements\n\n'
              'You can manage notification preferences in your account settings.',
            ),
            
            _buildSection(
              theme,
              '9. Limitation of Liability',
              'OssoPulse and its developers shall not be liable for:\n\n'
              '• Any direct, indirect, or consequential damages arising from use of the application\n'
              '• Health decisions made based on risk assessments provided\n'
              '• Technical failures, data loss, or service interruptions\n'
              '• Inaccuracies in risk assessments or health information',
            ),
            
            _buildSection(
              theme,
              '10. Modifications to Terms',
              'We reserve the right to modify these Terms & Conditions at any time. Users will be notified of significant changes. Continued use of the application after changes constitutes acceptance of the modified terms.',
            ),
            
            _buildSection(
              theme,
              '11. Account Termination',
              'We reserve the right to suspend or terminate user accounts that:\n\n'
              '• Violate these Terms & Conditions\n'
              '• Misuse the application or its services\n'
              '• Provide false or misleading information\n'
              '• Engage in fraudulent or illegal activities',
            ),
            
            _buildSection(
              theme,
              '12. Intellectual Property',
              'All content, features, and functionality of OssoPulse are owned by the developers and are protected by copyright, trademark, and other intellectual property laws.',
            ),
            
            _buildSection(
              theme,
              '13. Contact Information',
              'For questions or concerns about these Terms & Conditions, please contact us through the application support section.',
            ),
            
            const SizedBox(height: 20),
            
            Text(
              'Last Updated: February 2026',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
              ),
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
