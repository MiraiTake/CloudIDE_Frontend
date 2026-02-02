import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants.dart';

/// Модель пользователя (если понадобится где-то ещё)
class User {
  final String id;
  final String username;
  final String email;

  User({
    required this.id,
    required this.username,
    required this.email,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
    );
  }
}

/// Сервис авторизации: login, registration и подтверждение кода
class AuthService {
  /// Парсит user_id из JWT-токена
  String getUserIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return '';
      final payload = parts[1];
      final normalized = base64.normalize(payload);
      final payloadMap =
          json.decode(utf8.decode(base64Url.decode(normalized)));
      return payloadMap['user_id'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  /// HTTP POST на /login: возвращает { userId, token }
  Future<Map<String, String>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('${kServerIp}/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email.trim(),
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final token = data['token'] as String;
      final userId = getUserIdFromToken(token);
      return {
        'userId': userId,
        'token': token,
      };
    } else {
      throw Exception('Ошибка авторизации: ${response.body}');
    }
  }

  /// HTTP POST на /register:
  /// - возвращает false, если первая отправка кода (201)
  /// - возвращает true, если переотправка кода (202)
  Future<bool> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('${kServerIp}/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'username': username.trim(),
        'email': email.trim(),
        'password': password,
      }),
    );

    if (response.statusCode == 201) {
      // НОВАЯ регистрация, код отправлен впервые
      return false;
    } else if (response.statusCode == 202) {
      // Повторная отправка кода
      return true;
    } else {
      throw Exception('Ошибка регистрации: ${response.body}');
    }
  }

  /// HTTP POST на /verify-code: подтверждает email кодом
  Future<void> confirmCode({
    required String email,
    required String code,
  }) async {
    final response = await http.post(
      Uri.parse('${kServerIp}/verify-code'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email.trim(),
        'code': code.trim(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка подтверждения: ${response.body}');
    }
  }
}