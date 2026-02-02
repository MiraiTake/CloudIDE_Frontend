import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants.dart';

/// Модель «Пользователь»
class User {
  final String id;
  final String username;
  final String email;
  final String? githubLogin;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.githubLogin,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
      githubLogin: json['github_login'] as String?,
    );
  }
}

/// Сервис для работы с профилем пользователя: получение данных и привязка GitHub
class ProfileService {
  /// Запрос информации о пользователе по ID.
  /// Если код ответа != 200, бросает Exception с сообщением.
  Future<User> fetchUser({
    required String userId,
    required String jwtToken,
  }) async {
    final uri = Uri.parse('${kServerIp}/users/$userId');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
    );

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body) as Map<String, dynamic>;
      return User.fromJson(decoded);
    } else {
      throw Exception('Ошибка ${response.statusCode}: ${response.body}');
    }
  }

  /// Привязка GitHub-аккаунта — отправляет PAT.
  /// Если код ответа == 200, возвращает true, иначе бросает Exception.
  Future<bool> linkGitHub({
    required String userId,
    required String jwtToken,
    required String patToken,
  }) async {
    final uri = Uri.parse('${kServerIp}/users/$userId/github');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: json.encode({'token': patToken}),
    );

    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception('Ошибка привязки GitHub: ${response.body}');
    }
  }
}