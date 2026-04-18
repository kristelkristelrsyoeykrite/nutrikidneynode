import 'package:flutter/foundation.dart';

/// Centralized logging utility for debugging and tracking user flow
class AppLogger {
  static const String _prefix = '[NutriKidney]';

  /// Log info level messages
  static void info(String message, {String? tag}) {
    final logMessage = _formatMessage(message, tag, 'INFO');
    debugPrint(logMessage);
  }

  /// Log debug level messages
  static void debug(String message, {String? tag}) {
    final logMessage = _formatMessage(message, tag, 'DEBUG');
    debugPrint(logMessage);
  }

  /// Log warning level messages
  static void warning(String message, {String? tag}) {
    final logMessage = _formatMessage(message, tag, 'WARNING');
    debugPrint(logMessage);
  }

  /// Log error level messages
  static void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    final logMessage = _formatMessage(message, tag, 'ERROR');
    debugPrint(logMessage);
    if (error != null) {
      debugPrint('$_prefix [ERROR] Error: $error');
    }
    if (stackTrace != null) {
      debugPrint('$_prefix [ERROR] StackTrace: $stackTrace');
    }
  }

  /// Log success messages
  static void success(String message, {String? tag}) {
    final logMessage = _formatMessage(message, tag, 'SUCCESS');
    debugPrint(logMessage);
  }

  static String _formatMessage(String message, String? tag, String level) {
    final tagStr = tag != null ? '[$tag]' : '';
    return '$_prefix [$level] $tagStr $message';
  }
}

/// Common tags for logging
class LogTag {
  static const String auth = 'AUTH';
  static const String signup = 'SIGNUP';
  static const String otp = 'OTP';
  static const String profile = 'PROFILE';
  static const String onboarding = 'ONBOARDING';
  static const String firebase = 'FIREBASE';
  static const String database = 'DATABASE';
  static const String navigation = 'NAVIGATION';
}
