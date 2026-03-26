import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/user_session.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/dynamic_translation_service.dart';
import '../../../core/services/tts_service.dart';
import '../models/message.dart';
import '../widgets/message_bubble.dart';
import '../widgets/input_box.dart';
import '../widgets/typing_indicator.dart';

/// Refactored ChatbotPage with multi-language support using reusable components
class ChatbotPageRefactored extends StatefulWidget {
  const ChatbotPageRefactored({super.key});

  static const routePath = '/chatbot';

  @override
  State<ChatbotPageRefactored> createState() => _ChatbotPageRefactoredState();
}

class _ChatbotPageRefactoredState extends State<ChatbotPageRefactored> {
  late final ScrollController _scrollController;
  final ApiClient _apiClient = ApiClient();
  final List<Message> _messages = <Message>[];

  bool _isSending = false;
  bool _voiceEnabled = true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_messages.isEmpty) {
      _messages.add(
        Message(
          text: context.tr('chatbot_welcome'),
          isUser: false,
        ),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Auto-scroll to the latest message
  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100)).then((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Handle sending a message
  Future<void> _handleSend(String text) async {
    if (text.isEmpty || _isSending) return;

    setState(() {
      _messages.add(Message(text: text, isUser: true));
      _isSending = true;
    });

    _scrollToBottom();

    String reply;
    final selectedLangCode = context.locale.languageCode.toLowerCase();
    try {
      final userId = UserSession.instance.userId ??
          UserSession.instance.phone ??
          'anonymous';

      // Send message history to backend for context
      final history = _messages.take(8).map((m) => {
            'role': m.isUser ? 'user' : 'assistant',
            'content': m.text,
          }).toList();

      reply = await _apiClient.sendChatMessage(
        userId: userId,
        messages: history,
        context: const {
          'topic': 'osteoporosis_and_bone_health',
          'disclaimer': 'Educational only, not a medical diagnosis or treatment.',
        },
      );
      reply = await DynamicTranslationService.instance.translate(
        reply,
        langCode: selectedLangCode,
      );
    } catch (e) {
      // Fallback to on-device reply if backend is unavailable
      reply = _buildBotReply(text);
      reply = await DynamicTranslationService.instance.translate(
        reply,
        langCode: selectedLangCode,
      );
    }

    if (!mounted) return;
    setState(() {
      _messages.add(Message(text: reply, isUser: false));
      _isSending = false;
    });

    _scrollToBottom();

    // Speak the reply if voice is enabled
    if (_voiceEnabled) {
      await TtsService.instance.speakTip(
        reply,
        langCode: selectedLangCode,
      );
    }
  }

  /// Copy message text to clipboard
  void _copyMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('chatbot_copy_message')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Build fallback bot reply (on-device response)
  String _buildBotReply(String question) {
    final q = question.toLowerCase();

    if (q == 'hi' ||
        q == 'hey' ||
        q == 'hello' ||
        q.startsWith('hi ') ||
        q.startsWith('hello ') ||
        q.startsWith('hey ')) {
      return 'Hi, I am the OsteoCare+ assistant. You can ask me about osteoporosis, how to prevent it, '
          'safe exercises, food for strong bones, or how to reduce your fracture risk.';
    }

    if (q.contains('what is') && (q.contains('osteoporosis') || q.contains('bone'))) {
      return 'Osteoporosis is a condition where bones become weak and break more easily. '
          'It usually happens slowly over many years. You often cannot feel it until a fracture occurs. '
          'Early prevention with exercise, food, and avoiding risk factors can make a big difference.';
    }

    if (q.contains('prevent') ||
        q.contains('how can i avoid') ||
        q.contains('precaution')) {
      return 'To help prevent osteoporosis:\n'
          '• Do regular weight-bearing activities like walking, jogging, or stair-climbing.\n'
          '• Do strength training 2–3 days per week to keep muscles and bones strong.\n'
          '• Eat calcium-rich foods (milk, curd, paneer, ragi, leafy greens) and vitamin D sources.\n'
          '• Avoid smoking and limit alcohol.\n'
          '• Maintain a healthy body weight and avoid long periods of sitting.\n'
          'For personal guidance, always talk with your doctor.';
    }

    if (q.contains('food') ||
        q.contains('diet') ||
        q.contains('eat') ||
        q.contains('vitamin')) {
      return 'For stronger bones, focus on:\n'
          '• Calcium: milk, curd, paneer, cheese, ragi, sesame seeds, leafy greens.\n'
          '• Vitamin D: safe sunlight, fortified milk, eggs, some fish (if you eat non-veg).\n'
          '• Vitamin C: oranges, lemon, amla, guava, tomatoes, capsicum – these support collagen in bone.\n'
          '• Protein: dal, beans, nuts, seeds, eggs or lean meat.\n'
          'Try to reduce very salty, sugary, or fizzy drinks and very processed foods.';
    }

    if (q.contains('exercise') || q.contains('workout') || q.contains('walk')) {
      return 'Good exercises for bone health (if your doctor says they are safe for you) include:\n'
          '• Walking, brisk walking, light jogging, or stair-climbing.\n'
          '• Strength training with light weights or resistance bands for arms, legs, and back.\n'
          '• Balance exercises like standing on one leg or simple yoga poses to reduce falls.\n'
          'If you already have fractures, arthritis, or cancer treatment, ask your doctor or physiotherapist which exercises are safe.';
    }

    if (q.contains('fracture') ||
        q.contains('broken bone') ||
        q.contains('fall')) {
      return 'If you have had a fracture from a small fall, your bones may be weaker. '
          'It is important to talk to a doctor about osteoporosis testing and treatment. '
          'At home, keep floors dry, use non-slip footwear, keep good lighting, and remove loose rugs or wires to avoid falls.';
    }

    if (q.contains('arthritis') ||
        q.contains('cancer') ||
        q.contains('steroid')) {
      return 'Long-term steroid medicines, some cancer treatments, and severe arthritis can weaken bones. '
          'You should work closely with your doctor to protect your bones – this may include medicines, vitamin D and calcium, '
          'safe exercises, and regular follow-up. Do not stop or change any prescription medicine without your doctor\'s advice.';
    }

    return 'Thanks for your question. I can explain osteoporosis, prevention, exercise, diet, and safety tips.\n\n'
        'In general, regular weight-bearing exercise, enough calcium and vitamin D, not smoking, limiting alcohol, '
        'and preventing falls are key to protecting your bones. For diagnosis or medicines, please see your doctor.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2F80ED),
        elevation: 4,
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
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.health_and_safety,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr('chatbot_title'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    context.tr('chatbot_subtitle'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Tooltip(
            message: _voiceEnabled ? context.tr('voice_enabled') : context.tr('voice_disabled'),
            child: IconButton(
              icon: Icon(
                _voiceEnabled ? Icons.volume_up : Icons.volume_off,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _voiceEnabled = !_voiceEnabled;
                });
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Disclaimer banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.amber[100],
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('chatbot_disclaimer'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber[900],
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Messages list
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(context.tr('chatbot_empty')),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(10),
                    itemCount: _messages.length +
                        (_isSending ? 1 : 0), // Add space for typing indicator
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        // Show typing indicator while sending
                        return TypingIndicator(
                          label: context.tr('chatbot_thinking'),
                        );
                      }

                      final message = _messages[index];
                      return MessageBubble(
                        message: message,
                        onCopy: _copyMessage,
                      );
                    },
                  ),
          ),
          // Input box
          InputBox(
            onSend: _handleSend,
            hintText: context.tr('chatbot_placeholder'),
            isEnabled: !_isSending,
          ),
        ],
      ),
    );
  }
}
