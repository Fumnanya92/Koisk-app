import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinity_kiosk/constants/app_config.dart';
import 'package:infinity_kiosk/screens/admin_panel_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PlatformChannels.kioskChannel);
  final methodCalls = <MethodCall>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppConfig.incomingCallsEnabledKey: false,
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

  testWidgets('shows incoming calls toggle in Communication section', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminPanelScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Incoming Calls'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
  });

  testWidgets('Exit Kiosk Mode confirms and invokes native stop', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdminPanelScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Exit Kiosk Mode'));
    await tester.tap(find.text('Exit Kiosk Mode'), warnIfMissed: false);
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
