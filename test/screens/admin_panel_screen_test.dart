import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinity_kiosk/constants/app_config.dart';
import 'package:infinity_kiosk/screens/admin_panel_screen.dart';

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
          return true;
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

  testWidgets('Exit Kiosk Mode confirms and invokes native stop', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdminPanelScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Exit Kiosk Mode'));
    await tester.pumpAndSettle();

    expect(find.text('Exit Kiosk Mode?'), findsOneWidget);

    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();

    expect(
      methodCalls.any((call) => call.method == KioskMethods.stopKioskMode),
      isTrue,
    );
  });
}
