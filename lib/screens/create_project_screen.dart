import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../services/project_service.dart';
import '../theme/app_theme.dart';
import '../screens/code_editor_screen.dart';
import '../manager/connection_manager.dart';

class CreateProjectScreen extends StatefulWidget {
  final String jwtToken;
  final String userId;

  const CreateProjectScreen({
    Key? key,
    required this.jwtToken,
    required this.userId,
  }) : super(key: key);

  @override
  _CreateProjectScreenState createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _projectController = TextEditingController();
  final Map<String, bool> _selectedLanguages = {
    "python": false,
    "node": false,
    "java": false,
    "go": false,
    "php": false,
  };
  bool _isLoading = false;

  final ProjectService _projectService = ProjectService();

  Future<void> _createProject() async {
    if (!_formKey.currentState!.validate()) return;

    final projectName = _projectController.text.trim();
    final languages = _selectedLanguages.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    setState(() => _isLoading = true);

    try {
      await _projectService.createProject(
        jwtToken: widget.jwtToken,
        userId: widget.userId,
        projectName: projectName,
        languages: languages,
      );

      final terminal = Terminal(maxLines: 10000);
      final connectionManager = ConnectionManager()..jwtToken = widget.jwtToken;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CodeEditorScreen(
            terminal: terminal,
            projectName: projectName,
            connectionManager: connectionManager,
            userId: widget.userId,
          ),
        ),
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String error) {
    final msg = error.replaceFirst('Exception: ', '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.getContentBg(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Ошибка создания проекта',
          style: TextStyle(color: AppTheme.getTextColor(context)),
        ),
        content: Text(msg, style: TextStyle(color: AppTheme.getTextColor(context).withOpacity(0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('ОК', style: TextStyle(color: AppTheme.getAccent(context))),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _projectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formWidth = MediaQuery.of(context).size.width * 1;

    return Scaffold(
      backgroundColor: AppTheme.getBg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getRailBg(context),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.getTextColor(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Создание проекта',
          style: TextStyle(
            color: AppTheme.getTextColor(context),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: formWidth,
            child: Card(
              color: AppTheme.getCardBg(context).withOpacity(0.9),
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: _isLoading
                    ? _buildLoading()
                    : Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildNameField(),
                            const SizedBox(height: 16),
                            Text(
                              'Дополнительные настройки:',
                              style: TextStyle(
                                color: AppTheme.getTextColor(context),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildLanguageCard(),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _createProject,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.getAccent(context),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16, horizontal: 32),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Создать проект',
                                style: TextStyle(
                                  color: Theme.of(context).brightness == Brightness.light
                                      ? Colors.white
                                      : Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _projectController,
      style: TextStyle(color: AppTheme.getTextColor(context)),
      decoration: InputDecoration(
        labelText: 'Имя проекта',
        labelStyle: TextStyle(color: AppTheme.getTextColor(context).withOpacity(0.6)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.getDivider(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.getDivider(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.getAccent(context)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Введите имя проекта';
        }
        final trimmed = value.trim();
        if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(trimmed)) {
          return 'Недопустимые символы в имени';
        }
        return null;
      },
    );
  }

  Widget _buildLanguageCard() {
    return Card(
      color: AppTheme.getContentBg(context).withOpacity(0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      elevation: 2,
      child: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          dividerColor: AppTheme.getDivider(context),
        ),
        child: ExpansionTile(
          title: Text(
            'Предустановленные языки',
            style: TextStyle(color: AppTheme.getTextColor(context)),
          ),
          childrenPadding: EdgeInsets.zero,
          children: _selectedLanguages.keys.map((lang) {
            return CheckboxListTile(
              title: Text(lang, style: TextStyle(color: AppTheme.getTextColor(context))),
              value: _selectedLanguages[lang],
              activeColor: AppTheme.getAccent(context),
              checkColor: Theme.of(context).brightness == Brightness.light
                  ? Colors.white
                  : Colors.black,
              onChanged: (value) {
                setState(() {
                  _selectedLanguages[lang] = value ?? false;
                });
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(color: AppTheme.getAccent(context)),
        const SizedBox(height: 16),
        Text(
          'Подождите, ваш проект создается...',
          style: TextStyle(color: AppTheme.getTextColor(context).withOpacity(0.7)),
        ),
      ],
    );
  }
}