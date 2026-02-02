import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../constants.dart';
import 'jwt_service.dart';

/// Сервис для автоматического обновления JWT токенов
class TokenRefreshService {
  static Timer? _refreshTimer;
  static bool _isRefreshing = false;
  
  /// Запускает автоматическое обновление токена
  static void startAutoRefresh() {
    // Проверяем токен каждые 60 секунд
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _checkAndRefreshToken(),
    );
  }
  
  /// Останавливает автоматическое обновление
  static void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }
  
  /// Проверяет и обновляет токен при необходимости
  static Future<void> _checkAndRefreshToken() async {
    if (_isRefreshing) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken');
      
      if (jwtToken == null) return;
      
      // Если токен нужно обновить
      if (JwtHelper.shouldRefreshToken(jwtToken)) {
        debugPrint('🔄 Токен скоро истечёт, обновляем...');
        await refreshToken();
      }
    } catch (e) {
      debugPrint('❌ Ошибка проверки токена: $e');
    }
  }
  
  /// Обновляет JWT токен через API
  static Future<bool> refreshToken() async {
    if (_isRefreshing) {
      debugPrint('⏳ Обновление токена уже выполняется');
      return false;
    }
    
    _isRefreshing = true;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final oldToken = prefs.getString('jwtToken');
      
      if (oldToken == null) {
        debugPrint('❌ Токен не найден');
        return false;
      }
      
      // Проверяем, не истёк ли токен полностью
      if (!JwtHelper.isTokenValid(oldToken)) {
        debugPrint('❌ Токен полностью истёк, требуется повторный вход');
        await _clearSession(prefs);
        return false;
      }
      
      // Отправляем запрос на обновление токена
      final response = await http.post(
        Uri.parse('${kServerIp}$kRefreshTokenEndpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $oldToken',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Timeout при обновлении токена');
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newToken = data['token'] as String?;
        
        if (newToken == null) {
          debugPrint('❌ Новый токен не получен');
          return false;
        }
        
        // Проверяем валидность нового токена
        if (!JwtHelper.isTokenValid(newToken)) {
          debugPrint('❌ Получен невалидный токен');
          return false;
        }
        
        // Сохраняем новый токен
        await prefs.setString('jwtToken', newToken);
        
        final expiry = JwtHelper.getTokenExpiry(newToken);
        debugPrint('✅ Токен успешно обновлён. Истекает: $expiry');
        
        return true;
      } else if (response.statusCode == 401) {
        // Токен не может быть обновлён, требуется повторный вход
        debugPrint('❌ Токен не может быть обновлён (401)');
        await _clearSession(prefs);
        return false;
      } else {
        debugPrint('❌ Ошибка обновления токена: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Исключение при обновлении токена: $e');
      return false;
    } finally {
      _isRefreshing = false;
    }
  }
  
  /// Пытается обновить токен с повторными попытками
  static Future<bool> refreshTokenWithRetry({int maxAttempts = 3}) async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      debugPrint('🔄 Попытка обновления токена $attempt/$maxAttempts');
      
      final success = await refreshToken();
      if (success) {
        return true;
      }
      
      if (attempt < maxAttempts) {
        // Ждём перед следующей попыткой
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    
    debugPrint('❌ Не удалось обновить токен после $maxAttempts попыток');
    return false;
  }
  
  /// Очищает сессию
  static Future<void> _clearSession(SharedPreferences prefs) async {
    await prefs.remove('userId');
    await prefs.remove('jwtToken');
    await prefs.setBool('isLoggedIn', false);
  }
  
  /// Получает информацию о токене для отладки
  static Future<Map<String, dynamic>?> getTokenInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwtToken');
      
      if (token == null) return null;
      
      final isValid = JwtHelper.isTokenValid(token);
      final shouldRefresh = JwtHelper.shouldRefreshToken(token);
      final expiry = JwtHelper.getTokenExpiry(token);
      final timeUntilExpiry = JwtHelper.getTimeUntilExpiry(token);
      
      return {
        'isValid': isValid,
        'shouldRefresh': shouldRefresh,
        'expiry': expiry?.toString(),
        'timeUntilExpiry': timeUntilExpiry?.toString(),
      };
    } catch (e) {
      return null;
    }
  }
}