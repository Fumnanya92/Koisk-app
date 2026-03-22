package com.fynko.infinitykiosk

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/// ============================================================================
/// AdminReceiver - Device Admin Receiver
/// ============================================================================
/// Entry point for Device Owner mode setup
///
/// TO ACTIVATE DEVICE OWNER (one-time setup):
/// adb shell dpm set-device-owner com.fynko.infinitykiosk/.AdminReceiver
///
/// REQUIREMENTS:
/// - No Google account must be signed in on device
/// - No other device administrator apps installed
/// - Device must be factory reset or fresh
/// - ADB access required (via USB)
///
/// Once activated:
/// - App gains full device control
/// - Lock task mode becomes functional
/// - System restrictions can be enforced
/// - App cannot be uninstalled without accessing settings
///
/// Device owner mode is the FOUNDATION of kiosk security.
/// Without it, the kiosk can be easily bypassed.
class AdminReceiver : DeviceAdminReceiver() {

    companion object {
        private const val TAG = "AdminReceiver"
    }

    /// ========================================================================
    /// Lifecycle Callbacks
    /// ========================================================================

    /// Called when device admin is enabled/activated
    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.i(TAG, "✓ Device Admin capability ENABLED")
        Log.i(TAG, "Device is now fully managed by Infinity Kiosk")
    }

    /// Called when device admin is about to be disabled
    /// In device owner mode, this typically cannot happen without factory reset
    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.w(TAG, "⚠ Device Admin capability DISABLED - Security compromised!")
    }

    /// ========================================================================
    /// Lock Task Mode Callbacks
    /// ========================================================================

    /// Called when app enters lock task mode (kiosk is locked)
    override fun onLockTaskModeEntering(context: Context, intent: Intent, pkg: String) {
        super.onLockTaskModeEntering(context, intent, pkg)
        Log.i(TAG, "🔒 Lock Task Mode ENTERING for package: $pkg")
        Log.i(TAG, "App is now locked to foreground - users cannot exit")
    }

    /// Called when app exits lock task mode
    /// In production, this should NEVER happen
    /// If it does, it indicates a security breach
    override fun onLockTaskModeExiting(context: Context, intent: Intent) {
        super.onLockTaskModeExiting(context, intent)
        if (MainActivity.isExitRequested(context)) {
            Log.i(TAG, "Intentional admin exit detected - skipping kiosk relaunch")
            return
        }
        Log.e(TAG, "🚨 SECURITY ALERT: Lock Task Mode EXITING!")
        Log.e(TAG, "This should not happen in production. Device may be compromised.")
        Log.i(TAG, "Attempting to relaunch main activity...")

        // Force relaunch of kiosk app
        try {
            val relaunch = Intent(context, MainActivity::class.java)
            relaunch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            relaunch.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            relaunch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            context.startActivity(relaunch)
            Log.i(TAG, "Relaunch intent sent")
        } catch (e: Exception) {
            Log.e(TAG, "Error relaunching app: ${e.message}", e)
        }
    }

    /// ========================================================================
    /// Security Policy Callbacks
    /// ========================================================================

    /// Called when password policy is changed
    override fun onPasswordChanged(context: Context, intent: Intent) {
        super.onPasswordChanged(context, intent)
        Log.i(TAG, "Password policy changed")
    }

    /// Called when lock screen wallpaper changes
    override fun onPasswordFailed(context: Context, intent: Intent) {
        super.onPasswordFailed(context, intent)
        Log.w(TAG, "Password authentication failed")
    }

    /// Called when password succeeds
    override fun onPasswordSucceeded(context: Context, intent: Intent) {
        super.onPasswordSucceeded(context, intent)
        Log.i(TAG, "Password authentication succeeded")
    }

    /// Called when someone tries to disable device admin.
    /// Returning text here shows a system warning prompt before disabling.
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        Log.w(TAG, "Device admin disable requested")
        return "Disabling device administration will weaken kiosk protection."
    }
}
