import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:xterm/xterm.dart';
import '../constants.dart';

class ConnectionManager {
  IOWebSocketChannel? _channel;
  String status = "Ожидание подключения...";

  /// JWT, который вы получаете при логине
  String? jwtToken;

  /// GitHub Personal Access Token, полученный после OAuth и сохранённый на сервере
  String? githubToken;
  String? githubLogin;

  ConnectionManager({this.jwtToken, this.githubToken, this.githubLogin});

  /// Позволяет установить GitHub-токен «извне»
  void setGithubToken(String token) {
    githubToken = token;
  }

   void setGithubLogin(String login) {
    githubLogin = login;
  }

  Future<void> fetchUserProfile(String userId) async {
    final url = Uri.parse('${kServerIp}/users/$userId');
    final resp = await http.get(
      url,
      headers: { 'Authorization': 'Bearer $jwtToken' },
    );
    if (resp.statusCode != 200) {
      throw Exception('Не удалось получить профиль: ${resp.statusCode}');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    githubLogin = data['github_login'] as String?;
    githubToken = data['github_token'] as String?;
  }

  /// Функция для входа в систему и получения JWT-токена
  Future<void> login(
    String username,
    String password,
    Function(String) updateStatus,
  ) async {
    final uri = Uri.parse('${kServerIp}/login');

    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({"username": username, "password": password}),
      );

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        jwtToken = jsonResponse["token"];
        updateStatus("Успешный вход!");
      } else {
        updateStatus("Ошибка входа: ${response.body}");
      }
    } catch (e) {
      updateStatus("Ошибка: $e");
    }
  }

  /// Создание нового проекта
  void createProject(
    String projectName,
    List<String> languages,
    String userId,
    Function(String) updateStatus,
  ) async {
    if (jwtToken == null) {
      updateStatus("Ошибка: Войдите в систему сначала.");
      return;
    }

    if (projectName.isEmpty) {
      updateStatus("Введите имя проекта!");
      return;
    }

    updateStatus("Создание проекта...");

    try {
      final uri = Uri.parse('${kServerIp}/project');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
        body: json.encode({
          "name": projectName,
          "languages": languages,
          "user_id": userId,
        }),
      );

      if (response.statusCode == 201) {
        updateStatus("Проект создан!");
      } else {
        updateStatus("Ошибка создания проекта: ${response.body}");
      }
    } catch (e) {
      updateStatus("Ошибка: $e");
    }
  }

  /// Подключение к WebSocket серверу
  void connect(
    String projectName,
    Terminal terminal,
    Function(String) updateStatus,
  ) async {
    if (jwtToken == null) {
      updateStatus("Ошибка: Войдите в систему сначала.");
      return;
    }

    if (projectName.isEmpty) {
      updateStatus("Введите имя проекта");
      return;
    }

    final wsUrl  = '${kServerIpWs}/project/$projectName/ws?token=${Uri.encodeComponent(jwtToken!)}';
    print("Connecting to WebSocket: $wsUrl");

    try {
      _channel = IOWebSocketChannel.connect(wsUrl);
    } catch (e) {
      updateStatus("Ошибка подключения: $e");
      return;
    }

    updateStatus("Подключено к $projectName");

    _channel!.stream.listen(
      (data) => terminal.write(data.toString()),
      onError: (error) => updateStatus("Ошибка WebSocket: $error"),
      onDone: () => updateStatus("Соединение закрыто."),
    );

    terminal.onOutput = (input) => _channel?.sink.add(input);
  }

  /// Отправка команды через WebSocket
  void sendCommand(String command) {
    _channel?.sink.add(command);
  }

  /// Закрытие соединения
  void dispose() {
    _channel?.sink.close();
  }
}
