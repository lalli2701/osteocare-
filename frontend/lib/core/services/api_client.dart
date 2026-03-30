import 'package:dio/dio.dart';

import '../config/api_config.dart';

class ApiClient {
  ApiClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const String baseUrl = ApiConfig.baseUrl;

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

    final reply = data['reply'] as String;
    return reply;
  }
}

