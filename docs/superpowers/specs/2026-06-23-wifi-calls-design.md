# Design Spec: Wi-Fi Controls + Incoming Calls
**Date:** 2026-06-23  
**Project:** Infinity Estate Kiosk App  
**Status:** Approved

---

## Problem

Security guards using the kiosk phone cannot:
1. See whether Wi-Fi is on or connected
2. Turn Wi-Fi on/off or reconnect when it drops
3. Receive incoming phone calls (kiosk mode blocks the incoming call screen)

These gaps cause downtime — guards are stranded without network and miss calls.

---

## Goals

1. Show Wi-Fi status on the kiosk screen at all times
2. Let guards toggle Wi-Fi and manually reconnect without a PIN
3. Auto-reconnect silently in the background when Wi-Fi drops
4. Let the admin enable/disable incoming calls via the admin panel toggle

---

## Architecture

### New Flutter Service: `WifiService`

`lib/services/wifi_service.dart` — singleton, mirrors the pattern of `BatteryMonitoringService`.

Responsibilities:
- Calls native Kotlin methods via `MethodChannel` (`com.fynko.infinitykiosk/kiosk`)
- Exposes a broadcast `Stream<WifiStatus>` for UI to subscribe to
- Manages a 30-second periodic timer for auto-reconnect attempts
- Tracks reconnect attempt count for logging

```dart
enum WifiConnectionState { connected, disconnected, disabled }

class WifiStatus {
  final WifiConnectionState state;
  final String? ssid; // name of connected network, null if not connected
}
```

Public API:
- `initialize()` — fetch initial state, start polling timer
- `wifiStream` — `Stream<WifiStatus>` for UI binding
- `currentStatus` — synchronous getter for latest `WifiStatus`
- `setWifiEnabled(bool enabled)` — toggle Wi-Fi on/off
- `reconnect()` — trigger manual or auto reconnect
- `dispose()` — cancel timer and close stream

### Native Kotlin: `MainActivity.kt` additions

Four new method channel handlers added to the existing `when (call.method)` block:

| Method name | Action |
|---|---|
| `getWifiStatus` | Returns `Map<String, Any>` with `enabled: Boolean`, `connected: Boolean`, `ssid: String?` |
| `setWifiEnabled` | Takes `enabled: Boolean` arg; calls `WifiManager.setWifiEnabled()` (device owner) |
| `reconnectWifi` | Calls `WifiManager.reconnect()` or re-enables saved network |
| `setIncomingCallsEnabled` | Takes `enabled: Boolean`; adds/removes system phone package from lock task whitelist and persists setting to SharedPreferences |

### Android Manifest additions

```xml
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

No new `<queries>` entries needed — Wi-Fi is managed via system service, not package intents.

### `AppConfig` additions

```dart
// PlatformChannels — no new channel needed, reuse kiosk channel
// KioskMethods additions:
static const getWifiStatus = 'getWifiStatus';
static const setWifiEnabled = 'setWifiEnabled';
static const reconnectWifi = 'reconnectWifi';
static const setIncomingCallsEnabled = 'setIncomingCallsEnabled';

// Storage key for incoming calls preference
static const incomingCallsEnabledKey = 'incoming_calls_enabled';
```

---

## UI Design

### Kiosk Screen — Header Changes

Current header row: `[Battery] ........Clock........ `  
New header row:     `[WiFi] [Battery] ........Clock........ `

**Wi-Fi icon states:**
- Connected → `Icons.wifi` in green (`AppColors.success`)
- On but disconnected → `Icons.wifi_off` in amber, pulses/animates while auto-reconnecting
- Off → `Icons.wifi_off` in grey (50% opacity)

**Disconnection banner:**  
A slim `Container` (height ~32px) at the top of the body, amber background, white text:  
`"Wi-Fi disconnected — reconnecting…"`  
Appears instantly when `WifiStatus.state == disconnected`.  
Disappears automatically when reconnected. Not dismissible — it goes away on its own.

**Wi-Fi bottom sheet (tap the icon):**  
`showModalBottomSheet` — not full screen, rounded top corners.  
Contents:
1. Status line: "Connected to Estate_WiFi" / "Not connected" / "Wi-Fi Off"
2. `SwitchListTile` — "Wi-Fi" label, toggles `WifiService.setWifiEnabled()`
3. `ElevatedButton` — "Reconnect Now" — only visible when `state == disconnected`; calls `WifiService.reconnect()`
4. Close button or tap-outside to dismiss

### Admin Panel — New Toggle

Added to the existing "Device Settings" section (or a new "Communication" section if cleaner):

```
[ Incoming Calls ]  [Toggle ON/OFF]
Allow incoming calls to ring through on this device.
```

- Default: **OFF** (preserves existing locked-down behavior)
- ON: calls `KioskService.setIncomingCallsEnabled(true)` → native adds phone package to lock task whitelist
- OFF: calls `KioskService.setIncomingCallsEnabled(false)` → native removes it
- Setting persisted in `SharedPreferences` under key `incoming_calls_enabled`
- On app start (in `main.dart` or `KioskService.initialize()`), the saved preference is re-applied so the setting survives reboots

---

## Data Flow

### Wi-Fi auto-reconnect loop

```
WifiService.initialize()
  └─ fetch initial status → emit to stream
  └─ start 30s periodic timer
       └─ every 30s: getWifiStatus()
            └─ if enabled && !connected → reconnectWifi()
            └─ emit updated WifiStatus to stream

KioskScreen (StreamBuilder)
  └─ WifiStatus.connected → green icon, hide banner
  └─ WifiStatus.disconnected → amber icon, show banner, animate
  └─ WifiStatus.disabled → grey icon, hide banner
```

### Incoming calls toggle

```
AdminPanelScreen toggle changed
  └─ KioskService.setIncomingCallsEnabled(bool)
       └─ MethodChannel → MainActivity.setIncomingCallsEnabled(bool)
            └─ true: allowLockTaskPackages(systemPhone, systemDialer)
                     SharedPreferences.putBoolean("incoming_calls_enabled", true)
            └─ false: setLockTaskPackages(without phone packages)
                      SharedPreferences.putBoolean("incoming_calls_enabled", false)

App starts / KioskService.initialize()
  └─ read SharedPreferences "incoming_calls_enabled"
  └─ re-apply lock task packages accordingly
```

---

## Error Handling

- `setWifiEnabled` fails silently on Android 10+ for non-device-owner → log warning, show snackbar "Could not change Wi-Fi. Check device permissions."
- `reconnectWifi` returns false → increment retry counter, log, next attempt at next timer tick
- If auto-reconnect fails 5 consecutive times → show a more prominent alert dialog on the kiosk screen prompting guard to check the router
- `setIncomingCallsEnabled` platform exception → show error snackbar in admin panel, revert toggle state

---

## Files Changed

| File | Change type |
|---|---|
| `android/app/src/main/AndroidManifest.xml` | Add 3 Wi-Fi permissions |
| `android/app/src/main/kotlin/.../MainActivity.kt` | Add 4 new method handlers + helper methods |
| `lib/constants/app_config.dart` | Add 4 method name constants + storage key |
| `lib/services/wifi_service.dart` | **New file** |
| `lib/services/kiosk_service.dart` | Add `setIncomingCallsEnabled()` method |
| `lib/screens/kiosk_screen.dart` | Wi-Fi icon in header, banner, bottom sheet |
| `lib/screens/admin_panel_screen.dart` | Incoming calls toggle |
| `lib/main.dart` | Re-apply incoming calls preference on boot |

---

## Out of Scope

- Selecting a new Wi-Fi network (entering SSID/password) — that requires Settings UI
- Showing a list of available networks
- Mobile data toggle
- Call history or call log display
