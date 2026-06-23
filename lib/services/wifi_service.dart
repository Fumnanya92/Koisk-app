import 'dart:async';
import 'package:flutter/services.dart';
import '../constants/app_config.dart';
import '../utils/logger.dart';

enum WifiConnectionState { connected, disconnected, disabled }

class WifiStatus {
  final WifiConnectionState state;
  const WifiStatus(this.state);

  bool get isConnected => state == WifiConnectionState.connected;
  bool get isEnabled => state != WifiConnectionState.disabled;
}

class WifiService {
  WifiService._();
  static final WifiService instance = WifiService._();

  static const _channel = MethodChannel(PlatformChannels.kioskChannel);

  StreamController<WifiStatus> _streamController =
      StreamController<WifiStatus>.broadcast();

  Stream<WifiStatus> get wifiStream => _streamController.stream;

  WifiStatus _currentStatus = const WifiStatus(WifiConnectionState.disabled);
  WifiStatus get currentStatus => _currentStatus;

  Timer? _pollTimer;
  int _consecutiveFailures = 0;

  Future<void> initialize() async {
    // Recreate stream controller if previously disposed (e.g. in tests)
    if (_streamController.isClosed) {
      _streamController = StreamController<WifiStatus>.broadcast();
      _consecutiveFailures = 0;
    }

    await _fetchAndEmit();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      AppConfig.wifiCheckInterval,
      (_) => _pollAndReconnect(),
    );
    Logger.info('WifiService initialized', context: 'WifiService');
  }

  Future<void> _fetchAndEmit() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        KioskMethods.getWifiStatus,
      );
      if (result == null) return;

      final enabled = result['enabled'] as bool? ?? false;
      final connected = result['connected'] as bool? ?? false;

      final state = !enabled
          ? WifiConnectionState.disabled
          : connected
              ? WifiConnectionState.connected
              : WifiConnectionState.disconnected;

      _currentStatus = WifiStatus(state);
      if (!_streamController.isClosed) {
        _streamController.add(_currentStatus);
      }
    } on PlatformException catch (e) {
      Logger.error('Failed to get Wi-Fi status: ${e.message}',
          context: 'WifiService');
    }
  }

  Future<void> _pollAndReconnect() async {
    await _fetchAndEmit();
    if (_currentStatus.state == WifiConnectionState.disconnected) {
      await reconnect();
    } else if (_currentStatus.state == WifiConnectionState.connected) {
      _consecutiveFailures = 0;
    }
  }

  Future<bool> setWifiEnabled(bool enabled) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        KioskMethods.setWifiEnabled,
        {'enabled': enabled},
      );
      // Give the OS a moment to apply the change before reading status
      await Future.delayed(const Duration(seconds: 1));
      await _fetchAndEmit();
      Logger.info('Wi-Fi enabled set to $enabled', context: 'WifiService');
      return result ?? false;
    } on PlatformException catch (e) {
      Logger.error('Failed to set Wi-Fi enabled: ${e.message}',
          context: 'WifiService');
      return false;
    }
  }

  Future<bool> reconnect() async {
    try {
      final result =
          await _channel.invokeMethod<bool>(KioskMethods.reconnectWifi);
      final success = result ?? false;

      if (!success) {
        _consecutiveFailures++;
        Logger.warning(
          'Wi-Fi reconnect failed ($_consecutiveFailures consecutive failures)',
          context: 'WifiService',
        );
      } else {
        _consecutiveFailures = 0;
      }

      // Give OS time to connect before re-reading status
      await Future.delayed(const Duration(seconds: 3));
      await _fetchAndEmit();
      return success;
    } on PlatformException catch (e) {
      Logger.error('Failed to reconnect Wi-Fi: ${e.message}',
          context: 'WifiService');
      _consecutiveFailures++;
      return false;
    }
  }

  bool get shouldShowPersistentAlert =>
      _consecutiveFailures >= AppConfig.wifiMaxFailuresBeforeAlert;

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!_streamController.isClosed) {
      _streamController.close();
    }
    Logger.info('WifiService disposed', context: 'WifiService');
  }
}
