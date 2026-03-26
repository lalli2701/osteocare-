import 'package:flutter/material.dart';
import '../models/message.dart';

/// A reusable widget that displays a single message in the chat
class MessageBubble extends StatelessWidget {
  /// The message to display
  final Message message;

  /// Optional callback when the message is tapped
  final VoidCallback? onTap;

  /// Optional callback to copy message text
  final Function(String)? onCopy;

  const MessageBubble({
    super.key,
    required this.message,
    this.onTap,
    this.onCopy,
  });

  /// Determines the alignment based on message sender
  Alignment get _alignment => message.isUser ? Alignment.centerRight : Alignment.centerLeft;

  /// Gets the background color for the bubble
  Color get _bubbleColor {
    if (message.isUser) {
      return const Color(0xFF2F80ED); // Blue for user messages
    } else {
      return Colors.grey[300]!; // Light gray for bot messages
    }
  }

  /// Gets the text color for the bubble
  Color get _textColor => message.isUser ? Colors.white : Colors.black87;

  /// Gets the border radius for the bubble
  BorderRadius get _borderRadius {
    if (message.isUser) {
      return const BorderRadius.only(
        topLeft: Radius.circular(18),
        topRight: Radius.circular(4),
        bottomLeft: Radius.circular(18),
        bottomRight: Radius.circular(18),
      );
    } else {
      return const BorderRadius.only(
        topLeft: Radius.circular(4),
        topRight: Radius.circular(18),
        bottomLeft: Radius.circular(18),
        bottomRight: Radius.circular(18),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: _alignment,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onCopy != null ? () => onCopy!(message.text) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: _bubbleColor,
            borderRadius: _borderRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: TextStyle(
                  color: _textColor,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  color: _textColor.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Formats the timestamp for display
  String _formatTime(DateTime datetime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(datetime.year, datetime.month, datetime.day);

    if (msgDate == today) {
      return '${datetime.hour.toString().padLeft(2, '0')}:${datetime.minute.toString().padLeft(2, '0')}';
    } else if (msgDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return '${datetime.month}/${datetime.day}';
    }
  }
}
