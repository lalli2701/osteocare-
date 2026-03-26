import 'package:flutter/material.dart';

/// A reusable widget for message input with send button
class InputBox extends StatefulWidget {
  /// Callback function when the user sends a message
  final Function(String) onSend;

  /// Placeholder text for the input field
  final String hintText;

  /// Optional leading widget (e.g., emoji button)
  final Widget? leading;

  /// Optional trailing widget (e.g., attachment button)
  final Widget? trailing;

  /// Whether the input is currently disabled
  final bool isEnabled;

  const InputBox({
    super.key,
    required this.onSend,
    this.hintText = 'Type your message...',
    this.leading,
    this.trailing,
    this.isEnabled = true,
  });

  @override
  State<InputBox> createState() => _InputBoxState();
}

class _InputBoxState extends State<InputBox> {
  late final TextEditingController _controller;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  /// Handles text changes to update button state
  void _onTextChanged() {
    setState(() {
      _hasText = _controller.text.trim().isNotEmpty;
    });
  }

  /// Sends the message and clears the input
  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty && widget.isEnabled) {
      widget.onSend(text);
      _controller.clear();
      _hasText = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: Colors.white,
      child: SafeArea(
        child: Row(
          children: [
            if (widget.leading != null) ...[
              widget.leading!,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: widget.isEnabled,
                maxLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend(),
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(
                      color: Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(
                      color: Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: const BorderSide(
                      color: Color(0xFF2F80ED),
                      width: 2,
                    ),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(
                      color: Colors.grey[200]!,
                      width: 1,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  filled: !widget.isEnabled,
                  fillColor: Colors.grey[100],
                ),
                style: const TextStyle(fontSize: 15),
              ),
            ),
            const SizedBox(width: 8),
            if (widget.trailing != null) ...[
              widget.trailing!,
              const SizedBox(width: 4),
            ],
            IconButton(
              icon: Icon(
                Icons.send,
                color: _hasText && widget.isEnabled
                    ? const Color(0xFF2F80ED)
                    : Colors.grey[400],
                size: 22,
              ),
              onPressed: _hasText && widget.isEnabled ? _handleSend : null,
              tooltip: 'Send message',
            ),
          ],
        ),
      ),
    );
  }
}
