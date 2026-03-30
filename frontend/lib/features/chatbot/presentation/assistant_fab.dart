import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chatbot_page_refactored.dart';

class AssistantFab extends StatefulWidget {
  const AssistantFab({
    super.key,
    this.contextHint,
    this.emphasize = false,
  });

  final String? contextHint;
  final bool emphasize;

  @override
  State<AssistantFab> createState() => _AssistantFabState();
}

class _AssistantFabState extends State<AssistantFab> {
  static const _hintSeenKey = 'assistant_fab_hint_seen_v2';
  final GlobalKey<TooltipState> _tooltipKey = GlobalKey<TooltipState>();

  @override
  void initState() {
    super.initState();
    unawaited(_showFirstUseHint());
  }

  Future<void> _showFirstUseHint() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadySeen = prefs.getBool(_hintSeenKey) ?? false;
    if (alreadySeen || !mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _tooltipKey.currentState?.ensureTooltipVisible();
    });
    await prefs.setBool(_hintSeenKey, true);
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.contextHint ?? 'Ask anything about your bone health';
    final gradient = const LinearGradient(
      colors: [Color(0xFF2F80ED), Color(0xFF56CCF2)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final glowShadow = widget.emphasize
        ? const [
            BoxShadow(
              color: Color(0x663B82F6),
              blurRadius: 22,
              spreadRadius: 2,
              offset: Offset(0, 8),
            ),
          ]
        : const [
            BoxShadow(
              color: Color(0x2A1F2937),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ];

    return Tooltip(
      key: _tooltipKey,
      message: hint,
      waitDuration: const Duration(milliseconds: 250),
      showDuration: const Duration(seconds: 4),
      preferBelow: false,
      child: Semantics(
        button: true,
        label: hint,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => context.push(ChatbotPageRefactored.routePath),
            child: Ink(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: gradient,
                border: Border.all(
                  color: widget.emphasize
                      ? const Color(0xFFE8F0FF)
                      : const Color(0xFFDBEAFE),
                  width: widget.emphasize ? 2 : 1,
                ),
                boxShadow: glowShadow,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.chat_bubble_rounded,
                    size: 24,
                    color: Colors.white,
                  ),
                  Positioned(
                    right: 11,
                    top: 11,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        size: 10,
                        color: Color(0xFF2F80ED),
                      ),
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
