import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'chatbot_page.dart';

class AssistantFab extends StatelessWidget {
  const AssistantFab({super.key, this.label = 'OsteoCare+ AI'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final gradient = const LinearGradient(
      colors: [
        Color(0xFF0F766E),
        Color(0xFF14B8A6),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Semantics(
      button: true,
      label: 'Ask the OsteoCare+ assistant',
      child: Material(
        color: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: () => context.go(ChatbotPage.routePath),
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
