import 'package:dio/dio.dart';

class ApiClient {
  ApiClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Base URL for your backend that proxies AI chatbot requests and other APIs.
  ///
  /// Replace this with your real backend URL (for example, a Firebase
  /// Cloud Function endpoint).
  static const String baseUrl = 'https://your-backend.example.com';

  Future<String> sendChatMessage({
    required String userId,
    required List<Map<String, String>> messages,
    Map<String, dynamic>? context,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/chat',
      data: {
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

