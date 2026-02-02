import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants.dart';
import 'package:flutter/material.dart';

/// Модель «Проект»
class Project {
  final String id;
  final String name;
  final String updatedAt;

  Project({
    required this.id,
    required this.name,
    required this.updatedAt,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }
}

/// Сервис для работы с проектами: получение списка, создание и удаление
class ProjectService {
  /// Получаем список проектов (тот же метод, что был ранее)
  Future<List<Project>> fetchProjects({required String jwtToken}) async {
    final uri = Uri.parse('${kServerIp}/projects');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
    );

    if (response.statusCode == 204) {
      return [];
    }
    if (response.statusCode == 200) {
      if (response.body.isEmpty || response.body.trim() == 'null') {
        return [];
      }
      final decoded = json.decode(response.body);
      if (decoded is List) {
        return decoded
            .map((item) => Project.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        debugPrint('Unexpected JSON format for projects: $decoded');
        return [];
      }
    }
    return [];
  }

  Future<void> cloneProjectFromGitHub({
  required String jwtToken,
  required String userId,
  required String repoUrl,
}) async {
  final uri = Uri.parse('${kServerIp}/project/clone');
  final response = await http.post(
    uri,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwtToken',
    },
    body: json.encode({
      'repo_url': repoUrl, // Убрали user_id, так как он берется из JWT
    }),
  );

  if (response.statusCode == 201) {
    return;
  } else if (response.statusCode == 409) {
    throw Exception('Проект с таким именем уже существует');
  } else {
    throw Exception('Ошибка клонирования: ${response.body}');
  }
}

Future<void> startContainer({
  required String jwtToken,
  required String projectName,
}) async {
  final url = Uri.parse('${kServerIp}/project/start/$projectName');
  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwtToken',
    },
  );

  if (response.statusCode != 200) {
    throw Exception('Ошибка запуска контейнера: ${response.body}');
  }
}

  /// Удаляем проект по имени
  Future<void> deleteProject({
    required String jwtToken,
    required String projectName,
  }) async {
    final url = Uri.parse('${kServerIp}/project/$projectName');
    final response = await http.delete(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
    );

    if (response.statusCode == 200 || response.statusCode == 204) {
      return;
    } else {
      throw Exception('Ошибка удаления проекта: ${response.statusCode}');
    }
  }

  /// Создаёт новый проект. 
  /// В теле передаётся { name, languages, user_id }.
  /// Если код ответа != 201, бросает Exception с сообщением (тело ответа или свой текст).
  Future<void> createProject({
    required String jwtToken,
    required String userId,
    required String projectName,
    required List<String> languages,
  }) async {
    final uri = Uri.parse('${kServerIp}/project');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: json.encode({
        'name': projectName,
        'languages': languages,
        'user_id': userId,
      }),
    );

    if (response.statusCode == 201) {
      // Успех, проект создан
      return;
    } else {
      // Попробуем распознать, если сообщение об ошибке содержит проверку на дублирование имени
      final body = response.body;
      if (body.contains('Проект с таким именем уже существует')) {
        throw Exception('Проект с таким именем уже существует');
      }
      throw Exception('Ошибка создания проекта: $body');
    }
  }
}