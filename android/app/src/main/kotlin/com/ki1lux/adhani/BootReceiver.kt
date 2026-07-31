package com.ki1lux.adhani

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Re-schedules all prayer alarms after device reboot or app update.
 * Reads cached prayer trigger timestamps from SharedPreferences
 * and calls AlarmManager.setAlarmClock() for each enabled prayer.
 *
 * Registered in AndroidManifest.xml for:
 * - BOOT_COMPLETED
 * - MY_PACKAGE_REPLACED
 * - QUICKBOOT_POWERON (HTC/custom ROMs)
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return

        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> {
                Log.d(TAG, "Received $action — rescheduling all prayer alarms")
                AlarmSchedulerHelper.rescheduleAllFromPrefs(context)
                // Also restart the countdown notification
                PrayerCountdownService.startIfNeeded(context)
            }
            else -> {
                Log.d(TAG, "Ignoring action: $action")
            }
        }
    }
}
