import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../constants.dart';

/// Для удобства: модель «файловой ноды» (осталась в сервисе, чтобы при необходимости расширить парсинг)
class FileNode {
  final String name;
  final List<FileNode> children;
  final bool isFile;

  FileNode({
    required this.name,
    List<FileNode>? children,
    required this.isFile,
  }) : children = children ?? [];
}

/// Построение дерева из списка путей (без UI-логики)
List<FileNode> buildFileTree(List<String> paths) {
  final root = <FileNode>[];
  for (var path in paths) {
    bool isFile = !path.endsWith('/');
    String processedPath = isFile ? path : path.substring(0, path.length - 1);
    final parts = processedPath.split('/');
    List<FileNode> currentLevel = root;
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      bool lastIsFile = (i == parts.length - 1) ? isFile : false;
      var existing = currentLevel.firstWhere(
        (node) => node.name == part,
        orElse: () => FileNode(name: part, isFile: lastIsFile),
      );
      if (!currentLevel.contains(existing)) {
        final newNode = FileNode(name: part, isFile: lastIsFile);
        currentLevel.add(newNode);
        currentLevel = newNode.children;
      } else {
        currentLevel = existing.children;
      }
    }
  }
  return root;
}

/// Общие HTTP-запросы для работы с файлами/папками, содержимым и GitHub
class FileService {
  final String jwtToken;
  final String projectName;

  FileService({
    required this.jwtToken,
    required this.projectName,
  });

  Uri _filesListUri() => Uri.parse('${kServerIp}/project/$projectName/files');
  Uri _fileContentUri(String fileName) =>
      Uri.parse('${kServerIp}/project/$projectName/file?filename=$fileName');
  Uri _createFileUri() => Uri.parse('${kServerIp}/project/$projectName/file/create');
  Uri _createFolderUri() => Uri.parse('${kServerIp}/project/$projectName/folder');
  Uri _moveFileUri() => Uri.parse('${kServerIp}/project/$projectName/move');
  Uri _saveFileUri() => Uri.parse('${kServerIp}/project/$projectName/file');
  Uri _changedFilesGetUri() => Uri.parse('${kServerIp}/project/$projectName/changed-files');
  Uri _changedFilesPostUri() => Uri.parse('${kServerIp}/project/$projectName/changed-files');
  Uri _gitHubRefUri(String owner, String repo) =>
      Uri.parse('https://api.github.com/repos/$owner/$repo/git/refs/heads/main');
  Uri _gitHubBlobUri(String owner, String repo) =>
      Uri.parse('https://api.github.com/repos/$owner/$repo/git/blobs');
  Uri _gitHubTreeUri(String owner, String repo) =>
      Uri.parse('https://api.github.com/repos/$owner/$repo/git/trees');
  Uri _gitHubCommitUri(String owner, String repo) =>
      Uri.parse('https://api.github.com/repos/$owner/$repo/git/commits');
  Uri _gitHubRefsCreateUri(String owner, String repo) =>
      Uri.parse('https://api.github.com/repos/$owner/$repo/git/refs');
  Uri _gitHubRefsUpdateUri(String owner, String repo) =>
      Uri.parse('https://api.github.com/repos/$owner/$repo/git/refs/heads/main');

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/json; charset=utf-8',
      };

  /// 1. Получить список файлов (просто массив строк)
  Future<List<String>> fetchFileList() async {
    final resp = await http.get(_filesListUri(), headers: _authHeaders);
    if (resp.statusCode == 200) {
      final List<dynamic> decoded = json.decode(resp.body);
      return decoded.cast<String>();
    } else {
      debugPrint('Ошибка получения файлов: ${resp.statusCode} ${resp.body}');
      return [];
    }
  }

  /// 2. Получить содержимое одного файла (в utf-8)
  Future<String?> fetchFileContent(String fileName) async {
    final resp = await http.get(_fileContentUri(fileName), headers: _authHeaders);
    if (resp.statusCode == 200) {
      return utf8.decode(resp.bodyBytes);
    } else {
      debugPrint('Ошибка получения содержимого файла ($fileName): ${resp.statusCode}');
      return null;
    }
  }

  /// 3. Создать новый файл (имя передаётся в body)
  Future<bool> createFile(String fileName) async {
    final resp = await http.post(
      _createFileUri(),
      headers: _authHeaders,
      body: json.encode({'filename': fileName}),
    );
    return resp.statusCode == 201;
  }

  /// 4. Создать новую папку (путь передаётся в body)
  Future<bool> createFolder(String folderPath) async {
    final resp = await http.post(
      _createFolderUri(),
      headers: _authHeaders,
      body: json.encode({'folderPath': folderPath}),
    );
    return resp.statusCode == 201;
  }

  /// 5. Переместить файл: в body – { oldPath, newPath }
  Future<void> moveFile(String oldPath, String newPath) async {
    await http.post(
      _moveFileUri(),
      headers: _authHeaders,
      body: json.encode({'oldPath': oldPath, 'newPath': newPath}),
    );
  }

  /// 6. Сохранить содержимое (POST { filename, content })
  Future<bool> saveFile(String fileName, String content) async {
    final resp = await http.post(
      _saveFileUri(),
      headers: _authHeaders,
      body: json.encode({'filename': fileName, 'content': content}),
    );
    return resp.statusCode == 200;
  }

  /// 7. Получить список изменённых файлов (GET → { files: [...] })
  Future<List<String>> fetchChangedFiles() async {
    final resp = await http.get(_changedFilesGetUri(), headers: _authHeaders);
    if (resp.statusCode == 200) {
      final decoded = json.decode(resp.body) as Map<String, dynamic>;
      return (decoded['files'] as List).cast<String>();
    }
    return [];
  }

  /// 8. Отправить на сервер список изменённых файлов (POST { files: [...] })
  Future<void> syncChangedFiles(List<String> files) async {
    await http.post(
      _changedFilesPostUri(),
      headers: _authHeaders,
      body: json.encode({'files': files}),
    );
  }

  /// 9. Создание GitHub-коммита (блокирует UI, если что-то не так)
  Future<void> createGitHubCommit({
    required String owner,
    required String repo,
    required String githubToken,
    required List<String> changedFiles,
    required Map<String, String> fileContents, // key: путь, value: текст
    required String commitMessage,
  }) async {
    // 9.1. Получаем SHA (либо 404 → initial commit)
    bool isInitial = false;
    String baseSha = '';
    final refResp = await http.get(
      _gitHubRefUri(owner, repo),
      headers: {'Authorization': 'token $githubToken'},
    );
    if (refResp.statusCode == 200) {
      baseSha = json.decode(refResp.body)['object']['sha'];
    } else if (refResp.statusCode == 404) {
      isInitial = true;
    } else {
      throw Exception('Не удалось получить ветку: ${refResp.statusCode}');
    }

    // 9.2. Для каждого файла создаём новый blob
    List<Map<String, dynamic>> treeEntries = [];
    for (var file in changedFiles) {
      final content = fileContents[file] ?? '';
      final blobResp = await http.post(
        _gitHubBlobUri(owner, repo),
        headers: {
          'Authorization': 'token $githubToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({'content': content, 'encoding': 'utf-8'}),
      );
      if (blobResp.statusCode != 201) {
        throw Exception('Ошибка создания blob для $file: ${blobResp.statusCode}');
      }
      final blobSha = json.decode(blobResp.body)['sha'];
      // определяем относительный путь внутри репозитория
      final segments = file.split('/');
      final relativePath =
          (segments.length > 1 && segments[0] == repo) ? segments.sublist(1).join('/') : file;
      treeEntries.add({
        'path': relativePath,
        'mode': '100644',
        'type': 'blob',
        'sha': blobSha,
      });
    }

    // 9.3. Создаём дерево (POST → /git/trees)
    final treePayload = isInitial
        ? json.encode({'tree': treeEntries})
        : json.encode({'base_tree': baseSha, 'tree': treeEntries});
    final treeResp = await http.post(
      _gitHubTreeUri(owner, repo),
      headers: {
        'Authorization': 'token $githubToken',
        'Content-Type': 'application/json',
      },
      body: treePayload,
    );
    if (treeResp.statusCode != 201) {
      throw Exception('Ошибка создания дерева: ${treeResp.statusCode}');
    }
    final newTreeSha = json.decode(treeResp.body)['sha'];

    // 9.4. Создаём коммит (POST → /git/commits)
    final commitPayload = <String, dynamic>{
      'message': commitMessage,
      'tree': newTreeSha,
      if (!isInitial) 'parents': [baseSha],
    };
    final commitResp = await http.post(
      _gitHubCommitUri(owner, repo),
      headers: {
        'Authorization': 'token $githubToken',
        'Content-Type': 'application/json',
      },
      body: json.encode(commitPayload),
    );
    if (commitResp.statusCode != 201) {
      throw Exception('Ошибка создания коммита: ${commitResp.statusCode}');
    }
    final newCommitSha = json.decode(commitResp.body)['sha'];

    // 9.5. Обновляем или создаём ссылку на ветку
    if (isInitial) {
      final refCreate = await http.post(
        _gitHubRefsCreateUri(owner, repo),
        headers: {
          'Authorization': 'token $githubToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({'ref': 'refs/heads/main', 'sha': newCommitSha}),
      );
      if (refCreate.statusCode != 201) {
        throw Exception('Ошибка создания ссылки на ветку: ${refCreate.statusCode}');
      }
    } else {
      final refUpdate = await http.patch(
        _gitHubRefsUpdateUri(owner, repo),
        headers: {
          'Authorization': 'token $githubToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({'sha': newCommitSha}),
      );
      if (refUpdate.statusCode != 200) {
        throw Exception('Ошибка обновления ссылки: ${refUpdate.statusCode}');
      }
    }
  }

  /// 10. Удалить файл или папку
  Future<bool> deleteFile(String fileName) async {
    final uri = Uri.parse('${kServerIp}/project/$projectName/file?filename=$fileName');
    final resp = await http.delete(uri, headers: _authHeaders);
    return resp.statusCode == 200;
  }

  /// 11. Переименовать (переместить) файл или папку
  Future<bool> renameFile(String oldPath, String newPath) async {
    try {
      await moveFile(oldPath, newPath);
      return true;
    } catch (_) {
      return false;
    }
  }
}