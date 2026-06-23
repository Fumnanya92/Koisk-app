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
}
