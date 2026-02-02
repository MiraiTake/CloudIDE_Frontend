import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'jwt_service.dart';
import 'token_refresh_service.dart';
import '../constants.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Middleware для проверки авторизации перед доступом к защищённым экранам
class AuthMiddleware {
  /// Проверяет, авторизован ли пользователь и валиден ли его токен
  /// Если нет - перенаправляет на экран входа
  /// Если токен скоро истечёт - пытается обновить
  static Future<bool> checkAuth(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final jwtToken = prefs.getString('jwtToken');
    
    // Проверяем наличие токена
    if (!isLoggedIn || jwtToken == null) {
      _redirectToLogin(context);
      return false;
    }
    
    // Проверяем, нужно ли обновить токен
    if (JwtHelper.shouldRefreshToken(jwtToken)) {
      debugPrint('🔄 Токен скоро истечёт, пытаемся обновить...');
      
      final refreshed = await TokenRefreshService.refreshTokenWithRetry();
      
      if (!refreshed) {
        debugPrint('❌ Не удалось обновить токен');
        await _clearSession(prefs);
        _redirectToLogin(context, message: 'Сессия истекла. Пожалуйста, войдите снова.');
        return false;
      }
      
      debugPrint('✅ Токен успешно обновлён');
      return true;
    }
    
    // Проверяем валидность токена
    if (!JwtHelper.isTokenValid(jwtToken)) {
      await _clearSession(prefs);
      _redirectToLogin(context, message: 'Сессия истекла. Пожалуйста, войдите снова.');
      return false;
    }
    
    return true;
  }
  
  /// Очищает сессию пользователя
  static Future<void> _clearSession(SharedPreferences prefs) async {
    await prefs.remove('userId');
    await prefs.remove('jwtToken');
    await prefs.remove('refreshToken');
    await prefs.setBool('isLoggedIn', false);
  }
  
  /// Перенаправляет на экран входа
  static void _redirectToLogin(BuildContext context, {String? message}) {
    if (message != null) {
      // Показываем сообщение перед редиректом
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.orange[800],
            duration: const Duration(seconds: 3),
          ),
        );
      });
    }
    
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/',
      (route) => false,
    );
  }
  
  /// Получает данные авторизованного пользователя
  static Future<Map<String, String>?> getAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    final jwtToken = prefs.getString('jwtToken');
    
    if (userId == null || jwtToken == null) {
      return null;
    }
    
    if (!JwtHelper.isTokenValid(jwtToken)) {
      await _clearSession(prefs);
      return null;
    }
    
    return {
      'userId': userId,
      'jwtToken': jwtToken,
    };
  }
  
  /// Выполняет выход из системы с отзывом refresh token на сервере
  static Future<void> logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refreshToken');
    
    // Пытаемся отозвать токен на сервере
    if (refreshToken != null) {
      try {
        await http.post(
          Uri.parse('${kServerIp}/auth/logout'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'refresh_token': refreshToken}),
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('Ошибка отзыва токена: $e');
        // Продолжаем выход даже если отозвать не удалось
      }
    }
    
    await _clearSession(prefs);
    
    // Останавливаем автоматическое обновление токена
    TokenRefreshService.stopAutoRefresh();
    
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/',
        (route) => false,
      );
    }
  }
}