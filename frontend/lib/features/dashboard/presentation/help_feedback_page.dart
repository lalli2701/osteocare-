import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../chatbot/presentation/chatbot_page_refactored.dart';

class HelpFeedbackPage extends StatefulWidget {
  const HelpFeedbackPage({super.key});

  static const routePath = '/help-feedback';

  @override
  State<HelpFeedbackPage> createState() => _HelpFeedbackPageState();
}

class _HelpFeedbackPageState extends State<HelpFeedbackPage> {
  final TextEditingController _feedbackController = TextEditingController();
  int _rating = 0;
  bool _isSubmitting = false;

  static const List<_FaqItem> _faqs = [
    _FaqItem(
      question: 'What does my risk level mean?',
      answer:
          'Your risk level shows the likelihood of developing bone weakness based on your inputs.\n\n'
          '• Low Risk: Your bone health is stable\n'
          '• Moderate Risk: Some factors need attention\n'
          '• High Risk: Immediate lifestyle or medical action is recommended\n\n'
          'This is not a diagnosis, but a preventive insight.',
    ),
    _FaqItem(
      question: 'How accurate is this prediction?',
      answer:
          'The prediction is based on medical data patterns and your inputs.\n\n'
          'Confidence score meaning:\n'
          '• Higher confidence: More reliable prediction\n'
          '• Lower confidence: More variation possible\n\n'
          'For medical decisions, always consult a doctor.',
    ),
    _FaqItem(
      question: 'Why do I need to answer all questions?',
      answer:
          'Each question contributes to understanding your bone health.\n\n'
          'Skipping or incorrect answers may reduce prediction accuracy and affect recommendations.',
    ),
    _FaqItem(
      question: 'How often should I take the survey?',
      answer:
          'You should take the survey every 2-4 weeks or after lifestyle changes.\n\n'
          'Regular tracking helps monitor improvement or risk increase.',
    ),
    _FaqItem(
      question: 'Why am I getting these daily tasks?',
      answer:
          'Your daily tasks are personalized based on your survey answers and risk factors.\n\n'
          'They are designed to improve bone strength and reduce risk over time.',
    ),
    _FaqItem(
      question: 'What happens if I skip tasks?',
      answer:
          'Skipping tasks may slow down your improvement.\n\n'
          'Consistent completion helps maintain your streak and improve your health outcomes.',
    ),
    _FaqItem(
      question: 'How does voice assistance work?',
      answer:
          'Voice assistance reads questions aloud and allows you to answer using speech.\n\n'
          'Make sure microphone permissions are enabled for best performance.',
    ),
    _FaqItem(
      question: 'Why is voice input not working?',
      answer:
          'Check the following:\n\n'
          '• Microphone permission is enabled\n'
          '• Internet connection is stable\n'
          '• Speak clearly in a quiet environment\n\n'
          'If the issue persists, try restarting the app.',
    ),
    _FaqItem(
      question: 'Is my health data safe?',
      answer:
          'Yes, your data is securely stored and used only for generating predictions and recommendations.\n\n'
          'We do not share your personal data without your consent.',
    ),
    _FaqItem(
      question: 'Can I delete my data?',
      answer:
          'Yes, you can delete your account anytime from the profile section.\n\n'
          'This permanently removes your data from the system.',
    ),
    _FaqItem(
      question: 'Should I consult a doctor based on my result?',
      answer:
          'If your risk level is moderate or high, consulting a doctor is recommended.\n\n'
          'Especially if you have symptoms or existing medical conditions.',
    ),
    _FaqItem(
      question: 'Does this app replace medical tests?',
      answer:
          'No. This app is for early screening and prevention only.\n\n'
          'It does not replace clinical diagnosis or medical tests like bone density scans.',
    ),
    _FaqItem(
      question: 'How are nearby hospitals selected?',
      answer:
          'Hospitals are shown based on your location and relevant specialties.\n\n'
          'You can save or contact them directly from the app.',
    ),
    _FaqItem(
      question: 'Why should I use this app regularly?',
      answer:
          'Regular use helps track your bone health, build healthy habits, and detect risks early.\n\n'
          'Consistency leads to better long-term outcomes.',
    ),
  ];

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _openEmailSupport() async {
    final emailUri = Uri(
      scheme: 'mailto',
      path: 'support@osteocare.ai',
      queryParameters: {
        'subject': 'OsteoCare Support Request',
      },
    );

    final opened = await launchUrl(emailUri);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open email app.')),
      );
    }
  }

  Future<void> _callSupport() async {
    final callUri = Uri.parse('tel:+917702330100');
    final opened = await launchUrl(callUri);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open phone dialer.')),
      );
    }
  }

  Future<void> _submitFeedback() async {
    final feedbackText = _feedbackController.text.trim();
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a rating before submitting.')),
      );
      return;
    }
    if (feedbackText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write your feedback.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
      _rating = 0;
      _feedbackController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thanks! Your feedback has been submitted.')),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Feedback')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          _buildSectionTitle('Quick Help'),
          Card(
            child: Column(
              children: _faqs
                  .map(
                    (item) => ExpansionTile(
                      title: Text(
                        item.question,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      childrenPadding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      children: [
                        Text(
                          item.answer,
                          style: TextStyle(
                            height: 1.45,
                            color: Colors.blueGrey.shade700,
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 18),

          _buildSectionTitle('Contact Support'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Email Support'),
                  subtitle: const Text('support@osteocare.ai'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _openEmailSupport,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: const Text('Chat with Assistant'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => context.push(ChatbotPageRefactored.routePath),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.call_outlined),
                  title: const Text('Call Support'),
                  subtitle: const Text('+91 77023 30100'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _callSupport,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          _buildSectionTitle('Give Feedback'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rate your experience',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(5, (index) {
                      final star = index + 1;
                      return IconButton(
                        onPressed: () => setState(() => _rating = star),
                        icon: Icon(
                          _rating >= star ? Icons.star : Icons.star_border,
                          color: const Color(0xFFF59E0B),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'What can we improve?',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _feedbackController,
                    minLines: 4,
                    maxLines: 6,
                    decoration: InputDecoration(
                      hintText: 'Tell us what can be better...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _submitFeedback,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Submit'),
                    ),
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

class _FaqItem {
  const _FaqItem({required this.question, required this.answer});

  final String question;
  final String answer;
}
