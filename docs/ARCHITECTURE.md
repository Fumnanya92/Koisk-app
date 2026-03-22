## 🏗️ TECHNICAL ARCHITECTURE DOCUMENT

**Infinity Estate Kiosk - System Design & Implementation**

---

## System Overview

```
┌──────────────────────────────────────────────────────────────┐
│                    USER INTERFACE LAYER                      │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Flutter UI                                          │   │
│  │  - KioskScreen (locked UI)                          │   │
│  │  - AdminPanelScreen (PIN-protected)                 │   │
│  │  - Immersive fullscreen (no system chrome)          │   │
│  └──────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────┐
│                   APPLICATION LOGIC LAYER                    │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Dart Services                                       │   │
│  │  - KioskService (platform communication)            │   │
│  │  - PinService (secure storage)                      │   │
│  │  - Logger (centralized logging)                     │   │
│  └──────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────┐
│              PLATFORM CHANNEL / METHOD CHANNEL               │
│                   "com.fynko.infinitykiosk/kiosk"            │
│  Methods:                                                    │
│  - startKioskMode()                                         │
│  - stopKioskMode()                                          │
│  - isDeviceOwner()                                          │
│  - launchApp()                                              │
│  - openDialer()                                             │
│  - getDeviceInfo()                                          │
└──────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────┐
│                 ANDROID NATIVE LAYER (KOTLIN)               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  MainActivity                                        │   │
│  │  - Activity lifecycle management                    │   │
│  │  - Immersive mode enforcement                       │   │
│  │  - Lock task mode control                           │   │
│  │  - Method channel handler                           │   │
│  │                                                      │   │
│  │  AdminReceiver                                       │   │
│  │  - Device owner callbacks                           │   │
│  │  - Lock task callbacks                              │   │
│  │                                                      │   │
│  │  BootReceiver                                        │   │
│  │  - BOOT_COMPLETED broadcast handler                 │   │
│  │  - Auto-launch logic                                │   │
│  └──────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────┐
│                   ANDROID FRAMEWORK APIS                     │
│  - DevicePolicyManager (system restrictions)               │
│  - ActivityManager (lock task)                              │
│  - WindowManager (UI control)                               │
│  - PackageManager (app launching)                           │
│  - TelephonyManager (dialer)                                │
└──────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────┐
│                    ANDROID OS / KERNEL                       │
│  - Device Owner Mode enforcement                           │
│  - User restrictions                                       │
│  - System security policies                                │
└──────────────────────────────────────────────────────────────┘
```

---

## Module Breakdown

### 1. Flutter Presentation Layer (`lib/`)

#### `main.dart`
**Responsibility:** App initialization and theme setup

**Flow:**
1. `WidgetsFlutterBinding.ensureInitialized()` - Enable platform channels
2. `SystemChrome.setEnabledSystemUIMode(immersiveSticky)` - Hide system UI
3. `PinService.initialize()` - Set default PIN if first run
4. `KioskService.initialize()` - Activate lock task mode
5. Launch `KioskScreen`

**Key Features:**
- Material 3 dark theme
- Fullscreen immersive mode
- Proper error handling during startup

#### `screens/kiosk_screen.dart`
**Responsibility:** Main user-facing interface (locked)

**Components:**
- Estate branding & logo (tappable for admin access)
- AccessCode NG launch button (primary action)
- Admin call button (secondary action)
- Device owner status indicator

**Interaction Flow:**
1. User taps logo 5x within 3 seconds
2. Counter increments, timestamp tracked
3. On 5th tap, counter resets and PIN dialog shown
4. Admin enters PIN
5. If valid → `AdminPanelScreen` displayed
6. If invalid → Snackbar error, stays on kiosk screen

**Lifecycle Management:**
- `WidgetsBindingObserver` - Listen to app lifecycle
- On `resumed` - Re-enforce immersive mode & lock task
- On `paused` - No special handling (stays locked)

#### `screens/admin_panel_screen.dart`
**Responsibility:** Hidden administrator interface (PIN-protected)

**Features:**
- Device owner status display
- Admin PIN change form
- Exit kiosk mode button (drastic action)
- Device information display
- Warning dialogs for destructive actions

**PIN Change Process:**
1. Collect current PIN, new PIN, confirmation
2. Validate new PIN (4-8 digits, numbers only)
3. Verify current PIN against storage
4. If valid, write new PIN to secure storage
5. On success, show confirmation & return to form

### 2. Dart Services Layer (`lib/services/`)

#### `kiosk_service.dart`
**Responsibility:** Platform communication and kiosk control

**Methods:**
| Method | Purpose | Returns |
|--------|---------|---------|
| `initialize()` | Check device owner, activate kiosk | bool (success) |
| `activateKiosk()` | Start lock task mode | void |
| `deactivateKiosk()` | Stop lock task mode | void |
| `isDeviceOwner()` | Query device ownership | bool |
| `openAccessCodeNG()` | Launch AccessCode app | bool (success) |
| `openDialer(number)` | Open phone dialer | bool (success) |
| `getDeviceInfo()` | Get device metadata | Map<String, String> |

**Error Handling:**
- Try/catch all platform calls
- Log errors at appropriate levels
- Never rethrow (graceful degradation)
- Allow app to continue even if lock task fails (dev mode support)

**Platform Channel Communication:**
```
Dart Method Call
    ↓ (JSONizable parameters)
    ↓
Kotlin Method Call Handler
    ↓ (logic execution)
    ↓
Result Object (success/error)
    ↓ (JSON result)
    ↓
Dart Future Resolution
```

#### `pin_service.dart`
**Responsibility:** Secure PIN storage and verification

**Storage Mechanism:**
- Flutter Secure Storage (Android: EncryptedSharedPreferences)
- AES-256 encryption by default
- Key: `admin_pin_v1`
- Value: Plain text PIN (encrypted by storage layer)

**Methods:**
| Method | Purpose |
|--------|---------|
| `initialize()` | Create default PIN on first run |
| `verifyPin(input)` | Compare input with stored PIN |
| `changePin(...)` | Update PIN with validation |
| `isUsingDefaultPin()` | Check if default PIN still active |

**Security Validation:**
- PIN must be 4-8 digits
- Only numeric characters
- No leading/trailing spaces
- Confirmation PIN must match new PIN
- Current PIN verified before change

### 3. Utils Layer (`lib/utils/`)

#### `logger.dart`
**Responsibility:** Centralized logging with levels

**Levels:**
- `debug()` - Development info (debug builds only)
- `info()` - Important info (always logged)
- `warning()` - Potential issues
- `error()` - Failures/exceptions
- `critical()` - System-level failures

**Context Tagging:**
All logs include optional context: `Logger.info("message", context: "ModuleName")`

Output format:
```
🔵 DEBUG [ModuleName]: Message
ℹ️  INFO [ModuleName]: Message
⚠️  WARN [ModuleName]: Message
🔴 ERROR [ModuleName]: Message
🚨 CRITICAL [ModuleName]: Message
```

### 4. Android Native Layer (`android/app/src/main/kotlin/`)

#### `MainActivity.kt`
**Responsibility:** Main activity with kiosk control logic

**Key Lifecycle Events:**
```kotlin
onCreate() {
    // Get DevicePolicyManager
    // Setup screen wake lock
    // Hide system UI
}

onResume() {
    // Re-hide system UI (sticky)
    // Re-activate lock task if owner
}

onWindowFocusChanged(hasFocus) {
    // Re-hide system UI if focus gained
}

onBackPressed() {
    // Do nothing - prevent exit
}
```

**Immersive Mode Implementation:**
```kotlin
// Android 11+ (modern API)
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
    window.insetsController?.let { controller ->
        controller.hide(WindowInsets.Type.statusBars() or navigationBars())
        controller.systemBarsBehavior = BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }
}

// Android 10 and below (legacy flags)
window.decorView.systemUiVisibility = (
    SYSTEM_UI_FLAG_IMMERSIVE_STICKY      // Sticky behavior
    or SYSTEM_UI_FLAG_HIDE_NAVIGATION     // Hide nav buttons
    or SYSTEM_UI_FLAG_FULLSCREEN          // Hide status bar
    or SYSTEM_UI_FLAG_LAYOUT_STABLE       // Don't adjust margins
)
```

**Method Channel Handler:**
```kotlin
MethodChannel(...).setMethodCallHandler { call, result ->
    when (call.method) {
        "startKioskMode" -> {
            if (isDeviceOwner()) {
                startLockTask()
                applyKioskRestrictions()
                result.success(true)
            }
        }
        // ... other methods
    }
}
```

**Kiosk Restrictions:**
```kotlin
private fun applyKioskRestrictions() {
    devicePolicyManager.addUserRestriction(
        adminComponent,
        "no_install_apps"          // DISALLOW_INSTALL_APPS
        )
    // ... more restrictions
}
```

#### `AdminReceiver.kt`
**Responsibility:** Device owner mode management

**Callbacks:**
```kotlin
onEnabled(context, intent) {
    Log.i(TAG, "Device Admin ENABLED")
    // Device owner setup complete
}

onDisabled(context, intent) {
    Log.w(TAG, "Device Admin DISABLED")
    // Security compromised!
}

onLockTaskModeEntering(context, intent, pkg) {
    Log.i(TAG, "Lock Task Mode ENTERING for $pkg")
    // Kiosk is now locked
}

onLockTaskModeExiting(context, intent) {
    Log.e(TAG, "SECURITY ALERT: Lock Task Mode EXITING!")
    // CRITICAL: Try to relaunch
    val relaunch = Intent(context, MainActivity::class.java)
    context.startActivity(relaunch)
}
```

#### `BootReceiver.kt`
**Responsibility:** Auto-launch on device power-on

**Broadcast Handling:**
```kotlin
override fun onReceive(context: Context, intent: Intent) {
    if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
        intent.action == "android.intent.action.QUICKBOOT_POWERON") {
        
        val launch = Intent(context, MainActivity::class.java)
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(launch)
    }
}
```

**Broadcast Permissions:**
- `BOOT_COMPLETED` - Standard Android boot
- `QUICKBOOT_POWERON` - HTC Sense quick boot
- Added to `AndroidManifest.xml` as intent-filter

### 5. Configuration Layer (`lib/constants/`)

#### `app_config.dart`
**Responsibility:** Centralized configuration management

**Categories:**
1. **App Metadata**
   - Name, version, build number
   - Package name

2. **Estate Information**
   - Estate name, location
   - Admin contact, email

3. **Functional Config**
   - AccessCode NG package name
   - Timeout durations

4. **Security Defaults**
   - Default PIN (should be changed!)
   - Allowed app packages

5. **Platform Config**
   - Channel names
   - Method names
   - Permission names

---

## Data Flow Diagrams

### 1. App Initialization Flow

```
main()
  ↓
[WidgetsFlutterBinding.ensureInitialized()]
  ↓
[SystemChrome.setEnabledSystemUIMode(immersiveSticky)]
  ↓
PinService.initialize()
  ├─→ Read from secure storage
  ├─→ If empty: Write default PIN (1234)
  └─→ Return isFirstRun
  ↓
KioskService.initialize()
  ├─→ isDeviceOwner()? (→ bool query)
  ├─→ if true: activateKiosk()
  │   ├─→ Platform call: startKioskMode
  │   ├─→ Native: startLockTask()
  │   ├─→ Native: applyKioskRestrictions()
  │   └─→ Result: success/error
  └─→ Return bool
  ↓
runApp(InfinityKioskApp)
  ├─→ ThemeData configuration
  └─→ KioskScreen as home
  ↓
KioskScreen.initState()
  ├─→ WidgetsBinding.addObserver(this)
  ├─→ _checkDeviceOwner()
  ├─→ _enforceImmersiveMode()
  └─→ _checkDefaultPin()
  ↓
❌ UI Ready - Kiosk Active
```

### 2. Admin Panel Access Flow

```
User taps logo 5x
  ↓
_handleSecretTap()
  ├─→ Increment tap counter
  ├─→ Check time window (< 3 seconds)
  ├─→ If counter == 5: Reset & show PIN dialog
  └─→ Else: Increment counter
  ↓
_showPinDialog()
  ├─→ Display dialog with PIN input
  ├─→ Auto-focus on text field
  └─→ User enters PIN
  ↓
User taps "Verify"
  ↓
_verifyPin(pin)
  ├─→ PinService.verifyPin(pin)
  │   ├─→ FlutterSecureStorage.read("admin_pin_v1")
  │   ├─→ Compare input == stored
  │   └─→ Return bool (isValid)
  ├─→ if valid:
  │   ├─→ Close dialog
  │   ├─→ Pop to AdminPanelScreen
  │   └─→ Show Snackbar "Success"
  └─→ else:
      ├─→ Show Snackbar "Invalid PIN"
      └─→ Stay on dialog (allow retry)
  ↓
AdminPanelScreen displayed
```

### 3. PIN Change Flow

```
User taps "Change PIN"
  ↓
_showChangePinDialog()
  ├─→ Create TextControllers (current, new, confirm)
  └─→ Show dialog with 3 fields
  ↓
User fills fields & taps "Save"
  ↓
_performPinChange(current, new, confirm)
  ├─→ Validation:
  │   ├─→ Check non-empty: ✓
  │   ├─→ Check length 4-8: ✓
  │   ├─→ Check digits-only: ✓
  │   └─→ Check match: ✓
  ├─→ if validation fails:
  │   └─→ Show error Snackbar & return
  ├─→ PinService.changePin(current, new, confirm)
  │   ├─→ PinService.verifyPin(current)
  │   │   ├─→ Read stored PIN
  │   │   └─→ Compare
  │   ├─→ if invalid:
  │   │   └─→ Throw AppException
  │   ├─→ if valid:
  │   │   └─→ FlutterSecureStorage.write("admin_pin_v1", new)
  │   └─→ Return bool (success)
  ├─→ if success:
  │   ├─→ Close dialog
  │   └─→ Show success Snackbar
  └─→ else:
      └─→ Show error Snackbar
  ↓
AdminPanelScreen remains displayed
```

---

## Error Handling Strategy

### Three-Tier Error Handling

**Level 1: Platform Level (Kotlin)**
- Try/catch all operations
- Log with full context
- Return error codes/messages to Flutter
- Never crash app

**Level 2: Service Level (Dart)**
- Catch platform exceptions
- Log with context
- Wrap in AppException if needed
- Handle gracefully (allow app to continue)

**Level 3: UI Level (Screens)**
- Show user-friendly error messages
- Revert UI state
- Suggest remediation
- Allow retry

### Example: App Launch Error

```kotlin
// Kotlin
try {
    val intent = pm.getLaunchIntentForPackage(packageName)
    if (intent != null) {
        startActivity(intent)
        result.success(true)
    } else {
        result.error("APP_NOT_FOUND", "App not installed: $packageName", null)
    }
} catch (e: Exception) {
    result.error("LAUNCH_ERROR", e.message, null)
}
```

```dart
// Dart Service
try {
    final success = await _channel.invokeMethod<void>(
        KioskMethods.launchApp,
        {'packageName': packageName},
    );
    return true;
} on PlatformException catch (e) {
    Logger.error('Platform error: ${e.message}', context: 'KioskService');
    if (e.code == 'APP_NOT_FOUND') {
        // App not installed
        return false;
    }
    return false; // Swallow error
} catch (e) {
    Logger.error('Unexpected error', context: 'KioskService', error: e as Error?);
    return false;
}
```

```dart
// Dart UI
try {
    final success = await KioskService.openAccessCodeNG();
    if (!success) {
        _showSnackbar(
            'AccessCode NG not found. Please install it.',
            color: Colors.orange,
        );
    }
} catch (e) {
    _showSnackbar('Error launching app', color: Colors.red);
}
```

---

## Security Considerations

### 1. Intent Flag Combinations

```kotlin
// App launch - ensure new task
intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)  // Clear stack
intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP) // Reuse activity

// Boot launch - ensure visibility
intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
```

### 2. Permission Model

**Permissions Needed:**
- `RECEIVE_BOOT_COMPLETED` - Boot receiver
- `CALL_PHONE` - Dialer
- `REORDER_TASKS` - Lock task capability
- `DISABLE_KEYGUARD` - Skip lock screen

**User Restrictions (DeviceOwner only):**
- `no_install_apps` - Block installation
- `no_factory_reset` - Block factory reset
- `no_safe_boot` - Block recovery boot
- `no_usb_file_transfer` - USB data transfer
- `no_sms` - Block messaging

### 3. Data Protection

**PIN Storage:**
- Never stored in shared preferences (unencrypted)
- Always use FlutterSecureStorage (AES-256)
- Key is NOT hardcoded
- Device's TEE/secure storage is used

**Logs:**
- No PIN values in logs
- No sensitive data in logs
- Context metadata only

---

## Testing Strategy

### Unit Tests
- PIN validation logic
- Configuration parsing
- Error handling paths

### Integration Tests
- Platform channel communication
- Device owner detection
- Lock task lifecycle

### E2E Tests
- Full deployment flow
- User interactions
- Admin panel access
- PIN change process

### Manual Testing (80+ cases)
See: [DEPLOYMENT_GUIDE.md - Testing Checklist](DEPLOYMENT_GUIDE.md#testing-checklist)

---

## Performance Optimization

### Memory
- Use const constructors where possible
- Dispose resources in proper lifecycle
- Avoid memory leaks in listeners

### CPU
- Minimal background processing
- Platform channels only called on user action
- No tight loops

### Battery
- Screen stays on (required for kiosk)
- No frequent wakelocks
- Efficient UI rendering

---

## Future Enhancements

### v1.1.0
- [ ] Remote device management API
- [ ] Activity logging
- [ ] Biometric PIN unlock

### v2.0.0
- [ ] Multi-estate dashboard
- [ ] Device health monitoring
- [ ] Automated remote recovery

---

## References

- [Android DevicePolicyManager](https://developer.android.com/reference/android/app/admin/DevicePolicyManager)
- [Flutter Platform Channels](https://flutter.dev/docs/development/platform-integration/platform-channels)
- [Android Lock Task Mode](https://developer.android.com/guide/topics/admin/device-admin)
- [Immersive Mode](https://developer.android.com/training/system-ui/immersive)

---

**Last Updated:** March 2026  
**Version:** 1.0.0
