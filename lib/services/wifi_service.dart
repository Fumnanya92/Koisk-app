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

class WifiNetwork {
  final String ssid;
  final int signalLevel; // 0–4 bars
  final bool isSecured;
  final bool isConnected;

  const WifiNetwork({
    required this.ssid,
    required this.signalLevel,
    required this.isSecured,
    required this.isConnected,
  });

  static int _rssiToLevel(int rssi) {
    if (rssi >= -60) return 4;
    if (rssi >= -70) return 3;
    if (rssi >= -80) return 2;
    return 1;
  }

  factory WifiNetwork.fromMap(Map<dynamic, dynamic> map) {
    return WifiNetwork(
      ssid: map['ssid'] as String? ?? '',
      signalLevel: _rssiToLevel(map['level'] as int? ?? -100),
      isSecured: map['secured'] as bool? ?? false,
      isConnected: map['connected'] as bool? ?? false,
    );
  }
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

  String? _connectedSsid;
  String? get connectedSsid => _connectedSsid;

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
      _connectedSsid = result['ssid'] as String?;

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

  Future<List<WifiNetwork>> scanNetworks() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        KioskMethods.scanWifiNetworks,
      );
      if (result == null) return [];
      return result
          .cast<Map<dynamic, dynamic>>()
          .map(WifiNetwork.fromMap)
          .toList();
    } on PlatformException catch (e) {
      Logger.error('Failed to scan networks: ${e.message}',
          context: 'WifiService');
      return [];
    }
  }

  Future<bool> connectToNetwork(String ssid, String password) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        KioskMethods.connectToWifiNetwork,
        {'ssid': ssid, 'password': password},
      );
      final initiated = result?['initiated'] as bool? ?? false;
      if (!initiated) return false;

      // Wait for OS to establish the connection, then re-read status
      await Future.delayed(const Duration(seconds: 5));
      await _fetchAndEmit();

      return _connectedSsid == ssid;
    } on PlatformException catch (e) {
      Logger.error('Failed to connect to network: ${e.message}',
          context: 'WifiService');
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
