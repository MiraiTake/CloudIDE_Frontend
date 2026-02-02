import 'dart:convert';

/// Утилита для работы с JWT токенами
class JwtHelper {
  /// Проверяет, валиден ли JWT токен
  /// Возвращает true, если токен не истёк, false - в противном случае
  static bool isTokenValid(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        return false;
      }
      
      // Декодируем payload (вторая часть токена)
      final payload = parts[1];
      final normalized = base64.normalize(payload);
      final payloadMap = json.decode(
        utf8.decode(base64Url.decode(normalized))
      ) as Map<String, dynamic>;
      
      // Проверяем срок действия (exp - expiration time)
      final exp = payloadMap['exp'];
      if (exp == null) {
        // Если срок действия не указан, считаем токен валидным
        return true;
      }
      
      // Преобразуем Unix timestamp в DateTime
      final expiryDate = DateTime.fromMillisecondsSinceEpoch(
        (exp as int) * 1000
      );
      
      // Проверяем, не истёк ли токен
      // Добавляем небольшой буфер в 30 секунд для учёта расхождения времени
      final now = DateTime.now();
      final buffer = const Duration(seconds: 30);
      
      return now.isBefore(expiryDate.subtract(buffer));
    } catch (e) {
      // Если произошла ошибка при парсинге, считаем токен невалидным
      return false;
    }
  }
  
  /// Проверяет, нужно ли обновить токен (истекает в течение 5 минут)
  static bool shouldRefreshToken(String token) {
    try {
      final expiryDate = getTokenExpiry(token);
      if (expiryDate == null) {
        return false;
      }
      
      final now = DateTime.now();
      final timeUntilExpiry = expiryDate.difference(now);
      
      // Обновляем токен, если до истечения осталось меньше 5 минут
      return timeUntilExpiry.inMinutes < 5;
    } catch (e) {
      return false;
    }
  }
  
  /// Возвращает время до истечения токена
  static Duration? getTimeUntilExpiry(String token) {
    try {
      final expiryDate = getTokenExpiry(token);
      if (expiryDate == null) {
        return null;
      }
      
      final now = DateTime.now();
      return expiryDate.difference(now);
    } catch (e) {
      return null;
    }
  }
  
  /// Извлекает user_id из JWT токена
  static String? getUserIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        return null;
      }
      
      final payload = parts[1];
      final normalized = base64.normalize(payload);
      final payloadMap = json.decode(
        utf8.decode(base64Url.decode(normalized))
      ) as Map<String, dynamic>;
      
      return payloadMap['user_id'] as String?;
    } catch (e) {
      return null;
    }
  }
  
  /// Извлекает время истечения токена
  static DateTime? getTokenExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        return null;
      }
      
      final payload = parts[1];
      final normalized = base64.normalize(payload);
      final payloadMap = json.decode(
        utf8.decode(base64Url.decode(normalized))
      ) as Map<String, dynamic>;
      
      final exp = payloadMap['exp'] as int?;
      if (exp == null) {
        return null;
      }
      
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    } catch (e) {
      return null;
    }
  }
  
  /// Нормализует Base64 строку (добавляет padding если нужно)
  static String base64Normalize(String source) {
    return base64.normalize(source);
  }
}