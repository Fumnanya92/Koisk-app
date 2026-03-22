import 'package:flutter/services.dart';
import '../constants/app_config.dart';
import '../utils/logger.dart';

/// 🔒 Kiosk Service - Platform Communication Layer
/// Handles all communication with native Android layer for:
/// - Lock task mode activation/deactivation
/// - Device owner verification
/// - App launching (whitelisted apps only)
/// - Native device controls
///
/// This service uses method channels to invoke native Kotlin code
/// that manages device-level security and restrictions.
abstract class KioskService {
  static const _channel = MethodChannel(PlatformChannels.kioskChannel);

  /// Initialize kiosk service and activate lock task mode
  /// Call this on app startup
  /// Returns true if successfully activated, false if not device owner
  static Future<bool> initialize() async {
    try {
      Logger.info('Initializing kiosk service...', context: 'KioskService');

      final isOwner = await isDeviceOwner();
      if (!isOwner) {
        Logger.warning(
          'Device is not device owner - kiosk mode will not be fully secure',
          context: 'KioskService',
        );
        return false;
      }

      await activateKiosk();
      Logger.info('Kiosk mode activated successfully', context: 'KioskService');
      return true;
    } catch (e, st) {
      Logger.error(
        'Failed to initialize kiosk service',
        context: 'KioskService',
        error: e is Error ? e : null,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Start lock task mode (kiosk lock)
  /// Requires device owner mode to be effective
  /// When active:
  /// - App becomes locked in foreground
  /// - System navigation buttons disabled
  /// - Home button does not exit app
  /// - Recent apps hidden
  static Future<void> activateKiosk() async {
    try {
      Logger.info('Activating lock task mode', context: 'KioskService');
      await _channel.invokeMethod<bool>(KioskMethods.startKioskMode);
      Logger.info('Lock task mode activated', context: 'KioskService');
    } on PlatformException catch (e) {
      Logger.error(
        'PlatformException activating kiosk mode: ${e.message}',
        context: 'KioskService',
      );
      // Don't rethrow - allow app to continue even if kiosk mode fails
      // (might be in dev mode without device owner)
    } catch (e, st) {
      Logger.error(
        'Unexpected error activating kiosk',
        context: 'KioskService',
        error: e is Error ? e : null,
        stackTrace: st,
      );
    }
  }

  /// Stop lock task mode (kiosk unlock)
  /// Admin action - only called after successful PIN verification
  /// After this:
  /// - App is no longer locked in foreground
  /// - User can access other apps and settings
  /// - Lock task mode will be reactivated if app restarts
  static Future<void> deactivateKiosk() async {
    try {
      Logger.info('Deactivating lock task mode', context: 'KioskService');
      await _channel.invokeMethod<bool>(KioskMethods.stopKioskMode);
      Logger.info('Lock task mode deactivated', context: 'KioskService');
    } on PlatformException catch (e) {
      Logger.error(
        'PlatformException deactivating kiosk: ${e.message}',
        context: 'KioskService',
      );
    } catch (e, st) {
      Logger.error(
        'Unexpected error deactivating kiosk',
        context: 'KioskService',
        error: e is Error ? e : null,
        stackTrace: st,
      );
    }
  }

  /// Launch the Android APK picker and hand the chosen update to the system
  /// package installer. Intended for admin-only use on managed devices.
  static Future<bool> installUpdateApk() async {
    try {
      Logger.info('Launching managed APK update flow', context: 'KioskService');
      final started = await _channel.invokeMethod<bool>(KioskMethods.installUpdateApk);
      final didStart = started ?? false;

      if (didStart) {
        Logger.info('APK update flow launched', context: 'KioskService');
      } else {
        Logger.warning('APK update flow did not start', context: 'KioskService');
      }

      return didStart;
    } on PlatformException catch (e) {
      Logger.error(
        'PlatformException starting update flow: ${e.message}',
        context: 'KioskService',
      );
      return false;
    } catch (e, st) {
      Logger.error(
        'Unexpected error starting update flow',
        context: 'KioskService',
        error: e is Error ? e : null,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Check if device is in device owner mode
  /// Device owner mode enables:
  /// - Full device control and restrictions
  /// - Lock task mode functionality
  /// - System-level policy enforcement
  /// - User restrictions
  /// Without device owner mode, security is severely limited
  static Future<bool> isDeviceOwner() async {
    try {
      final result = await _channel.invokeMethod<bool>(KioskMethods.isDeviceOwner);
      final isOwner = result ?? false;

      if (isOwner) {
        Logger.info('Device owner mode is active', context: 'KioskService');
      } else {
        Logger.warning('Device owner mode is NOT active', context: 'KioskService');
      }

      return isOwner;
    } on PlatformException catch (e) {
      Logger.error(
        'PlatformException checking device owner: ${e.message}',
        context: 'KioskService',
      );
      return false;
    } catch (e, st) {
      Logger.error(
        'Unexpected error checking device owner',
        context: 'KioskService',
        error: e is Error ? e : null,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Launch AccessCode NG application
  /// This is the main app that kiosk users interact with
  /// Only called after user taps the main button on kiosk screen
  static Future<bool> openAccessCodeNG() async {
    try {
      Logger.info('Attempting to launch AccessCode NG', context: 'KioskService');
      return await _launchApp(
        AppConfig.accessCodeNGPackage,
        appLabel: 'AccessCode NG',
      );
    } catch (e, st) {
      Logger.error(
        'Error launching AccessCode NG',
        context: 'KioskService',
        error: e is Error ? e : null,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Launch phone dialer to call admin
  /// The number is predefined in AppConfig (currently 08167322603)
  /// Only dialer is whitelisted - SMS/messaging not allowed
  static Future<bool> openDialer(String number) async {
    try {
      if (number.isEmpty) {
        Logger.warning('Empty phone number provided', context: 'KioskService');
        return false;
      }

      Logger.info('Attempting to open dialer for: $number', context: 'KioskService');
      final opened = await _channel.invokeMethod<bool>(
        KioskMethods.openDialer,
        {'number': number},
      );
      if (opened != true) {
        Logger.warning('Dialer did not report success', context: 'KioskService');
        return false;
      }
      Logger.info('Dialer opened successfully', context: 'KioskService');
      return true;
    } on PlatformException catch (e) {
      Logger.error(
        'PlatformException opening dialer: ${e.message}',
        context: 'KioskService',
      );
      return false;
    } catch (e, st) {
      Logger.error(
        'Error opening dialer',
        context: 'KioskService',
        error: e is Error ? e : null,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Generic app launcher (internal use)
  /// Safely launches whitelisted apps
  static Future<bool> _launchApp(String packageName, {String? appLabel}) async {
    try {
      if (packageName.isEmpty) {
        Logger.warning('Empty package name provided', context: 'KioskService');
        return false;
      }

      final opened = await _channel.invokeMethod<bool>(
        KioskMethods.launchApp,
        {
          'packageName': packageName,
          if (appLabel != null) 'appLabel': appLabel,
        },
      );
      if (opened != true) {
        Logger.warning(
          'App launch did not report success: $packageName',
          context: 'KioskService',
        );
        return false;
      }
      Logger.info('App launched: $packageName', context: 'KioskService');
      return true;
    } on PlatformException catch (e) {
      if (e.code == 'APP_NOT_FOUND') {
        Logger.warning(
          'App not installed: $packageName',
          context: 'KioskService',
        );
      } else {
          Logger.error(
            'PlatformException launching app: ${e.message}',
            context: 'KioskService',
          );
      }
      return false;
    } catch (e, st) {
      Logger.error(
        'Error launching app: $packageName',
        context: 'KioskService',
        error: e is Error ? e : null,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Get device information for debugging and status display
  static Future<Map<String, dynamic>?> getDeviceInfo() async {
    try {
      Logger.info('Fetching device info', context: 'KioskService');
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        KioskMethods.getDeviceInfo,
      );
      final info = result?.cast<String, dynamic>();
      Logger.info('Device info retrieved', context: 'KioskService');
      return info;
    } catch (e, st) {
      Logger.error(
        'Error getting device info',
        context: 'KioskService',
        error: e is Error ? e : null,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Re-enforce immersive mode when app comes to foreground
  /// Call from didChangeAppLifecycleState when state == resumed
  static Future<void> reactivateOnResume() async {
    try {
      await activateKiosk();
    } catch (e) {
      Logger.warning(
        'Error reactivating on resume',
        context: 'KioskService',
        error: e is Error ? e : null,
      );
    }
  }
}
