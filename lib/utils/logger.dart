import 'package:flutter/foundation.dart';

/// 🔍 Centralized Logging Service
/// Handles all app logging with different levels and contexts.
/// In production, this should integrate with a remote logging service.
class Logger {
  static final Logger _instance = Logger._internal();

  factory Logger() {
    return _instance;
  }

  Logger._internal();

  static const String _tag = '[KIOSK]';

  /// Log debug information
  static void debug(String message, {String? context}) {
    if (kDebugMode) {
      final prefix = context != null ? '$_tag[$context]' : _tag;
      debugPrint('🔵 DEBUG $prefix: $message');
    }
  }

  /// Log important information
  static void info(String message, {String? context}) {
    final prefix = context != null ? '$_tag[$context]' : _tag;
    debugPrint('ℹ️  INFO $prefix: $message');
  }

  /// Log warnings
  static void warning(String message, {String? context, Error? error, StackTrace? stackTrace}) {
    final prefix = context != null ? '$_tag[$context]' : _tag;
    debugPrint('⚠️  WARN $prefix: $message');
    if (error != null) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// Log errors
  static void error(String message, {String? context, Error? error, StackTrace? stackTrace}) {
    final prefix = context != null ? '$_tag[$context]' : _tag;
    debugPrint('🔴 ERROR $prefix: $message');
    if (error != null) {
      debugPrint('   Error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// Log critical issues
  static void critical(String message, {String? context, Error? error, StackTrace? stackTrace}) {
    final prefix = context != null ? '$_tag[$context]' : _tag;
    debugPrint('🚨 CRITICAL $prefix: $message');
    if (error != null) {
      debugPrint('   Error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}

/// 🛡️ Exception handling utility
class AppException implements Exception {
  final String message;
  final String code;
  final dynamic originalError;
  final StackTrace? stackTrace;

  AppException({
    required this.message,
    required this.code,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => 'AppException($code): $message';
}

/// User-facing error messages
class ErrorMessages {
  static const String genericError = 'An error occurred. Please try again.';
  static const String kioskActivationFailed = 'Failed to activate kiosk mode. Device may not be device owner.';
  static const String invalidPin = 'Invalid PIN. Please try again.';
  static const String pinTooShort = 'PIN must be at least 4 digits.';
  static const String pinsMismatch = 'PINs do not match.';
  static const String fileAccessError = 'Failed to access secure storage.';
  static const String appLaunchError = 'Failed to launch application.';
  static const String deviceOwnerRequired = 'Device owner mode is required for full security.';
}
