# WiFi Network Scanner & Manual Connect — Design Spec
_Date: 2026-06-24_

## Problem

When the estate internet goes down, guards have no way to switch the kiosk to a different network (personal hotspot, mobile tether). The existing WiFi controls only toggle the radio and retry the last network.

## Solution

Extend the existing WiFi bottom sheet with a network scanner and manual connect flow. Guards can see all nearby SSIDs by name, identify which one they're currently on, and connect to any network (open or secured) without a PIN.

---

## Architecture

### New native Kotlin methods (`MainActivity.kt`)

| Method | Arguments | Return type | Description |
|---|---|---|---|
| `scanWifiNetworks` | — | `List<Map<String, Any>>` | Triggers a scan and returns results |
| `connectToWifiNetwork` | `ssid: String`, `password: String` | `Map<String, Any>` `{success, error?}` | Connects to the named network |

**Scan implementation:**
- Call `WifiManager.startScan()` then read `WifiManager.scanResults`
- Each result maps to `{ssid, level, secured, connected}` where `level` is the raw RSSI integer
- `ACCESS_FINE_LOCATION` is required on Android 10+ for `getScanResults()` — granted programmatically via `DevicePolicyManager.setPermissionGrantState(PERMISSION_GRANT_STATE_GRANTED)` in `onCreate()` (Device Owner privilege, no user prompt)

**Connect implementation:**
- Android < 33: `WifiConfiguration` + `WifiManager.addNetwork()` / `enableNetwork()` / `reconnect()` (deprecated, suppressed with `@Suppress("DEPRECATION")` — same pattern already in codebase)
- Android ≥ 33 (API level check): `DevicePolicyManager.addWifiNetwork()` via `WifiEnterpriseConfig` or `WifiNetworkSuggestion` as Device Owner
- Returns `{success: true}` on connection accepted, `{success: false, error: "AUTHENTICATION_FAILED"}` or `{success: false, error: "TIMEOUT"}` on failure

**New permissions in `AndroidManifest.xml`:**
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```
(Already has `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `ACCESS_NETWORK_STATE`)

**New constants in `AppConfig` / `KioskMethods`:**
```dart
static const String scanWifiNetworks = 'scanWifiNetworks';
static const String connectToWifiNetwork = 'connectToWifiNetwork';
```

---

### New Flutter model: `WifiNetwork`

```dart
class WifiNetwork {
  final String ssid;
  final int signalLevel;   // 0–4 bars, derived from RSSI
  final bool isSecured;
  final bool isConnected;
}
```

Signal level mapping (bars from RSSI):
- `< -80 dBm` → 1 bar
- `< -70 dBm` → 2 bars
- `< -60 dBm` → 3 bars
- `≥ -60 dBm` → 4 bars

### `WifiService` additions

```dart
Future<List<WifiNetwork>> scanNetworks()
Future<bool> connectToNetwork(String ssid, String password)
String? get connectedSsid   // null when disconnected/disabled
```

`connectedSsid` is populated from `getWifiStatus` (extend the native return map to include `ssid: String?`).

---

## UX Design

### Bottom sheet layout (extended)

```
┌─────────────────────────────────┐
│  ━━━ (drag handle)              │
│                                 │
│  Wi-Fi                          │
│  Connected to Estate_WiFi  ●    │  ← SSID name shown here
│                                 │
│  [■] Enable Wi-Fi               │  ← existing toggle
│  [Reconnect]                    │  ← existing button (if disconnected)
│                                 │
│  ─── Available Networks ─────   │
│  [Scan]                         │
│                                 │
│  📶 Estate_WiFi          ✓      │  ← connected, checkmark
│  📶 MTN_Hotspot_4G    🔒        │  ← secured
│  📶 Airtel_John       🔒        │  ← secured
│  📶 AndroidAP                   │  ← open
│                                 │
└─────────────────────────────────┘
```

- Connected network shows SSID in the status line at the top ("Connected to **Estate_WiFi**")
- Disconnected: "Not connected" (no SSID)
- Disabled: "Wi-Fi Off"
- Each network row: signal bars icon + SSID name + lock icon (if secured) + checkmark (if connected)
- Tapping an open network → connects immediately
- Tapping a secured network → password dialog (see below)
- During scan: spinner + "Scanning…" replaces network list
- No results: "No networks found. Tap Scan to retry."

### Password dialog

```
┌──────────────────────────────┐
│  Connect to MTN_Hotspot_4G   │
│                              │
│  Password                    │
│  [________________] 👁       │  ← show/hide toggle
│                              │
│  [Cancel]        [Connect]   │
└──────────────────────────────┘
```

- "Connect" disabled until at least 8 characters entered
- On failure: dialog stays open, shows red error text ("Incorrect password. Try again.")
- On success: dialog closes, bottom sheet status updates to new SSID

---

## Error States

| Scenario | UI response |
|---|---|
| Scan returns empty | "No networks found. Tap Scan to retry." |
| Wrong password | Inline red error in password dialog: "Incorrect password" |
| Connection timeout | Inline error: "Connection timed out. Try again." |
| Location permission denied | "Network scan unavailable" (should not occur as Device Owner) |
| Already connecting | Scan button and network rows disabled with spinner |

---

## Testing

- `WifiService.scanNetworks()`: mock channel returns list, verify `WifiNetwork` models populated correctly
- `WifiService.connectToNetwork()`: mock success and failure responses, verify return value
- `connectedSsid`: verify populated from `getWifiStatus` extended response
- Widget test — bottom sheet: scan button triggers method call, network list renders SSIDs
- Widget test — password dialog: appears for secured network, disabled until 8+ chars
- Widget test — connected badge: network with `isConnected: true` shows checkmark

---

## Out of Scope

- Forgetting / removing saved networks
- Enterprise (WPA-Enterprise / 802.1X) networks
- Admin-only restriction on which networks guards can connect to
