import 'package:flutter/material.dart';
import '../services/profile_service.dart';
import '../services/project_service.dart';
import '../theme/app_theme.dart';
import 'github_auth_screen.dart';

class CloneRepositoryScreen extends StatefulWidget {
  final String userId;
  final String jwtToken;

  const CloneRepositoryScreen({
    Key? key,
    required this.userId,
    required this.jwtToken,
  }) : super(key: key);

  @override
  State<CloneRepositoryScreen> createState() => _CloneRepositoryScreenState();
}

class _CloneRepositoryScreenState extends State<CloneRepositoryScreen> {
  final TextEditingController _repoUrlController = TextEditingController();
  bool _isGitHubLinked = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkGitHubConnection();
  }

  Future<void> _checkGitHubConnection() async {
    final profileService = ProfileService();
    try {
      final user = await profileService.fetchUser(
        userId: widget.userId,
        jwtToken: widget.jwtToken,
      );
      setState(() {
        _isGitHubLinked = user.githubLogin != null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка проверки GitHub: $e'),
          backgroundColor: Colors.red[800],
        ),
      );
    }
  }

  Future<void> _cloneRepository() async {
    final repoUrl = _repoUrlController.text.trim();
    if (repoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Введите URL репозитория'),
          backgroundColor: Colors.red[800],
        ),
      );
      return;
    }

    try {
      setState(() => _isLoading = true);
      final projectService = ProjectService();
      await projectService.cloneProjectFromGitHub(
        jwtToken: widget.jwtToken,
        userId: widget.userId,
        repoUrl: repoUrl,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Репозиторий успешно клонирован'),
          backgroundColor: Colors.green[800],
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      setState(() => _isLoading = false);
      String errorMessage = "Ошибка клонирования";
      final error = e.toString();
      if (error.contains("Project with this name already exists")) {
        errorMessage = "Проект с таким именем уже существует";
      } else if (error.contains("GitHub token not found")) {
        errorMessage = "Токен GitHub не найден. Перепривяжите аккаунт";
      } else if (error.contains("Clone failed")) {
        errorMessage = "Ошибка доступа к репозиторию:\n${error.replaceFirst('Exception: Clone failed: ', '')}";
      } else if (error.contains("Invalid repository URL")) {
        errorMessage = "Некорректный URL репозитория";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red[800],
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppTheme.getAccent(context)),
      );
    }

    if (!_isGitHubLinked) {
      return _buildGitHubCard();
    }
    return _buildCloneCard();
  }

  Widget _buildGitHubCard() {
    return Center(
      child: Container(
        width: 500,
        margin: const EdgeInsets.all(16),
        child: Card(
          color: AppTheme.getCardBg(context).withOpacity(0.9),
          elevation: 6,
          shadowColor: AppTheme.getAccent(context).withOpacity(0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Для клонирования необходимо привязать аккаунт GitHub',
                  style: TextStyle(
                    color: AppTheme.getTextColor(context),
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GitHubAuthScreen(jwtToken: widget.jwtToken),
                      ),
                    ).then((_) => _checkGitHubConnection());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.getAccent(context),
                    foregroundColor: Theme.of(context).brightness == Brightness.light
                        ? Colors.white
                        : Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Привязать GitHub', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCloneCard() {
    return Center(
      child: Container(
        width: 500,
        margin: const EdgeInsets.all(16),
        child: Card(
          color: AppTheme.getCardBg(context).withOpacity(0.9),
          elevation: 6,
          shadowColor: AppTheme.getAccent(context).withOpacity(0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Введите URL репозитория GitHub:',
                  style: TextStyle(
                    color: AppTheme.getTextColor(context),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _repoUrlController,
                  style: TextStyle(color: AppTheme.getTextColor(context)),
                  decoration: InputDecoration(
                    hintText: 'https://github.com/username/repository.git',
                    hintStyle: TextStyle(color: AppTheme.getTextColor(context).withOpacity(0.5)),
                    filled: true,
                    fillColor: AppTheme.getContentBg(context),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _cloneRepository,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.getAccent(context),
                    foregroundColor: Theme.of(context).brightness == Brightness.light
                        ? Colors.white
                        : Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Клонировать репозиторий', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.getBg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getCardBg(context),
        title: Text(
          'Клонировать репозиторий',
          style: TextStyle(color: AppTheme.getTextColor(context)),
        ),
        iconTheme: IconThemeData(color: AppTheme.getTextColor(context)),
      ),
      body: _buildContent(),
    );
  }
}