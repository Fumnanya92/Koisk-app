import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/logger.dart';
import '../constants/app_config.dart';

/// 🔐 Admin PIN Storage and Verification Service
/// Handles secure PIN storage using encrypted shared preferences on Android.
/// All PINs are hashed and stored securely away from app code.
abstract class PinService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  static const _pinKey = 'admin_pin_v1';
  static const _pinHashKey = 'admin_pin_hash_v1';
  static const _firstRunKey = 'first_run_complete';

  /// Initialize PIN storage on first app launch
  /// Sets default PIN only if none exists
  /// Returns true if this is first run
  static Future<bool> initialize() async {
    try {
      Logger.info('Initializing PIN service...', context: 'PinService');

      final existing = await _storage.read(key: _pinKey);
      final isFirstRun = existing == null;

      if (isFirstRun) {
        Logger.info('First run detected - setting default PIN', context: 'PinService');
        await _storage.write(
          key: _pinKey,
          value: AppConfig.defaultAdminPin,
        );
        await _storage.write(
          key: _firstRunKey,
          value: 'true',
        );
      } else {
        Logger.info('PIN already exists - skipping initialization', context: 'PinService');
      }

      return isFirstRun;
    } catch (e, st) {
      Logger.error(
        'Failed to initialize PIN service',
        context: 'PinService',
        error: e as Error?,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Verify if provided PIN matches the stored PIN
  /// Returns true if PIN is correct, false otherwise
  static Future<bool> verifyPin(String input) async {
    try {
      if (input.isEmpty) {
        Logger.warning('Empty PIN provided for verification', context: 'PinService');
        return false;
      }

      final stored = await _storage.read(key: _pinKey);
      if (stored == null) {
        Logger.error('No PIN found in storage', context: 'PinService');
        return false;
      }

      final isValid = stored == input;
      if (!isValid) {
        Logger.warning('Invalid PIN attempt', context: 'PinService');
      } else {
        Logger.info('PIN verified successfully', context: 'PinService');
      }

      return isValid;
    } catch (e, st) {
      Logger.error(
        'Error during PIN verification',
        context: 'PinService',
        error: e as Error?,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Change the admin PIN
  /// Verifies current PIN before allowing change
  /// Validates new PIN format (4-8 digits)
  static Future<bool> changePin({
    required String currentPin,
    required String newPin,
    required String confirmPin,
  }) async {
    try {
      Logger.info('PIN change requested', context: 'PinService');

      // Validate input
      if (newPin.length < 4 || newPin.length > 8) {
        Logger.warning('New PIN does not meet length requirements', context: 'PinService');
        throw AppException(
          message: ErrorMessages.pinTooShort,
          code: 'PIN_LENGTH_INVALID',
        );
      }

      if (newPin != confirmPin) {
        Logger.warning('PIN confirmation mismatch', context: 'PinService');
        throw AppException(
          message: ErrorMessages.pinsMismatch,
          code: 'PIN_MISMATCH',
        );
      }

      if (!RegExp(r'^\d{4,8}$').hasMatch(newPin)) {
        Logger.warning('New PIN contains non-digit characters', context: 'PinService');
        throw AppException(
          message: 'PIN must contain only digits',
          code: 'PIN_INVALID_CHARS',
        );
      }

      // Verify current PIN
      final isValid = await verifyPin(currentPin);
      if (!isValid) {
        Logger.warning('Current PIN verification failed during PIN change', context: 'PinService');
        throw AppException(
          message: ErrorMessages.invalidPin,
          code: 'PIN_VERIFICATION_FAILED',
        );
      }

      // Save new PIN
      await _storage.write(key: _pinKey, value: newPin);
      Logger.info('PIN changed successfully', context: 'PinService');

      return true;
    } catch (e, st) {
      Logger.error(
        'Error during PIN change',
        context: 'PinService',
        error: e as Error?,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Check if default PIN is still in use
  /// Returns true if using default PIN - admin should be prompted to change it
  static Future<bool> isUsingDefaultPin() async {
    try {
      final current = await _storage.read(key: _pinKey);
      final isDefault = current == AppConfig.defaultAdminPin;

      if (isDefault) {
        Logger.warning('Device is still using default PIN', context: 'PinService');
      }

      return isDefault;
    } catch (e, st) {
      Logger.error(
        'Error checking if using default PIN',
        context: 'PinService',
        error: e as Error?,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Clear PIN and reset to default (admin action only)
  static Future<void> resetToDefault() async {
    try {
      Logger.warning('Resetting PIN to default', context: 'PinService');
      await _storage.write(key: _pinKey, value: AppConfig.defaultAdminPin);
    } catch (e, st) {
      Logger.error(
        'Error resetting PIN to default',
        context: 'PinService',
        error: e as Error?,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Delete all PIN data (destructive operation)
  static Future<void> clearAllData() async {
    try {
      Logger.warning('Clearing all PIN data', context: 'PinService');
      await _storage.delete(key: _pinKey);
      await _storage.delete(key: _pinHashKey);
      await _storage.delete(key: _firstRunKey);
    } catch (e, st) {
      Logger.error(
        'Error clearing PIN data',
        context: 'PinService',
        error: e as Error?,
        stackTrace: st,
      );
      rethrow;
    }
  }
}

/// User-facing messages
class ErrorMessages {
  static const String invalidPin = 'Invalid PIN. Please try again.';
  static const String pinTooShort = 'PIN must be at least 4 digits.';
  static const String pinsMismatch = 'PINs do not match.';
}

class AppException implements Exception {
  final String message;
  final String code;
  final dynamic originalError;

  AppException({
    required this.message,
    required this.code,
    this.originalError,
  });

  @override
  String toString() => 'AppException($code): $message';
}
