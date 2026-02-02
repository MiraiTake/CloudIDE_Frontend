import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/profile_service.dart';
import 'github_auth_screen.dart';
import '../main.dart';
import '../services/auth_middleware.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final String jwtToken;

  const ProfileScreen({
    Key? key,
    required this.userId,
    required this.jwtToken,
  }) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<User> _userFuture;
  bool _showEmail = false;
  String _selectedOption = 'account';
  bool _showGitFolder = false;

  final ProfileService _profileService = ProfileService();

  @override
  void initState() {
    super.initState();
    _loadShowGitPreference();
    _refreshProfile();
  }

  Future<void> _loadShowGitPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showGitFolder = prefs.getBool('showGitFolder') ?? false;
    });
  }

  Future<void> _saveShowGitPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showGitFolder', value);
    setState(() {
      _showGitFolder = value;
    });
  }

  Future<void> _onToggleShowGit(bool newValue) async {
    if (newValue) {
      final confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.getContentBg(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text('Внимание',
              style: TextStyle(
                  color: Colors.red, fontWeight: FontWeight.bold)),
          content: Text(
            'Отображение папки .git позволяет видеть скрытые файлы управления версиями. '
            'Любые изменения внутри этой папки могут привести к необратимым последствиям. '
            'Вы уверены, что хотите включить показ .git?',
            style: TextStyle(color: AppTheme.getTextColor(context)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Отмена',
                  style: TextStyle(color: AppTheme.getTextColor(context))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[900],
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Подтвердить'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await _saveShowGitPreference(true);
      }
    } else {
      await _saveShowGitPreference(false);
    }
  }

  void _refreshProfile() {
    setState(() {
      _userFuture = _profileService.fetchUser(
        userId: widget.userId,
        jwtToken: widget.jwtToken,
      );
    });
  }

  Future<void> _startGitHubLink() async {
    final pat = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => GitHubAuthScreen(jwtToken: widget.jwtToken),
      ),
    );
    if (pat == null || pat.isEmpty) return;
    try {
      await _profileService.linkGitHub(
        userId: widget.userId,
        jwtToken: widget.jwtToken,
        patToken: pat,
      );
      _refreshProfile();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red[800],
        ),
      );
    }
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final local = parts[0], domain = parts[1];
    if (local.length <= 2) return '*' * local.length + '@' + domain;
    return '${local[0]}${'*' * (local.length - 2)}${local[local.length - 1]}@$domain';
  }

  Future<void> _setTheme(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode);
    themeNotifier.value = mode == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.getContentBg(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('Подтвердите выход',
            style: TextStyle(color: AppTheme.getTextColor(context))),
        content: Text('Вы уверены, что хотите выйти из аккаунта?',
            style: TextStyle(color: AppTheme.getTextColor(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена', style: TextStyle(color: AppTheme.getTextColor(context))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB71C1C),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await AuthMiddleware.logout(context);
            },
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountInfo(User user) {
    final displayEmail = _showEmail ? user.email : _maskEmail(user.email);
    return Card(
      color: AppTheme.getCardBg(context).withOpacity(0.9),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      shadowColor: AppTheme.getAccent(context).withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: AppTheme.getAccent(context).withOpacity(0.2),
              child: Icon(Icons.person, size: 40, color: AppTheme.getAccent(context)),
            ),
            const SizedBox(height: 16),
            Text(
              user.username,
              style: TextStyle(
                  color: AppTheme.getTextColor(context), 
                  fontSize: 24, 
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    displayEmail,
                    style: TextStyle(color: AppTheme.getTextColor(context), fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _showEmail ? Icons.visibility_off : Icons.visibility,
                    color: AppTheme.getTextColor(context),
                  ),
                  onPressed: () => setState(() => _showEmail = !_showEmail),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (user.githubLogin != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.link, color: AppTheme.getAccent(context)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'GitHub: ${user.githubLogin}',
                      style: TextStyle(color: AppTheme.getTextColor(context)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            else
              ElevatedButton(
                onPressed: _startGitHubLink,
                child: const Text('Подключить GitHub'),
              ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _confirmLogout,
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text(
                'Выйти',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: Colors.red[900]?.withOpacity(0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemSettings() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Card(
      color: AppTheme.getCardBg(context).withOpacity(0.9),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      shadowColor: AppTheme.getAccent(context).withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Выбор темы',
              style: TextStyle(
                  color: AppTheme.getTextColor(context), 
                  fontSize: 20, 
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                GestureDetector(
                  onTap: () => _setTheme('light'),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: !isDark
                          ? Border.all(color: AppTheme.getAccent(context), width: 3)
                          : null,
                    ),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.wb_sunny, color: Colors.amber[700]),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                GestureDetector(
                  onTap: () => _setTheme('dark'),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: isDark
                          ? Border.all(color: AppTheme.getAccent(context), width: 3)
                          : null,
                    ),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF121212),
                      child: const Icon(Icons.nightlight_round, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            Divider(height: 32, color: AppTheme.getDivider(context)),
            Text(
              'Параметры редактора кода',
              style: TextStyle(
                  color: AppTheme.getTextColor(context), 
                  fontSize: 20, 
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text(
                'Показывать папку .git в дереве файлов',
                style: TextStyle(color: AppTheme.getTextColor(context)),
              ),
              value: _showGitFolder,
              onChanged: _onToggleShowGit,
              activeColor: AppTheme.getAccent(context),
              inactiveTrackColor: AppTheme.getDivider(context),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Card(
      color: AppTheme.getRailBg(context),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      shadowColor: AppTheme.getAccent(context).withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Настройки',
              style: TextStyle(
                  color: AppTheme.getTextColor(context), 
                  fontSize: 20, 
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.person,
                  color: _selectedOption == 'account' 
                      ? AppTheme.getAccent(context) 
                      : AppTheme.getTextColor(context)),
              title: Text(
                'Аккаунт',
                style: TextStyle(
                  color: _selectedOption == 'account' 
                      ? AppTheme.getTextColor(context) 
                      : AppTheme.getTextColor(context).withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
              selected: _selectedOption == 'account',
              onTap: () => setState(() => _selectedOption = 'account'),
            ),
            ListTile(
              leading: Icon(Icons.palette,
                  color: _selectedOption == 'system' 
                      ? AppTheme.getAccent(context) 
                      : AppTheme.getTextColor(context)),
              title: Text(
                'Системные',
                style: TextStyle(
                  color: _selectedOption == 'system' 
                      ? AppTheme.getTextColor(context) 
                      : AppTheme.getTextColor(context).withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
              selected: _selectedOption == 'system',
              onTap: () => setState(() => _selectedOption = 'system'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileTabBar() {
    return Container(
      color: AppTheme.getRailBg(context),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _selectedOption = 'account'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _selectedOption == 'account' 
                          ? AppTheme.getAccent(context) 
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person,
                      color: _selectedOption == 'account' 
                          ? AppTheme.getAccent(context) 
                          : AppTheme.getTextColor(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Аккаунт',
                      style: TextStyle(
                        color: _selectedOption == 'account' 
                            ? AppTheme.getTextColor(context) 
                            : AppTheme.getTextColor(context).withOpacity(0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _selectedOption = 'system'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _selectedOption == 'system' 
                          ? AppTheme.getAccent(context) 
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.palette,
                      color: _selectedOption == 'system' 
                          ? AppTheme.getAccent(context) 
                          : AppTheme.getTextColor(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Системные',
                      style: TextStyle(
                        color: _selectedOption == 'system' 
                            ? AppTheme.getTextColor(context) 
                            : AppTheme.getTextColor(context).withOpacity(0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: AppTheme.getBg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getRailBg(context),
        title: Text(
          'Профиль пользователя',
          style: TextStyle(
            color: AppTheme.getTextColor(context),
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
        bottom: !isWideScreen
            ? PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: _buildMobileTabBar(),
              )
            : null,
      ),
      body: isWideScreen
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 300,
                    child: _buildSidebar(),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildContent(),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildContent(),
            ),
    );
  }

  Widget _buildContent() {
    return _selectedOption == 'account'
        ? FutureBuilder<User>(
            future: _userFuture,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(color: AppTheme.getAccent(context)),
                );
              }
              if (snap.hasError) {
                return Center(
                  child: Text(
                    'Ошибка загрузки:\n${snap.error}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return _buildAccountInfo(snap.data!);
            },
          )
        : _buildSystemSettings();
  }
}