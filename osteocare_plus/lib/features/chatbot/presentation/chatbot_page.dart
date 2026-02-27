import 'package:flutter/material.dart';

import '../../../core/auth/user_session.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/tts_service.dart';

class ChatbotPage extends StatefulWidget {
  const ChatbotPage({super.key});

  static const routePath = '/chatbot';

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  final _controller = TextEditingController();
  final ApiClient _apiClient = ApiClient();
  final List<_Message> _messages = <_Message>[
    const _Message(
      fromUser: false,
      text:
          'Hi, I am the OsteoCare+ assistant. I can explain osteoporosis, how to prevent it, and what precautions to take. I do not replace a doctor.',
    ),
  ];

  bool _isSending = false;
  bool _voiceEnabled = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _messages.add(_Message(fromUser: true, text: text));
      _controller.clear();
      _isSending = true;
    });

    String reply;
    try {
      final userId = UserSession.instance.userId ??
          UserSession.instance.phone ??
          'anonymous';

      // Send a short history so the backend (OpenAI, etc.) has context.
      final history = _messages
          .take(8)
          .map(
            (m) => <String, String>{
              'role': m.fromUser ? 'user' : 'assistant',
              'content': m.text,
            },
          )
          .toList();

      reply = await _apiClient.sendChatMessage(
        userId: userId,
        messages: history,
        context: const {
          'topic': 'osteoporosis_and_bone_health',
          'disclaimer':
              'Educational only, not a medical diagnosis or treatment.',
        },
      );
    } catch (_) {
      // If backend/OpenAI is not available, fall back to an on-device answer.
      reply = _buildBotReply(text);
    }

    if (!mounted) return;
    setState(() {
      _messages.add(
        _Message(
          fromUser: false,
          text: reply,
        ),
      );
      _isSending = false;
    });

    if (_voiceEnabled) {
      await TtsService.instance.speakTip(reply);
    }
  }

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
          '• Do regular weight‑bearing activities like walking, jogging, or stair‑climbing.\n'
          '• Do strength training 2–3 days per week to keep muscles and bones strong.\n'
          '• Eat calcium‑rich foods (milk, curd, paneer, ragi, leafy greens) and vitamin D sources.\n'
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
          '• Vitamin D: safe sunlight, fortified milk, eggs, some fish (if you eat non‑veg).\n'
          '• Vitamin C: oranges, lemon, amla, guava, tomatoes, capsicum – these support collagen in bone.\n'
          '• Protein: dal, beans, nuts, seeds, eggs or lean meat.\n'
          'Try to reduce very salty, sugary, or fizzy drinks and very processed foods.';
    }

    if (q.contains('exercise') || q.contains('workout') || q.contains('walk')) {
      return 'Good exercises for bone health (if your doctor says they are safe for you) include:\n'
          '• Walking, brisk walking, light jogging, or stair‑climbing.\n'
          '• Strength training with light weights or resistance bands for arms, legs, and back.\n'
          '• Balance exercises like standing on one leg or simple yoga poses to reduce falls.\n'
          'If you already have fractures, arthritis, or cancer treatment, ask your doctor or physiotherapist which exercises are safe.';
    }

    if (q.contains('fracture') ||
        q.contains('broken bone') ||
        q.contains('fall')) {
      return 'If you have had a fracture from a small fall, your bones may be weaker. '
          'It is important to talk to a doctor about osteoporosis testing and treatment. '
          'At home, keep floors dry, use non‑slip footwear, keep good lighting, and remove loose rugs or wires to avoid falls.';
    }

    if (q.contains('arthritis') ||
        q.contains('cancer') ||
        q.contains('steroid')) {
      return 'Long‑term steroid medicines, some cancer treatments, and severe arthritis can weaken bones. '
          'You should work closely with your doctor to protect your bones – this may include medicines, vitamin D and calcium, '
          'safe exercises, and regular follow‑up. Do not stop or change any prescription medicine without your doctor’s advice.';
    }

    return 'Thanks for your question. I can explain osteoporosis, prevention, exercise, diet, and safety tips.\n\n'
        'In general, regular weight‑bearing exercise, enough calcium and vitamin D, not smoking, limiting alcohol, '
        'and preventing falls are key to protecting your bones. For diagnosis or medicines, please see your doctor.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('OsteoCare+ assistant'),
        actions: [
          IconButton(
            tooltip: _voiceEnabled ? 'Mute voice' : 'Enable voice',
            icon: Icon(
              _voiceEnabled ? Icons.volume_up_outlined : Icons.volume_off,
            ),
            onPressed: () {
              setState(() {
                _voiceEnabled = !_voiceEnabled;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(12),
            child: const Text(
              'This chatbot is for education only and does not provide medical diagnosis or treatment.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final alignment =
                    msg.fromUser ? Alignment.centerRight : Alignment.centerLeft;
                final color = msg.fromUser
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest;
                final textColor =
                    msg.fromUser ? Colors.white : theme.colorScheme.onSurface;
                return Align(
                  alignment: alignment,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      msg.text,
                      style: TextStyle(color: textColor),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Ask about osteoporosis, exercise, food, etc.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  onPressed: _isSending ? null : _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Message {
  const _Message({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;
}

