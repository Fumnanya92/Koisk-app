/// 🚀 Infinity Estate Kiosk - Main Entry Point
/// 
/// APP STARTUP SEQUENCE:
/// 1. Initialize Flutter bindings
/// 2. Hide all system UI (status bar, navigation)
/// 3. Initialize secure PIN storage
/// 4. Activate kiosk lock mode
/// 5. Launch main Kiosk screen
///
/// SECURITY MEASURES:
/// - Immersive sticky mode hides all system UI
/// - Lock task mode prevents app switching
/// - PIN protected admin panel
/// - Device owner mode enforces system restrictions
///
/// This app is designed to be the ONLY usable interface on the device.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'constants/app_config.dart';
import 'screens/kiosk_screen.dart';
import 'services/kiosk_service.dart';
import 'services/pin_service.dart';
import 'utils/logger.dart';

void main() async {
  try {
    // Ensure Flutter bindings are initialized
    // Required before calling native platform code
    WidgetsFlutterBinding.ensureInitialized();

    Logger.info('=== APP START ===', context: 'main');
    Logger.info('App: ${AppConfig.appName} v${AppConfig.version}', context: 'main');
    Logger.info('Estate: ${AppConfig.estateName}', context: 'main');

    // CRITICAL: Hide ALL system UI immediately
    // This prevents users from seeing system elements that might allow escape
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    Logger.info('System UI hidden (immersive mode)', context: 'main');

    // Lock screen orientation to portrait
    // Prevents rotation which could expose system UI
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    Logger.info('Screen orientation locked to portrait', context: 'main');

    // Initialize PIN service
    // Sets default PIN on first run
    // After first run, only changes if admin updates it
    final isFirstRun = await PinService.initialize();
    if (isFirstRun) {
      Logger.warning('FIRST RUN: Default PIN has been set (${AppConfig.defaultAdminPin})', context: 'main');
    }

    // Activate kiosk lock mode
    // This enables lock task mode if device is device owner
    // If device owner not set, app will still run but security is limited
    await KioskService.initialize();

    Logger.info('Initialization complete - launching app', context: 'main');

    runApp(const InfinityKioskApp());
  } catch (e, st) {
    Logger.critical(
      'FATAL ERROR during app initialization',
      context: 'main',
      error: e as Error?,
      stackTrace: st,
    );
    // Continue anyway - user will see error UI
    runApp(const InfinityKioskApp());
  }
}

/// Main app widget
/// Sets up Material theme and navigation
class InfinityKioskApp extends StatelessWidget {
  const InfinityKioskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryDark,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: AppColors.surfaceDark,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primaryDark,
          elevation: 4,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        buttonTheme: const ButtonThemeData(
          height: AppDimensions.buttonHeight,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingLarge,
              vertical: AppDimensions.paddingMedium,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.cardDark,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
            borderSide: const BorderSide(color: AppColors.accentBlue),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
            borderSide: const BorderSide(color: AppColors.accentBlue, width: 2),
          ),
          labelStyle: const TextStyle(color: AppColors.accentBlue),
          hintStyle: const TextStyle(color: AppColors.textHint),
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          bodyMedium: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 16,
          ),
          bodySmall: TextStyle(
            color: AppColors.textHint,
            fontSize: 14,
          ),
        ),
      ),
      home: const KioskScreen(),
    );
  }
}

// Theme colors exported from app_config
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

class AppDimensions {
  static const double borderRadius = 12.0;
  static const double buttonHeight = 56.0;
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
}
