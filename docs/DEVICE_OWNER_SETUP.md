# Device Owner Mode Setup Guide

## What is Device Owner Mode?

Device Owner mode is an Android system-level feature that allows your kiosk app to:
- **Enforce lock task** - Keep the app locked in foreground, preventing users from exiting
- **Set lock task whitelist** - Allow specific apps (dialer, etc.) to appear on screen
- **Apply system restrictions** - Prevent app installation, factory reset, safe boot, SMS, etc.
- **Disable developer options** - Prevent ADB and debug access

**Without Device Owner**: Lock task is weak and doesn't prevent workarounds. Other apps can't display properly.

---

## Prerequisites

1. **Android Device with USB Debugging**
   - Device should be a dedicated kiosk device (not a user phone)
   - USB debugging must be enabled
   - Developer options unlocked

2. **Android SDK Platform Tools** (ADB)
   - Download from: https://developer.android.com/tools/releases/platform-tools
   - Extract to a known location

3. **Device Connected via USB**
   - Connect via USB cable
   - Accept USB debugging prompt on device

---

## Step-by-Step Setup

### Step 1: Install ADB (Android Debug Bridge)

#### Windows:
```powershell
# Download Android SDK Platform Tools
# https://developer.android.com/tools/releases/platform-tools

# Extract the zip file (e.g., to C:\platform-tools)

# Add to PATH (optional, for easier access)
$env:PATH += ";C:\platform-tools"

# Verify installation
adb version
```

#### macOS/Linux:
```bash
# Using Homebrew (macOS)
brew install android-platform-tools

# Or manually download and add to PATH
# https://developer.android.com/tools/releases/platform-tools

# Verify
adb version
```

---

### Step 2: Connect Device via USB

```bash
adb devices
```

**Output should show:**
```
List of attached devices
a1b2c3d4e5f6        device
```

If it says **"unauthorized"**: 
- Check your device for an authorization dialog
- Tap "Allow" to authorize the computer
- Run `adb devices` again

---

### Step 3: Build and Install Your Kiosk App

```powershell
cd c:\Users\DELL.COM\Desktop\Darey\koisk-app

# Build and install APK
flutter install
```

**Or manually:**
```bash
# Build APK
flutter build apk

# Install
adb install -r build/app/outputs/apk/release/app-release.apk
```

---

### Step 4: Set Device Owner Mode

**CRITICAL**: This command must be run BEFORE the user first launches the app.

```bash
adb shell dpm set-device-owner com.fynko.infinitykiosk/.AdminReceiver
```

**Expected output:**
```
Success: Device owner set.
```

---

### Step 5: Verify Device Owner Mode

```bash
adb shell cmd device_policy get-device-owner
```

**Output should show:**
```
com.fynko.infinitykiosk/com.fynko.infinitykiosk.AdminReceiver
```

---

### Step 6: Launch the App

Now the kiosk app will have full lock task enforcement:

```bash
adb shell am start -n com.fynko.infinitykiosk/.MainActivity
```

Or just tap the app icon on the device.

---

## Troubleshooting

### Problem: "Device owner already set"

Another app is already the device owner. Remove it first:

```bash
# View current device owner
adb shell cmd device_policy get-device-owner

# Remove existing device owner
adb shell dpm remove-active-admin com.other.app/.AdminReceiver
adb shell dpm remove-active-admin com.fynko.infinitykiosk/.AdminReceiver

# Then set our app as device owner
adb shell dpm set-device-owner com.fynko.infinitykiosk/.AdminReceiver
```

---

### Problem: "Can't set device owner - device has Google account"

Factory reset or remove Google account:

```bash
# Remove Google account (on device: Settings > Accounts > Google > Remove)

# Or factory reset if needed:
adb shell settings put secure install_non_market_apps 1
adb reboot bootloader
# Select wipe data/factory reset from bootloader menu
```

---

### Problem: "adb: command not found"

ADB is not in your PATH. Either:
1. Add platform-tools to PATH
2. Use the full path: `C:\platform-tools\adb.exe devices`

---

### Problem: USB Debugging Not Showing in Device Settings

Enable Developer Options:
1. Go to: Settings > About Phone
2. Tap "Build Number" 7 times
3. Go back to Settings > Developer Options (now visible)
4. Enable "USB Debugging"

---

## How the App Works with Device Owner

Once Device Owner is set:

### App Launch Sequence:
```
User taps app icon
    ↓
App starts
    ↓
MainActivity.onCreate() calls activateKiosk()
    ↓
startLockTask() - Lock app in foreground
    ↓
allowLockTaskPackages() - Whitelist:
    - com.fynko.infinitykiosk (kiosk app)
    - com.truecaller (dialer)
    - com.android.phone (phone system)
    ↓
Display kiosk screen (locked in place)
```

### Call Button Flow:
```
User taps "Call Admin"
    ↓
openDialer() called
    ↓
allowLockTaskPackages() adds dialer to whitelist
    ↓
startActivity(Intent.ACTION_DIAL with phone number)
    ↓
Dialer displays (permitted by lock task)
    ↓
User makes call
    ↓
User returns home or ends call
    ↓
Kiosk app back in focus
    ↓
onResume() re-activates lock task
    ↓
Back to locked kiosk (user can't exit)
```

### Exception: Incoming Call
```
Incoming call arrives
    ↓
System allows incoming call UI (exception)
    ↓
User can accept or reject
    ↓
After call ends
    ↓
Kiosk app re-activates lock task
    ↓
User trapped in kiosk again
```

---

## Security Features Enabled by Device Owner

Once Device Owner is set, these restrictions are automatically applied:

```kotlin
// From MainActivity.applyKioskRestrictions()

1. DISALLOW_SAFE_BOOT
   ✗ Cannot boot into recovery mode

2. DISALLOW_FACTORY_RESET  
   ✗ Cannot factory reset from Settings

3. DISALLOW_INSTALL_APPS
   ✗ Cannot install new apps

4. DISALLOW_UNINSTALL_APPS
   ✗ Cannot uninstall apps

5. DISALLOW_USB_FILE_TRANSFER
   ✗ USB is charging-only, no file access

6. DISALLOW_SMS
   ✗ Cannot send SMS messages

7. DEVELOPMENT_SETTINGS_ENABLED = 0
   ✗ Developer options disabled

8. ADB_ENABLED = 0
   ✗ Android Debug Bridge disabled
```

---

## Removing Device Owner (for Testing/Switching Devices)

```bash
adb shell dpm remove-active-admin com.fynko.infinitykiosk/.AdminReceiver
```

---

## Testing Checklist

After setting Device Owner:

- [ ] App launches and locks in place
- [ ] Back button does nothing
- [ ] Home button does nothing
- [ ] Recent apps button does nothing
- [ ] Status bar is hidden
- [ ] Call Admin button → Dialer appears
- [ ] Can make calls from dialer
- [ ] Incoming calls display properly
- [ ] AccessCode NG button → App launches/displays
- [ ] Returning from app → Back to kiosk (locked)
- [ ] Cannot access Settings
- [ ] Cannot access other apps
- [ ] USB debugging is disabled
- [ ] Cannot install new apps

---

## Important Notes

⚠️ **BACKUP YOUR DATA FIRST**
- Setting Device Owner restricts access
- Store important files elsewhere before setup

⚠️ **DEDICATED DEVICE ONLY**
- Do not use a personal phone
- Consider a tablet or budget kiosk device
- Once locked, only the admin pin can escape

⚠️ **RECOVERY PLAN**
- Document the admin PIN
- Store it securely
- You'll need it to access admin panel

---

## Quick Reference Commands

```bash
# Verify ADB connection
adb devices

# Install app
adb install -r build/app/outputs/apk/release/app-release.apk

# Set Device Owner
adb shell dpm set-device-owner com.fynko.infinitykiosk/.AdminReceiver

# Check if Device Owner is set
adb shell cmd device_policy get-device-owner

# View device logs
adb logcat | grep InfinityKiosk

# Remove Device Owner (if needed)
adb shell dpm remove-active-admin com.fynko.infinitykiosk/.AdminReceiver

# Factory reset
adb reboot bootloader

# Check app permissions
adb shell dumpsys package-info com.fynko.infinitykiosk

# Uninstall app
adb uninstall com.fynko.infinitykiosk
```

---

## Support

If Device Owner setup fails:
1. Check device has no Google account
2. Ensure USB debugging is fully enabled
3. Try factory reset on device
4. Check Android version is 5.0+
5. Verify package name: `com.fynko.infinitykiosk`
6. Verify receiver: `.AdminReceiver`
