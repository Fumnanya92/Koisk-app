# Wi-Fi Controls + Incoming Calls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Wi-Fi status/toggle/reconnect controls to the kiosk screen and an admin toggle for incoming calls.

**Architecture:** Native Kotlin methods added to the existing `MainActivity` method channel handle Wi-Fi state and incoming call whitelisting. A new `WifiService` singleton in Flutter wraps those calls, runs a 30-second auto-reconnect timer, and exposes a broadcast stream. The kiosk screen subscribes to that stream for its Wi-Fi icon and disconnection banner; the admin panel reads/writes the incoming calls preference via a new `KioskService` method.

**Tech Stack:** Flutter 3+, Kotlin, Android WifiManager + ConnectivityManager, MethodChannel `com.fynko.infinitykiosk/kiosk`, flutter_secure_storage (already present), SharedPreferences (native side).

## Global Constraints

- Reuse the existing method channel `com.fynko.infinitykiosk/kiosk` — do NOT add new channels
- Follow the existing pattern in `KioskService` (abstract class with static methods, `PlatformException` catch)
- `AppColors` and `AppDimensions` — import from `lib/constants/app_config.dart` (not from `main.dart`)
- All new Kotlin code goes inside `MainActivity.kt` — do NOT create new Kotlin files
- `WifiManager.setWifiEnabled()` is deprecated on Android 10+ but still works for Device Owner apps — suppress the deprecation warning with `@Suppress("DEPRECATION")`
- Default for incoming calls setting is `false` (off) — preserves current locked-down behavior
- Never require `ACCESS_FINE_LOCATION` — skip SSID display entirely; only show connected/disconnected/disabled state

---

## File Map

| File | Change |
|---|---|
| `android/app/src/main/AndroidManifest.xml` | Add 3 Wi-Fi permissions |
| `android/app/src/main/kotlin/com/fynko/infinitykiosk/MainActivity.kt` | Add 4 method handlers + 3 helper methods + 1 companion const + onCreate boot logic |
| `lib/constants/app_config.dart` | Add 4 method name constants + 1 storage key constant to existing classes |
| `lib/services/wifi_service.dart` | **New file** — `WifiStatus`, `WifiConnectionState`, `WifiService` singleton |
| `lib/services/kiosk_service.dart` | Add `setIncomingCallsEnabled(bool)` static method |
| `lib/main.dart` | Call `KioskService.applyIncomingCallsPreference()` during startup |
| `lib/screens/kiosk_screen.dart` | Add `WifiService` init/dispose, Wi-Fi icon in header, disconnection banner, bottom sheet |
| `lib/screens/admin_panel_screen.dart` | Add `_incomingCallsEnabled` state, load/save toggle, new "Communication" `_SectionCard` |

---

## Task 1: Permissions + Constants

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `lib/constants/app_config.dart`

**Interfaces:**
- Produces: `KioskMethods.getWifiStatus`, `KioskMethods.setWifiEnabled`, `KioskMethods.reconnectWifi`, `KioskMethods.setIncomingCallsEnabled`, `AppConfig.incomingCallsEnabledKey` — used by Tasks 2, 3, 4

- [ ] **Step 1: Add Wi-Fi permissions to AndroidManifest.xml**

Open `android/app/src/main/AndroidManifest.xml`. After the existing `INTERNET` permission line (line 24), add:

```xml
    <!-- Wi-Fi state reading and control -->
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

- [ ] **Step 2: Add method name constants to AppConfig**

Open `lib/constants/app_config.dart`. In the `KioskMethods` class, after the existing `getDeviceInfo` constant, add:

```dart
  static const String getWifiStatus = 'getWifiStatus';
  static const String setWifiEnabled = 'setWifiEnabled';
  static const String reconnectWifi = 'reconnectWifi';
  static const String setIncomingCallsEnabled = 'setIncomingCallsEnabled';
```

In the `AppConfig` class, after `batteryCheckInterval`, add:

```dart
  // Incoming calls preference key (stored natively in SharedPreferences)
  static const String incomingCallsEnabledKey = 'incoming_calls_enabled';
  
  // Wi-Fi auto-reconnect
  static const Duration wifiCheckInterval = Duration(seconds: 30);
  static const int wifiMaxFailuresBeforeAlert = 5;
```

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml lib/constants/app_config.dart
git commit -m "feat: add Wi-Fi permissions and method name constants"
```

---

## Task 2: Kotlin Native Methods

**Files:**
- Modify: `android/app/src/main/kotlin/com/fynko/infinitykiosk/MainActivity.kt`

**Interfaces:**
- Consumes: existing `allowLockTaskPackages()`, `getSystemDialerPackage()`, `getSystemPhonePackage()`, `isDeviceOwner()`, `PREFS_NAME`, companion object
- Produces: method channel handlers for `getWifiStatus`, `setWifiEnabled`, `reconnectWifi`, `setIncomingCallsEnabled`; boot-time preference re-application in `onCreate`

- [ ] **Step 1: Add imports at the top of MainActivity.kt**

After the existing import block (after `import io.flutter.plugin.common.MethodChannel`), add:

```kotlin
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
```

- [ ] **Step 2: Add companion object constant**

Inside the `companion object { ... }` block, after `private const val REQUEST_CODE_PICK_UPDATE_APK = 1001`, add:

```kotlin
        private const val KEY_INCOMING_CALLS_ENABLED = "incoming_calls_enabled"
```

- [ ] **Step 3: Re-apply incoming calls preference on boot**

In `onCreate()`, after the existing `allowLockTaskPackages(getSystemDialerPackage(), getSystemPhonePackage())` call (line ~95), add:

```kotlin
        // Re-apply incoming calls preference from previous session
        val incomingCallsEnabled = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_INCOMING_CALLS_ENABLED, false)
        if (incomingCallsEnabled) {
            allowLockTaskPackages(getSystemDialerPackage(), getSystemPhonePackage())
            Log.i(TAG, "Incoming calls re-enabled from saved preference")
        } else {
            // Ensure phone apps are NOT in whitelist unless enabled
            rebuildLockTaskWithoutPhone()
            Log.i(TAG, "Incoming calls remain disabled (saved preference)")
        }
```

- [ ] **Step 4: Add 4 method channel handlers**

In `configureFlutterEngine`, inside the `when (call.method)` block, after the `"getDeviceInfo" -> result.success(getDeviceInfo())` line, add:

```kotlin
                        "getWifiStatus" -> result.success(getWifiStatus())
                        "setWifiEnabled" -> {
                            val enabled = call.argument<Boolean>("enabled") ?: false
                            result.success(setWifiEnabled(enabled))
                        }
                        "reconnectWifi" -> result.success(reconnectWifi())
                        "setIncomingCallsEnabled" -> {
                            val enabled = call.argument<Boolean>("enabled") ?: false
                            setIncomingCallsEnabled(enabled)
                            result.success(null)
                        }
```

- [ ] **Step 5: Add the 4 helper methods**

Add these methods anywhere after `getDeviceInfo()` and before the closing `}` of `MainActivity`:

```kotlin
    /// ========================================================================
    /// Wi-Fi Control Methods
    /// ========================================================================

    private fun getWifiStatus(): Map<String, Any> {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val enabled = wifiManager.isWifiEnabled

        val connected = if (enabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val caps = cm.getNetworkCapabilities(cm.activeNetwork)
            caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        } else if (enabled) {
            @Suppress("DEPRECATION")
            wifiManager.connectionInfo?.networkId != -1
        } else {
            false
        }

        Log.d(TAG, "Wi-Fi status — enabled: $enabled, connected: $connected")
        return mapOf("enabled" to enabled, "connected" to connected)
    }

    @Suppress("DEPRECATION")
    private fun setWifiEnabled(enabled: Boolean): Boolean {
        return try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val result = wifiManager.setWifiEnabled(enabled)
            Log.i(TAG, "setWifiEnabled($enabled) → $result")
            result
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set Wi-Fi enabled: ${e.message}", e)
            false
        }
    }

    private fun reconnectWifi(): Boolean {
        return try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val result = wifiManager.reconnect()
            Log.i(TAG, "reconnectWifi() → $result")
            result
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reconnect Wi-Fi: ${e.message}", e)
            false
        }
    }

    /// ========================================================================
    /// Incoming Calls Toggle
    /// ========================================================================

    private fun setIncomingCallsEnabled(enabled: Boolean) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_INCOMING_CALLS_ENABLED, enabled)
            .apply()

        if (enabled) {
            allowLockTaskPackages(getSystemDialerPackage(), getSystemPhonePackage())
            Log.i(TAG, "Incoming calls enabled — phone apps added to lock task whitelist")
        } else {
            rebuildLockTaskWithoutPhone()
            Log.i(TAG, "Incoming calls disabled — phone apps removed from lock task whitelist")
        }
    }

    private fun rebuildLockTaskWithoutPhone() {
        if (!isDeviceOwner()) return
        try {
            devicePolicyManager.setLockTaskPackages(adminComponent, arrayOf(packageName))
            Log.d(TAG, "Lock task packages rebuilt (phone apps excluded)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to rebuild lock task packages: ${e.message}", e)
        }
    }
```

- [ ] **Step 6: Verify the file compiles**

```bash
cd android && ./gradlew compileDebugKotlin 2>&1 | tail -20
```

Expected: `BUILD SUCCESSFUL` with no errors. If there are import errors, check that the 3 new imports were added correctly in Step 1.

- [ ] **Step 7: Commit**

```bash
git add android/app/src/main/kotlin/com/fynko/infinitykiosk/MainActivity.kt
git commit -m "feat: add Wi-Fi control and incoming calls methods to MainActivity"
```

---

## Task 3: WifiService (New Flutter Service)

**Files:**
- Create: `lib/services/wifi_service.dart`

**Interfaces:**
- Consumes: `KioskMethods.getWifiStatus`, `KioskMethods.setWifiEnabled`, `KioskMethods.reconnectWifi`, `PlatformChannels.kioskChannel`, `AppConfig.wifiCheckInterval`, `AppConfig.wifiMaxFailuresBeforeAlert`
- Produces:
  - `enum WifiConnectionState { connected, disconnected, disabled }`
  - `class WifiStatus { final WifiConnectionState state; }`
  - `class WifiService { static final WifiService instance; Stream<WifiStatus> wifiStream; WifiStatus get currentStatus; Future<void> initialize(); Future<bool> setWifiEnabled(bool); Future<bool> reconnect(); bool get shouldShowPersistentAlert; void dispose(); }`

- [ ] **Step 1: Write the failing tests**

Create `test/services/wifi_service_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koisk_app/services/wifi_service.dart';

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
      if (call.method == 'getWifiStatus') return {'enabled': false, 'connected': false};
      return null;
    });
    final service = WifiService.instance;
    await service.initialize();
    expect(service.currentStatus.state, WifiConnectionState.disabled);
  });

  test('enabled but not connected maps to disconnected', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getWifiStatus') return {'enabled': true, 'connected': false};
      return null;
    });
    final service = WifiService.instance;
    await service.initialize();
    expect(service.currentStatus.state, WifiConnectionState.disconnected);
  });

  test('setWifiEnabled calls platform and refreshes status', () async {
    final service = WifiService.instance;
    await service.initialize();
    final result = await service.setWifiEnabled(false);
    expect(result, isTrue);
  });

  test('reconnect calls platform method', () async {
    final service = WifiService.instance;
    await service.initialize();
    final result = await service.reconnect();
    expect(result, isTrue);
  });

  test('shouldShowPersistentAlert is false initially', () async {
    final service = WifiService.instance;
    await service.initialize();
    expect(service.shouldShowPersistentAlert, isFalse);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/wifi_service_test.dart
```

Expected: FAIL — `wifi_service.dart` does not exist yet.

- [ ] **Step 3: Implement WifiService**

Create `lib/services/wifi_service.dart`:

```dart
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

  final _streamController = StreamController<WifiStatus>.broadcast();
  Stream<WifiStatus> get wifiStream => _streamController.stream;

  WifiStatus _currentStatus = const WifiStatus(WifiConnectionState.disabled);
  WifiStatus get currentStatus => _currentStatus;

  Timer? _pollTimer;
  int _consecutiveFailures = 0;

  Future<void> initialize() async {
    await _fetchAndEmit();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(AppConfig.wifiCheckInterval, (_) => _pollAndReconnect());
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
      Logger.error('Failed to get Wi-Fi status: ${e.message}', context: 'WifiService');
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
      await Future.delayed(const Duration(seconds: 1));
      await _fetchAndEmit();
      Logger.info('Wi-Fi enabled set to $enabled', context: 'WifiService');
      return result ?? false;
    } on PlatformException catch (e) {
      Logger.error('Failed to set Wi-Fi enabled: ${e.message}', context: 'WifiService');
      return false;
    }
  }

  Future<bool> reconnect() async {
    try {
      final result = await _channel.invokeMethod<bool>(KioskMethods.reconnectWifi);
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

      // Give the OS a moment to connect before re-reading status
      await Future.delayed(const Duration(seconds: 3));
      await _fetchAndEmit();
      return success;
    } on PlatformException catch (e) {
      Logger.error('Failed to reconnect Wi-Fi: ${e.message}', context: 'WifiService');
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/wifi_service_test.dart
```

Expected: All 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/wifi_service.dart test/services/wifi_service_test.dart
git commit -m "feat: add WifiService with auto-reconnect and stream"
```

---

## Task 4: KioskService + main.dart Updates

**Files:**
- Modify: `lib/services/kiosk_service.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `KioskMethods.setIncomingCallsEnabled`
- Produces: `KioskService.setIncomingCallsEnabled(bool enabled) → Future<bool>`; `KioskService.applyIncomingCallsPreference()` is NOT needed — `main.dart` calls the native side is already handled by Kotlin `onCreate` boot logic in Task 2. Only the Flutter-side toggle method is needed here.

- [ ] **Step 1: Write failing test for setIncomingCallsEnabled**

Open `test/services/kiosk_service_test.dart`. Add this test inside the existing `main()` function:

```dart
  test('setIncomingCallsEnabled sends correct value to platform', () async {
    String? calledMethod;
    bool? calledEnabled;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.fynko.infinitykiosk/kiosk'),
      (call) async {
        calledMethod = call.method;
        calledEnabled = call.arguments['enabled'] as bool?;
        return null;
      },
    );

    await KioskService.setIncomingCallsEnabled(true);
    expect(calledMethod, 'setIncomingCallsEnabled');
    expect(calledEnabled, isTrue);

    await KioskService.setIncomingCallsEnabled(false);
    expect(calledEnabled, isFalse);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/services/kiosk_service_test.dart
```

Expected: FAIL — `setIncomingCallsEnabled` does not exist on `KioskService`.

- [ ] **Step 3: Add setIncomingCallsEnabled to KioskService**

Open `lib/services/kiosk_service.dart`. After the `reactivateOnResume()` method (at the end of the class, before the closing `}`), add:

```dart
  /// Enable or disable incoming calls ringing through over the kiosk screen.
  /// When enabled, the system phone app is whitelisted in lock task mode.
  /// When disabled, the phone app is removed (default behavior).
  /// Setting is persisted natively and survives reboots.
  static Future<bool> setIncomingCallsEnabled(bool enabled) async {
    try {
      Logger.info(
        'Setting incoming calls enabled: $enabled',
        context: 'KioskService',
      );
      await _channel.invokeMethod<void>(
        KioskMethods.setIncomingCallsEnabled,
        {'enabled': enabled},
      );
      Logger.info('Incoming calls setting updated to $enabled', context: 'KioskService');
      return true;
    } on PlatformException catch (e) {
      Logger.error(
        'PlatformException setting incoming calls: ${e.message}',
        context: 'KioskService',
      );
      return false;
    } catch (e, st) {
      Logger.error(
        'Error setting incoming calls',
        context: 'KioskService',
        error: e is Error ? e : null,
        stackTrace: st,
      );
      return false;
    }
  }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/services/kiosk_service_test.dart
```

Expected: All tests PASS.

- [ ] **Step 5: Initialize WifiService in main.dart**

Open `lib/main.dart`. Add the import at the top, after the existing imports:

```dart
import 'services/wifi_service.dart';
```

In the `main()` function, after `await KioskService.initialize();` and before `Logger.info('Initialization complete...', ...)`, add:

```dart
    // Initialize Wi-Fi monitoring service
    await WifiService.instance.initialize();
    Logger.info('Wi-Fi service initialized', context: 'main');
```

- [ ] **Step 6: Commit**

```bash
git add lib/services/kiosk_service.dart lib/main.dart test/services/kiosk_service_test.dart
git commit -m "feat: add setIncomingCallsEnabled to KioskService and init WifiService on boot"
```

---

## Task 5: KioskScreen — Wi-Fi Icon, Banner, Bottom Sheet

**Files:**
- Modify: `lib/screens/kiosk_screen.dart`

**Interfaces:**
- Consumes: `WifiService.instance`, `WifiStatus`, `WifiConnectionState`, `WifiService.wifiStream`, `WifiService.currentStatus`, `WifiService.setWifiEnabled(bool)`, `WifiService.reconnect()`, `WifiService.shouldShowPersistentAlert`

- [ ] **Step 1: Write failing widget test**

Open `test/screens/kiosk_screen_test.dart`. Add this test:

```dart
  testWidgets('shows Wi-Fi icon in header', (tester) async {
    // Existing mock setup for secure storage and method channel applies.
    // Add Wi-Fi mock:
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.fynko.infinitykiosk/kiosk'),
      (call) async {
        if (call.method == 'getWifiStatus') return {'enabled': true, 'connected': true};
        if (call.method == 'isDeviceOwner') return false;
        if (call.method == 'startKioskMode') return true;
        return null;
      },
    );

    await tester.pumpWidget(const MaterialApp(home: KioskScreen()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.wifi), findsOneWidget);
  });

  testWidgets('shows disconnection banner when Wi-Fi disconnected', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.fynko.infinitykiosk/kiosk'),
      (call) async {
        if (call.method == 'getWifiStatus') return {'enabled': true, 'connected': false};
        if (call.method == 'isDeviceOwner') return false;
        if (call.method == 'startKioskMode') return true;
        if (call.method == 'reconnectWifi') return false;
        return null;
      },
    );

    await tester.pumpWidget(const MaterialApp(home: KioskScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Wi-Fi disconnected — reconnecting…'), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/screens/kiosk_screen_test.dart
```

Expected: FAIL — `KioskScreen` has no Wi-Fi icon yet.

- [ ] **Step 3: Add WifiService fields and lifecycle to _KioskScreenState**

Open `lib/screens/kiosk_screen.dart`.

At the top of the file, add the import:
```dart
import '../services/wifi_service.dart';
```

In `_KioskScreenState`, after the `StreamSubscription<int>? _batterySubscription;` field, add:
```dart
  // Wi-Fi monitoring
  StreamSubscription<WifiStatus>? _wifiSubscription;
  WifiStatus _wifiStatus = const WifiStatus(WifiConnectionState.disabled);
```

In `initState()`, after `_initializeBatteryMonitoring();`, add:
```dart
    _initializeWifiMonitoring();
```

After the `_initializeBatteryMonitoring()` method, add:
```dart
  void _initializeWifiMonitoring() {
    final wifiService = WifiService.instance;
    _wifiStatus = wifiService.currentStatus;

    _wifiSubscription = wifiService.wifiStream.listen((status) {
      if (!mounted) return;
      setState(() => _wifiStatus = status);

      if (wifiService.shouldShowPersistentAlert) {
        _showWifiPersistentAlert();
      }
    });
  }

  void _showWifiPersistentAlert() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        icon: const Icon(Icons.wifi_off, color: Colors.orange, size: 36),
        title: const Text(
          'Wi-Fi Not Connecting',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'The kiosk has been unable to reconnect to Wi-Fi after several attempts.\n\n'
          'Please check the router or contact your network administrator.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              WifiService.instance.reconnect();
            },
            child: const Text('Try Again', style: TextStyle(color: Color(0xFF4FC3F7))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss', style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  void _showWifiBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Wi-Fi',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              StreamBuilder<WifiStatus>(
                stream: WifiService.instance.wifiStream,
                initialData: WifiService.instance.currentStatus,
                builder: (context, snapshot) {
                  final status = snapshot.data ?? WifiService.instance.currentStatus;
                  final statusText = switch (status.state) {
                    WifiConnectionState.connected => 'Connected',
                    WifiConnectionState.disconnected => 'Not connected',
                    WifiConnectionState.disabled => 'Wi-Fi Off',
                  };
                  final statusColor = switch (status.state) {
                    WifiConnectionState.connected => Colors.green[400]!,
                    WifiConnectionState.disconnected => Colors.orange,
                    WifiConnectionState.disabled => Colors.grey,
                  };
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusText,
                        style: TextStyle(color: statusColor, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Enable Wi-Fi',
                          style: TextStyle(color: Colors.white),
                        ),
                        value: status.isEnabled,
                        activeColor: const Color(0xFF4FC3F7),
                        onChanged: (val) async {
                          await WifiService.instance.setWifiEnabled(val);
                          setS(() {});
                        },
                      ),
                      if (status.state == WifiConnectionState.disconnected) ...[
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await WifiService.instance.reconnect();
                            setS(() {});
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reconnect Now'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A237E),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
```

In `dispose()`, after `_batterySubscription?.cancel();`, add:
```dart
    _wifiSubscription?.cancel();
```

- [ ] **Step 4: Add Wi-Fi icon to the header row**

In `build()`, find the header `Row` (starts around line 422 with `mainAxisAlignment: MainAxisAlignment.spaceBetween`). The current children are `[BatteryWidget, ClockWidget]`.

Replace the `children: [` list so it reads:
```dart
                children: [
                  // Wi-Fi icon on far left
                  GestureDetector(
                    onTap: _showWifiBottomSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: switch (_wifiStatus.state) {
                            WifiConnectionState.connected => Colors.green[400]!,
                            WifiConnectionState.disconnected => Colors.orange,
                            WifiConnectionState.disabled => Colors.grey,
                          },
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        _wifiStatus.isConnected ? Icons.wifi : Icons.wifi_off,
                        color: switch (_wifiStatus.state) {
                          WifiConnectionState.connected => Colors.green[400]!,
                          WifiConnectionState.disconnected => Colors.orange,
                          WifiConnectionState.disabled => Colors.grey,
                        },
                        size: 18,
                      ),
                    ),
                  ),
                  // Battery status (existing widget — no change)
                  if (_batteryService != null)
                    StreamBuilder<int>(
```

Keep the rest of the battery and clock widgets exactly as they are. Make sure the closing `],` of the children list is still present after the clock widget.

- [ ] **Step 5: Add disconnection banner above main content**

In `build()`, find the `// Main content` comment just after the header `Padding` widget closes (around line 493). The structure is:
```dart
            // Main content
            Expanded(
              child: Center( ...
```

Between the closing `),` of the header `Padding` and the `// Main content` comment, insert:

```dart
            // Wi-Fi disconnection banner
            if (_wifiStatus.state == WifiConnectionState.disconnected)
              Container(
                width: double.infinity,
                color: Colors.orange.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.orange, size: 14),
                    const SizedBox(width: 6),
                    const Text(
                      'Wi-Fi disconnected — reconnecting…',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
```

- [ ] **Step 6: Run the tests**

```bash
flutter test test/screens/kiosk_screen_test.dart
```

Expected: All tests PASS including the 2 new Wi-Fi tests.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/kiosk_screen.dart test/screens/kiosk_screen_test.dart
git commit -m "feat: add Wi-Fi icon, disconnection banner, and bottom sheet to kiosk screen"
```

---

## Task 6: AdminPanelScreen — Incoming Calls Toggle

**Files:**
- Modify: `lib/screens/admin_panel_screen.dart`

**Interfaces:**
- Consumes: `KioskService.setIncomingCallsEnabled(bool)`, `AppConfig.incomingCallsEnabledKey`, `shared_preferences` package (already in pubspec)

- [ ] **Step 1: Write failing widget test**

Open `test/screens/admin_panel_screen_test.dart`. Add this test inside `main()`:

```dart
  testWidgets('shows incoming calls toggle in admin panel', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminPanelScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Incoming Calls'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/screens/admin_panel_screen_test.dart
```

Expected: FAIL — no `SwitchListTile` or "Incoming Calls" text in the current admin panel.

- [ ] **Step 3: Add imports to admin_panel_screen.dart**

At the top of `lib/screens/admin_panel_screen.dart`, add:
```dart
import 'package:shared_preferences/shared_preferences.dart';
```

- [ ] **Step 4: Add state variable and load logic**

In `_AdminPanelScreenState`, after `String? _deviceInfo;`, add:
```dart
  bool _incomingCallsEnabled = false;
```

In `_loadDeviceStatus()`, after `setState(() => _isDeviceOwner = isOwner);`, add:
```dart
      // Load incoming calls preference
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _incomingCallsEnabled = prefs.getBool(AppConfig.incomingCallsEnabledKey) ?? false;
      });
```

- [ ] **Step 5: Add the toggle method**

After `_showSnackbar()`, add:
```dart
  Future<void> _setIncomingCalls(bool enabled) async {
    _resetInactivityTimer();
    final success = await KioskService.setIncomingCallsEnabled(enabled);
    if (!mounted) return;

    if (success) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConfig.incomingCallsEnabledKey, enabled);
      setState(() => _incomingCallsEnabled = enabled);
      _showSnackbar(
        enabled ? 'Incoming calls enabled' : 'Incoming calls disabled',
        color: enabled ? Colors.green : Colors.orange,
      );
    } else {
      _showSnackbar('Could not update incoming calls setting', color: Colors.red);
    }
  }
```

- [ ] **Step 6: Add the Communication section to the build method**

In `build()`, find the `const SizedBox(height: 20),` that appears after the "Device Status" `_SectionCard` closes (around line 438). After that `SizedBox` and before the "Admin Actions" `_SectionCard`, insert:

```dart
                    // Communication Section
                    _SectionCard(
                      title: 'Communication',
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Incoming Calls',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: const Text(
                            'Allow incoming calls to ring through on this device.',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          value: _incomingCallsEnabled,
                          activeColor: const Color(0xFF4FC3F7),
                          onChanged: _setIncomingCalls,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
```

- [ ] **Step 7: Run the tests**

```bash
flutter test test/screens/admin_panel_screen_test.dart
```

Expected: All tests PASS.

- [ ] **Step 8: Run full test suite**

```bash
flutter test
```

Expected: All tests PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/screens/admin_panel_screen.dart test/screens/admin_panel_screen_test.dart
git commit -m "feat: add incoming calls toggle to admin panel"
```

---

## Task 7: Build Verification

**Files:** None changed — verification only.

- [ ] **Step 1: Run flutter analyze**

```bash
flutter analyze
```

Expected: No issues found. Fix any warnings before continuing.

- [ ] **Step 2: Build debug APK**

```bash
flutter build apk --debug 2>&1 | tail -30
```

Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`. If it fails, check the Kotlin compile errors from the gradle output and fix.

- [ ] **Step 3: Full test run**

```bash
flutter test --reporter expanded
```

Expected: All tests pass with 0 failures.

- [ ] **Step 4: Final commit**

```bash
git add .
git commit -m "chore: verify Wi-Fi + incoming calls build passes"
```

---

## Self-Review Checklist

- [x] Task 1 covers permissions + constants — matches spec "Android Manifest additions" and "AppConfig additions"
- [x] Task 2 covers all 4 Kotlin methods + boot preference re-application — matches spec "Native Kotlin additions"
- [x] Task 3 covers `WifiService` with stream, auto-reconnect timer, consecutive failure tracking — matches spec data flow
- [x] Task 4 covers `KioskService.setIncomingCallsEnabled` and `WifiService.initialize()` in `main.dart`
- [x] Task 5 covers Wi-Fi icon (green/orange/grey), disconnection banner, bottom sheet with toggle + reconnect button — matches spec UI design
- [x] Task 6 covers admin panel "Communication" section with `SwitchListTile`, persisted via `SharedPreferences` — matches spec
- [x] Task 7 covers build verification
- [x] Type consistency: `WifiStatus`, `WifiConnectionState`, `WifiService.instance` used consistently across Tasks 3, 5
- [x] `AppConfig.incomingCallsEnabledKey` defined in Task 1, consumed in Tasks 4 and 6
- [x] Default for incoming calls is `false` in both Kotlin (`getBoolean(KEY_INCOMING_CALLS_ENABLED, false)`) and Flutter (`prefs.getBool(...) ?? false`)
- [x] No TBDs or placeholders
