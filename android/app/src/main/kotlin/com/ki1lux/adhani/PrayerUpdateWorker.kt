package com.ki1lux.adhani

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.work.*
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * Native CoroutineWorker that runs every ~24 hours (starting at 00:05 midnight).
 *
 * Flow, cache first:
 *   1. Read cached lat/lng from FlutterSharedPreferences
 *   2. Satisfy today from [PrayerMonthCache] and arm everything from it
 *   3. Only then go to the network, to extend the cache for future days
 *   4. Call AlarmSchedulerHelper.rescheduleAllFromPrefs()
 *   5. Refresh the PrayerCountdownService
 *
 * The order matters. This used to fetch first and treat the cache as a failure
 * path — and that path was unreachable anyway, because the worker required
 * NetworkType.CONNECTED and so simply never ran with no connection. The result
 * was that adhan alarms went silent from the second offline day. Doing the
 * local work first means a device that never sees the network again still arms
 * correct alarms every day for as long as the cache has days left.
 */
class PrayerUpdateWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    companion object {
        private const val TAG = "PrayerUpdateWorker"
        private const val UNIQUE_WORK_NAME = "daily_prayer_update"
        private const val PREFS_NAME = "FlutterSharedPreferences"

        private const val DAY_MS = 24 * 60 * 60 * 1000L

        /**
         * Below this much remaining coverage we top the cache up, so a month
         * boundary never arrives with nothing on the other side of it.
         * Matches `PrayerTimesNotifier._coverageFloorDays` on the Dart side.
         */
        private const val COVERAGE_FLOOR_DAYS = 7

        private val PRAYER_MAP = listOf(
            PrayerInfo(1, "الفجر", "fajr"),
            PrayerInfo(2, "الظهر", "dhuhr"),
            PrayerInfo(3, "العصر", "asr"),
            PrayerInfo(4, "المغرب", "maghrib"),
            PrayerInfo(5, "العشاء", "isha"),
        )

        /**
         * Enqueue the daily periodic worker.
         *
         * Deliberately **unconstrained**. Requiring NetworkType.CONNECTED meant
         * the job never ran on an offline device — which is precisely the
         * device that most needs its alarms re-armed from cached data each day.
         * doWork() now does its local work unconditionally and simply skips the
         * network leg when the fetch fails.
         *
         * Uses ExistingPeriodicWorkPolicy.UPDATE, not KEEP: with KEEP, this
         * constraint change would never reach anyone who already has the app
         * installed, since their work request is already registered.
         */
        fun enqueue(context: Context) {
            val delay = calculateDelayUntilMidnight()

            val request = PeriodicWorkRequestBuilder<PrayerUpdateWorker>(
                24, TimeUnit.HOURS
            )
                .setInitialDelay(delay, TimeUnit.MILLISECONDS)
                .addTag(UNIQUE_WORK_NAME)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request
            )

            Log.d(TAG, "📅 Daily prayer worker enqueued (delay=${delay / 1000}s)")
        }

        /**
         * Milliseconds until the *next* 00:05 — today's if it hasn't happened
         * yet, otherwise tomorrow's. This unconditionally targeted tomorrow,
         * so a first run at 00:03 waited nearly 24 hours instead of two minutes.
         */
        private fun calculateDelayUntilMidnight(): Long {
            val now = Calendar.getInstance()
            val midnight = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 5)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            if (midnight.timeInMillis <= now.timeInMillis) {
                midnight.add(Calendar.DAY_OF_YEAR, 1)
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

        // Determine if we are past today's Isha (+ 35m). If so, target tomorrow.
        val targetCal = resolveTargetDay(prefs)
        val targetDate = targetCal.time

        // ── 1. Local first ───────────────────────────────────────────────
        // Whatever happens on the network below, arm today from the cache now.
        // This is the step that keeps the app alive offline.
        var cache = PrayerMonthCache.read(prefs)
        var satisfiedLocally = false
        cache?.dayFor(targetDate)?.let { day ->
            saveDay(prefs, day, targetCal)
            satisfiedLocally = true
            Log.d(TAG, "💾 Armed ${PrayerMonthCache.dayKey(targetDate)} from month cache")
        }

        if (satisfiedLocally) {
            AlarmSchedulerHelper.rescheduleAllFromPrefs(applicationContext)
            PrayerCountdownService.startIfNeeded(applicationContext)
        }

        // ── 2. Then top the cache up, if the network is there ────────────
        val refreshed = refreshCacheIfNeeded(prefs, cache, targetCal, lat, lng, method)

        if (!refreshed && !satisfiedLocally) {
            // Neither source could answer. Fall back to the single-day endpoint
            // in case the calendar endpoint specifically is the problem.
            val response = AladhanApiClient.fetchPrayerTimes(
                lat, lng, method = method, date = targetDate
            )
            if (response == null) {
                Log.w(TAG, "⚠️ No cache and no network — rescheduling from existing prefs")
                AlarmSchedulerHelper.rescheduleAllFromPrefs(applicationContext)
                PrayerCountdownService.startIfNeeded(applicationContext)
                return Result.retry()
            }
            savePrayerTimes(prefs, response)
            AlarmSchedulerHelper.rescheduleAllFromPrefs(applicationContext)
            PrayerCountdownService.startIfNeeded(applicationContext)
            broadcastWidgetUpdate()
            return Result.success()
        }

        if (refreshed) {
            // Re-read: the cache we just wrote may cover the target day the
            // stale one didn't.
            cache = PrayerMonthCache.read(prefs)
            cache?.dayFor(targetDate)?.let { day ->
                saveDay(prefs, day, targetCal)
                satisfiedLocally = true
            }
            AlarmSchedulerHelper.rescheduleAllFromPrefs(applicationContext)
            PrayerCountdownService.startIfNeeded(applicationContext)
        }

        broadcastWidgetUpdate()

        Log.d(TAG, "✅ Prayer times updated and alarms rescheduled")
        // A cache that answered today is a complete success even if the network
        // leg failed — retrying burns battery for a result we already have.
        return if (satisfiedLocally) Result.success() else Result.retry()
    }

    /** After Isha + 35m the day that matters is tomorrow. */
    private fun resolveTargetDay(prefs: SharedPreferences): Calendar {
        val nowCal = Calendar.getInstance()
        val ishaTimeStr = prefs.getString("flutter.prayer_5_time", null) ?: return nowCal

        try {
            val parts = ishaTimeStr.split(" ")[0].split(":")
            val ishaCal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, parts[0].toInt())
                set(Calendar.MINUTE, parts[1].toInt())
            }
            ishaCal.add(Calendar.MINUTE, 35)

            if (nowCal.timeInMillis > ishaCal.timeInMillis) {
                nowCal.add(Calendar.DAY_OF_YEAR, 1)
            }
        } catch (e: Exception) {}

        return nowCal
    }

    /**
     * Pulls the month containing [targetCal] — plus the next one when this one
     * is nearly over — but only when the cache can't already answer.
     *
     * @return true if the cache was successfully extended.
     */
    private fun refreshCacheIfNeeded(
        prefs: SharedPreferences,
        cache: PrayerMonthCache.Cache?,
        targetCal: Calendar,
        lat: Double,
        lng: Double,
        method: Int
    ): Boolean {
        if (!needsRefresh(cache, targetCal, lat, lng, method)) {
            Log.d(TAG, "✅ Month cache is current — skipping network fetch")
            return false
        }

        val year = targetCal.get(Calendar.YEAR)
        val month = targetCal.get(Calendar.MONTH) + 1

        val days = AladhanApiClient.fetchMonth(lat, lng, year, month, method = method)
        if (days == null) {
            Log.w(TAG, "⚠️ Month fetch failed")
            return false
        }

        val merged = HashMap<String, PrayerMonthCache.Day>(days)

        // Reach into next month when this one is nearly out, so the month
        // boundary never arrives with nothing on the other side of it.
        val daysInMonth = targetCal.getActualMaximum(Calendar.DAY_OF_MONTH)
        if (daysInMonth - targetCal.get(Calendar.DAY_OF_MONTH) < COVERAGE_FLOOR_DAYS) {
            val next = (targetCal.clone() as Calendar).apply {
                add(Calendar.MONTH, 1)
                set(Calendar.DAY_OF_MONTH, 1)
            }
            AladhanApiClient.fetchMonth(
                lat, lng,
                next.get(Calendar.YEAR),
                next.get(Calendar.MONTH) + 1,
                method = method
            )?.let { merged.putAll(it) }
        }

        PrayerMonthCache.merge(applicationContext, merged, lat, lng, method)
        return true
    }

    private fun needsRefresh(
        cache: PrayerMonthCache.Cache?,
        targetCal: Calendar,
        lat: Double,
        lng: Double,
        method: Int
    ): Boolean {
        if (cache == null) return true
        if (cache.method != method) return true
        if (!cache.isNear(lat, lng)) return true
        if (cache.dayFor(targetCal.time) == null) return true

        val end = cache.coverageEndMillis() ?: return true
        val remainingDays = (end - targetCal.timeInMillis) / DAY_MS
        if (remainingDays < COVERAGE_FLOOR_DAYS) return true

        // Even with coverage to spare, re-sync daily — the Hijri date and the
        // calculation can both be corrected upstream.
        return System.currentTimeMillis() - cache.fetchedAtMillis >= DAY_MS
    }

    /** Writes one cached day into the `prayer_{id}_*` keys the rest of the app reads. */
    private fun saveDay(prefs: SharedPreferences, day: PrayerMonthCache.Day, targetCal: Calendar) {
        val editor = prefs.edit()
        val now = System.currentTimeMillis()

        for (prayer in PRAYER_MAP) {
            val timeStr = day.timeForId(prayer.id)
            val parts = timeStr.split(":")
            if (parts.size != 2) continue
            val hour = parts[0].toIntOrNull() ?: continue
            val minute = parts[1].toIntOrNull() ?: continue

            val cal = (targetCal.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            // Roll forward until it's actually in the future. A `while`, not an
            // `if`: on a device several days stale a single +24h still lands in
            // the past, and AlarmManager silently drops past alarms.
            while (cal.timeInMillis <= now) {
                cal.add(Calendar.DAY_OF_YEAR, 1)
            }

            editor.putString("flutter.prayer_${prayer.id}_name", prayer.arabicName)
            editor.putString("flutter.prayer_${prayer.id}_time", timeStr)
            editor.putLong("flutter.prayer_${prayer.id}_trigger_millis", cal.timeInMillis)
        }

        if (day.hijri.isNotEmpty()) {
            editor.putString("flutter.cached_hijri_date", day.hijri)
        }

        editor.putString("flutter.last_prayer_update", java.text.SimpleDateFormat(
            "yyyy-MM-dd'T'HH:mm:ss.SSS", java.util.Locale.US
        ).format(java.util.Date()))

        editor.apply()
    }

    private fun broadcastWidgetUpdate() {
        val intent = android.content.Intent("com.ki1lux.adhani.ACTION_PRAYER_UPDATED")
        intent.setPackage(applicationContext.packageName)
        applicationContext.sendBroadcast(intent)
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
