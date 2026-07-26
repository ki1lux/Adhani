package com.example.myadhan

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.work.*
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * Native CoroutineWorker that runs every ~24 hours (starting at 00:05 midnight).
 *
 * Flow:
 *   1. Read cached lat/lng from FlutterSharedPreferences
 *   2. Fetch today's prayer times from Aladhan API
 *   3. Save prayer names, display times, and trigger timestamps to SharedPreferences
 *      (same keys the existing native code expects)
 *   4. Call AlarmSchedulerHelper.rescheduleAllFromPrefs() — the critical fix
 *   5. Refresh the PrayerCountdownService
 *
 * On network failure: still reschedules from cached prefs, then returns Result.retry().
 */
class PrayerUpdateWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    companion object {
        private const val TAG = "PrayerUpdateWorker"
        private const val UNIQUE_WORK_NAME = "daily_prayer_update"
        private const val PREFS_NAME = "FlutterSharedPreferences"

        private val PRAYER_MAP = listOf(
            PrayerInfo(1, "الفجر", "fajr"),
            PrayerInfo(2, "الظهر", "dhuhr"),
            PrayerInfo(3, "العصر", "asr"),
            PrayerInfo(4, "المغرب", "maghrib"),
            PrayerInfo(5, "العشاء", "isha"),
        )

        /**
         * Enqueue the daily periodic worker.
         * Uses ExistingPeriodicWorkPolicy.KEEP — won't replace if already registered.
         */
        fun enqueue(context: Context) {
            val delay = calculateDelayUntilMidnight()

            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val request = PeriodicWorkRequestBuilder<PrayerUpdateWorker>(
                24, TimeUnit.HOURS
            )
                .setInitialDelay(delay, TimeUnit.MILLISECONDS)
                .setConstraints(constraints)
                .addTag(UNIQUE_WORK_NAME)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )

            Log.d(TAG, "📅 Daily prayer worker enqueued (delay=${delay / 1000}s)")
        }

        /** Milliseconds until next 00:05 */
        private fun calculateDelayUntilMidnight(): Long {
            val now = Calendar.getInstance()
            val midnight = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 5)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            return midnight.timeInMillis - now.timeInMillis
        }
    }

    private data class PrayerInfo(val id: Int, val arabicName: String, val apiField: String)

    override suspend fun doWork(): Result {
        Log.d(TAG, "🔄 Worker started")

        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val lat = getDouble(prefs, "flutter.last_latitude")
        val lng = getDouble(prefs, "flutter.last_longitude")

        if (lat == null || lng == null) {
            Log.w(TAG, "❌ No stored location, rescheduling from cached prefs")
            AlarmSchedulerHelper.rescheduleAllFromPrefs(applicationContext)
            PrayerCountdownService.startIfNeeded(applicationContext)
            return Result.success()
        }

        // Read user's preferred calculation method (default: 19 = Algeria)
        val method = prefs.getInt("flutter.calculation_method", 19)

        // Determine if we are past today's Isha (+ 35m). If so, fetch tomorrow's data.
        var targetDate: java.util.Date? = null
        val ishaTimeStr = prefs.getString("flutter.prayer_5_time", null)
        if (ishaTimeStr != null) {
            try {
                val parts = ishaTimeStr.split(" ")[0].split(":")
                val nowCal = Calendar.getInstance()
                val ishaCal = Calendar.getInstance().apply {
                    set(Calendar.HOUR_OF_DAY, parts[0].toInt())
                    set(Calendar.MINUTE, parts[1].toInt())
                }
                ishaCal.add(Calendar.MINUTE, 35)

                if (nowCal.timeInMillis > ishaCal.timeInMillis) {
                    nowCal.add(Calendar.DAY_OF_YEAR, 1)
                    targetDate = nowCal.time
                }
            } catch (e: Exception) {}
        }

        // Attempt API fetch
        val response = AladhanApiClient.fetchPrayerTimes(lat, lng, method = method, date = targetDate)

        if (response == null) {
            // Network failure — still reschedule from whatever is cached
            Log.w(TAG, "⚠️ API fetch failed, rescheduling from cached prefs")
            AlarmSchedulerHelper.rescheduleAllFromPrefs(applicationContext)
            PrayerCountdownService.startIfNeeded(applicationContext)
            return Result.retry()
        }

        // Save prayer times to SharedPreferences
        savePrayerTimes(prefs, response)

        // THE FIX: directly call native rescheduling
        AlarmSchedulerHelper.rescheduleAllFromPrefs(applicationContext)

        // Refresh countdown notification
        PrayerCountdownService.startIfNeeded(applicationContext)

        // Notify Home Screen Widget to update
        val intent = android.content.Intent("com.example.myadhan.ACTION_PRAYER_UPDATED")
        intent.setPackage(applicationContext.packageName)
        applicationContext.sendBroadcast(intent)

        Log.d(TAG, "✅ Prayer times updated and alarms rescheduled")
        return Result.success()
    }

    private fun savePrayerTimes(prefs: SharedPreferences, response: AladhanApiClient.PrayerTimesResponse) {
        val editor = prefs.edit()
        val now = System.currentTimeMillis()

        val timeMap = mapOf(
            "fajr" to response.fajr,
            "dhuhr" to response.dhuhr,
            "asr" to response.asr,
            "maghrib" to response.maghrib,
            "isha" to response.isha,
        )

        for (prayer in PRAYER_MAP) {
            val timeStr = timeMap[prayer.apiField] ?: continue

            // Parse "HH:mm" → epoch millis for today
            val parts = timeStr.split(":")
            if (parts.size != 2) continue
            val hour = parts[0].toIntOrNull() ?: continue
            val minute = parts[1].toIntOrNull() ?: continue

            val cal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            // If prayer time has passed today, schedule for tomorrow
            if (cal.timeInMillis <= now) {
                cal.add(Calendar.DAY_OF_YEAR, 1)
            }

            // Always store name/time/trigger, even if adhan is disabled for this prayer —
            // the widget still needs to display and track it. AlarmSchedulerHelper is what
            // decides whether to actually arm the sound alarm based on the enabled flag.
            editor.putString("flutter.prayer_${prayer.id}_name", prayer.arabicName)
            editor.putString("flutter.prayer_${prayer.id}_time", timeStr)
            editor.putLong("flutter.prayer_${prayer.id}_trigger_millis", cal.timeInMillis)

            Log.d(TAG, "💾 ${prayer.arabicName}: $timeStr → trigger at ${cal.timeInMillis}")
        }

        // Update Hijri date
        if (response.hijriDate.isNotEmpty()) {
            editor.putString("flutter.cached_hijri_date", response.hijriDate)
            Log.d(TAG, "📅 Hijri: ${response.hijriDate}")
        }

        // Mark last update time
        editor.putString("flutter.last_prayer_update", java.text.SimpleDateFormat(
            "yyyy-MM-dd'T'HH:mm:ss.SSS", java.util.Locale.US
        ).format(java.util.Date()))

        editor.apply()
    }

    /**
     * Flutter's SharedPreferences stores doubles as Strings with a specific prefix
     * in newer versions (2.4.15+), or as raw long bits in older versions.
     */
    private fun getDouble(prefs: SharedPreferences, key: String): Double? {
        if (!prefs.contains(key)) return null

        // Try the new String format first (prefix: "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu")
        try {
            val strVal = prefs.getString(key, null)
            if (strVal != null && strVal.startsWith("VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu")) {
                val numStr = strVal.removePrefix("VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu")
                return numStr.toDoubleOrNull()
            }
        } catch (e: ClassCastException) {
            // It's not a String, fallback to the old Long format below
        }

        // Try the old Long format (raw bits)
        return try {
            val raw = prefs.getLong(key, 0L)
            if (raw == 0L) null else java.lang.Double.longBitsToDouble(raw)
        } catch (e: Exception) {
            // Fallback: try reading as float (shouldn't happen, but defensive)
            try {
                prefs.getFloat(key, Float.MIN_VALUE).toDouble().takeIf { it != Float.MIN_VALUE.toDouble() }
            } catch (e2: Exception) {
                null
            }
        }
    }
}
