package com.fynko.infinitykiosk

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.content.pm.PackageManager.PERMISSION_GRANTED
import android.net.Uri
import android.telecom.TelecomManager
import android.util.Log
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

enum class KioskMethod {
    START_KIOSK_MODE, STOP_KIOSK_MODE, IS_DEVICE_OWNER,
    LAUNCH_APP, OPEN_DIALER, SET_GLOBAL_SETTINGS,
    APPLY_KIOSK_RESTRICTIONS, GET_DEVICE_INFO
}

/// ============================================================================
/// MainActivity - Main Kiosk Activity
/// ============================================================================
/// Handles:
/// - Immersive fullscreen mode (hides all system UI)
/// - Lock task mode activation/deactivation
/// - Method channel communication with Flutter
/// - Platform-level device control
/// - System UI enforcement
///
/// KEY SECURITY FEATURES:
/// - Keeps screen on to prevent sleep lock
/// - Hides system UI continuously
/// - Re-enforces lock task on every resume
/// - Disables status bar and navigation through multiple methods
/// - Terminates the entire app if lock task exits unexpectedly
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "InfinityKiosk"
        private const val CHANNEL = "com.fynko.infinitykiosk/kiosk"
        private const val PREFS_NAME = "kiosk_prefs"
        private const val KEY_EXIT_KIOSK_REQUESTED = "exit_kiosk_requested"
        private const val REQUEST_CODE_PICK_UPDATE_APK = 1001

        @JvmStatic
        fun isExitRequested(context: Context): Boolean {
            return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_EXIT_KIOSK_REQUESTED, false)
        }

        @JvmStatic
        fun setExitRequested(context: Context, requested: Boolean) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_EXIT_KIOSK_REQUESTED, requested)
                .apply()
        }
    }

    private lateinit var devicePolicyManager: DevicePolicyManager
    private lateinit var adminComponent: ComponentName
    private var pendingUpdateResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i(TAG, "MainActivity created")

        // Get device policy manager for admin operations
        devicePolicyManager = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        adminComponent = ComponentName(this, AdminReceiver::class.java)

        // CRITICAL: Keep screen on to prevent lock screen appearance
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        Log.i(TAG, "Screen wake lock applied")

        // Hide all system UI immediately
        hideSystemUI()

        // Ensure the kiosk app itself is always allowed in lock task mode
        allowLockTaskPackages(packageName)
        
        // Add system dialer and phone apps for incoming/outgoing calls
        allowLockTaskPackages(getSystemDialerPackage(), getSystemPhonePackage())
    }

    override fun onResume() {
        super.onResume()
        Log.i(TAG, "Activity resumed - re-enforcing kiosk mode")

        if (isExitRequested(this)) {
            Log.i(TAG, "Admin exit in progress - skipping kiosk re-enforcement")
            showSystemUI()
            return
        }

        // Re-hide system UI on every resume
        hideSystemUI()

        // Re-activate kiosk mode if it was somehow disabled
        if (isDeviceOwner()) {
            try {
                startLockTask()
                Log.i(TAG, "Lock task re-activated on resume")
            } catch (e: Exception) {
                Log.e(TAG, "Error re-activating lock task: ${e.message}", e)
            }
        } else {
            Log.w(TAG, "Not device owner - cannot re-activate lock task")
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && !isExitRequested(this)) {
            Log.d(TAG, "Window focus changed - re-hiding system UI")
            hideSystemUI()
        }
    }

    override fun onBackPressed() {
        Log.w(TAG, "Back button pressed - IGNORED (kiosk mode active)")
        // Do absolutely nothing - back button does not work in kiosk
    }

    override fun onPause() {
        super.onPause()
        Log.d(TAG, "Activity paused")
    }

    override fun onDestroy() {
        Log.i(TAG, "MainActivity destroying")
        super.onDestroy()
    }

    /// ========================================================================
    /// IMMERSIVE MODE - Hide ALL system UI
    /// ========================================================================
    /// Uses multiple methods to ensure maximum compatibility:
    /// - WindowInsetsController (Android 11+)
    /// - Legacy View flags (Android 10 and below)
    /// - Sticky immersive flag prevents brief flashes
    private fun hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // ANDROID 11+: Use WindowInsetsController for modern UI hiding
            window.insetsController?.let { controller ->
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                Log.d(TAG, "WindowInsetsController insets hidden")
            }
        }

        // LEGACY SUPPORT: Also apply old flags for compatibility
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY          // Sticky immersive
                        or View.SYSTEM_UI_FLAG_LAYOUT_STABLE           // Stable margins
                        or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION  // Don't reserve nav bar space
                        or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN       // Don't reserve status bar space
                        or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION         // Hide navigation buttons
                        or View.SYSTEM_UI_FLAG_FULLSCREEN              // Hide status bar
                )
        Log.d(TAG, "Legacy system UI flags applied")
    }

    private fun showSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.show(
                WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars()
            )
        }

        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
    }

    /// ========================================================================
    /// Method Channel Handler - Communication with Flutter
    /// ========================================================================
    /// Defines platform methods that Flutter can call
    /// Each method returns success/failure and error codes
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.i(TAG, "Configuring Flutter engine and method channel")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                Log.i(TAG, "Method called: ${call.method}")

                try {
                    when (call.method) {
                        "startKioskMode" -> handleStartKiosk(result)
                        "stopKioskMode" -> handleStopKiosk(result)
                        "installUpdateApk" -> handleInstallUpdateApk(result)
                        "isDeviceOwner" -> result.success(isDeviceOwner())
                        "launchApp" -> handleLaunchApp(call, result)
                        "openDialer" -> handleOpenDialer(call, result)
                        "getDeviceInfo" -> result.success(getDeviceInfo())
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Exception handling method ${call.method}: ${e.message}", e)
                    result.error("EXCEPTION", e.message, null)
                }
            }
    }

    /// ========================================================================
    /// Kiosk Mode Control Methods
    /// ========================================================================

    private fun handleStartKiosk(result: MethodChannel.Result) {
        Log.i(TAG, "Starting kiosk mode")
        try {
            if (!isDeviceOwner()) {
                Log.w(TAG, "Not device owner - cannot start lock task")
                result.error("NOT_DEVICE_OWNER", "Device is not device owner", null)
                return
            }

            setExitRequested(this, false)
            startLockTask()
            applyKioskRestrictions()
            
            // Whitelist system phone apps for incoming/outgoing calls
            allowLockTaskPackages(getSystemDialerPackage(), getSystemPhonePackage())
            
            Log.i(TAG, "Kiosk mode started successfully")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error starting kiosk mode: ${e.message}", e)
            result.error("KIOSK_START_FAILED", e.message, null)
        }
    }

    private fun handleStopKiosk(result: MethodChannel.Result) {
        Log.i(TAG, "Stopping kiosk mode - attempting ROBUST exit")
        try {
            setExitRequested(this, true)

            // METHOD 1: Try to stop lock task if device owner
            if (isDeviceOwner()) {
                try {
                    stopLockTask()
                    Log.i(TAG, "Lock task stopped successfully")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to stop lock task: ${e.message}")
                }
            } else {
                Log.w(TAG, "Not device owner - using fallback exit method")
            }

            // METHOD 2: Clear lock task packages to allow other apps to show
            try {
                devicePolicyManager.setLockTaskPackages(adminComponent, arrayOf())
                Log.d(TAG, "Lock task packages cleared")
            } catch (e: Exception) {
                Log.d(TAG, "Could not clear lock task packages: ${e.message}")
            }

            // METHOD 3: Clear kiosk restrictions so admin can manage the device
            clearKioskRestrictions()

            // METHOD 4: Hide immersive mode to allow user to see system UI
            try {
                showSystemUI()
                Log.d(TAG, "System UI visibility reset")
            } catch (e: Exception) {
                Log.d(TAG, "Could not reset system UI: ${e.message}")
            }

            // METHOD 5: Force app exit
            Log.i(TAG, "Force exiting app via finishAffinity()")
            moveTaskToBack(true)
            finishAffinity()
            
            Log.i(TAG, "Kiosk mode stopped - app finished")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping kiosk mode: ${e.message}", e)
            result.error("KIOSK_STOP_FAILED", e.message, null)
        }
    }

    private fun handleInstallUpdateApk(result: MethodChannel.Result) {
        Log.i(TAG, "Starting admin-managed APK update flow")

        if (pendingUpdateResult != null) {
            result.error("UPDATE_IN_PROGRESS", "An APK update flow is already running", null)
            return
        }

        try {
            prepareForAdminExternalAction()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            ) {
                Log.w(TAG, "Unknown app installs not yet allowed for this app")
                val settingsIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(settingsIntent)
                result.error(
                    "INSTALL_PERMISSION_REQUIRED",
                    "Allow installs from this app, then try again",
                    null
                )
                return
            }

            pendingUpdateResult = result
            val pickIntent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/vnd.android.package-archive"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            }
            startActivityForResult(pickIntent, REQUEST_CODE_PICK_UPDATE_APK)
        } catch (e: ActivityNotFoundException) {
            Log.e(TAG, "No document picker available for APK selection", e)
            result.error("APK_PICKER_UNAVAILABLE", e.message, null)
        } catch (e: Exception) {
            Log.e(TAG, "Error starting APK update flow: ${e.message}", e)
            result.error("APK_UPDATE_FAILED", e.message, null)
        }
    }

    private fun handleSelectedUpdateApk(uri: Uri?) {
        val result = pendingUpdateResult
        pendingUpdateResult = null

        if (result == null) {
            Log.w(TAG, "APK picker returned without a pending Flutter result")
            return
        }

        if (uri == null) {
            Log.i(TAG, "Admin cancelled APK selection")
            result.success(false)
            return
        }

        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: SecurityException) {
            Log.d(TAG, "Persistable URI permission not granted for selected APK")
        }

        try {
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            startActivity(installIntent)
            Log.i(TAG, "System package installer launched for selected APK")
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            Log.e(TAG, "No package installer available to open selected APK", e)
            result.error("INSTALLER_UNAVAILABLE", e.message, null)
        } catch (e: Exception) {
            Log.e(TAG, "Error launching package installer: ${e.message}", e)
            result.error("INSTALLER_LAUNCH_FAILED", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != REQUEST_CODE_PICK_UPDATE_APK) {
            return
        }

        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        handleSelectedUpdateApk(uri)
    }

    private fun prepareForAdminExternalAction() {
        setExitRequested(this, true)

        try {
            if (isDeviceOwner()) {
                stopLockTask()
                Log.i(TAG, "Lock task stopped for admin external action")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Unable to stop lock task for admin action: ${e.message}")
        }

        try {
            allowLockTaskPackages(
                packageName,
                getSystemDialerPackage(),
                getSystemPhonePackage(),
                "com.android.documentsui",
                "com.google.android.documentsui",
                "com.android.packageinstaller",
                "com.google.android.packageinstaller",
                "com.android.permissioncontroller",
                "com.google.android.permissioncontroller",
                "com.android.settings"
            )
        } catch (e: Exception) {
            Log.w(TAG, "Unable to expand allowed admin packages: ${e.message}")
        }

        clearKioskRestrictions()
        showSystemUI()
    }

    private fun isDeviceOwner(): Boolean {
        val isOwner = devicePolicyManager.isDeviceOwnerApp(packageName)
        Log.d(TAG, "Device owner check: $isOwner")
        return isOwner
    }

    /// ========================================================================
    /// App Launching Methods
    /// ========================================================================

    private fun handleLaunchApp(call: MethodCall, result: MethodChannel.Result) {
        try {
            val packageName = call.argument<String>("packageName")
                ?: throw IllegalArgumentException("packageName is required")

            Log.i(TAG, "=== LAUNCHING APP: $packageName ===")

            // STEP 1: Verify package is installed
            val packageInfo = try {
                packageManager.getPackageInfo(packageName, 0)
            } catch (e: PackageManager.NameNotFoundException) {
                Log.e(TAG, "ERROR: Package NOT installed: $packageName")
                result.error("APP_NOT_INSTALLED", "Package not found: $packageName", null)
                return
            }

            Log.d(TAG, "✓ Package installed: $packageName")

            // STEP 2: Try direct launch intent (most reliable for Android 15)
            try {
                val intent = packageManager.getLaunchIntentForPackage(packageName)
                if (intent != null) {
                    Log.d(TAG, "✓ Got launch intent via getLaunchIntentForPackage")
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    
                    allowLockTaskPackages(packageName)
                    
                    try {
                        startActivity(intent)
                        Log.i(TAG, "✓✓✓ APP LAUNCHED SUCCESSFULLY: $packageName")
                        result.success(true)
                        return
                    } catch (e: Exception) {
                        Log.e(TAG, "ERROR launching via intent: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "ERROR getting launch intent: ${e.message}")
            }

            // STEP 3: Fallback - Try creating explicit component intent
            Log.d(TAG, "Fallback: Trying explicit component intent...")
            try {
                // Query for the main activity
                val intent = Intent(Intent.ACTION_MAIN).apply {
                    setPackage(packageName)
                    addCategory(Intent.CATEGORY_LAUNCHER)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }

                val resolveInfo = packageManager.resolveActivity(intent, 0)
                if (resolveInfo != null && resolveInfo.activityInfo != null) {
                    Log.d(TAG, "✓ Found activity: ${resolveInfo.activityInfo.name}")
                    
                    val explicitIntent = Intent().apply {
                        setClassName(packageName, resolveInfo.activityInfo.name)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    }

                    allowLockTaskPackages(packageName)
                    
                    try {
                        startActivity(explicitIntent)
                        Log.i(TAG, "✓✓✓ APP LAUNCHED (explicit): $packageName")
                        result.success(true)
                        return
                    } catch (e: Exception) {
                        Log.e(TAG, "ERROR with explicit intent: ${e.message}")
                    }
                } else {
                    Log.e(TAG, "ERROR: No activity found for $packageName")
                }
            } catch (e: Exception) {
                Log.e(TAG, "ERROR in explicit component fallback: ${e.message}")
            }

            // STEP 4: Final error
            Log.e(TAG, "FAILED: Could not launch $packageName")
            result.error("LAUNCH_FAILED", "Failed to launch app: $packageName", null)

        } catch (e: Exception) {
            Log.e(TAG, "ERROR in handleLaunchApp: ${e.message}", e)
            result.error("LAUNCH_ERROR", e.message, null)
        }
    }

    /// Auto-detect package by app label (name)
    private fun findPackageByLabel(label: String): String? {
        try {
            val launcherIntent = Intent(Intent.ACTION_MAIN, null).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            
            val activities = packageManager.queryIntentActivities(
                launcherIntent,
                PackageManager.MATCH_ALL
            )
            
            val labelLower = label.lowercase()
            
            // First try: exact match
            for (activity in activities) {
                val appLabel = activity.loadLabel(packageManager)?.toString()?.lowercase() ?: ""
                val pkgName = activity.activityInfo.packageName
                if (appLabel == labelLower || pkgName.lowercase().contains(labelLower)) {
                    Log.d(TAG, "Found exact match: $pkgName ($appLabel)")
                    return pkgName
                }
            }
            
            // Second try: partial match
            for (activity in activities) {
                val appLabel = activity.loadLabel(packageManager)?.toString()?.lowercase() ?: ""
                val pkgName = activity.activityInfo.packageName.lowercase()
                if (appLabel.contains(labelLower) || pkgName.contains(labelLower)) {
                    Log.d(TAG, "Found partial match: $pkgName ($appLabel)")
                    return activity.activityInfo.packageName
                }
            }
            
            Log.d(TAG, "No package found for label: $label")
            return null
        } catch (e: Exception) {
            Log.e(TAG, "Error finding package by label: ${e.message}")
            return null
        }
    }

    private fun handleOpenDialer(call: MethodCall, result: MethodChannel.Result) {
        try {
            val number = call.argument<String>("number")
                ?: throw IllegalArgumentException("number is required")

            if (number.isEmpty()) {
                throw IllegalArgumentException("Phone number cannot be empty")
            }

            Log.i(TAG, "Opening dialer for: $number")

            // Get system phone app packages
            val systemDialer = getSystemDialerPackage()
            val systemPhone = getSystemPhonePackage()
            val telecomPackage = "com.android.server.telecom"
            
            Log.d(TAG, "System dialer: $systemDialer, System phone: $systemPhone")
            
            // Whitelist system phone apps in lock task
            allowLockTaskPackages(systemDialer, systemPhone, telecomPackage)

            // Build intents in order of preference. Use ACTION_DIAL only so we
            // do not depend on CALL_PHONE being granted on managed devices.
            val intents = listOf(
                Intent(Intent.ACTION_DIAL).apply {
                    data = Uri.parse("tel:$number")
                    `package` = systemDialer
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    Log.d(TAG, "Built explicit ACTION_DIAL intent for $systemDialer")
                },
                Intent(Intent.ACTION_DIAL).apply {
                    data = Uri.parse("tel:$number")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    Log.d(TAG, "Built implicit ACTION_DIAL intent")
                },
                Intent("com.android.phone.action.TOUCH_DIALER").apply {
                    data = Uri.parse("tel:$number")
                    `package` = systemDialer
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    Log.d(TAG, "Built TOUCH_DIALER intent for $systemDialer")
                }
            )

            for (intent in intents) {
                try {
                    val resolvedActivity = intent.resolveActivity(packageManager)
                    if (resolvedActivity != null) {
                        Log.d(TAG, "Resolved activity: ${resolvedActivity.packageName}, action: ${intent.action}")
                        allowLockTaskPackages(
                            resolvedActivity.packageName,
                            systemDialer,
                            systemPhone,
                            telecomPackage
                        )
                        startActivity(intent)
                        Log.i(TAG, "Dialer opened successfully with action: ${intent.action}")
                        result.success(true)
                        return
                    }
                } catch (e: ActivityNotFoundException) {
                    Log.d(TAG, "ActivityNotFoundException (${intent.action}): ${e.message}")
                } catch (e: Exception) {
                    Log.d(TAG, "Exception (${intent.action}): ${e.message}")
                }
            }

            // Fallback: Try to open system dialer directly
            Log.d(TAG, "Trying fallback: system dialer direct launch")
            try {
                val launchIntent = packageManager.getLaunchIntentForPackage(systemDialer)
                if (launchIntent != null) {
                    launchIntent.data = Uri.parse("tel:$number")
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    allowLockTaskPackages(systemDialer, systemPhone, telecomPackage)
                    startActivity(launchIntent)
                    Log.i(TAG, "System dialer ($systemDialer) opened successfully")
                    result.success(true)
                    return
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error launching system dialer ($systemDialer): ${e.message}")
            }

            // All attempts failed
            Log.e(TAG, "All dialer launch attempts failed")
            val errorMsg = "No dialer application available. Tried: $systemDialer, $systemPhone"
            result.error("DIALER_ERROR", errorMsg, null)
        } catch (e: Exception) {
            Log.e(TAG, "Error opening dialer: ${e.message}", e)
            result.error("DIALER_ERROR", e.message, null)
        }
    }

    private fun allowLockTaskPackages(vararg packages: String) {
        if (!isDeviceOwner()) {
            Log.d(TAG, "Not device owner - skipping lock task package whitelist")
            return
        }

        val normalizedPackages = (listOf(packageName) + packages.toList())
            .filter { it.isNotBlank() }
            .distinct()
            .toTypedArray()

        if (normalizedPackages.isEmpty()) {
            Log.d(TAG, "No packages to add to lock task whitelist")
            return
        }

        try {
            devicePolicyManager.setLockTaskPackages(adminComponent, normalizedPackages)
            Log.d(TAG, "Updated lock task packages (${normalizedPackages.size}): ${normalizedPackages.joinToString()}")
        } catch (e: IllegalArgumentException) {
            Log.e(TAG, "Invalid lock task packages configuration: ${e.message}", e)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update lock task packages: ${e.message}", e)
        }
    }

    private fun launchAdminExitDestination() {
        val settingsIntent = Intent(Settings.ACTION_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(settingsIntent)
    }

    private fun resolveLaunchTarget(
        packageName: String,
        appLabel: String?
    ): Pair<Intent, String>? {
        // METHOD 1: Direct getLaunchIntentForPackage (most reliable)
        packageManager.getLaunchIntentForPackage(packageName)?.let {
            Log.d(TAG, "Got direct launch intent for: $packageName")
            return Pair(it, packageName)
        }
        
        Log.d(TAG, "Direct launch intent failed for: $packageName - trying alternatives")

        // METHOD 2: Query all activities and find LAUNCHER category
        val targetLabel = appLabel?.trim()?.lowercase()
        val launcherIntent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }

        val activities = packageManager.queryIntentActivities(
            launcherIntent,
            PackageManager.MATCH_ALL
        )
        
        Log.d(TAG, "Found ${activities.size} launcher activities")

        val fallbackMatch = activities.firstOrNull { resolveInfo ->
            val resolvedPackage = resolveInfo.activityInfo?.packageName.orEmpty()
            val resolvedLabel = resolveInfo.loadLabel(packageManager)?.toString()?.lowercase().orEmpty()
            
            Log.d(TAG, "Checking: $resolvedPackage ($resolvedLabel) vs target: $packageName")

            resolvedPackage == packageName ||
                resolvedPackage.contains(packageName.lowercase()) ||
                (targetLabel != null && resolvedLabel.contains(targetLabel))
        }
        
        if (fallbackMatch != null) {
            Log.d(TAG, "Found fallback match: ${fallbackMatch.activityInfo.packageName}")
            val resolvedPackage = fallbackMatch.activityInfo.packageName
            val intent = packageManager.getLaunchIntentForPackage(resolvedPackage)
            if (intent != null) {
                return Pair(intent, resolvedPackage)
            }
        }
        
        // METHOD 3: Brute force - try to create implicit intent
        Log.d(TAG, "Trying implicit intent approach for: $packageName")
        try {
            val implicitIntent = Intent(Intent.ACTION_MAIN).apply {
                setPackage(packageName)
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            
            val resolveInfo = packageManager.resolveActivity(implicitIntent, 0)
            if (resolveInfo?.activityInfo != null) {
                Log.d(TAG, "Resolved via implicit intent: $packageName")
                val intent = Intent(Intent.ACTION_MAIN).apply {
                    setClassName(packageName, resolveInfo.activityInfo.name)
                }
                return Pair(intent, packageName)
            }
        } catch (e: Exception) {
            Log.d(TAG, "Implicit intent failed: ${e.message}")
        }
        
        Log.w(TAG, "Could not resolve launch target for: $packageName")
        return null
    }

    /// ========================================================================
    /// Device Restrictions - Lockdown Settings
    /// ========================================================================
    /// These restrictions prevent users from:
    /// - Installing/uninstalling apps
    /// - Accessing safe boot or recovery
    /// - Factory reset
    /// - USB file transfer
    /// - SMS/texting
    /// - Developer options
    ///
    /// IMPORTANT: These require Device Owner mode to take effect
    private fun applyKioskRestrictions() {
        if (!isDeviceOwner()) {
            Log.w(TAG, "Not device owner - cannot apply restrictions")
            return
        }

        Log.i(TAG, "Applying kiosk restrictions")

        try {
            // Disable safe boot - prevents booting into recovery
            devicePolicyManager.addUserRestriction(
                adminComponent,
                "no_safe_boot" // android.os.UserManager.DISALLOW_SAFE_BOOT
            )

            // Disable factory reset from settings
            devicePolicyManager.addUserRestriction(
                adminComponent,
                "no_factory_reset" // android.os.UserManager.DISALLOW_FACTORY_RESET
            )

            // Block app installation
            devicePolicyManager.addUserRestriction(
                adminComponent,
                "no_install_apps" // android.os.UserManager.DISALLOW_INSTALL_APPS
            )

            // Block app uninstallation
            devicePolicyManager.addUserRestriction(
                adminComponent,
                "no_uninstall_apps" // android.os.UserManager.DISALLOW_UNINSTALL_APPS
            )

            // Disable USB file transfer (allow charging only)
            devicePolicyManager.addUserRestriction(
                adminComponent,
                "no_usb_file_transfer" // android.os.UserManager.DISALLOW_USB_FILE_TRANSFER
            )

            // Disable SMS - prevent messaging
            devicePolicyManager.addUserRestriction(
                adminComponent,
                "no_sms" // android.os.UserManager.DISALLOW_SMS
            )

            // Disable development settings
            devicePolicyManager.setGlobalSetting(
                adminComponent,
                Settings.Global.DEVELOPMENT_SETTINGS_ENABLED,
                "0"
            )

            // Disable ADB (Android Debug Bridge)
            devicePolicyManager.setGlobalSetting(
                adminComponent,
                Settings.Global.ADB_ENABLED,
                "0"
            )

            Log.i(TAG, "Kiosk restrictions applied successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error applying restrictions: ${e.message}", e)
        }
    }

    private fun clearKioskRestrictions() {
        if (!isDeviceOwner()) {
            Log.w(TAG, "Not device owner - cannot clear restrictions")
            return
        }

        Log.i(TAG, "Clearing kiosk restrictions for admin exit")

        try {
            devicePolicyManager.clearUserRestriction(adminComponent, "no_safe_boot")
            devicePolicyManager.clearUserRestriction(adminComponent, "no_factory_reset")
            devicePolicyManager.clearUserRestriction(adminComponent, "no_install_apps")
            devicePolicyManager.clearUserRestriction(adminComponent, "no_uninstall_apps")
            devicePolicyManager.clearUserRestriction(adminComponent, "no_usb_file_transfer")
            devicePolicyManager.clearUserRestriction(adminComponent, "no_sms")

            devicePolicyManager.setGlobalSetting(
                adminComponent,
                Settings.Global.DEVELOPMENT_SETTINGS_ENABLED,
                "1"
            )

            devicePolicyManager.setGlobalSetting(
                adminComponent,
                Settings.Global.ADB_ENABLED,
                "1"
            )

            Log.i(TAG, "Kiosk restrictions cleared successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing restrictions: ${e.message}", e)
        }
    }

    /// ========================================================================
    /// Device Information
    /// ========================================================================
    private fun getDeviceInfo(): Map<String, String> {
        return mapOf(
            "device" to Build.DEVICE,
            "model" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "android_version" to Build.VERSION.RELEASE,
            "sdk_int" to Build.VERSION.SDK_INT.toString(),
            "is_device_owner" to isDeviceOwner().toString()
        )
    }

    /// ========================================================================
    /// System App Package Resolution
    /// ========================================================================
    
    private fun getSystemDialerPackage(): String {
        val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val defaultDialer = telecomManager.defaultDialerPackage
        if (!defaultDialer.isNullOrBlank()) {
            Log.d(TAG, "Default dialer: $defaultDialer")
            return defaultDialer
        }
        
        // Fallback to common dialer packages
        val commonDialers = listOf(
            "com.android.dialer",
            "com.google.android.dialer",
            "com.samsung.android.dialer",
            "com.htc.android.phone"
        )
        
        for (pkgName in commonDialers) {
            try {
                packageManager.getPackageInfo(pkgName, 0)
                Log.d(TAG, "Found dialer: $pkgName")
                return pkgName
            } catch (e: Exception) {
                // Package not found, continue
            }
        }
        
        Log.w(TAG, "No system dialer found, using com.android.dialer as fallback")
        return "com.android.dialer"
    }
    
    private fun getSystemPhonePackage(): String {
        val commonPhonePackages = listOf(
            "com.android.phone",
            "com.samsung.android.phone",
            "com.htc.android.phone"
        )
        
        for (pkgName in commonPhonePackages) {
            try {
                packageManager.getPackageInfo(pkgName, 0)
                Log.d(TAG, "Found phone package: $pkgName")
                return pkgName
            } catch (e: Exception) {
                // Package not found, continue
            }
        }
        
        Log.w(TAG, "No system phone package found")
        return "com.android.phone"
    }
}
