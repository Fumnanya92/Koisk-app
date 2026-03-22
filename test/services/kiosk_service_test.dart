import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinity_kiosk/constants/app_config.dart';
import 'package:infinity_kiosk/services/kiosk_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PlatformChannels.kioskChannel);
  final methodCalls = <MethodCall>[];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methodCalls.add(call);
      switch (call.method) {
        case KioskMethods.isDeviceOwner:
          return false;
        case KioskMethods.getDeviceInfo:
          return <String, dynamic>{'model': 'test-device'};
        default:
          return true;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('openAccessCodeNG sends launchApp with package and label', () async {
    final success = await KioskService.openAccessCodeNG();

    expect(success, isTrue);
    expect(methodCalls, hasLength(1));
    expect(methodCalls.single.method, KioskMethods.launchApp);
    expect(methodCalls.single.arguments, <String, dynamic>{
      'packageName': AppConfig.accessCodeNGPackage,
      'appLabel': 'AccessCode NG',
    });
  });

  test('openDialer sends openDialer with phone number', () async {
    final success = await KioskService.openDialer(AppConfig.adminContactNumber);

    expect(success, isTrue);
    expect(methodCalls, hasLength(1));
    expect(methodCalls.single.method, KioskMethods.openDialer);
    expect(methodCalls.single.arguments, <String, dynamic>{
      'number': AppConfig.adminContactNumber,
    });
  });

  test('isDeviceOwner returns false from native channel', () async {
    final result = await KioskService.isDeviceOwner();

    expect(result, isFalse);
    expect(methodCalls.single.method, KioskMethods.isDeviceOwner);
  });
}
