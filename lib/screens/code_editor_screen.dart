import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/php.dart';
import 'package:highlight/languages/scala.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:xterm/xterm.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_simple_treeview/flutter_simple_treeview.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/terminal_widget.dart';
import '../manager/connection_manager.dart';
import '../services/file_service.dart';
import '../constants.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'dart:io' show Platform;

class CodeEditorScreen extends StatefulWidget {
  final Terminal terminal;
  final String projectName;
  final ConnectionManager connectionManager;
  final String userId;

  const CodeEditorScreen({
    Key? key,
    required this.terminal,
    required this.projectName,
    required this.connectionManager,
    required this.userId,
  }) : super(key: key);

  @override
  _CodeEditorScreenState createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late FileService _fileService;

  // Оптимизация: используем Map вместо трёх отдельных списков
  final Map<String, _FileData> _fileDataMap = {};
  List<String> _sortedFileNames = [];
  int? currentFileIndex;
  
  bool isSourceControlView = false;
  List<String> changedFiles = [];
  final TextEditingController _commitMessageController = TextEditingController();
  late final TabController _tabController;
  String? _folderForCommit;
  
  bool _showGitFolder = false;

  // Кэшируем языковую карту как static const
  static final Map<String, dynamic> _languageMap = {
    'dart': dart,
    'py': python,
    'js': javascript,
    'java': java,
    'cpp': cpp,
    'go': go,
    'scala': scala,
    'yaml': yaml,
    'php': php,
  };

  bool isLeftPanelVisible = true;
  final PanelController _panelController = PanelController();
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _tabsScrollController = ScrollController();

  // Оптимизация: используем LinkedHashSet для сохранения порядка и быстрого доступа
  final Set<int> _openOrder = {};
  
  // Кэш для дерева файлов
  List<FileNode>? _cachedFileTree;
  bool _fileTreeNeedsRebuild = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _fileService = FileService(
      jwtToken: widget.connectionManager.jwtToken!,
      projectName: widget.projectName,
    );

    _loadShowGitPreferenceAndFetch();
    _fetchChangedFilesFromServer();
    _tabController = TabController(length: 2, vsync: this);

    widget.connectionManager
        .fetchUserProfile(widget.userId)
        .catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось загрузить профиль: $e')),
        );
      }
    });
  }

  @override
  void dispose() {
    _tabsScrollController.dispose();
    _tabController.dispose();
    _commitMessageController.dispose();
    _editorFocusNode.dispose();
    
    // Освобождаем контроллеры
    for (var data in _fileDataMap.values) {
      data.controller.dispose();
    }
    
    super.dispose();
  }

  Future<void> _loadShowGitPreferenceAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    _showGitFolder = prefs.getBool('showGitFolder') ?? false;
    await fetchFileList();
  }

  // Оптимизированная загрузка списка файлов
  Future<void> fetchFileList() async {
    final files = await _fileService.fetchFileList();

    // Фильтрация и нормализация путей
    final normalizedFiles = files
        .map((f) => f.replaceAll(RegExp(r'[\\/]+$'), ''))
        .toSet()
        .where((f) {
          if (_showGitFolder) return true;
          final segments = f.split(RegExp(r'[\\/]+'));
          return !segments.any((seg) => seg.toLowerCase() == '.git');
        })
        .toList();

    // Сортировка
    normalizedFiles.sort(_compareFilePaths);

    setState(() {
      // Удаляем файлы, которых больше нет
      _fileDataMap.removeWhere((key, value) {
        if (!normalizedFiles.contains(key)) {
          value.controller.dispose();
          return true;
        }
        return false;
      });

      // Добавляем новые файлы
      for (var fileName in normalizedFiles) {
        if (!_fileDataMap.containsKey(fileName)) {
          final ext = p.extension(fileName).replaceFirst('.', '');
          _fileDataMap[fileName] = _FileData(
            controller: CodeController(
              text: '// Файл: $fileName',
              language: _languageMap[ext] ?? java,
            ),
            isOpen: false,
          );
        }
      }

      _sortedFileNames = normalizedFiles;
      _fileTreeNeedsRebuild = true;
      
      // Очищаем открытые файлы, которых больше нет
      _openOrder.removeWhere((idx) => idx >= _sortedFileNames.length);
      
      if (currentFileIndex != null && currentFileIndex! >= _sortedFileNames.length) {
        currentFileIndex = _openOrder.isNotEmpty ? _openOrder.first : null;
      }
    });
  }

  // Вынесли сравнение в отдельный метод для переиспользования
  int _compareFilePaths(String a, String b) {
    final aBase = p.basename(a);
    final bBase = p.basename(b);

    final aIsDir = !aBase.contains('.') && !aBase.startsWith('.');
    final bIsDir = !bBase.contains('.') && !bBase.startsWith('.');

    final aIsHidden = aBase.startsWith('.');
    final bIsHidden = bBase.startsWith('.');

    if (aIsDir && !bIsDir) return -1;
    if (!aIsDir && bIsDir) return 1;

    if (!aIsHidden && bIsHidden) return -1;
    if (aIsHidden && !bIsHidden) return 1;

    return aBase.toLowerCase().compareTo(bBase.toLowerCase());
  }

  Future<void> fetchFileContent(int index) async {
    if (index < 0 || index >= _sortedFileNames.length) return;

    final fileName = _sortedFileNames[index];
    final content = await _fileService.fetchFileContent(fileName);

    if (content != null && currentFileIndex == index && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _fileDataMap.containsKey(fileName)) {
          _fileDataMap[fileName]!.controller.text = content;
        }
      });
    }
  }

  void addNewFile() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Создать новый файл'),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            hintText: 'Введите имя файла (например, main.dart)'
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена')
          ),
          TextButton(
            onPressed: () async {
              final fileName = nameController.text.trim();
              if (fileName.isNotEmpty) {
                final success = await _fileService.createFile(fileName);
                if (success) {
                  if (!mounted) return;
                  await fetchFileList();
                } else {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка создания файла: $fileName')),
                  );
                }
              }
              if (mounted) Navigator.pop(context);
            },
            child: Text('Создать'),
          ),
        ],
      ),
    );
  }

  void addNewFolder() {
    final folderController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Создать новую папку'),
        content: TextField(
          controller: folderController,
          decoration: InputDecoration(hintText: 'Введите имя папки'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена')
          ),
          TextButton(
            onPressed: () async {
              final folderName = folderController.text.trim();
              if (folderName.isNotEmpty) {
                final success = await _fileService.createFolder(folderName);
                if (success) {
                  await fetchFileList();
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка создания папки: $folderName')),
                    );
                  }
                }
              }
              if (mounted) Navigator.pop(context);
            },
            child: Text('Создать'),
          ),
        ],
      ),
    );
  }

  void closeTab(int index) {
    setState(() {
      if (index >= 0 && index < _sortedFileNames.length) {
        final fileName = _sortedFileNames[index];
        if (_fileDataMap.containsKey(fileName)) {
          _fileDataMap[fileName]!.isOpen = false;
        }
      }
      
      _openOrder.remove(index);
      
      if (currentFileIndex == index) {
        currentFileIndex = _openOrder.isNotEmpty ? _openOrder.first : null;
      }
    });
  }

  void openFile(int index) {
    if (index < 0 || index >= _sortedFileNames.length) return;
    
    setState(() {
      final fileName = _sortedFileNames[index];
      if (_fileDataMap.containsKey(fileName)) {
        _fileDataMap[fileName]!.isOpen = true;
      }

      _openOrder.remove(index);
      _openOrder.add(index);

      currentFileIndex = index;
    });
    
    fetchFileContent(index);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tabsScrollController.hasClients) {
        _tabsScrollController.animateTo(
          _tabsScrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void openFileByPath(String filePath) {
    final idx = _sortedFileNames.indexOf(filePath);
    if (idx != -1) {
      openFile(idx);
    }
  }

  Future<void> onFileDrop(String oldPath, String? targetFolderPath) async {
    final idx = _sortedFileNames.indexOf(oldPath);
    if (idx == -1) return;
    
    final baseName = oldPath.split('/').last;
    final newPath = (targetFolderPath != null && targetFolderPath.isNotEmpty)
        ? '$targetFolderPath/$baseName'
        : baseName;
        
    await _fileService.moveFile(oldPath, newPath);
    await fetchFileList();
  }

  Future<void> saveCurrentFile() async {
    if (currentFileIndex == null || currentFileIndex! >= _sortedFileNames.length) return;
    
    final fileName = _sortedFileNames[currentFileIndex!];
    if (!_fileDataMap.containsKey(fileName)) return;
    
    final content = _fileDataMap[fileName]!.controller.text;
    final success = await _fileService.saveFile(fileName, content);
    
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Файл успешно сохранён: $fileName')),
        );
        await markFileAsChanged(fileName);
        await _syncChangedFilesToServer();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения файла: $fileName')),
        );
      }
    }
  }

  void runCurrentFile() {
    if (currentFileIndex == null || currentFileIndex! >= _sortedFileNames.length) return;
    
    final fileName = _sortedFileNames[currentFileIndex!];
    final command = _getRunCommand(fileName);
    
    if (_panelController.isPanelClosed) {
      _panelController.open();
    }
    widget.connectionManager.sendCommand(command);
  }

  String _getRunCommand(String fileName) {
    final projectPath = '/${widget.projectName}/$fileName';
    
    if (fileName.endsWith('.py')) {
      return "python3 $projectPath\n";
    } else if (fileName.endsWith('.dart')) {
      return "dart $projectPath\n";
    } else if (fileName.endsWith('.js')) {
      return "node $projectPath\n";
    } else if (fileName.endsWith('.go')) {
      return "go run $projectPath\n";
    } else if (fileName.endsWith('.php')) {
      return "php $projectPath\n";
    } else if (fileName.endsWith('.java')) {
      return "javac $projectPath && java -cp /${widget.projectName} Main\n";
    }
    
    return "echo 'Неподдерживаемый тип файла'\n";
  }

  void reconnectTerminal() {
    widget.connectionManager.dispose();
    widget.connectionManager.connect(
      widget.projectName,
      widget.terminal,
      (status) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                status.startsWith("Подключено")
                    ? "Терминал переподключён"
                    : "Ошибка подключения: $status",
              ),
            ),
          );
        }
      }
    );
  }

  Future<void> markFileAsChanged(String fileName) async {
    if (!changedFiles.contains(fileName)) {
      setState(() => changedFiles.add(fileName));
      await _fileService.syncChangedFiles(changedFiles);
    }
  }

  Future<void> _fetchChangedFilesFromServer() async {
    final list = await _fileService.fetchChangedFiles();
    if (mounted) {
      setState(() => changedFiles = list);
    }
  }

  Future<void> _syncChangedFilesToServer() async {
    await _fileService.syncChangedFiles(changedFiles);
  }

  Future<void> _createGitHubCommit() async {
    final token = widget.connectionManager.githubToken;
    final owner = widget.connectionManager.githubLogin;
    final repo = _folderForCommit;
    const branch = 'main';

    if (owner == null || owner.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GitHub owner (login) не задан.'))
        );
      }
      return;
    }
    
    if (repo == null || repo.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Выберите папку для коммита.'))
        );
      }
      return;
    }
    
    if (token == null || token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GitHub token отсутствует.'))
        );
      }
      return;
    }

    final Map<String, String> fileContents = {};
    for (var file in changedFiles) {
      if (_fileDataMap.containsKey(file) && _fileDataMap[file]!.isOpen) {
        fileContents[file] = _fileDataMap[file]!.controller.text;
      } else {
        final content = await _fileService.fetchFileContent(file);
        fileContents[file] = content ?? '';
      }
    }

    try {
      await _fileService.createGitHubCommit(
        owner: owner,
        repo: repo,
        githubToken: token,
        changedFiles: changedFiles,
        fileContents: fileContents,
        commitMessage: _commitMessageController.text.trim(),
      );
      
      if (mounted) {
        setState(() => changedFiles.clear());
        await _syncChangedFilesToServer();
        
        final commitUrl = 'https://github.com/$owner/$repo/commits/main';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Коммит успешно создан!'),
            action: SnackBarAction(
              label: 'Открыть',
              onPressed: () => launchUrl(Uri.parse(commitUrl)),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка коммита: $e'))
        );
      }
    }
  }

  void _showFileContextMenu(BuildContext context, String filePath) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.drive_file_rename_outline, color: Colors.white),
                title: Text('Переименовать', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showRenameDialog(context, filePath);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.white),
                title: Text('Удалить', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation(context, filePath);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showRenameDialog(BuildContext context, String oldPath) async {
    final nameController = TextEditingController(text: oldPath.split('/').last);
    String? newName;
    
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          title: Text('Переименовать файл', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: nameController,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Новое имя (без пути)',
              hintStyle: TextStyle(color: Colors.grey),
              filled: true,
              fillColor: Colors.grey[800],
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Отмена', style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () {
                newName = nameController.text.trim();
                Navigator.pop(ctx);
              },
              child: Text('Переименовать', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (newName == null || newName!.isEmpty) return;

    final segments = oldPath.split('/');
    segments.removeLast();
    segments.add(newName!);
    final newPath = segments.join('/');

    final success = await _fileService.renameFile(oldPath, newPath);
    
    if (mounted) {
      if (success) {
        await fetchFileList();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Файл переименован: $newName')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при переименовании')),
        );
      }
    }
  }

  Future<void> _showDeleteConfirmation(BuildContext context, String filePath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: Text('Удалить файл?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Вы уверены, что хотите удалить "$filePath"?',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Удалить', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await _fileService.deleteFile(filePath);
    
    if (mounted) {
      if (success) {
        await fetchFileList();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Файл удалён: $filePath')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка удаления файла')),
        );
      }
    }
  }

  TreeNode buildTreeNode(
    FileNode node,
    String parentPath,
    void Function(String filePath) onFileTap,
    void Function(String draggedFilePath, String? targetFolderPath) onFileDrop,
    BuildContext context,
  ) {
    final fullPath = parentPath.isEmpty ? node.name : '$parentPath/${node.name}';
    Widget content = Text(node.name, style: TextStyle(color: Colors.white));

    if (node.isFile) {
      content = Draggable<String>(
        data: fullPath,
        feedback: Material(
          color: Colors.transparent,
          child: Text(
            node.name,
            style: TextStyle(
              color: Colors.blueAccent,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.5, child: content),
        child: GestureDetector(
          onTap: () => onFileTap(fullPath),
          onLongPress: () => _showFileContextMenu(context, fullPath),
          child: content,
        ),
      );
    } else {
      content = DragTarget<String>(
        builder: (context, candidateData, rejectedData) {
          return Container(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(node.name, style: TextStyle(color: Colors.white)),
          );
        },
        onWillAccept: (_) => true,
        onAccept: (draggedFilePath) {
          onFileDrop(draggedFilePath, fullPath);
        },
      );
    }

    return TreeNode(
      content: content,
      children: node.children
          .map((child) => buildTreeNode(child, fullPath, onFileTap, onFileDrop, context))
          .toList(),
    );
  }

  Widget buildFileTreeView(
    List<FileNode> nodes,
    void Function(String filePath) onFileTap,
    void Function(String draggedFilePath, String? targetFolderPath) onFileDrop,
    BuildContext context,
  ) {
    return TreeView(
      treeController: TreeController(allNodesExpanded: false),
      nodes: nodes
          .map((node) => buildTreeNode(node, '', onFileTap, onFileDrop, context))
          .toList(),
    );
  }

  List<String> extractRootFolders(List<String> paths) {
    final folders = <String>{};
    
    for (var p in paths) {
      final segments = p.split('/');
      if (segments.isNotEmpty && segments[0] != widget.projectName) {
        folders.add(segments[0]);
      }
    }
    
    return [widget.projectName, ...folders.toList()]..sort();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Для AutomaticKeepAliveClientMixin
    
    // Кэшируем дерево файлов
    if (_fileTreeNeedsRebuild) {
      _cachedFileTree = buildFileTree(_sortedFileNames);
      _fileTreeNeedsRebuild = false;
    }
    
    final isDesktop = kIsWeb || 
        (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS));
    final bottomPadding = isDesktop ? 30.0 : 60.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(30.0),
        child: _buildAppBar(),
      ),
      body: SlidingUpPanel(
        controller: _panelController,
        color: Colors.transparent,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        minHeight: 0,
        maxHeight: MediaQuery.of(context).size.height * 0.5,
        panel: _buildTerminalPanel(),
        body: Row(
          children: [
            _buildLeftPanel(),
            Expanded(
              child: Column(
                children: [
                  _buildTabBar(),
                  Expanded(child: _buildEditor()),
                  SizedBox(height: bottomPadding),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return AppBar(
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      backgroundColor: Colors.black87,
      title: Row(
        children: [
          IconButton(
            icon: SvgPicture.string(
              '''<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24"><path fill="currentColor" d="M4 20q-.825 0-1.412-.587T2 18V6q0-.825.588-1.412T4 4h16q.825 0 1.413.588T22 6v12q0 .825-.587 1.413T20 20zm9-2h7V6h-7zm1-3h5v-1.5h-5zm0-2.5h5V11h-5zm0-2.5h5V8.5h-5z"/></svg>''',
              width: 20,
              height: 20,
              color: Colors.white,
            ),
            onPressed: () => setState(() => isLeftPanelVisible = !isLeftPanelVisible),
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: fetchFileList,
            tooltip: 'Обновить дерево файлов',
          ),
          IconButton(
            icon: Icon(Icons.add, color: Colors.white),
            onPressed: addNewFile,
            tooltip: 'Создать новый файл',
          ),
          IconButton(
            icon: Icon(Icons.create_new_folder, color: Colors.white),
            onPressed: addNewFolder,
            tooltip: 'Создать новую папку',
          ),
          IconButton(
            icon: Icon(Icons.save, color: Colors.white),
            onPressed: saveCurrentFile,
            tooltip: 'Сохранить файл',
          ),
          IconButton(
            icon: Icon(Icons.terminal, color: Colors.white),
            onPressed: () {
              _panelController.isPanelClosed
                  ? _panelController.open()
                  : _panelController.close();
            },
            tooltip: 'Терминал',
          ),
          Spacer(),
          IconButton(
            icon: Icon(Icons.play_arrow, color: Colors.white),
            onPressed: runCurrentFile,
            tooltip: 'Запустить код',
          ),
          IconButton(
            icon: Icon(Icons.stop, color: Colors.white),
            onPressed: () => widget.connectionManager.sendCommand("\x03"),
            tooltip: 'Остановить выполнение кода',
          ),
          Spacer(),
          Text(
            widget.projectName,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Spacer(),
          PopupMenuButton<String>(
            icon: Icon(Icons.person, color: Colors.white),
            onSelected: (value) {
              if (value == 'main_screen' &&
                  widget.connectionManager.jwtToken != null) {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/main',
                  (route) => false,
                  arguments: {
                    'userId': widget.userId,
                    'jwtToken': widget.connectionManager.jwtToken!,
                  },
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                value: 'main_screen',
                child: Text('Выбор проекта'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalPanel() {
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
      ),
      child: Container(
        color: Colors.black87,
        child: Column(
          children: [
            Container(
              margin: EdgeInsets.symmetric(vertical: 8),
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.refresh, color: Colors.white),
                    onPressed: reconnectTerminal,
                  ),
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_down, color: Colors.white),
                    onPressed: () => _panelController.close(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: TerminalWidget(
                  terminal: widget.terminal,
                  onTerminalCreated: (_) {},
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftPanel() {
    return AnimatedContainer(
      duration: Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: isLeftPanelVisible ? 250 : 0,
      color: Colors.grey[850],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.folder,
                    color: isSourceControlView ? Colors.grey : Colors.white,
                  ),
                  onPressed: () {
                    if (isSourceControlView) {
                      setState(() => isSourceControlView = false);
                    }
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.commit,
                    color: isSourceControlView ? Colors.white : Colors.grey,
                  ),
                  onPressed: () {
                    if (!isSourceControlView) {
                      setState(() => isSourceControlView = true);
                    }
                  },
                ),
              ],
            ),
          ),
          Divider(color: Colors.grey[700]),
          Expanded(
            child: isSourceControlView
                ? _buildSourceControlView()
                : _buildFileTreePanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceControlView() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Изменённые файлы:', style: TextStyle(color: Colors.white)),
          ...changedFiles.map((f) => Text('• $f', style: TextStyle(color: Colors.white))),
          SizedBox(height: 8),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: 'Папка для коммита',
              filled: true,
              fillColor: Colors.grey[800],
              border: OutlineInputBorder(),
              isDense: true,
            ),
            value: _folderForCommit,
            items: extractRootFolders(_sortedFileNames)
                .map((f) => DropdownMenuItem(
                      value: f,
                      child: Text(f, style: TextStyle(color: Colors.white)),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _folderForCommit = v),
            style: TextStyle(color: Colors.white),
          ),
          SizedBox(height: 8),
          TextField(
            controller: _commitMessageController,
            decoration: InputDecoration(
              hintText: 'Commit message',
              filled: true,
              fillColor: Colors.grey[800],
              border: OutlineInputBorder(),
              isDense: true,
            ),
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: changedFiles.isEmpty ? null : _createGitHubCommit,
              child: Text('Commit'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileTreePanel() {
    return DragTarget<String>(
      builder: (context, candidateData, rejectedData) {
        if (_sortedFileNames.isEmpty) {
          return Center(
            child: Text(
              "Нет доступных файлов",
              style: TextStyle(color: Colors.white),
            ),
          );
        }

        return ClipRect(
          child: InteractiveViewer(
            constrained: false,
            scaleEnabled: false,
            panEnabled: true,
            boundaryMargin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: buildFileTreeView(
                _cachedFileTree!,
                (path) {
                  final idx = _sortedFileNames.indexOf(path);
                  if (idx != -1) openFile(idx);
                },
                onFileDrop,
                context,
              ),
            ),
          ),
        );
      },
      onWillAccept: (_) => true,
      onAccept: (draggedFilePath) {
        onFileDrop(draggedFilePath, null);
      },
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 35,
      color: Colors.grey[850],
      alignment: Alignment.centerLeft,
      child: _openOrder.isEmpty
          ? SizedBox.shrink()
          : SingleChildScrollView(
              controller: _tabsScrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _openOrder.map((i) {
                  if (i >= _sortedFileNames.length) return SizedBox.shrink();
                  
                  return GestureDetector(
                    onTap: () => openFile(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: i == currentFileIndex
                                ? Colors.blue
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _sortedFileNames[i],
                            style: TextStyle(
                              color: i == currentFileIndex
                                  ? Colors.blue
                                  : Colors.white,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => closeTab(i),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
    );
  }

  Widget _buildEditor() {
    if (currentFileIndex == null || currentFileIndex! >= _sortedFileNames.length) {
      return Center(
        child: Text(
          "Выберите или создайте файл",
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    final fileName = _sortedFileNames[currentFileIndex!];
    if (!_fileDataMap.containsKey(fileName)) {
      return Center(
        child: Text(
          "Файл не найден",
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return CodeTheme(
      data: CodeThemeData(styles: monokaiSublimeTheme),
      child: Container(
        color: const Color(0xFF1F1F1F),
        child: RawKeyboardListener(
          focusNode: _editorFocusNode,
          autofocus: true,
          onKey: (event) {
            if (event is RawKeyDownEvent &&
                event.isControlPressed &&
                event.logicalKey == LogicalKeyboardKey.keyS) {
              saveCurrentFile();
            }
          },
          child: SingleChildScrollView(
            child: CodeField(
              controller: _fileDataMap[fileName]!.controller,
              background: const Color(0xFF1F1F1F),
              wrap: false,
              textStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.5,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Вспомогательный класс для хранения данных файла
class _FileData {
  final CodeController controller;
  bool isOpen;

  _FileData({
    required this.controller,
    this.isOpen = false,
  });
}