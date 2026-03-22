package com.fynko.infinitykiosk

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log

/// ============================================================================
/// BootReceiver - Ultra-Fast Auto-Launch on Device Boot
/// ============================================================================
/// Listens for device boot events and launches kiosk immediately
///
/// Supported boot broadcasts:
/// - android.intent.action.BOOT_COMPLETED (standard Android boot)
/// - android.intent.action.QUICKBOOT_POWERON (HTC/Sense devices)
///
/// KEY SECURITY FEATURES:
/// 1. Highest priority (1000) ensures we run first
/// 2. Acquires wake lock to ensure device is fully awake
/// 3. Uses aggressive activity flags for instant launch
/// 4. Skips animations to reach kiosk screen faster
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.i(TAG, "Boot broadcast received: ${intent.action}")

        // Check if this is a boot-related action
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON"
        ) {
            Log.i(TAG, "🚀 Device boot completed - IMMEDIATELY launching kiosk...")

            try {
                // Acquire wake lock to ensure device is awake
                val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                val wakeLock = pm.newWakeLock(
                    PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "InfinityKiosk:BootWakeLock"
                )
                wakeLock.acquire(3000) // Hold for 3 seconds max
                Log.i(TAG, "Wake lock acquired")

                // Create intent to launch main kiosk activity with aggressive flags
                val launch = Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)           // Launch as new task
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)          // Clear activity stack
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)         // Single instance
                    addFlags(Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED) // Fresh task
                    addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)       // Skip animations
                    addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)   // Bring to front immediately
                }

                context.startActivity(launch)
                Log.i(TAG, "✓✓✓ KIOSK APP LAUNCHED IMMEDIATELY ON BOOT")
            } catch (e: Exception) {
                Log.e(TAG, "Error launching app on boot: ${e.message}", e)
            } catch (e: Exception) {
                Log.e(TAG, "Error launching app on boot: ${e.message}", e)
            }
        } else {
            Log.d(TAG, "Ignoring non-boot broadcast: ${intent.action}")
        }
    }
}
