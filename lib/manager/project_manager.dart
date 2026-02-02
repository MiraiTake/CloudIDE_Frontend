import 'package:flutter/material.dart';
import 'connection_manager.dart';
import 'package:xterm/xterm.dart';
import '../screens/code_editor_screen.dart';

class ProjectManager {
  final TextEditingController projectController;
  final Function(String) updateStatus;
  final String userId;
  final String jwtToken;
  late Terminal terminal;
  final ConnectionManager connectionManager = ConnectionManager();

  ProjectManager({
    required this.projectController,
    required this.updateStatus,
    required this.userId,
    required this.jwtToken,
  }) {
    terminal = Terminal(maxLines: 10000);
    connectionManager.jwtToken = jwtToken;
  }

  void createProject({required List<String> languages}) {
    final projectName = projectController.text.trim();
    if (projectName.isEmpty) {
      updateStatus("Введите имя проекта!");
      return;
    }
    // Передаём userId вместе с данными проекта
    connectionManager.createProject(projectName, languages, userId, updateStatus);
  }

   bool _navigated = false;

  void connect(BuildContext context) {
    String projectName = projectController.text.trim();
    if (projectName.isEmpty) {
      updateStatus("Введите имя проекта!");
      return;
    }

    connectionManager.connect(projectName, terminal, (status) {
      updateStatus(status);
      if (!_navigated && status.startsWith("Подключено")) {
        _navigated = true;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CodeEditorScreen(
              terminal: terminal,
              projectName: projectName,
              connectionManager: connectionManager,
              userId: userId,
            ),
          ),
        );
      } else if (status.contains("Ошибка") ||
          status.contains("не найден") ||
          status.contains("Доступ")) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(status)),
        );
      }
    });
  }

  void dispose() {
    connectionManager.dispose();
  }
}