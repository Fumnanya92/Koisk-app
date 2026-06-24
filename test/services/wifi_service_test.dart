import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinity_kiosk/services/wifi_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.fynko.infinitykiosk/kiosk');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getWifiStatus':
          return {'enabled': true, 'connected': true};
        case 'setWifiEnabled':
          return true;
        case 'reconnectWifi':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    WifiService.instance.dispose();
  });

  test('initialize fetches status and emits to stream', () async {
    final service = WifiService.instance;
    await service.initialize();
    expect(service.currentStatus.state, WifiConnectionState.connected);
  });

  test('disabled wifi maps to disabled state', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getWifiStatus') {
        return {'enabled': false, 'connected': false};
      }
      return null;
    });
    await WifiService.instance.initialize();
    expect(WifiService.instance.currentStatus.state, WifiConnectionState.disabled);
  });

  test('enabled but not connected maps to disconnected', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getWifiStatus') {
        return {'enabled': true, 'connected': false};
      }
      return null;
    });
    await WifiService.instance.initialize();
    expect(WifiService.instance.currentStatus.state, WifiConnectionState.disconnected);
  });

  test('setWifiEnabled calls platform and refreshes status', () async {
    await WifiService.instance.initialize();
    final result = await WifiService.instance.setWifiEnabled(false);
    expect(result, isTrue);
  });

  test('reconnect calls platform method', () async {
    await WifiService.instance.initialize();
    final result = await WifiService.instance.reconnect();
    expect(result, isTrue);
  });

  test('shouldShowPersistentAlert is false initially', () async {
    await WifiService.instance.initialize();
    expect(WifiService.instance.shouldShowPersistentAlert, isFalse);
  });

  test('scanNetworks returns list of WifiNetwork from platform', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getWifiStatus') {
        return {'enabled': true, 'connected': true, 'ssid': 'Estate_WiFi'};
      }
      if (call.method == 'scanWifiNetworks') {
        return [
          {'ssid': 'Estate_WiFi', 'level': -55, 'secured': true, 'connected': true},
          {'ssid': 'OpenNet', 'level': -75, 'secured': false, 'connected': false},
        ];
      }
      return null;
    });
    await WifiService.instance.initialize();
    final networks = await WifiService.instance.scanNetworks();
    expect(networks.length, 2);
    expect(networks[0].ssid, 'Estate_WiFi');
    expect(networks[0].signalLevel, 4); // -55 dBm → 4 bars
    expect(networks[0].isSecured, true);
    expect(networks[0].isConnected, true);
    expect(networks[1].ssid, 'OpenNet');
    expect(networks[1].signalLevel, 2); // -75 dBm → 2 bars
    expect(networks[1].isSecured, false);
  });

  test('scanNetworks returns empty list on platform error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getWifiStatus') {
        return {'enabled': true, 'connected': true, 'ssid': 'Estate_WiFi'};
      }
      if (call.method == 'scanWifiNetworks') {
        throw PlatformException(code: 'ERROR');
      }
      return null;
    });
    await WifiService.instance.initialize();
    final networks = await WifiService.instance.scanNetworks();
    expect(networks, isEmpty);
  });

  test('connectToNetwork returns true when ssid matches after connection', () async {
    var statusCallCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getWifiStatus') {
        statusCallCount++;
        if (statusCallCount >= 2) {
          return {'enabled': true, 'connected': true, 'ssid': 'Hotspot'};
        }
        return {'enabled': true, 'connected': true, 'ssid': 'Estate_WiFi'};
      }
      if (call.method == 'connectToWifiNetwork') {
        return {'initiated': true};
      }
      return null;
    });
    await WifiService.instance.initialize();
    final result = await WifiService.instance.connectToNetwork('Hotspot', 'pass1234');
    expect(result, isTrue);
  });

  test('connectToNetwork returns false when not initiated', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getWifiStatus') {
        return {'enabled': true, 'connected': true, 'ssid': 'Estate_WiFi'};
      }
      if (call.method == 'connectToWifiNetwork') {
        return {'initiated': false};
      }
      return null;
    });
    await WifiService.instance.initialize();
    final result = await WifiService.instance.connectToNetwork('BadNet', 'pass');
    expect(result, isFalse);
  });

  test('connectedSsid is populated from getWifiStatus', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getWifiStatus') {
        return {'enabled': true, 'connected': true, 'ssid': 'Estate_WiFi'};
      }
      return null;
    });
    await WifiService.instance.initialize();
    expect(WifiService.instance.connectedSsid, 'Estate_WiFi');
  });
}
