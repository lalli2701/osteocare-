/// Represents a single chat message in the conversation
class Message {
  /// The text content of the message
  final String text;

  /// Whether the message is from the user (true) or from the chatbot/assistant (false)
  final bool isUser;

  /// Timestamp when the message was created
  final DateTime timestamp;

  Message({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Create a copy of this message with optional field replacements
  Message copyWith({
    String? text,
    bool? isUser,
    DateTime? timestamp,
  }) {
    return Message(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Convert message to JSON for API storage
  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
      };

  /// Create a message from JSON
  factory Message.fromJson(Map<String, dynamic> json) => Message(
        text: json['text'] as String,
        isUser: json['isUser'] as bool,
        timestamp: DateTime.parse(json['timestamp'] as String? ?? DateTime.now().toIso8601String()),
      );

  @override
  String toString() => 'Message(text: $text, isUser: $isUser, timestamp: $timestamp)';
}
