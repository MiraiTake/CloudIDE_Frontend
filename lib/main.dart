import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/main_screen.dart';
import 'services/jwt_service.dart';
import 'theme/app_theme.dart';

late final ValueNotifier<ThemeMode> themeNotifier;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); 

  final prefs = await SharedPreferences.getInstance();
  
  // Загрузка сохранённой темы
  final savedMode = prefs.getString('themeMode') ?? 'dark';
  themeNotifier = ValueNotifier(
    savedMode == 'light' ? ThemeMode.light : ThemeMode.dark,
  );

  runApp(MyApp(prefs: prefs));
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;
  
  const MyApp({Key? key, required this.prefs}) : super(key: key);

  /// Очищает данные истёкшей сессии
  void _clearExpiredSession() {
    prefs.remove('userId');
    prefs.remove('jwtToken');
    prefs.setBool('isLoggedIn', false);
  }

  @override
  Widget build(BuildContext context) {
    // Проверяем, есть ли сохраненные данные авторизации
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final userId = prefs.getString('userId');
    final jwtToken = prefs.getString('jwtToken');
    
    // Определяем начальный маршрут
    String initialRoute = '/';
    
    // Проверяем валидность токена
    if (isLoggedIn && userId != null && jwtToken != null) {
      if (JwtHelper.isTokenValid(jwtToken)) {
        // Токен валиден, автоматически входим
        initialRoute = '/main';
      } else {
        // Токен истёк, очищаем данные
        _clearExpiredSession();
      }
    }
    
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'CloudIDE',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          themeMode: mode,
          initialRoute: initialRoute,
          routes: {
            '/': (context) => const LoginScreen(),
            '/main': (context) {
              // Пробуем получить аргументы из навигации
              final args = ModalRoute.of(context)?.settings.arguments as Map<String, String>?;
              
              // Если аргументы есть, используем их, иначе берем из SharedPreferences
              final finalUserId = args?['userId'] ?? userId ?? '';
              final finalJwtToken = args?['jwtToken'] ?? jwtToken ?? '';
              
              return MainScreen(
                userId: finalUserId,
                jwtToken: finalJwtToken,
              );
            },
            '/profile': (context) {
              final args =
                  ModalRoute.of(context)!.settings.arguments as Map<String, String>;
              return ProfileScreen(
                userId: args['userId']!,
                jwtToken: args['jwtToken']!,
              );
            },
          },
        );
      },
    );
  }
}