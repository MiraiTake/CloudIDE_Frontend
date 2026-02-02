import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants.dart';
import 'jwt_service.dart';

/// Модель пользователя
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
    return JwtHelper.getUserIdFromToken(token) ?? '';
  }

  /// HTTP POST на /login: возвращает { userId, token, refreshToken }
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
      final accessToken = data['access_token'] as String;
      final refreshToken = data['refresh_token'] as String;
      
      // Проверяем валидность access токена
      if (!JwtHelper.isTokenValid(accessToken)) {
        throw Exception('Получен невалидный токен от сервера');
      }
      
      final userId = getUserIdFromToken(accessToken);
      if (userId.isEmpty) {
        throw Exception('Не удалось извлечь user_id из токена');
      }
      
      return {
        'userId': userId,
        'token': accessToken,
        'refreshToken': refreshToken,
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