import 'package:dio/dio.dart';

class ApiClient {
  ApiClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Local backend URL for development.
  static const String baseUrl = 'http://127.0.0.1:5000';

  Future<String> sendChatMessage({
    required String userId,
    required List<Map<String, String>> messages,
    Map<String, dynamic>? context,
  }) async {
    final lastUserMessage = messages.reversed
        .firstWhere(
          (m) => (m['role'] ?? '').toLowerCase() == 'user',
          orElse: () => const {'content': ''},
        )['content']
        ?.trim() ??
        '';

    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/chat',
      data: {
        'message': lastUserMessage,
        'uid': userId,
        'messages': messages,
        'context': context,
      },
    );

    final data = response.data;
    if (data == null || data['reply'] is! String) {
      throw Exception('Unexpected chatbot response');
    }

    return data['reply'] as String;
  }
}

