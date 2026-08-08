package com.ki1lux.adhani

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log

/**
 * BroadcastReceiver that is triggered by AlarmManager when prayer time arrives.
 * This works even when the app is killed since it's registered in AndroidManifest.xml.
 * It reads prayer info + sound preference from SharedPreferences and starts AdhanAlarmService.
 */
class PrayerAlarmReceiver : BroadcastReceiver() {
    
    companion object {
        const val TAG = "PrayerAlarmReceiver"
        const val EXTRA_PRAYER_ID = "prayer_id"
        const val PREFS_NAME = "FlutterSharedPreferences"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "onReceive called!")
        
        val prayerId = intent.getIntExtra(EXTRA_PRAYER_ID, 0)
        Log.d(TAG, "Prayer ID: $prayerId")

        // Re-arm immediately, before anything else can fail or return early.
        //
        // AlarmManager alarms are one-shot. Nothing here used to re-arm them,
        // so the five alarms set for a given day were simply consumed by it —
        // and with the daily worker unable to run offline, the second offline
        // day had no alarms at all and the adhan went silent. Rescheduling from
        // prefs on every fire means the alarms perpetuate themselves with no
        // network and no daily job. It covers all five prayers, so it must run
        // before the per-prayer `isEnabled` early-return below.
        try {
            AlarmSchedulerHelper.rescheduleAllFromPrefs(context)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to re-arm alarms: ${e.message}")
        }

        // Get prayer info from SharedPreferences (Flutter stores with 'flutter.' prefix)
        val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val prayerName = prefs.getString("flutter.prayer_${prayerId}_name", "الصلاة") ?: "الصلاة"
        val prayerTime = prefs.getString("flutter.prayer_${prayerId}_time", "") ?: ""
        
        // Get the user's selected sound for this prayer
        val soundName = prefs.getString("flutter.adhan_sound_$prayerName", "adhan1") ?: "adhan1"
        
        // Check if adhan is enabled for this prayer
        val isEnabled = prefs.getBoolean("flutter.adhan_enabled_$prayerName", true)
        if (!isEnabled) {
            Log.d(TAG, "Adhan disabled for $prayerName, skipping")
            return
        }

        // Vibrate instead of playing the Adhan.
        //
        // Two independent keys rather than one three-valued one, because
        // `adhan_enabled_*` already gates alarm *scheduling* in
        // AlarmSchedulerHelper — folding "vibrate" into it would have meant
        // either no alarm being armed (so nothing to vibrate) or teaching the
        // scheduler a third state it doesn't otherwise care about. It also
        // keeps the pref backward compatible: an install that predates this
        // has no `adhan_vibrate_*` key, defaults to false, and behaves
        // exactly as it did. Mirrors `_AdhanAlertMode` in
        // lib/view/PrayerTimeScreen.dart — see CLAUDE.md on this contract.
        val vibrateOnly = prefs.getBoolean("flutter.adhan_vibrate_$prayerName", false)
        if (vibrateOnly) {
            Log.d(TAG, "Vibrate mode for $prayerName — buzzing instead of playing")
            AdhanVibrator.alert(context, prayerName, prayerTime)
            PrayerCountdownService.startIfNeeded(context)
            return
        }

        Log.d(TAG, "Prayer: $prayerName, Time: $prayerTime, Sound: $soundName")

        // Start the AdhanAlarmService which plays audio + shows notification
        val serviceIntent = Intent(context, AdhanAlarmService::class.java).apply {
            putExtra("prayerName", prayerName)
            putExtra("prayerTime", prayerTime)
            putExtra("soundName", soundName)
        }
        
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                Log.d(TAG, "Starting foreground service...")
                context.startForegroundService(serviceIntent)
            } else {
                Log.d(TAG, "Starting service...")
                context.startService(serviceIntent)
            }
            Log.d(TAG, "Service started successfully")
            // Also ensure countdown service is running
            PrayerCountdownService.startIfNeeded(context)
        } catch (e: Exception) {
            Log.e(TAG, "Error starting service: ${e.message}")
            e.printStackTrace()
        }
    }
}
