import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinity_kiosk/constants/app_config.dart';
import 'package:infinity_kiosk/screens/kiosk_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PlatformChannels.kioskChannel);
  final methodCalls = <MethodCall>[];

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: KioskScreen(),
      ),
    );
    await tester.pumpAndSettle();

    if (find.text('OK').evaluate().isNotEmpty) {
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'admin_pin_v1': AppConfig.defaultAdminPin,
    });
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

  testWidgets('Open AccessCode NG button invokes native launch', (tester) async {
    await pumpScreen(tester);

    final button = find.widgetWithText(ElevatedButton, 'Open AccessCode NG');
    await tester.ensureVisible(button);
    await tester.tap(button, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      methodCalls.any((call) => call.method == KioskMethods.launchApp),
      isTrue,
    );
  });

  testWidgets('Call Admin button invokes native phone action', (tester) async {
    await pumpScreen(tester);

    final button = find.widgetWithText(ElevatedButton, 'Call Admin');
    await tester.ensureVisible(button);
    await tester.tap(button, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      methodCalls.any((call) => call.method == KioskMethods.openDialer),
      isTrue,
    );
  });

  testWidgets('entering correct admin PIN opens admin panel', (tester) async {
    await pumpScreen(tester);

    final logo = find.byIcon(Icons.security_rounded);
    final logoCenter = tester.getCenter(logo);
    for (var i = 0; i < 5; i++) {
      await tester.tapAt(logoCenter);
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.pumpAndSettle();
    expect(find.text('Admin Access'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, AppConfig.defaultAdminPin);
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(find.text('Admin Panel'), findsOneWidget);
  });
}
