package com.ki1lux.adhani

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import java.util.Calendar

/**
 * Shared helper for scheduling AlarmManager alarms from SharedPreferences.
 * Used by:
 * - MainActivity (when Flutter schedules alarms via MethodChannel)
 * - BootReceiver (re-schedules after device reboot)
 * - WorkManager daily refresh (saves to SharedPrefs, triggers reschedule)
 */
object AlarmSchedulerHelper {
    private const val TAG = "AlarmSchedulerHelper"
    private const val PREFS_NAME = "FlutterSharedPreferences"

    // Request codes 101..105 — kept separate from the adhan alarm codes (1..5, 999)
    // so cancelling/rescheduling one doesn't clobber the other.
    private const val WIDGET_REFRESH_ID_OFFSET = 100

    /** Bound on the re-derivation search in [nextOccurrence]. */
    private const val LOOKAHEAD_DAYS = 3

    /**
     * True when the OS will let us set an exact alarm.
     *
     * On Android 12+ `SCHEDULE_EXACT_ALARM` is a user-revocable permission,
     * and it can be revoked at any time after being granted. Calling
     * [AlarmManager.setAlarmClock] without it throws `SecurityException`.
     */
    fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return alarmManager.canScheduleExactAlarms()
    }

    /**
     * Schedule a single prayer alarm using AlarmManager.setAlarmClock() —
     * the highest priority alarm on Android, which survives Doze.
     *
     * When the user hasn't granted the exact-alarm permission this degrades to
     * `setAndAllowWhileIdle` rather than doing nothing. That alarm can drift by
     * a few minutes, which is a far better outcome than the previous
     * behaviour: the `SecurityException` was swallowed by the catch-all below
     * and the Adhan simply never sounded, with nothing to indicate why.
     */
    fun scheduleAlarm(context: Context, prayerId: Int, triggerAtMillis: Long) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        Log.d(TAG, "Scheduling alarm: prayerId=$prayerId, triggerAt=$triggerAtMillis")

        // Don't schedule alarms in the past
        if (triggerAtMillis <= System.currentTimeMillis()) {
            Log.w(TAG, "Skipping alarm $prayerId — trigger time is in the past")
            return
        }

        val intent = Intent(context, PrayerAlarmReceiver::class.java).apply {
            putExtra(PrayerAlarmReceiver.EXTRA_PRAYER_ID, prayerId)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            prayerId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            if (canScheduleExact(context)) {
                val alarmClockInfo = AlarmManager.AlarmClockInfo(triggerAtMillis, pendingIntent)
                alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
                Log.d(TAG, "setAlarmClock scheduled for prayer $prayerId")
            } else {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent
                )
                Log.w(
                    TAG,
                    "Exact alarms not permitted — prayer $prayerId scheduled inexactly"
                )
            }
        } catch (e: SecurityException) {
            // Permission revoked between the check and the call.
            Log.e(TAG, "Exact alarm denied for $prayerId, falling back to inexact")
            try {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent
                )
            } catch (e2: Exception) {
                Log.e(TAG, "Inexact fallback also failed for $prayerId: ${e2.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error scheduling alarm $prayerId: ${e.message}")
        }
    }

    /**
     * Schedule a silent alarm that only refreshes the home screen widget, firing exactly
     * at the prayer's trigger time regardless of whether that prayer's Adhan sound is
     * enabled. Without this, the widget's "next prayer" highlight and countdown only
     * refresh on the daily WorkManager run or app open, so it goes stale as soon as a
     * prayer time passes.
     */
    fun scheduleWidgetRefresh(context: Context, prayerId: Int, triggerAtMillis: Long) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        if (triggerAtMillis <= System.currentTimeMillis()) {
            Log.w(TAG, "Skipping widget refresh alarm $prayerId — trigger time is in the past")
            return
        }

        val intent = Intent(context, PrayerWidgetProvider::class.java).apply {
            action = "com.ki1lux.adhani.ACTION_PRAYER_UPDATED"
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            WIDGET_REFRESH_ID_OFFSET + prayerId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            // A widget repaint a minute late is invisible, so this never needs
            // the exact-alarm permission — `setExactAndAllowWhileIdle` throws
            // SecurityException without it on Android 12+, which used to take
            // the widget's per-prayer refresh down with it.
            if (canScheduleExact(context)) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent
                )
            } else {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent
                )
            }
            Log.d(TAG, "Widget refresh alarm scheduled: prayerId=$prayerId")
        } catch (e: Exception) {
            Log.e(TAG, "Error scheduling widget refresh alarm $prayerId: ${e.message}")
        }
    }

    /**
     * Cancel all 5 prayer alarms + test alarm + widget refresh alarms.
     */
    fun cancelAll(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        for (prayerId in 1..5) {
            val intent = Intent(context, PrayerAlarmReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                prayerId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)

            val widgetIntent = Intent(context, PrayerWidgetProvider::class.java).apply {
                action = "com.ki1lux.adhani.ACTION_PRAYER_UPDATED"
            }
            val widgetPendingIntent = PendingIntent.getBroadcast(
                context,
                WIDGET_REFRESH_ID_OFFSET + prayerId,
                widgetIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(widgetPendingIntent)
        }

        // Also cancel test alarm (ID 999)
        val testIntent = Intent(context, PrayerAlarmReceiver::class.java)
        val testPending = PendingIntent.getBroadcast(
            context, 999, testIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(testPending)

        Log.d(TAG, "All native prayer alarms cancelled")
    }

    /**
     * Re-schedule all prayer alarms from SharedPreferences.
     * Reads the trigger timestamps saved by the Dart side or WorkManager,
     * and schedules AlarmManager alarms for each enabled prayer.
     *
     * SharedPrefs keys (with flutter. prefix):
     * - flutter.prayer_{id}_name → prayer name (String)
     * - flutter.prayer_{id}_time → display time HH:mm (String)
     * - flutter.prayer_{id}_trigger_millis → epoch millis for next alarm (Long)
     * - flutter.adhan_enabled_{name} → whether adhan is enabled (Boolean)
     */
    fun rescheduleAllFromPrefs(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        var scheduledCount = 0

        // Parsed once for all five prayers.
        //
        // [nextOccurrence] used to call `PrayerMonthCache.read` itself, so a
        // reschedule where several triggers had passed re-parsed the same
        // ~30-day JSON document up to five times. This function runs on the
        // main thread of a BroadcastReceiver — from BootReceiver during the
        // boot storm, and from PrayerAlarmReceiver at every prayer — where the
        // budget before an ANR is ten seconds and the device is already busy.
        val cache = PrayerMonthCache.read(prefs)

        Log.d(TAG, "Rescheduling all alarms from SharedPreferences...")

        for (prayerId in 1..5) {
            val name = prefs.getString("flutter.prayer_${prayerId}_name", null)
            if (name == null) {
                Log.d(TAG, "Prayer $prayerId: no name found, skipping")
                continue
            }

            // Read the trigger timestamp
            val triggerMillis = prefs.getLong("flutter.prayer_${prayerId}_trigger_millis", 0L)
            if (triggerMillis == 0L) {
                Log.d(TAG, "Prayer $prayerId ($name): no trigger time found, skipping")
                continue
            }

            // If the trigger time has passed, re-derive the next occurrence.
            var actualTrigger = triggerMillis
            if (actualTrigger <= now) {
                actualTrigger = nextOccurrence(cache, prefs, prayerId, now)

                if (actualTrigger <= now) {
                    Log.w(TAG, "Prayer $prayerId ($name): could not resolve a future trigger")
                    continue
                }

                // Update SharedPrefs with the new trigger time
                prefs.edit().putLong("flutter.prayer_${prayerId}_trigger_millis", actualTrigger).apply()
                Log.d(TAG, "Prayer $prayerId ($name): trigger was in past, re-derived to $actualTrigger")
            }

            // Always refresh the widget exactly at this prayer's time, regardless of
            // whether the Adhan sound is enabled for it.
            scheduleWidgetRefresh(context, prayerId, actualTrigger)

            // Check if adhan is enabled for this prayer
            val isEnabled = prefs.getBoolean("flutter.adhan_enabled_$name", true)
            if (!isEnabled) {
                Log.d(TAG, "Prayer $prayerId ($name): adhan disabled, skipping sound alarm")
                continue
            }

            scheduleAlarm(context, prayerId, actualTrigger)
            scheduledCount++

            val timeStr = prefs.getString("flutter.prayer_${prayerId}_time", "??:??")
            Log.d(TAG, "Prayer $prayerId ($name) at $timeStr → scheduled for ${actualTrigger}ms")
        }

        Log.d(TAG, "Rescheduled $scheduledCount alarms from SharedPreferences")

        // Notify Home Screen Widget to update
        val intent = Intent("com.ki1lux.adhani.ACTION_PRAYER_UPDATED")
        intent.setPackage(context.packageName)
        context.sendBroadcast(intent)
    }

    /**
     * Works out when prayer [prayerId] next occurs, for a trigger that has
     * already passed.
     *
     * This replaces a bare `trigger += 24h`, which was wrong three ways:
     * it only ever advanced by one day (so a device three days stale resolved
     * to a time still in the past, and [scheduleAlarm] silently dropped it —
     * meaning a reboot armed *zero* alarms); it shifted by an hour across a DST
     * boundary while the displayed `prayer_{id}_time` string didn't, so the
     * adhan disagreed with the widget; and it froze the astronomical drift of
     * ~1-2 minutes a day at whatever it was on the day of the last fetch.
     *
     * Preference order: the month cache knows the correct time for each
     * specific date, so it fixes the drift too. Failing that, re-parse the
     * stored `HH:mm` onto today's calendar — the same self-healing trick
     * [PrayerWidgetProvider] already uses — which at least gets the wall-clock
     * time and DST right.
     */
    private fun nextOccurrence(
        cache: PrayerMonthCache.Cache?,
        prefs: SharedPreferences,
        prayerId: Int,
        now: Long
    ): Long {
        // Look ahead a bounded number of days rather than looping forever on a
        // malformed time string.
        for (dayOffset in 0..LOOKAHEAD_DAYS) {
            val candidate = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, dayOffset)
            }

            val timeStr = cache?.dayFor(candidate.time)?.timeForId(prayerId)
                ?: prefs.getString("flutter.prayer_${prayerId}_time", null)
                ?: return 0L

            val parts = timeStr.split(" ")[0].split(":")
            if (parts.size != 2) return 0L
            val hour = parts[0].toIntOrNull() ?: return 0L
            val minute = parts[1].toIntOrNull() ?: return 0L

            candidate.set(Calendar.HOUR_OF_DAY, hour)
            candidate.set(Calendar.MINUTE, minute)
            candidate.set(Calendar.SECOND, 0)
            candidate.set(Calendar.MILLISECOND, 0)

            if (candidate.timeInMillis > now) {
                // Keep the displayed time in step with the alarm we just armed.
                if (cache?.dayFor(candidate.time) != null) {
                    prefs.edit()
                        .putString("flutter.prayer_${prayerId}_time", timeStr)
                        .apply()
                }
                return candidate.timeInMillis
            }
        }

        Log.w(TAG, "No future occurrence for prayer $prayerId within $LOOKAHEAD_DAYS days")
        return 0L
    }
}
