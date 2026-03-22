## 📚 PRODUCTION DEPLOYMENT GUIDE

**Infinity Estate Secure Kiosk - Complete Setup Manual**

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Prerequisites & Requirements](#prerequisites--requirements)
3. [Pre-Build Setup](#pre-build-setup)
4. [Building the APK](#building-the-apk)
5. [Device Preparation](#device-preparation)
6. [Device Owner Setup (CRITICAL)](#device-owner-setup-critical)
7. [Installation & Deployment](#installation--deployment)
8. [Testing Checklist](#testing-checklist)
9. [Troubleshooting](#troubleshooting)
10. [Maintenance & Support](#maintenance--support)

---

## Project Overview

### Purpose

Convert a low-end Android phone into a **controlled, locked-down terminal** for Infinity Estate visitor verification. The device becomes a single-purpose machine that:

- ✓ Runs only AccessCode NG for visitor verification
- ✓ Blocks all other apps, settings, and system access
- ✓ Cannot be exited or restarted by non-admins
- ✓ Automatically relaunches after power loss or restart
- ✓ Resists tampering and theft (useless if stolen)

### Tech Stack

- **Frontend:** Flutter 3.0+
- **Backend:** Native Android (Kotlin)
- **Security:** Device Owner mode + Lock Task mode
- **Storage:** AES-256 encrypted secure storage
- **Target:** Android 8.0+ (API 26+)

---

## Prerequisites & Requirements

### Development Environment

Required tools:

```bash
# Check versions
flutter --version
android --version
java -version
adb version

# Required minimum versions:
- Flutter SDK: 3.0.0+
- Android SDK: API 34 (target)
- Java: JDK 11+
- Kotlin: 1.7+
```

### Device Requirements

**Device Specifications:**
- Android 8.0+ (API 26+)
- Minimum 1GB RAM
- Phones with physical home button (preferred)
- ADB-capable (USB port)

**NOT Recommended:**
- Tablets (too easy to bypass)
- Devices with on-screen home button only
- Devices running custom ROMs (security risk)
- Very old devices (Android < 8.0)

### Recommended Devices

- Samsung A10/A20 series
- Xiaomi Redmi 9
- Realme C series
- Motorola Moto G series

---

## Pre-Build Setup

### 1. Clone or Extract Project

```bash
# Into your development directory
cd /path/to/projects
# Project structure should have:
# - lib/              (Dart code)
# - android/          (Kotlin code)
# - pubspec.yaml
# - AndroidManifest.xml
```

### 2. Update App Configuration

Edit `lib/constants/app_config.dart`:

```dart
class AppConfig {
  static const String estateName = 'Your Estate Name';  // ✏️ Customize
  static const String estateLocation = 'Your Location'; // ✏️ Customize  
  static const String adminContactNumber = '08000000000'; // ✏️ Update
  static const String adminEmail = 'admin@yourestate.ng'; // ✏️ Update
  static const String defaultAdminPin = '1234'; // ✏️ CHANGE LATER
}
```

### 3. Package Name (Optional - For Multi-Estate Apps)

To use different package names for different estates:

```bash
# Edit android/app/build.gradle
defaultConfig {
    applicationId "com.fynko.infinitykiosk.estate1"
    // ...
}

# Edit AndroidManifest.xml
<manifest package="com.fynko.infinitykiosk.estate1">
```

### 4. Install Dependencies

```bash
# Fetch Flutter packages
flutter pub get

# Update dependencies
flutter pub upgrade

# Check for issues
flutter analyze
dart analyze
```

---

## Building the APK

### 1. Clean Build (Recommended for First Build)

```bash
# Clear previous builds
flutter clean

# Get dependencies again
flutter pub get

# Build release APK
flutter build apk --release

# Output location:
# build/app/outputs/flutter-apk/app-release.apk
```

### 2. Build with Obfuscation (Extra Security)

```bash
# For Android native code obfuscation
flutter build apk --release --obfuscate

# Note: This only obfuscates Dart code
# Android code is already minified in release mode
```

### 3. Verify APK

```bash
# Check APK file exists and size is reasonable (5-15 MB)
ls -lh build/app/outputs/flutter-apk/app-release.apk

# Verify APK integrity
aapt dump badging build/app/outputs/flutter-apk/app-release.apk
```

### 4. Optional: Build AAB for Playstore (Not Recommended)

```bash
# Android App Bundle format (for Play Store)
flutter build appbundle --release

# Output: build/app/outputs/bundle/release/app-release.aab
```

---

## Device Preparation

### ⚠️ CRITICAL: Factory Reset

1. **Power off the device completely**
2. **DO NOT turn it on yet**

### Enable Developer Options & ADB

1. Connect device via USB to computer
2. Turn on device
3. Go to **Settings** > **About Phone**
4. Tap **Build Number** 7 times until developer mode enables
5. Go to **Settings** > **Developer Options**
6. Enable **USB Debugging**
7. On device, allow USB Debugging from computer

### Verify ADB Connection

```bash
# Check device is detected
adb devices

# Output should show:
# List of attached devices
# XXXXX  device

# If device shows "unauthorized":
# - Tap "Allow USB Debugging" on phone screen
# - Run: adb devices
```

### Remove Google Account

**CRITICAL:** Device owner mode cannot be set if Google account exists.

```bash
# Method 1: Via device UI
Settings > Accounts > Remove all accounts

# Method 2: Via ADB
adb shell settings put global device_provisioned 0
adb shell settings put secure user_setup_complete 0
adb reboot
```

### Disable Android Setup Wizard

```bash
adb shell settings put global device_provisioned 0
adb shell settings put secure user_setup_complete 0
```

---

## Device Owner Setup (CRITICAL)

### ⚠️ This step is NON-NEGOTIABLE for production

Without Device Owner mode, the kiosk can be easily bypassed by users.

### Step 1: Check Package Names Are Correct

```bash
# Current package in code (see build.gradle):
# applicationId "com.fynko.infinitykiosk"

# Verify in APK
aapt dump badging app-release.apk | grep package
```

### Step 2: Set Device Owner via ADB

**Run this ONLY on a clean/factory-reset device with no accounts:**

```bash
adb shell dpm set-device-owner com.fynko.infinitykiosk/.AdminReceiver
```

### Expected Output:

```bash
# Success:
Success: Device owner set to package com.fynko.infinitykiosk

# Failure messages:
# "Not allowed to set the device owner because there are already some accounts on the device"
#     → Remove all Google/email accounts first
#
# "Cannot set device owner: user is not running in user mode"
#     → Device needs factory reset
#
# "Receiver not found"  
#     → AppBundle receiver class name is wrong or app not installed yet
```

### Step 3: Verify Device Owner Assignment

```bash
adb shell dumpsys device_policy

# Look for section:
# Device Owner:
#   mName=com.fynko.infinitykiosk
```

---

## Installation & Deployment

### Method 1: ADB Installation (Recommended for Testing)

```bash
# Install APK to device
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Expected output:
# Success
# 
# Launch app
adb shell am start -n com.fynko.infinitykiosk/.MainActivity

# Check logs
adb logcat | grep -i kiosk
```

### Method 2: Manual Installation (Via File Transfer)

```bash
# Copy APK to device
adb push build/app/outputs/flutter-apk/app-release.apk /sdcard/

# On Phone: 
# - Open Files app
# - Navigate to /sdcard/
# - Tap app-release.apk
# - Install
```

### Method 3: Sideload from Android Studio

1. Open Android Studio
2. **Run** > **Select Device**
3. Choose target device
4. Click **Run** button
5. App builds and installs automatically

---

## Startup Verification & Initial Configuration

### First Launch

```bash
# App should:
1. Display "Infinity Estate" logo
2. Show "Open AccessCode NG" button
3. Show "Call Admin" button
4. No system UI visible (no status bar, no navigation)
5. Home button does nothing
```

### Admin Panel Access (First Time)

1. Tap the Infinity Estate logo 5 times (in 3 seconds) to trigger admin panel
2. Enter default PIN: **1234**
3. Inside admin panel, **CHANGE PIN IMMEDIATELY** to a secure 6-8 digit code
4. Note: This must be done before deployment

### Test Kiosk Restrictions

After entering admin panel and relocking:

```bash
# All of these should FAIL (indicating security is working):
- Press Home button
- Press Back button
- Pull down notification panel
- Access Settings
- Open other apps
- Install new apps
- Uninstall the kiosk app
- Factory reset option

# These SHOULD work:
- Tap button to open AccessCode NG
- Tap button to call admin
- Tap logo 5 times to enter admin panel (with correct PIN)
```

---

## Testing Checklist

### Pre-Deployment Testing (80+ Test Cases)

#### 1. Device Owner & Lock Task Mode ✓

- [ ] Device owner mode active (`adb shell dumpsys device_policy`)
- [ ] Lock task mode activates on app launch
- [ ] Lock task mode shows in `dumpsys deviceidle`

#### 2. System UI Blocking ✓

- [ ] No status bar visible
- [ ] No navigation buttons visible
- [ ] Status bar cannot be pulled down
- [ ] Swipe gestures don't reveal system UI
- [ ] Screen rotation stays enabled (portrait locked)

#### 3. Navigation Blocking ✓

- [ ] Home button → stays in app
- [ ] Back button → stays in app
- [ ] Recent apps button (or gesture) → stays in app
- [ ] Volume buttons → work normally (optional)
- [ ] Long-press power button → stays in app (might bring up power menu - acceptable)

#### 4. App Restrictions ✓

- [ ] Cannot open Settings
- [ ] Cannot open Chrome/Play Store
- [ ] Cannot open File Manager
- [ ] Cannot open Contacts/Messaging
- [ ] Can open AccessCode NG (if installed)
- [ ] Can make calls via Dialer

#### 5. PIN & Admin Access ✓

- [ ] Default PIN (1234) works initially
- [ ] Admin panel accessible after 5 taps + correct PIN
- [ ] Can change PIN in admin panel
- [ ] New PIN works after change
- [ ] Invalid PINs rejected
- [ ] Multiple invalid attempts show errors

#### 6. Boot & Resume ✓

- [ ] Device powers on → Kiosk launches automatically
- [ ] Reboot → Kiosk relaunches
- [ ] Resume from sleep → Kiosk still locked
- [ ] App crashes → Auto-relaunches (if lock task exits)
- [ ] Cold restart → Kiosk is first screen

#### 7. AccessCode NG Integration ✓

- [ ] Button opens AccessCode NG successfully
- [ ] Returning from AccessCode NG brings back kiosk (returns to lock task)
- [ ] AccessCode NG cannot launch other apps

#### 8. Admin Functions ✓

- [ ] Can view device status
- [ ] Can change admin PIN
- [ ] Can exit kiosk mode (unlocks device)
- [ ] Can call admin number

---

## Troubleshooting

### Common Issues & Solutions

#### Issue: Device Owner Setup Fails

**Error:** "Not allowed to set the device owner because there are already some accounts"

**Solution:**
```bash
# Remove all accounts
adb shell pm clear com.google.android.gms
adb shell settings put global device_provisioned 0
adb shell settings put secure user_setup_complete 0
adb reboot

# Try again:
adb shell dpm set-device-owner com.fynko.infinitykiosk/.AdminReceiver
```

---

#### Issue: App Won't Launch on Boot

**Symptom:** Device restarts, shows Android UI (doesn't launch kiosk)

**Cause:** Boot receiver not working

**Solution:**
```bash
# Check boot receiver in manifest
grep -A5 "BootReceiver" AndroidManifest.xml

# Verify permissions
dumpsys package permissions | grep BOOT_COMPLETED

# Check receiver is registered
adb shell pm dump com.fynko.infinitykiosk | grep -i receiver

# Manually trigger boot  
adb shell am broadcast -a android.intent.action.BOOT_COMPLETED -c android.intent.category.DEFAULT
```

---

#### Issue: Lock Task Not Activating

**Symptom:** App runs but system UI is visible

**Cause:** Not device owner OR lock task call failed

**Solution:**
```bash
# Verify device owner
adb shell dumpsys device_policy | grep "Device Owner"

# Manually trigger lock task
adb shell am start-task-lock com.fynko.infinitykiosk/.MainActivity

# Check logs
adb logcat | grep -i "lockTask"
```

---

#### Issue: PIN Verification Fails (Default 1234)

**Symptom:** Admin panel says "Invalid PIN" for 1234

**Path:** App not initialized properly

**Solution:**
```bash
# Clear app data
adb shell pm clear com.fynko.infinitykiosk

# Reinstall app
adb install -r app-release.apk

# Launch and wait for initialization
adb shell am start -n com.fynko.infinitykiosk/.MainActivity

# Try PIN again
```

---

#### Issue: AccessCode NG Won't Launch

**Symptom:** "AccessCode NG not found" message

**Cause:** AccessCode NG not installed

**Solution:**
1. Manually install AccessCode NG APK via: `adb install accesscodeng.apk`
2. Or request download link from AccessCode developers
3. Verify installation: `adb shell pm list packages | grep accesscode`

---

### Debugging via Logs

```bash
# View all kiosk logs in real-time
adb logcat | grep -i "kiosk\|kiosk\|admin"

# View logs to file
adb logcat > kiosk_logs.txt &

# Filter by severity
adb logcat *:E  # Errors only
adb logcat *:W  # Warnings
adb logcat *:I  # Info level

# View Flutter logs
adb logcat | grep flutter
```

---

## Maintenance & Support

### Regular Maintenance Tasks

#### Weekly:
- [ ] Monitor device for errors in logs
- [ ] Test admin panel access (change temporary PIN and change back)
- [ ] Verify device still locked and functional

#### Monthly:
- [ ] Review access logs  
- [ ] Test boot/restart procedure
- [ ] Verify all buttons responsive

#### Quarterly:
- [ ] Update admin contact number if needed
- [ ] Test full factory reset & redeploy process
- [ ] Audit device security settings

---

### Emergency Procedures

#### Device Won't Boot Into Kiosk

```bash
# Remove lock task to recover
adb shell am stack lock -d

# Or full data wipe + redeploy
adb shell wipe data
adb install -r app-release.apk
```

#### Need to Exit Kiosk Mode

1. Tap logo 5 times  
2. Enter admin PIN
3. Select "Exit Kiosk Mode"
4. Device unlocks (returns to normal Android)

To relock:
```bash
adb shell am start -n com.fynko.infinitykiosk/.MainActivity
# App relaunches in lock task mode
```

---

### Support & Escalation

**For Issues:**
1. Check logs: `adb logcat | grep -E "(Error|Exception|kiosk)"`
2. Review this troubleshooting guide
3. Factory reset and redeploy if needed
4. Contact Fynko Technologies: 08167322603

---

## Security Best Practices

### After Deployment:

1. **PIN Security**
   - Change default PIN (1234) immediately
   - Use strong 6-8 digit code  
   - Document PIN securely
   - Contact only admin knows PIN

2. **Device Security**
   - Keep device in secure location
   - Check regularly for tampering (cracks, loose buttons)
   - Monitor logs for suspicious activity

3. **Software Security**
   - Never sideload untrusted APKs
   - Keep device on latest Android version
   - Disable USB debugging after setup completed

4. **Hardware Security**
   - Use theft-resistant mount
   - Disable screenshot functionality if needed
   - Consider security camera monitoring

---

## End of Deployment Guide

For questions or issues, contact: **Fynko Technologies - 08167322603**

---

*Last Updated: March 2026*
*Version: 1.0.0*
