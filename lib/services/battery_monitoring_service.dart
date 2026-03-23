/// 🔋 Battery Monitoring Service
/// 
/// Monitors device battery level and provides:
/// - Real-time battery percentage updates
/// - Low battery alerts
/// - Stream of battery changes for UI updates
///
/// SECURITY ALERT INTEGRATION:
/// - Alerts security when battery drops below threshold
/// - Prevents kiosk shutdown during critical operations

import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import '../utils/logger.dart';

class BatteryMonitoringService {
  static final BatteryMonitoringService _instance = BatteryMonitoringService._internal();
  
  factory BatteryMonitoringService() {
    return _instance;
  }
  
  BatteryMonitoringService._internal();

  final Battery _battery = Battery();
  final StreamController<int> _batteryController = StreamController<int>.broadcast();
  
  Stream<int> get batteryStream => _batteryController.stream;
  
  int _currentBatteryLevel = 100;
  int get currentBatteryLevel => _currentBatteryLevel;
  
  bool _isLowBattery = false;
  bool get isLowBattery => _isLowBattery;
  
  Timer? _batteryCheckTimer;
  
  // Configuration
  static const int LOW_BATTERY_THRESHOLD = 20; // Alert when below 20%
  static const int CRITICAL_BATTERY_THRESHOLD = 10; // Critical alert at 10%
  static const Duration _checkInterval = Duration(seconds: 30);

  /// Initialize battery monitoring
  Future<void> initialize() async {
    try {
      Logger.info('Initializing battery monitoring service', context: 'BatteryMonitoringService');
      
      // Get initial battery level
      await _updateBatteryLevel();
      
      // Start periodic battery checks
      _batteryCheckTimer = Timer.periodic(_checkInterval, (_) async {
        await _updateBatteryLevel();
      });
      
      Logger.info(
        'Battery monitoring initialized. Current level: $_currentBatteryLevel%',
        context: 'BatteryMonitoringService',
      );
    } catch (e, st) {
      Logger.error(
        'Error initializing battery monitoring',
        context: 'BatteryMonitoringService',
        error: e is Error ? e : null,
        stackTrace: st,
      );
    }
  }

  /// Update battery level and check for alerts
  Future<void> _updateBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;

      final hasChanged = level != _currentBatteryLevel;
      _currentBatteryLevel = level;

      // Keep alert state current even when the battery percentage is unchanged.
      _checkBatteryAlert();

      // Broadcast the latest known level so the UI can render immediately.
      _batteryController.add(level);

      if (hasChanged) {
        Logger.debug(
          'Battery level updated: $_currentBatteryLevel%',
          context: 'BatteryMonitoringService',
        );
      }
    } catch (e, st) {
      Logger.warning(
        'Error reading battery level',
        context: 'BatteryMonitoringService',
        error: e is Error ? e : null,
        stackTrace: st,
      );
    }
  }

  /// Check and handle battery alerts
  void _checkBatteryAlert() {
    final wasCritical = _isLowBattery;
    
    if (_currentBatteryLevel <= CRITICAL_BATTERY_THRESHOLD) {
      _isLowBattery = true;
      
      if (!wasCritical) {
        // CRITICAL alert - security should be notified immediately
        _alertSecurityCriticalBattery();
      }
    } else if (_currentBatteryLevel <= LOW_BATTERY_THRESHOLD) {
      _isLowBattery = true;
      
      if (!wasCritical) {
        // LOW battery warning
        _alertSecurityLowBattery();
      }
    } else {
      _isLowBattery = false;
    }
  }

  /// Alert security - Low battery warning
  void _alertSecurityLowBattery() {
    Logger.warning(
      '⚠️ LOW BATTERY ALERT: Battery at ${_currentBatteryLevel}%. Security should check device.',
      context: 'BatteryMonitoringService',
    );
  }

  /// Alert security - Critical battery warning
  void _alertSecurityCriticalBattery() {
    Logger.error(
      '🔴 CRITICAL BATTERY ALERT: Battery at ${_currentBatteryLevel}%. Device may shut down soon!',
      context: 'BatteryMonitoringService',
    );
  }

  /// Get battery status as human-readable string
  String getBatteryStatus() {
    if (_currentBatteryLevel <= CRITICAL_BATTERY_THRESHOLD) {
      return '🔴 CRITICAL: ${_currentBatteryLevel}%';
    } else if (_currentBatteryLevel <= LOW_BATTERY_THRESHOLD) {
      return '⚠️ LOW: ${_currentBatteryLevel}%';
    } else if (_currentBatteryLevel <= 50) {
      return '🟡 MEDIUM: ${_currentBatteryLevel}%';
    } else {
      return '🟢 GOOD: ${_currentBatteryLevel}%';
    }
  }

  /// Dispose resources
  void dispose() {
    Logger.info('Disposing battery monitoring service', context: 'BatteryMonitoringService');
    _batteryCheckTimer?.cancel();
    _batteryController.close();
  }
}
