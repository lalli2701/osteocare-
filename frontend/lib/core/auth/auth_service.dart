import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'user_session.dart';

class AuthService {
  AuthService._internal();

  static final AuthService instance = AuthService._internal();

  static const String baseUrl = ApiConfig.baseUrl;
  
  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _userDataKey = 'user_data';

  /// Sign up a new user and auto-login
  Future<Map<String, dynamic>> signUp({
    required String fullName,
    required String phoneNumber,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'full_name': fullName,
          'phone_number': phoneNumber,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        // Auto-login after successful signup
        final loginResp = await http.post(
          Uri.parse('$baseUrl/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'phone_number': phoneNumber,
            'password': password,
          }),
        );

        if (loginResp.statusCode == 200) {
          final loginData = jsonDecode(loginResp.body);
          // Store token and user data
          await _storage.write(key: _tokenKey, value: loginData['access_token']);
          await _storage.write(key: _userDataKey, value: jsonEncode(loginData['user']));
          
          // Update session
          UserSession.instance.userId = loginData['user']['id'].toString();
          UserSession.instance.userName = loginData['user']['full_name'];
          UserSession.instance.phone = loginData['user']['phone_number'];
          
          return {'success': true, 'message': 'Account created and logged in'};
        }
        
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Signup failed'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Login with phone and password
  Future<Map<String, dynamic>> login({
    required String phoneNumber,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone_number': phoneNumber,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Store token and user data
        await _storage.write(key: _tokenKey, value: data['access_token']);
        await _storage.write(key: _userDataKey, value: jsonEncode(data['user']));
        
        // Update session
        UserSession.instance.userId = data['user']['id'].toString();
        UserSession.instance.userName = data['user']['full_name'];
        UserSession.instance.phone = data['user']['phone_number'];
        
        return {'success': true};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Login failed'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Check if user is logged in
  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null) return false;
    
    // Verify token with backend
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/auth/verify'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Update session with user data
        UserSession.instance.userId = data['user']['id'].toString();
        UserSession.instance.userName = data['user']['full_name'];
        UserSession.instance.phone = data['user']['phone_number'];
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Get stored token
  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  /// Get stored user data
  Future<Map<String, dynamic>?> getUserData() async {
    final userDataJson = await _storage.read(key: _userDataKey);
    if (userDataJson != null) {
      return jsonDecode(userDataJson);
    }
    return null;
  }

  /// Logout user
  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userDataKey);
    UserSession.instance.clear();
  }

  /// Delete current user account from backend and clear local session.
  Future<Map<String, dynamic>> deleteAccount() async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      final response = await http.delete(
        Uri.parse('$baseUrl/api/user/account'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final body = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode == 200) {
        await logout();
        return {
          'success': true,
          'message': body['message']?.toString() ?? 'Account deleted',
        };
      }

      return {
        'success': false,
        'error': body['error']?.toString() ?? 'Unable to delete account',
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Make authenticated API request
  Future<http.Response> authenticatedRequest({
    required String endpoint,
    required String method,
    Map<String, dynamic>? body,
  }) async {
    final token = await getToken();
    
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final uri = Uri.parse('$baseUrl$endpoint');

    switch (method.toUpperCase()) {
      case 'GET':
        return await http.get(uri, headers: headers);
      case 'POST':
        return await http.post(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
      case 'PUT':
        return await http.put(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
      case 'DELETE':
        return await http.delete(uri, headers: headers);
      default:
        throw Exception('Unsupported HTTP method: $method');
    }
  }
}