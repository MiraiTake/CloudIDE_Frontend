import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../services/project_service.dart';
import '../theme/app_theme.dart';
import 'create_project_screen.dart';
import '../screens/code_editor_screen.dart';
import '../manager/connection_manager.dart';
import 'profile_screen.dart';
import 'clone_repository_screen.dart';
import 'dart:math' as math;
import '../services/auth_middleware.dart';

class MainScreen extends StatefulWidget {
  final String userId;
  final String jwtToken;

  const MainScreen({
    Key? key,
    required this.userId,
    required this.jwtToken,
  }) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late Future<List<Project>> _projectsFuture;
  final ProjectService _projectService = ProjectService();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _checkAuthAndLoad();
  }

  void _loadProjects() {
    _projectsFuture = _projectService.fetchProjects(jwtToken: widget.jwtToken);
    setState(() {});
  }

  Future<void> _checkAuthAndLoad() async {
    final isAuth = await AuthMiddleware.checkAuth(context);
    if (!isAuth) {
      return;
    }
    _loadProjects();
  }

  void _navigateToCreate() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateProjectScreen(
          userId: widget.userId,
          jwtToken: widget.jwtToken,
        ),
      ),
    ).then((_) => _loadProjects());
  }

  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          userId: widget.userId,
          jwtToken: widget.jwtToken,
        ),
      ),
    );
  }

  void _navigateToClone() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CloneRepositoryScreen(
          userId: widget.userId,
          jwtToken: widget.jwtToken,
        ),
      ),
    ).then((_) => _loadProjects());
  }

  void _onSelect(int idx) {
    if (idx == 1) {
      _navigateToCreate();
    } else if (idx == 2) {
      _navigateToProfile();
    } else if (idx == 3) {
      _navigateToClone();
    }
    setState(() => _selectedIndex = 0);
  }

  void _connect(Project p) async {
    final terminal = Terminal(maxLines: 10000);
    final mgr = ConnectionManager()..jwtToken = widget.jwtToken;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (_) => const _LoadingOverlay(),
    );

    try {
      final service = ProjectService();
      await service.startContainer(
        jwtToken: widget.jwtToken,
        projectName: p.name,
      );

      await Future.delayed(const Duration(seconds: 5));

      mgr.connect(p.name, terminal, (status) {
        if (status.startsWith('Подключено')) {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CodeEditorScreen(
                terminal: terminal,
                projectName: p.name,
                connectionManager: mgr,
                userId: widget.userId,
              ),
            ),
          );
        } else if (status.startsWith('Ошибка') ||
            status.contains('failed') ||
            status.contains('не удалось')) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(status)));
        }
      });
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _delete(Project p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.getContentBg(context),
        title: Text('Удалить "${p.name}"?',
            style: TextStyle(color: AppTheme.getTextColor(context))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.getAccent(context)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _projectService.deleteProject(
          jwtToken: widget.jwtToken, projectName: p.name);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Проект удалён')));
      _loadProjects();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Widget _buildSidebar() {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: AppTheme.getRailBg(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(3, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Text('CloudIDE',
              style: TextStyle(
                  color: AppTheme.getTextColor(context),
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          _navButton(Icons.folder_open, 'Проекты', 0),
          _navButton(Icons.add, 'Новый проект', 1),
          _navButton(Icons.download, 'Клонировать репозиторий', 3),
          const Spacer(),
          _navButton(Icons.person, 'Профиль', 2),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, String label, int idx) {
    final selected = _selectedIndex == idx;
    final accent = AppTheme.getAccent(context);
    final textColor = AppTheme.getTextColor(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          backgroundColor:
              selected ? accent.withOpacity(0.2) : Colors.transparent,
          foregroundColor: selected ? accent : textColor.withOpacity(0.6),
          minimumSize: const Size(double.infinity, 48),
          alignment: Alignment.centerLeft,
        ),
        icon: Icon(icon),
        label: Text(label),
        onPressed: () => _onSelect(idx),
      ),
    );
  }

  Widget _buildProjectCard(Project p) {
    final accent = AppTheme.getAccent(context);
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: AppTheme.getCardBg(context).withOpacity(0.8),
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      shadowColor: accent.withOpacity(0.3),
      child: InkWell(
        onTap: () => _connect(p),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.code, size: 24, color: accent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: TextStyle(
                        color: AppTheme.getTextColor(context),
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Обновлён: ${p.updatedAt}',
                      style: TextStyle(
                        color: AppTheme.getTextColor(context).withOpacity(0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 22),
                color: Colors.redAccent,
                onPressed: () => _delete(p),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onPressed,
  }) {
    final accent = AppTheme.getAccent(context);
    
    return Container(
      width: 220,
      height: 180,
      margin: const EdgeInsets.all(16),
      child: Card(
        color: AppTheme.getCardBg(context).withOpacity(0.9),
        elevation: 6,
        shadowColor: accent.withOpacity(0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 36, color: accent),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.getTextColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.getTextColor(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProjects() {
    return FutureBuilder<List<Project>>(
      future: _projectsFuture,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: AppTheme.getAccent(context),
            ),
          );
        }

        final list = snap.data ?? [];

        if (list.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Добро пожаловать в CloudIDE',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w300,
                      color: AppTheme.getTextColor(context).withOpacity(0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        _buildActionCard(
                          icon: Icons.create_new_folder,
                          title: "Создать проект",
                          subtitle: "Начните новый проект с нуля",
                          onPressed: _navigateToCreate,
                        ),
                        _buildActionCard(
                          icon: Icons.download,
                          title: "Клонировать репозиторий",
                          subtitle: "Скопируйте существующий проект",
                          onPressed: _navigateToClone,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 16),
          itemCount: list.length,
          itemBuilder: (_, i) => _buildProjectCard(list[i]),
        );
      },
    );
  }

  Widget _buildMobileDrawer() {
    final accent = AppTheme.getAccent(context);
    final textColor = AppTheme.getTextColor(context);
    
    return Drawer(
      backgroundColor: AppTheme.getRailBg(context),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: AppTheme.getBg(context),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.code, size: 48, color: accent),
                const SizedBox(height: 8),
                Text(
                  'CloudIDE',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(Icons.folder_open, color: textColor),
            title: Text('Проекты', style: TextStyle(color: textColor)),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 0);
            },
          ),
          ListTile(
            leading: Icon(Icons.add, color: textColor),
            title: Text('Новый проект', style: TextStyle(color: textColor)),
            onTap: () {
              Navigator.pop(context);
              _navigateToCreate();
            },
          ),
          ListTile(
            leading: Icon(Icons.download, color: textColor),
            title: Text('Клонировать', style: TextStyle(color: textColor)),
            onTap: () {
              Navigator.pop(context);
              _navigateToClone();
            },
          ),
          Divider(color: AppTheme.getDivider(context)),
          ListTile(
            leading: Icon(Icons.person, color: textColor),
            title: Text('Профиль', style: TextStyle(color: textColor)),
            onTap: () {
              Navigator.pop(context);
              _navigateToProfile();
            },
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
      appBar: !isWideScreen
          ? AppBar(
              backgroundColor: AppTheme.getRailBg(context),
              title: Text(
                'CloudIDE',
                style: TextStyle(
                  color: AppTheme.getTextColor(context),
                  fontWeight: FontWeight.bold,
                ),
              ),
              elevation: 0,
            )
          : null,
      drawer: !isWideScreen ? _buildMobileDrawer() : null,
      body: isWideScreen
          ? Row(
              children: [
                _buildSidebar(),
                VerticalDivider(width: 1, color: AppTheme.getDivider(context)),
                Expanded(child: _buildProjects()),
              ],
            )
          : _buildProjects(),
    );
  }
}

class _LoadingOverlay extends StatefulWidget {
  const _LoadingOverlay({Key? key}) : super(key: key);

  @override
  State<_LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<_LoadingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _circleController;
  late final AnimationController _fadeController;

  final List<String> _messages = [
    "Подключение к окружению...",
    "Подготовка проекта...",
    "Почти готово..."
  ];

  int _currentMessageIndex = 0;

  @override
  void initState() {
    super.initState();

    _circleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
      lowerBound: 0.0,
      upperBound: 1.0,
    )..forward();

    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return false;
      await _fadeController.reverse();
      if (!mounted) return false;
      setState(() {
        _currentMessageIndex =
            (_currentMessageIndex + 1) % _messages.length;
      });
      await _fadeController.forward();
      return true;
    });
  }

  @override
  void dispose() {
    _circleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.getAccent(context);
    
    return Center(
      child: Dialog(
        backgroundColor: AppTheme.getCardBg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: AnimatedBuilder(
                  animation: _circleController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _CirclePainter(
                        progress: _circleController.value,
                        accentColor: accent,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              FadeTransition(
                opacity: _fadeController,
                child: Text(
                  _messages[_currentMessageIndex],
                  style: TextStyle(
                    color: AppTheme.getTextColor(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              _PulsingText(
                'Пожалуйста, подождите',
                color: AppTheme.getTextColor(context).withOpacity(0.38),
                fontSize: 13,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CirclePainter extends CustomPainter {
  final double progress;
  final Color accentColor;

  _CirclePainter({required this.progress, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paintBg = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final paintProgress = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: Offset(radius, radius), radius: radius);

    const sweep = 2 * math.pi;
    final startAngle = progress * sweep;
    final sweepAngle = math.pi / 2;

    canvas.drawArc(rect, 0, sweep, false, paintBg);
    canvas.drawArc(rect, startAngle, sweepAngle, false, paintProgress);
  }

  @override
  bool shouldRepaint(covariant _CirclePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.accentColor != accentColor;
}

class _PulsingText extends StatefulWidget {
  final String text;
  final double fontSize;
  final Color color;

  const _PulsingText(
    this.text, {
    this.fontSize = 16,
    this.color = Colors.white70,
    Key? key,
  }) : super(key: key);

  @override
  State<_PulsingText> createState() => _PulsingTextState();
}

class _PulsingTextState extends State<_PulsingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      lowerBound: 0.4,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeController,
      child: Text(
        widget.text,
        style: TextStyle(
          color: widget.color,
          fontSize: widget.fontSize,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}