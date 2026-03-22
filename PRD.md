Alright — this is the right move. You’re thinking like a system owner now.

I’ll give you a **clean, production-ready PRD** you can hand to yourself (or any dev) and start building immediately. No fluff. Just what you need to get a **locked estate device running fast and reliably**.

---

# 📄 PRODUCT REQUIREMENTS DOCUMENT (PRD)

## Product Name

**Infinity Estate Secure Device (Kiosk Mode App)**

---

## 📍 Overview

A lightweight Android application built with Flutter that converts a low-end Android phone into a **single-purpose secure terminal**.

The device will:

* Run only **AccessCode NG**
* Block all other apps and system access
* Prevent unauthorized exit
* Remain locked even after reboot
* Be useless if stolen or tampered with

---

## 🎯 Objective

Ensure estate security personnel can **only perform visitor verification tasks** without accessing any other part of the device.

---

## 🧱 Core Principles

* Simple > Complex
* Locked > Flexible
* Reliable > Fancy
* Offline-capable
* No dependency on third-party kiosk apps

---

## 👤 Stakeholders

* **Owner:** Fynko Technologies
* **Estate:** Infinity Estate, Addo Road, Ajah
* **Admin Contact:** 08167322603 (editable)

---

# ⚙️ FUNCTIONAL REQUIREMENTS

---

## 1. 🔒 Kiosk Lock Mode (CRITICAL)

### Description:

The app must run in **full kiosk mode**, making it the only usable interface.

### Requirements:

* App becomes **default launcher (home screen)**
* Disable:

  * Home button
  * Recent apps
  * Status bar (swipe down)
* Prevent switching apps

### Expected Behavior:

* Pressing any system navigation keeps user inside app
* No visible Android UI outside your app

---

## 2. 🚀 Auto Launch on Boot

### Description:

App must automatically start after device restarts.

### Requirements:

* Register boot receiver
* Launch app immediately on boot
* Skip lock screen if possible

### Expected Behavior:

* Device powers on → directly opens your app

---

## 3. 📱 Allowed Apps (Whitelist)

### Description:

Only specific apps can run.

### Allowed:

* AccessCode NG
* Phone (Dialer only – optional)

### Block:

* Settings
* Chrome
* Play Store
* File Manager
* Messaging (SMS)

---

## 4. 🔐 Admin Exit System

### Description:

Hidden way for admin to unlock device.

### Requirements:

* Hidden gesture (e.g. tap screen 5 times OR long press logo)
* Prompt for **Admin PIN**
* Correct PIN → exit kiosk mode

### Notes:

* No visible “Exit” button
* No default PIN anywhere in UI

---

## 5. 🔑 Admin Authentication

### Description:

Secure access control for admin actions.

### Requirements:

* Default PIN set on first install
* Ability to change PIN
* Store securely (encrypted storage)

---

## 6. 📵 System Restrictions

### Description:

Prevent misuse or tampering.

### Must Disable:

* App installation
* USB debugging
* Developer options access
* Notifications panel
* Split screen / multi-window

---

## 7. 📞 Call Control

### Description:

Allow only voice calls if needed.

### Requirements:

* Allow dialer app
* Block SMS (do not expose messaging app)

---

## 8. 🧪 Tamper Resistance

### Description:

Make device useless if stolen or tampered with.

### Requirements:

* App relaunches if closed
* Detect if kiosk mode is broken → re-enable
* Prevent uninstall (via device owner mode)

---

## 9. 📴 Offline Operation

### Description:

App should work without internet.

### Requirement:

* No dependency on online services for core lock functionality

---

# 🏗️ TECHNICAL REQUIREMENTS

---

## Framework

* Flutter (UI layer)
* Native Android (Kotlin/Java) for kiosk control

---

## Android Capabilities Required

### 1. Device Owner Mode (IMPORTANT)

This enables:

* Full device control
* Lock task mode
* Prevent uninstall
* System-level restrictions

---

### 2. Lock Task Mode

Used to:

* Pin app permanently
* Disable navigation buttons

---

### 3. Broadcast Receivers

* BOOT_COMPLETED → auto launch app

---

### 4. Permissions Required

* Device Admin
* Usage Access
* Overlay (optional)
* Boot access

---

# 🧩 ARCHITECTURE

```
Flutter App (UI)
   ↓
Platform Channel
   ↓
Native Android Layer
   ↓
Device Owner + Lock Task APIs
```

---

# 🎨 UI REQUIREMENTS

---

## Main Screen

* Fullscreen
* No system UI visible
* Large buttons:

  * Open AccessCode NG
  * Call Admin (optional)

---

## Hidden Admin Panel

* Trigger via gesture
* PIN input screen
* Options:

  * Exit kiosk
  * Change PIN

---

# 🔐 SECURITY REQUIREMENTS

---

## Must Have:

* No visible exit paths
* No debug mode access
* No default credentials exposed
* App cannot be uninstalled without admin

---

## If Phone is Stolen:

* Cannot access apps
* Cannot reset easily
* Cannot use device normally

---

# 🚀 DEPLOYMENT PLAN

---

## Step 1 — Prepare Device

* Factory reset phone
* Do NOT sign into Google account

---

## Step 2 — Set Device Owner

Using ADB:

```
adb shell dpm set-device-owner com.yourapp/.AdminReceiver
```

---

## Step 3 — Install App

* Install APK manually
* Launch once to configure

---

## Step 4 — Lock Device

* Activate kiosk mode
* Set admin PIN

---

# 🧪 TEST CASES

---

## Must Pass:

* Restart phone → app launches automatically
* Press home → stays in app
* Try to open settings → blocked
* Try to install app → blocked
* Try random tapping → no exit
* Enter admin PIN → unlock works

---

# ⚠️ RISKS

---

## If Device Owner Mode is NOT used:

* Users can bypass restrictions
* App can be uninstalled
* Security is weak

👉 So this is NON-NEGOTIABLE

---

# 🧠 FUTURE (Optional – Not Now)

* Remote control dashboard
* Multiple estate support
* Device monitoring
* Activity logs

---

# ✅ FINAL NOTE

This is not just an app — it’s a **controlled device system**.

If implemented correctly:

* Security staff cannot misuse it
* Phone becomes a **dedicated estate machine**
* Even if stolen → low value, hard to reuse

