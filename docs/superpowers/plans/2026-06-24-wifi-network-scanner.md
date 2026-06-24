# WiFi Network Scanner & Manual Connect — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let guards see nearby WiFi network names and connect to a different network (e.g. personal hotspot) directly from the kiosk WiFi bottom sheet.

**Architecture:** Two new Kotlin methods (`scanWifiNetworks`, `connectToWifiNetwork`) return results via the existing `MethodChannel`. `WifiService` gains a `WifiNetwork` model, `scanNetworks()`, `connectToNetwork()`, and a `connectedSsid` getter populated by extending the existing `getWifiStatus` response. The kiosk screen's WiFi bottom sheet is extended in-place to show the network list and a password dialog.

**Tech Stack:** Flutter 3.41.5, Kotlin, Android `WifiManager` (deprecated `WifiConfiguration` suppressed — same pattern as existing codebase), `DevicePolicyManager.setPermissionGrantState` for auto-granting `ACCESS_FINE_LOCATION`.

## Global Constraints

- Single `MethodChannel("com.fynko.infinitykiosk/kiosk")` for all platform calls — no new channels
- Deprecated Android APIs used as Device Owner: suppress with `@Suppress("DEPRECATION")`  
- No PIN required to access network scanner — guard-accessible
- Flutter method names are string constants in `KioskMethods` class (`lib/constants/app_config.dart`)
- All colors use existing `AppColors` constants or the existing dark theme hex literals (`0xFF1A1A2E`, `0xFF4FC3F7`, etc.)
- Run `flutter test --reporter expanded` after each task to catch regressions

---

### Task 1: Permission + Constants

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/kotlin/com/fynko/infinitykiosk/MainActivity.kt` (onCreate only)
- Modify: `lib/constants/app_config.dart`

**Interfaces:**
- Produces: `KioskMethods.scanWifiNetworks = 'scanWifiNetworks'` and `KioskMethods.connectToWifiNetwork = 'connectToWifiNetwork'` — used by Tasks 3 and 4

---

- [ ] **Step 1: Add ACCESS_FINE_LOCATION to AndroidManifest.xml**

In `android/app/src/main/AndroidManifest.xml`, add this line immediately after the `ACCESS_NETWORK_STATE` permission line (line 29):

```xml
    <!-- Fine location - required for WiFi network scanning on Android 10+ -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

- [ ] **Step 2: Auto-grant location permission in onCreate (Device Owner)**

In `MainActivity.kt`, add this block at the end of `onCreate()`, after the incoming calls block (after line 110, before the closing `}`):

```kotlin
        // Grant location permission to self for WiFi scanning (Device Owner privilege)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && isDeviceOwner()) {
            try {
                devicePolicyManager.setPermissionGrantState(
                    adminComponent,
                    packageName,
                    android.Manifest.permission.ACCESS_FINE_LOCATION,
                    DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED
                )
                Log.i(TAG, "ACCESS_FINE_LOCATION auto-granted via DevicePolicyManager")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to auto-grant location permission: ${e.message}")
            }
        }
```

- [ ] **Step 3: Add new method name constants to KioskMethods**

In `lib/constants/app_config.dart`, add two lines at the end of the `KioskMethods` class (after the `setIncomingCallsEnabled` line):

```dart
  static const String scanWifiNetworks = 'scanWifiNetworks';
  static const String connectToWifiNetwork = 'connectToWifiNetwork';
```

- [ ] **Step 4: Run tests to confirm nothing is broken**

```
flutter test --reporter expanded
```

Expected: all existing tests pass (currently 17).

- [ ] **Step 5: Commit**

```
git add android/app/src/main/AndroidManifest.xml android/app/src/main/kotlin/com/fynko/infinitykiosk/MainActivity.kt lib/constants/app_config.dart
git commit -m "feat: add WiFi scanner permission and method name constants"
```

---

### Task 2: Native Kotlin Methods

**Files:**
- Modify: `android/app/src/main/kotlin/com/fynko/infinitykiosk/MainActivity.kt`

**Interfaces:**
- Consumes: `ACCESS_FINE_LOCATION` permission (granted in Task 1)
- Produces:
  - `getWifiStatus()` now returns `Map<String, Any?>` with additional `"ssid": String?` key alongside existing `"enabled"` and `"connected"` keys
  - `scanWifiNetworks()` returns `List<Map<String, Any>>` where each map has `{ssid: String, level: Int, secured: Boolean, connected: Boolean}`
  - `connectToWifiNetwork(ssid, password)` returns `Map<String, Any>` with `{initiated: Boolean}`

---

- [ ] **Step 1: Add `getCurrentSsid` helper method**

Add this new private method to `MainActivity.kt` in the Wi-Fi section (after the existing `reconnectWifi()` method, around line 1017):

```kotlin
    @Suppress("DEPRECATION")
    private fun getCurrentSsid(wifiManager: WifiManager): String? {
        val ssid = wifiManager.connectionInfo?.ssid?.removeSurrounding("\"")
        return if (ssid.isNullOrBlank() || ssid == "<unknown ssid>") null else ssid
    }
```

- [ ] **Step 2: Extend `getWifiStatus()` to return the connected SSID**

Replace the existing `getWifiStatus()` method (around line 975) with:

```kotlin
    private fun getWifiStatus(): Map<String, Any?> {
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

        val ssid = if (connected) getCurrentSsid(wifiManager) else null
        Log.d(TAG, "Wi-Fi status — enabled: $enabled, connected: $connected, ssid: $ssid")
        return mapOf("enabled" to enabled, "connected" to connected, "ssid" to ssid)
    }
```

- [ ] **Step 3: Add `scanWifiNetworks()` method**

Add after `getCurrentSsid()`:

```kotlin
    @Suppress("DEPRECATION")
    private fun scanWifiNetworks(): List<Map<String, Any>> {
        return try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val connectedSsid = getCurrentSsid(wifiManager)
            wifiManager.startScan()
            val results = wifiManager.scanResults ?: emptyList()
            results
                .filter { it.SSID.isNotBlank() }
                .distinctBy { it.SSID }
                .sortedByDescending { it.level }
                .map { result ->
                    mapOf(
                        "ssid" to result.SSID,
                        "level" to result.level,
                        "secured" to (result.capabilities.contains("WPA") ||
                                      result.capabilities.contains("WEP")),
                        "connected" to (result.SSID == connectedSsid)
                    )
                }
        } catch (e: Exception) {
            Log.e(TAG, "scanWifiNetworks failed: ${e.message}", e)
            emptyList()
        }
    }
```

- [ ] **Step 4: Add `connectToWifiNetwork()` method**

Add after `scanWifiNetworks()`:

```kotlin
    @Suppress("DEPRECATION")
    private fun connectToWifiNetwork(ssid: String, password: String): Map<String, Any> {
        return try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            if (!wifiManager.isWifiEnabled) {
                @Suppress("DEPRECATION")
                wifiManager.setWifiEnabled(true)
            }
            val config = android.net.wifi.WifiConfiguration().apply {
                SSID = "\"$ssid\""
                if (password.isBlank()) {
                    allowedKeyManagement.set(android.net.wifi.WifiConfiguration.KeyMgmt.NONE)
                } else {
                    preSharedKey = "\"$password\""
                    allowedKeyManagement.set(android.net.wifi.WifiConfiguration.KeyMgmt.WPA_PSK)
                }
            }
            // Remove any existing saved config for this SSID
            wifiManager.configuredNetworks
                ?.filter { it.SSID == "\"$ssid\"" }
                ?.forEach { wifiManager.removeNetwork(it.networkId) }

            val networkId = wifiManager.addNetwork(config)
            if (networkId == -1) {
                Log.e(TAG, "addNetwork returned -1 for SSID: $ssid")
                return mapOf("initiated" to false)
            }
            wifiManager.enableNetwork(networkId, true)
            wifiManager.reconnect()
            Log.i(TAG, "connectToWifiNetwork initiated for SSID: $ssid")
            mapOf("initiated" to true)
        } catch (e: Exception) {
            Log.e(TAG, "connectToWifiNetwork failed: ${e.message}", e)
            mapOf("initiated" to false)
        }
    }
```

- [ ] **Step 5: Register the two new methods in the `when` block**

In the `configureFlutterEngine` `when` block (around line 218), add two cases before the `else -> result.notImplemented()` line:

```kotlin
                        "scanWifiNetworks" -> result.success(scanWifiNetworks())
                        "connectToWifiNetwork" -> {
                            val ssid = call.argument<String>("ssid") ?: ""
                            val password = call.argument<String>("password") ?: ""
                            result.success(connectToWifiNetwork(ssid, password))
                        }
```

- [ ] **Step 6: Run tests to confirm nothing is broken**

```
flutter test --reporter expanded
```

Expected: all 17 tests still pass.

- [ ] **Step 7: Commit**

```
git add android/app/src/main/kotlin/com/fynko/infinitykiosk/MainActivity.kt
git commit -m "feat: add scanWifiNetworks and connectToWifiNetwork native methods"
```

---

### Task 3: WifiService — Model + New Methods

**Files:**
- Modify: `lib/services/wifi_service.dart`
- Modify: `test/services/wifi_service_test.dart`

**Interfaces:**
- Consumes: `KioskMethods.scanWifiNetworks`, `KioskMethods.connectToWifiNetwork` (Task 1); native methods returning `{ssid}` in `getWifiStatus` and `List<Map>` from `scanWifiNetworks` (Task 2)
- Produces:
  - `WifiNetwork` — model class with `ssid`, `signalLevel` (0–4), `isSecured`, `isConnected`
  - `WifiService.instance.connectedSsid` — `String?`, current connected SSID
  - `WifiService.instance.scanNetworks()` — `Future<List<WifiNetwork>>`
  - `WifiService.instance.connectToNetwork(String ssid, String password)` — `Future<bool>`

---

- [ ] **Step 1: Write failing tests for the new service methods**

In `test/services/wifi_service_test.dart`, add the following tests inside the `main()` block, after the existing `shouldShowPersistentAlert` test:

```dart
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
        // First call: old network. Second call (post-connect): new network.
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```
flutter test test/services/wifi_service_test.dart --reporter expanded
```

Expected: new tests FAIL with `NoSuchMethodError` or similar (methods don't exist yet).

- [ ] **Step 3: Add WifiNetwork model and update WifiService**

Replace the entire contents of `lib/services/wifi_service.dart` with:

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
```

- [ ] **Step 4: Run the service tests — they should all pass now**

```
flutter test test/services/wifi_service_test.dart --reporter expanded
```

Expected: all tests PASS (existing 6 + new 5 = 11 total).

- [ ] **Step 5: Run full suite to confirm no regressions**

```
flutter test --reporter expanded
```

Expected: all 17 existing tests still pass.

- [ ] **Step 6: Commit**

```
git add lib/services/wifi_service.dart test/services/wifi_service_test.dart
git commit -m "feat: add WifiNetwork model, scanNetworks, connectToNetwork, connectedSsid"
```

---

### Task 4: Kiosk Screen — Network List + Password Dialog

**Files:**
- Modify: `lib/screens/kiosk_screen.dart`
- Modify: `test/screens/kiosk_screen_test.dart`

**Interfaces:**
- Consumes:
  - `WifiService.instance.connectedSsid` — `String?`
  - `WifiService.instance.scanNetworks()` — `Future<List<WifiNetwork>>`
  - `WifiService.instance.connectToNetwork(ssid, password)` — `Future<bool>`
  - `WifiNetwork` — model with `ssid`, `signalLevel`, `isSecured`, `isConnected`

---

- [ ] **Step 1: Write failing widget tests**

In `test/screens/kiosk_screen_test.dart`, add these two tests inside `main()` after the existing tests:

```dart
  testWidgets('wifi bottom sheet shows network list after scan', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == KioskMethods.isDeviceOwner) return true;
      if (call.method == KioskMethods.getDeviceInfo) {
        return <String, dynamic>{'model': 'test-device'};
      }
      if (call.method == KioskMethods.getWifiStatus) {
        return {'enabled': true, 'connected': true, 'ssid': 'Estate_WiFi'};
      }
      if (call.method == KioskMethods.scanWifiNetworks) {
        return [
          {'ssid': 'Estate_WiFi', 'level': -55, 'secured': true, 'connected': true},
          {'ssid': 'John_Hotspot', 'level': -70, 'secured': true, 'connected': false},
        ];
      }
      return true;
    });

    await WifiService.instance.initialize();
    await tester.pumpWidget(const MaterialApp(home: KioskScreen()));
    await tester.pump();
    WifiService.instance.dispose();
    await tester.pumpAndSettle();

    if (find.text('OK').evaluate().isNotEmpty) {
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    // Tap WiFi icon to open bottom sheet
    final wifiIcon = find.byWidgetPredicate(
      (w) => w is Icon && (w.icon == Icons.wifi || w.icon == Icons.wifi_off),
    ).first;
    await tester.tap(wifiIcon, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Tap Scan button
    expect(find.text('Scan'), findsOneWidget);
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(find.text('Estate_WiFi'), findsWidgets);
    expect(find.text('John_Hotspot'), findsOneWidget);
  });

  testWidgets('tapping secured network shows password dialog', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == KioskMethods.isDeviceOwner) return true;
      if (call.method == KioskMethods.getDeviceInfo) {
        return <String, dynamic>{'model': 'test-device'};
      }
      if (call.method == KioskMethods.getWifiStatus) {
        return {'enabled': true, 'connected': true, 'ssid': 'Estate_WiFi'};
      }
      if (call.method == KioskMethods.scanWifiNetworks) {
        return [
          {'ssid': 'John_Hotspot', 'level': -70, 'secured': true, 'connected': false},
        ];
      }
      return true;
    });

    await WifiService.instance.initialize();
    await tester.pumpWidget(const MaterialApp(home: KioskScreen()));
    await tester.pump();
    WifiService.instance.dispose();
    await tester.pumpAndSettle();

    if (find.text('OK').evaluate().isNotEmpty) {
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    final wifiIcon = find.byWidgetPredicate(
      (w) => w is Icon && (w.icon == Icons.wifi || w.icon == Icons.wifi_off),
    ).first;
    await tester.tap(wifiIcon, warnIfMissed: false);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('John_Hotspot'));
    await tester.pumpAndSettle();

    expect(find.text('Connect to John_Hotspot'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
```

- [ ] **Step 2: Run tests to confirm they fail**

```
flutter test test/screens/kiosk_screen_test.dart --reporter expanded
```

Expected: new tests FAIL (no Scan button, no network list yet).

- [ ] **Step 3: Replace `_showWifiBottomSheet()` in kiosk_screen.dart**

Find the existing `_showWifiBottomSheet()` method and replace it entirely with:

```dart
  void _showWifiBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _WifiBottomSheet(),
    );
  }
```

- [ ] **Step 4: Add `_WifiBottomSheet` stateful widget at the bottom of kiosk_screen.dart (before the closing brace of the file)**

Add this new class after the `_KioskScreenState` class:

```dart
class _WifiBottomSheet extends StatefulWidget {
  @override
  State<_WifiBottomSheet> createState() => _WifiBottomSheetState();
}

class _WifiBottomSheetState extends State<_WifiBottomSheet> {
  List<WifiNetwork>? _networks;
  bool _scanning = false;

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _networks = null;
    });
    final results = await WifiService.instance.scanNetworks();
    if (mounted) {
      setState(() {
        _networks = results;
        _scanning = false;
      });
    }
  }

  void _onNetworkTap(WifiNetwork network) {
    if (network.isConnected) return;
    if (network.isSecured) {
      _showPasswordDialog(network.ssid);
    } else {
      _connectTo(network.ssid, '');
    }
  }

  Future<void> _connectTo(String ssid, String password) async {
    final success = await WifiService.instance.connectToNetwork(ssid, password);
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to $ssid'),
          backgroundColor: const Color(0xFF1A237E),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not connect — check the password and try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
    // Refresh network list to show updated connected state
    await _scan();
  }

  void _showPasswordDialog(String ssid) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _WifiPasswordDialog(
        ssid: ssid,
        onConnect: (password) {
          Navigator.pop(ctx);
          _connectTo(ssid, password);
        },
      ),
    );
  }

  Widget _signalIcon(int level, bool isConnected) {
    final color = isConnected ? Colors.green[400]! : const Color(0xFF4FC3F7);
    final icon = switch (level) {
      4 => Icons.wifi,
      3 => Icons.wifi,
      2 => Icons.wifi_2_bar,
      _ => Icons.wifi_1_bar,
    };
    return Icon(icon, color: color, size: 20);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (ctx, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
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
                final ssid = WifiService.instance.connectedSsid;
                final statusText = switch (status.state) {
                  WifiConnectionState.connected =>
                    ssid != null ? 'Connected to $ssid' : 'Connected',
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
                      activeThumbColor: const Color(0xFF4FC3F7),
                      onChanged: (val) async {
                        await WifiService.instance.setWifiEnabled(val);
                        setState(() {});
                      },
                    ),
                    if (status.state == WifiConnectionState.disconnected) ...[
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await WifiService.instance.reconnect();
                          setState(() {});
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
            const SizedBox(height: 20),
            const Divider(color: Colors.white12),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Available Networks',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                _scanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF4FC3F7),
                        ),
                      )
                    : TextButton(
                        onPressed: _scan,
                        child: const Text(
                          'Scan',
                          style: TextStyle(color: Color(0xFF4FC3F7)),
                        ),
                      ),
              ],
            ),
            const SizedBox(height: 8),
            if (_networks == null && !_scanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Tap Scan to see available networks.',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              )
            else if (_networks != null && _networks!.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No networks found. Tap Scan to retry.',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              )
            else if (_networks != null)
              ...(_networks!.map((network) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _signalIcon(network.signalLevel, network.isConnected),
                    title: Text(
                      network.ssid,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (network.isSecured)
                          const Icon(Icons.lock, color: Colors.white38, size: 14),
                        if (network.isConnected) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.check_circle,
                              color: Colors.green, size: 16),
                        ],
                      ],
                    ),
                    onTap: () => _onNetworkTap(network),
                  ))),
          ],
        ),
      ),
    );
  }
}

class _WifiPasswordDialog extends StatefulWidget {
  final String ssid;
  final void Function(String password) onConnect;

  const _WifiPasswordDialog({required this.ssid, required this.onConnect});

  @override
  State<_WifiPasswordDialog> createState() => _WifiPasswordDialogState();
}

class _WifiPasswordDialogState extends State<_WifiPasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: Text(
        'Connect to ${widget.ssid}',
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: TextField(
        controller: _controller,
        obscureText: _obscure,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: 'Password',
          labelStyle: const TextStyle(color: Colors.white54),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white24),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF4FC3F7)),
          ),
          suffixIcon: IconButton(
            icon: Icon(
              _obscure ? Icons.visibility : Icons.visibility_off,
              color: Colors.white38,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (ctx, value, _) => TextButton(
            onPressed: value.text.length >= 8
                ? () => widget.onConnect(_controller.text)
                : null,
            child: const Text(
              'Connect',
              style: TextStyle(color: Color(0xFF4FC3F7)),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Run the widget tests**

```
flutter test test/screens/kiosk_screen_test.dart --reporter expanded
```

Expected: all kiosk screen tests pass including the two new ones.

- [ ] **Step 6: Run full test suite**

```
flutter test --reporter expanded
```

Expected: all tests pass (17 existing + 5 wifi service + 2 widget = 24 total).

- [ ] **Step 7: Commit**

```
git add lib/screens/kiosk_screen.dart test/screens/kiosk_screen_test.dart
git commit -m "feat: extend WiFi bottom sheet with network scanner and password connect"
```

---

### Task 5: Final Verification

**Files:** No changes — verification only.

---

- [ ] **Step 1: Run flutter analyze**

```
flutter analyze
```

Expected: No issues found. If any deprecation warnings appear that are NOT in the `@Suppress`-wrapped Kotlin code, fix them before continuing.

- [ ] **Step 2: Run full test suite one final time**

```
flutter test --reporter expanded
```

Expected: all 24 tests pass, 0 failures.

- [ ] **Step 3: Commit any final fixes, then tag the feature complete**

```
git add .
git commit -m "chore: wifi network scanner feature complete — all tests pass"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| `ACCESS_FINE_LOCATION` permission + auto-grant as Device Owner | Task 1 |
| `scanWifiNetworks` + `connectToWifiNetwork` constants in `KioskMethods` | Task 1 |
| `getCurrentSsid` helper, extended `getWifiStatus` with `ssid` | Task 2 |
| `scanWifiNetworks()` Kotlin — filter blank, dedupe, sort by RSSI | Task 2 |
| `connectToWifiNetwork()` Kotlin — `WifiConfiguration`, enable, reconnect | Task 2 |
| Method channel `when` cases for both new methods | Task 2 |
| `WifiNetwork` model with `fromMap` + RSSI → bars conversion | Task 3 |
| `connectedSsid` getter populated from `getWifiStatus` | Task 3 |
| `WifiService.scanNetworks()` and `connectToNetwork()` | Task 3 |
| Bottom sheet extended: SSID in status text | Task 4 |
| Bottom sheet: Available Networks section + Scan button | Task 4 |
| Network list: SSID name, signal icon, lock icon, connected checkmark | Task 4 |
| Password dialog for secured networks, disabled until 8+ chars | Task 4 |
| Open network connects immediately | Task 4 |
| Error feedback via SnackBar | Task 4 |
| Tests for all new service methods | Task 3 |
| Tests for bottom sheet network list + password dialog | Task 4 |

All spec requirements covered. No placeholders. Type names consistent across all tasks.
