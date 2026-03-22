## 🚀 QUICK START GUIDE

**Build & Deploy Infinity Estate Kiosk - 15-Minute Setup**

### Prerequisites Checklist

- ✓ Flutter SDK installed
- ✓ Android SDK (API 34) installed
- ✓ Java 11+ installed
- ✓ USB cable + Android phone (Android 8.0+)
- ✓ USB Debugging enabled on phone
- ✓ Phone connected via USB to computer

---

## Step 1: Prepare Your Device

```bash
# Connect device via USB
# Enable USB Debugging on phone (Settings > Developer Options > USB Debugging)
# Verify connection
adb devices

# Output should show your device as "device"
```

---

## Step 2: Build the APK

```bash
# Navigate to project
cd /path/to/koisk-app

# Clean build
flutter clean

# Get dependencies
flutter pub get

# Build APK
flutter build apk --release

# APK is ready at: build/app/outputs/flutter-apk/app-release.apk
```

---

## Step 3: Set Device Owner (CRITICAL)

This step is **MANDATORY** for production security.

```bash
# Make sure phone has NO Google accounts
# Settings > Accounts > Remove all

# Remove provisioning
adb shell settings put global device_provisioned 0
adb shell settings put secure user_setup_complete 0

# Set device owner (one-time only)
adb shell dpm set-device-owner com.fynko.infinitykiosk/.AdminReceiver

# Should see: "Success: Device owner set to package com.fynko.infinitykiosk"
```

---

## Step 4: Install the App

```bash
# Install APK
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Launch it
adb shell am start -n com.fynko.infinitykiosk/.MainActivity

# Done! App should launch in full kiosk mode
```

---

## Step 5: Access Admin Panel (First Time)

On the phone:
1. **Tap the Infinity Estate logo 5 times** (within 3 seconds)
2. **Enter PIN: 1234** (default)
3. **Click Change Admin PIN** and set your own 6-8 digit PIN
4. **Return to Kiosk Mode**

---

## Step 6: Verify It Works

Test these - they should ALL FAIL (meaning security is working):

- ✗ Press Home button
- ✗ Press Back button  
- ✗ Pull down notification bar
- ✗ Open Settings
- ✗ Install any app
- ✗ Uninstall this app

Test these - they SHOULD WORK:

- ✓ Tap "Open AccessCode NG" (if installed)
- ✓ Tap "Call Admin"
- ✓ Tap logo 5x to access admin panel

---

## Troubleshooting

### Device owner setup fails

```bash
# Error: "device already has accounts"
# Solution: Remove accounts first
adb shell pm clear com.google.android.gms
adb shell settings put global device_provisioned 0
adb shell settings put secure user_setup_complete 0
adb reboot

# Then try again:
adb shell dpm set-device-owner com.fynko.infinitykiosk/.AdminReceiver
```

### App won't install

```bash
# Uninstall old version first
adb uninstall com.fynko.infinitykiosk

# Then install
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Lock task not working

```bash
# Verify device owner is set
adb shell dumpsys device_policy | grep "Device Owner"

# Should show: "com.fynko.infinitykiosk"
```

### Can't enter admin panel

```bash
# Reset app data and try again
adb shell pm clear com.fynko.infinitykiosk

# Reinstall
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Default PIN should work again: 1234
```

---

## What's Next?

1. **Install AccessCode NG** on the device
2. **Configure admin contact number** (update in code if needed)
3. **Deploy to estate**
4. **Train security staff** on button usage
5. **Document PIN securely** (not on device!)

---

## Need Help?

See full deployment guide: `docs/DEPLOYMENT_GUIDE.md`

Contact: **Fynko Technologies - 08167322603**
