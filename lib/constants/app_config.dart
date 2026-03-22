/// 📱 Application Configuration & Constants
/// All environment-specific settings and constants are defined here
/// for easy maintenance and deployment across different estates.

import 'package:flutter/material.dart';

/// Application Metadata
class AppConfig {
  // App identification
  static const String appName = 'Infinity Estate Kiosk';
  static const String packageName = 'com.fynko.infinitykiosk';
  static const String version = '1.0.0';
  static const int buildNumber = 1;

  // Estate information (editable per deployment)
  static const String estateName = 'Infinity Estate';
  static const String estateLocation = 'Addo Road, Ajah, Lagos';
  static const String adminContactNumber = '08167322603';
  static const String adminEmail = 'admin@infinityestate.ng';

  // Default PIN - MUST be changed by admin on first run
  static const String defaultAdminPin = '1234';

  // App package names for whitelist
  // Try AccessCode NG first, fallback to Settings for testing
  static const String accessCodeNGPackage = 'ng.accesscode.app';
  static const String fallbackAppPackage = 'com.android.settings'; // Fallback for testing
  static const String dialerPackage = 'com.android.dialer';
  static const String phonePackage = 'com.android.phone';

  // Security timeouts
  static const Duration pinDialogTimeout = Duration(minutes: 5);
  static const Duration screenLockTimeout = Duration(minutes: 30);

  // Logging
  static const bool enableLogging = true;
  static const bool enableDetailedLogging = false; // Only in debug builds
}

/// Platform channel identifiers
class PlatformChannels {
  static const String kioskChannel = 'com.fynko.infinitykiosk/kiosk';
  static const String lockTaskChannel = 'com.fynko.infinitykiosk/locktask';
  static const String appLauncherChannel = 'com.fynko.infinitykiosk/launcher';
}

/// Method names for platform channels
class KioskMethods {
  static const String startKioskMode = 'startKioskMode';
  static const String stopKioskMode = 'stopKioskMode';
  static const String installUpdateApk = 'installUpdateApk';
  static const String isDeviceOwner = 'isDeviceOwner';
  static const String launchApp = 'launchApp';
  static const String openDialer = 'openDialer';
  static const String setGlobalSettings = 'setGlobalSettings';
  static const String applyKioskRestrictions = 'applyKioskRestrictions';
  static const String getDeviceInfo = 'getDeviceInfo';
}

/// UI Colors
class AppColors {
  static const Color primaryDark = Color(0xFF1A237E);
  static const Color surfaceDark = Color(0xFF0D1117);
  static const Color cardDark = Color(0xFF1A1A2E);
  static const Color accentBlue = Color(0xFF4FC3F7);
  static const Color errorRed = Color(0xFFEF5350);
  static const Color successGreen = Color(0xFF66BB6A);
  static const Color warningOrange = Color(0xFFFFB74D);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0BEC5);
  static const Color textHint = Color(0xFF546E7A);
}

/// UI Dimensions
class AppDimensions {
  static const double borderRadius = 12.0;
  static const double buttonHeight = 56.0;
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double iconSize = 48.0;
  static const double largeIconSize = 80.0;
}
