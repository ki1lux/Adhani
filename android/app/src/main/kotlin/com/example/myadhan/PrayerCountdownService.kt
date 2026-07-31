package com.example.myadhan

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import androidx.core.text.HtmlCompat

/**
 * Foreground Service that shows a persistent notification with countdown
 * to the next prayer time.
 *
 * Optimizations applied:
 * 1. Doze-resilient: uses postAtTime(SystemClock.uptimeMillis) instead of postDelayed
 * 2. Cached builder: reuses NotificationCompat.Builder, only updates text
 * 3. Zero-moment state machine: handles prayer transition gracefully
 * 4. 1-second ticks for live countdown and instant midnight detection
 */
class PrayerCountdownService : Service() {

    companion object {
        private const val TAG = "PrayerCountdownService"
        private const val CHANNEL_ID = "prayer_countdown_channel"
        private const val NOTIFICATION_ID = 2001
        private const val TICK_INTERVAL_MS = 1_000L // 1 second updates ALWAYS

        /**
         * How long to wait before re-attempting a day rollover that didn't
         * resolve. The tick is 1s, so without this an offline device would
         * hammer the API once a second for the rest of the day.
         */
        private const val ROLLOVER_RETRY_INTERVAL_MS = 5 * 60 * 1000L

        /** Bound on the roll-forward search in [findNextPrayer]. */
        private const val MAX_ROLL_FORWARD_DAYS = 400
        private const val PREFS_NAME = "FlutterSharedPreferences"

        /**
         * Static helper to start the countdown service from anywhere.
         * Called by BootReceiver, PrayerAlarmReceiver, and onTaskRemoved.
         */
        fun startIfNeeded(context: Context) {
            try {
                val intent = Intent(context, PrayerCountdownService::class.java)
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                Log.d(TAG, "Countdown service (re)started")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start countdown service: ${e.message}")
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var prefs: SharedPreferences

    // Pro-tip #2: Keep a reference to the builder — don't recreate every tick
    private var cachedBuilder: NotificationCompat.Builder? = null
    private var currentPrayerId: Int? = null // Track which prayer we're counting down to
    private var lastTrackedDate: String = "" // Track date to detect midnight crossing
    private var lastNotificationHour: Int = -1 // Track hour to refresh setWhen() each hour
    
    @Volatile
    private var midnightRefreshInProgress = false // Flag while fetching new data at midnight

    /// The day a refresh is currently trying to resolve. Only promoted to
    /// [lastTrackedDate] once that refresh actually succeeds — otherwise a
    /// failed attempt would consume the day's one and only rollover trigger.
    @Volatile
    private var pendingTrackedDate: String = ""

    @Volatile
    private var rolloverResolved = false

    /// Stops a failed rollover from re-firing on every 1s tick.
    @Volatile
    private var lastRolloverAttemptMs: Long = 0L

    private val updateRunnable = object : Runnable {
        override fun run() {
            updateNotification()
            // Pro-tip #1: Use postAtTime with uptimeMillis for Doze resilience
            val nextTick = SystemClock.uptimeMillis() + TICK_INTERVAL_MS
            handler.postAtTime(this, nextTick)
        }
    }

    override fun onCreate() {
        super.onCreate()
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        // Initialize as empty so the first tick sets it correctly based on the current time vs Isha
        lastTrackedDate = ""
        createNotificationChannel()
        Log.d(TAG, "Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Service started")

        // Build initial notification
        val notification = buildInitialNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start foreground: ${e.message}")
            stopSelf()
            return START_NOT_STICKY
        }

        // Start periodic updates
        handler.removeCallbacks(updateRunnable)
        handler.post(updateRunnable)

        return START_STICKY
    }

    override fun onDestroy() {
        Log.d(TAG, "Service destroyed")
        handler.removeCallbacks(updateRunnable)
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Auto-restart when user swipes app from recents
        Log.d(TAG, "Task removed — restarting countdown service")
        startIfNeeded(this)
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * Perform a direct API fetch on a background thread at midnight.
     * Much faster than WorkManager — updates SharedPreferences within seconds.
     */
    private fun fetchFreshDataDirectly(targetDate: java.util.Date? = null) {
        if (midnightRefreshInProgress) return
        midnightRefreshInProgress = true
        Log.d(TAG, "Fetching fresh prayer data directly... (target: $targetDate)")

        Thread {
            try {
                val lat = getDouble(prefs, "flutter.last_latitude")
                val lng = getDouble(prefs, "flutter.last_longitude")
                if (lat == null || lng == null) {
                    Log.w(TAG, "No stored location for midnight refresh")
                    midnightRefreshInProgress = false
                    return@Thread
                }

                val method = prefs.getInt("flutter.calculation_method", 19)

                // Try the cache before the network. On a device that fetched a
                // month while online, the day we need is already here and the
                // rollover completes instantly with no request at all.
                val resolvedDate = targetDate ?: java.util.Date()
                val cachedDay = PrayerMonthCache.read(prefs)?.dayFor(resolvedDate)
                val response = if (cachedDay != null) {
                    Log.d(TAG, "Rollover satisfied from month cache")
                    AladhanApiClient.PrayerTimesResponse(
                        fajr = cachedDay.fajr,
                        dhuhr = cachedDay.dhuhr,
                        asr = cachedDay.asr,
                        maghrib = cachedDay.maghrib,
                        isha = cachedDay.isha,
                        hijriDate = cachedDay.hijri
                    )
                } else {
                    AladhanApiClient.fetchPrayerTimes(lat, lng, method = method, date = targetDate)
                }

                if (response != null) {
                    val editor = prefs.edit()
                    val nowMillis = System.currentTimeMillis()

                    if (response.hijriDate.isNotEmpty()) {
                        editor.putString("flutter.cached_hijri_date", response.hijriDate)
                    }

                    val timeMap = listOf(
                        Triple(1, "الفجر", response.fajr),
                        Triple(2, "الظهر", response.dhuhr),
                        Triple(3, "العصر", response.asr),
                        Triple(4, "المغرب", response.maghrib),
                        Triple(5, "العشاء", response.isha)
                    )

                    for ((id, arabicName, timeStr) in timeMap) {
                        val parts = timeStr.split(":")
                        if (parts.size != 2) continue
                        val hour = parts[0].toIntOrNull() ?: continue
                        val minute = parts[1].toIntOrNull() ?: continue

                        // If we fetched data for a specific targetDate (e.g. tomorrow after Isha),
                        // seed the calendar from that target date to avoid a double +1 day shift.
                        val cal = if (targetDate != null) {
                            Calendar.getInstance().apply {
                                time = targetDate
                                set(Calendar.HOUR_OF_DAY, hour)
                                set(Calendar.MINUTE, minute)
                                set(Calendar.SECOND, 0)
                                set(Calendar.MILLISECOND, 0)
                            }
                        } else {
                            Calendar.getInstance().apply {
                                set(Calendar.HOUR_OF_DAY, hour)
                                set(Calendar.MINUTE, minute)
                                set(Calendar.SECOND, 0)
                                set(Calendar.MILLISECOND, 0)
                            }
                        }

                        // Only push to the next day if the resolved time is still in the past.
                        // For targetDate-based fetches this should almost never be needed,
                        // but acts as a safety net for edge cases (e.g. clock drift).
                        if (cal.timeInMillis <= nowMillis) {
                            cal.add(Calendar.DAY_OF_YEAR, 1)
                        }

                        editor.putString("flutter.prayer_${id}_name", arabicName)
                        editor.putString("flutter.prayer_${id}_time", timeStr)
                        editor.putLong("flutter.prayer_${id}_trigger_millis", cal.timeInMillis)
                    }

                    editor.putString("flutter.last_prayer_update", java.text.SimpleDateFormat(
                        "yyyy-MM-dd'T'HH:mm:ss.SSS", java.util.Locale.US
                    ).format(java.util.Date()))
                    
                    editor.apply()
                    Log.d(TAG, "Direct update: Saved new prayer times and Hijri date.")

                    rolloverResolved = true
                } else {
                    Log.w(TAG, "No cached day and API fetch failed at midnight")
                }

                // Re-arm regardless of which branch we took. On failure this is
                // what keeps the notification moving: AlarmSchedulerHelper
                // re-derives each prayer's next occurrence from the cache or
                // the stored HH:mm, so a failed rollover degrades to yesterday's
                // schedule instead of freezing on "حان وقت صلاة الفجر" forever.
                AlarmSchedulerHelper.rescheduleAllFromPrefs(this@PrayerCountdownService)

                // The backup worker used to be enqueued only on success — the
                // one case that didn't need a backup. It belongs here.
                try {
                    val fullUpdate = OneTimeWorkRequestBuilder<PrayerUpdateWorker>().build()
                    WorkManager.getInstance(this@PrayerCountdownService).enqueue(fullUpdate)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to enqueue full update worker: ${e.message}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Midnight fetch error: ${e.message}")
            } finally {
                midnightRefreshInProgress = false
                // Only bank the day once we actually resolved it. Marking it
                // done on failure consumed the rollover, so the day's single
                // refresh attempt was spent and never retried.
                if (rolloverResolved) {
                    lastTrackedDate = pendingTrackedDate
                }
                pendingTrackedDate = ""
                // Trigger an immediate notification update on main thread
                handler.post { updateRunnable.run() }
            }
        }.start()
    }

    /**
     * Flutter's SharedPreferences stores doubles as Strings with a specific prefix
     * in newer versions (2.4.15+), or as raw long bits in older versions.
     */
    private fun getDouble(prefs: SharedPreferences, key: String): Double? {
        if (!prefs.contains(key)) return null

        try {
            val strVal = prefs.getString(key, null)
            if (strVal != null && strVal.startsWith("VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu")) {
                val numStr = strVal.removePrefix("VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu")
                return numStr.toDoubleOrNull()
            }
        } catch (e: ClassCastException) {
            // It's not a String, fallback to the old Long format below
        }

        return try {
            val raw = prefs.getLong(key, 0L)
            if (raw == 0L) null else java.lang.Double.longBitsToDouble(raw)
        } catch (e: Exception) {
            try {
                prefs.getFloat(key, Float.MIN_VALUE).toDouble().takeIf { it != Float.MIN_VALUE.toDouble() }
            } catch (e2: Exception) {
                null
            }
        }
    }

    /**
     * Update notification. Ticks every 1 second now.
     */
    private fun updateNotification() {
        val now = System.currentTimeMillis()

        // 1. Calculate Target Date based on Isha + 15m rule
        var targetDate: java.util.Date? = null
        val ishaTimeStr = prefs.getString("flutter.prayer_5_time", null)
        val nowCal = Calendar.getInstance()
        
        if (ishaTimeStr != null) {
            try {
                val parts = ishaTimeStr.split(" ")[0].split(":")
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

        val targetDayStr = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(nowCal.time)

        val monthCache = PrayerMonthCache.read(prefs)

        // Does the data on disk actually describe the day we're reporting on?
        // A fresh service instance used to assume it did — lastTrackedDate is
        // reset to "" in onCreate, so the first tick simply adopted whatever
        // the current reporting day was. Any restart between Isha+35m and
        // midnight (Android restarts foreground services routinely) therefore
        // swallowed that day's rollover entirely, leaving the 00:05 worker as
        // the only thing that would ever refresh the data.
        val dataCoversReportingDay = monthCache?.dayFor(nowCal.time) != null

        val needsRollover = if (lastTrackedDate.isEmpty()) {
            lastTrackedDate = targetDayStr
            !dataCoversReportingDay
        } else {
            targetDayStr != lastTrackedDate
        }

        if (needsRollover) {
            // Retry a failed rollover, but not on every one-second tick.
            val sinceLastAttempt = System.currentTimeMillis() - lastRolloverAttemptMs
            if (sinceLastAttempt >= ROLLOVER_RETRY_INTERVAL_MS) {
                Log.d(TAG, "🌙 Shifted to new reporting day: $targetDayStr")
                lastRolloverAttemptMs = System.currentTimeMillis()

                // Refresh the persistent notification's system timestamp so it doesn't get stuck
                cachedBuilder?.setWhen(System.currentTimeMillis())
                cachedBuilder?.setShowWhen(true)

                // lastTrackedDate is advanced by the fetch itself, and only if
                // it succeeds — see fetchFreshDataDirectly's finally block.
                pendingTrackedDate = targetDayStr
                rolloverResolved = false
                fetchFreshDataDirectly(targetDate)
            }
        }

        val nextPrayer = findNextPrayer(now)

        // Line 1: City + Hijri date.
        //
        // Resolved from the cache on every tick rather than read from the
        // stored `cached_hijri_date` string, so the date turns over exactly at
        // Maghrib — when the Islamic day actually begins — instead of whenever
        // something last happened to write that key. The stored value remains
        // the fallback for installs whose cache hasn't been filled yet.
        val city = prefs.getString("flutter.city_name", null) ?: ""
        val hijri = monthCache?.hijriNow()
            ?: prefs.getString("flutter.cached_hijri_date", null)
            ?: ""
        val title = when {
            city.isNotEmpty() && hijri.isNotEmpty() -> "$city • $hijri"
            city.isNotEmpty() -> city
            hijri.isNotEmpty() -> hijri
            else -> "أوقات الصلاة"
        }

        // Line 2: Prayer name + time + live countdown
        var text: CharSequence

        if (nextPrayer != null) {
            val remainingMs = nextPrayer.triggerMillis - now
            val displayTime = prefs.getString("flutter.prayer_${nextPrayer.id}_time", null) ?: ""

            if (remainingMs <= 0) {
                // Determine how much time has passed since the prayer triggered
                val elapsedSinceTrigger = now - nextPrayer.triggerMillis
                // If it's Maghrib, Iqamah is 15 minutes. Otherwise, 30 minutes.
                val iqamaLimitMs = if (nextPrayer.name == "المغرب") {
                    15 * 60 * 1000L // 15 minutes
                } else {
                    30 * 60 * 1000L // 30 minutes
                }

                if (elapsedSinceTrigger < iqamaLimitMs) {
                    // Count UPwards: How much time has elapsed since the Adhan
                    val totalSeconds = elapsedSinceTrigger / 1000
                    val minutes = totalSeconds / 60
                    val seconds = totalSeconds % 60

                    val formattedMinutes = String.format("%02d", minutes)
                    val formattedSeconds = String.format("%02d", seconds)

                    val iqamaCountdownStr = if (minutes > 0) {
                        "$formattedMinutes:$formattedSeconds+" // Changed format to minutes:seconds
                    } else {
                        "$formattedMinutes:$formattedSeconds+"
                    }
                    
                    val htmlText = "<b><font color='#FF5E5E'>$iqamaCountdownStr</font></b> — ${nextPrayer.name} $displayTime"
                    text = HtmlCompat.fromHtml(htmlText, HtmlCompat.FROM_HTML_MODE_LEGACY)
                    currentPrayerId = nextPrayer.id 
                } else {
                    text = "حان وقت صلاة ${nextPrayer.name}"
                    currentPrayerId = null
                }
            } else {
                val totalSeconds = remainingMs / 1_000
                val hours = totalSeconds / 3600
                val minutes = (totalSeconds % 3600) / 60
                val seconds = totalSeconds % 60

                val formattedHours = String.format("%02d", hours)
                val formattedMinutes = String.format("%02d", minutes)
                val formattedSeconds = String.format("%02d", seconds)

                val countdownStr = when {
                    hours > 0 -> "$formattedHours:$formattedMinutes:$formattedSeconds"
                    minutes > 0 -> "$formattedMinutes:$formattedSeconds"
                    else -> "$formattedMinutes:$formattedSeconds"
                }

                text = if (displayTime.isNotEmpty()) {
                    "$countdownStr — ${nextPrayer.name} $displayTime"
                } else {
                    "$countdownStr — ${nextPrayer.name}"
                }
                currentPrayerId = nextPrayer.id
            }
        } else {
            text = "لا توجد صلاة قادمة"
        }

        val builder = getOrCreateBuilder()
        builder.setContentTitle(title)

        // Refresh the notification's displayed timestamp every hour so it never shows "yesterday".
        // We compare the current hour-of-day to detect when the hour rolls over.
        val currentHour = nowCal.get(Calendar.HOUR_OF_DAY)
        if (currentHour != lastNotificationHour) {
            lastNotificationHour = currentHour
            builder.setWhen(System.currentTimeMillis())
        }
        
        if (midnightRefreshInProgress) {
            builder.setContentText("جاري تحديث التاريخ...")
        } else {
            builder.setContentText(text)
        }

        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        mgr.notify(NOTIFICATION_ID, builder.build())
    }

    private fun getOrCreateBuilder(): NotificationCompat.Builder {
        cachedBuilder?.let { return it }

        val tapIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val tapPending = PendingIntent.getActivity(
            this, 0, tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_adhan)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .setContentIntent(tapPending)
            .setSilent(true)

        cachedBuilder = builder
        return builder
    }

    private fun buildInitialNotification(): android.app.Notification {
        val builder = getOrCreateBuilder()
        builder.setContentTitle("أوقات الصلاة")
        builder.setContentText("جاري التحميل...")
        return builder.build()
    }

    private fun findNextPrayer(now: Long): NextPrayer? {
        var closestFuture: NextPrayer? = null
        var activeIqamah: NextPrayer? = null
        var earliestToday: NextPrayer? = null

        for (prayerId in 1..5) {
            val name = prefs.getString("flutter.prayer_${prayerId}_name", null) ?: continue
            val triggerMillis = prefs.getLong("flutter.prayer_${prayerId}_trigger_millis", 0L)

            val isEnabled = prefs.getBoolean("flutter.adhan_enabled_$name", true)
            if (!isEnabled || triggerMillis <= 0) continue

            // Track the earliest prayer of the day (usually Fajr) to use as a fallback
            if (earliestToday == null || triggerMillis < earliestToday.triggerMillis) {
                earliestToday = NextPrayer(prayerId, name, triggerMillis)
            }

            // For Maghrib, Iqama is 15 mins (900,000s), otherwise 30 mins (1,800,000s)
            val iqamaLimitMs = if (name == "المغرب") {
                15 * 60 * 1000L // 15 minutes
            } else {
                30 * 60 * 1000L // 30 minutes
            }

            // The flutter plugin updates the `triggerMillis` to tomorrow once the prayer passes.
            // So if `triggerMillis` is tomorrow, we must check if *today's* version of this prayer 
            // just passed and is still in the Iqamah window.
            val todaysTriggerMillis = if (triggerMillis > now + 12 * 60 * 60 * 1000L) {
                // If it's more than 12 hours away, it's likely tomorrow's time. 
                // Subtract 24 hours to get today's trigger time.
                triggerMillis - 24 * 60 * 60 * 1000L
            } else {
                triggerMillis
            }

            // If the prayer has passed today, check if we are *currently* in its Iqamah window
            if (now >= todaysTriggerMillis && now < todaysTriggerMillis + iqamaLimitMs) {
                activeIqamah = NextPrayer(prayerId, name, todaysTriggerMillis)
            }

            // Only consider for "closestFuture" if it hasn't passed (or is exactly now)
            if (triggerMillis >= now) {
                if (closestFuture == null || triggerMillis < closestFuture.triggerMillis) {
                    closestFuture = NextPrayer(prayerId, name, triggerMillis)
                }
            }
        }

        // If we are actively in an Iqamah window, prioritize showing that
        if (activeIqamah != null) return activeIqamah
        
        // If there's a future prayer today, return it
        if (closestFuture != null) return closestFuture
        
        // If NO prayers are left today (e.g. Isha finished running in complete background),
        // fall back to tomorrow's Fajr by rolling today's earliest prayer forward.
        //
        // This has to be a loop. A single +24h assumes the stored triggers are
        // at most one day stale — on a device that has been offline longer, the
        // result was *still* in the past, so remainingMs stayed negative and the
        // notification froze on "حان وقت صلاة الفجر" permanently.
        if (earliestToday != null) {
            var rolled = earliestToday.triggerMillis
            var guard = 0
            while (rolled <= now && guard < MAX_ROLL_FORWARD_DAYS) {
                rolled += 24 * 60 * 60 * 1000L
                guard++
            }
            if (rolled > now) {
                return NextPrayer(earliestToday.id, earliestToday.name, rolled)
            }
        }

        return null
    }

    private data class NextPrayer(
        val id: Int,
        val name: String,
        val triggerMillis: Long
    )

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "عداد الصلاة",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "يعرض الوقت المتبقي للصلاة القادمة"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }

            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            mgr.createNotificationChannel(channel)
        }
    }
}
