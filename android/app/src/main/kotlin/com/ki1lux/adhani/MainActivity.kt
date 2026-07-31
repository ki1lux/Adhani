package com.ki1lux.adhani

import android.app.AlarmManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The entire Dart ↔ Kotlin bridge surface (see CLAUDE.md).
 *
 * Every handler here is defensive: an exception thrown out of a MethodChannel
 * handler crosses back into Dart as an opaque failure, and several of these
 * are invoked during startup where one would take the first frame with it.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    handle(call, result)
                } catch (e: Exception) {
                    Log.e(TAG, "Method ${call.method} failed: ${e.message}")
                    result.error("NATIVE_ERROR", e.message, null)
                }
            }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startAdhanService" -> {
                val prayerName = call.argument<String>("prayerName") ?: "صلاة"
                val prayerTime = call.argument<String>("prayerTime") ?: "حان وقت الصلاة"

                val serviceIntent = Intent(this, AdhanAlarmService::class.java).apply {
                    putExtra("prayerName", prayerName)
                    putExtra("prayerTime", prayerTime)
                }
                startForegroundService(serviceIntent)
                result.success(true)
            }

            "scheduleNativePrayerAlarm" -> {
                val prayerId = call.argument<Int>("prayerId") ?: 0
                // Epoch millis: read defensively rather than letting a
                // ClassCastException silently drop the alarm.
                val triggerAtMillis = (call.argument<Any>("triggerAtMillis") as? Number)
                    ?.toLong() ?: 0L

                AlarmSchedulerHelper.scheduleAlarm(this, prayerId, triggerAtMillis)
                result.success(true)
            }

            "cancelAllNativeAlarms" -> {
                AlarmSchedulerHelper.cancelAll(this)
                result.success(true)
            }

            "requestExactAlarmPermission" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    if (!alarmManager.canScheduleExactAlarms()) {
                        // Not every OEM ships this settings screen; falling
                        // back to the app's own settings page beats an
                        // ActivityNotFoundException crash.
                        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                            .setData(Uri.fromParts("package", packageName, null))
                        if (!startActivitySafely(intent)) {
                            startActivitySafely(appDetailsIntent())
                        }
                        result.success(false)
                    } else {
                        result.success(true)
                    }
                } else {
                    result.success(true)
                }
            }

            "checkExactAlarmPermission" -> {
                result.success(AlarmSchedulerHelper.canScheduleExact(this))
            }

            "openBatterySettings" -> {
                // Deliberately the *list* screen, not
                // ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS: Play forbids
                // apps from requesting that exemption directly unless they're
                // in one of a few exempt categories. Sending the user to the
                // settings screen to make the change themselves is allowed.
                val opened = startActivitySafely(
                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                ) || startActivitySafely(appDetailsIntent())
                if (opened) result.success(true)
                else result.error("NO_ACTIVITY", "Could not open settings", null)
            }

            "openNotificationSettings" -> {
                val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                val opened = startActivitySafely(intent) ||
                    startActivitySafely(appDetailsIntent())
                result.success(opened)
            }

            "rescheduleFromPrefs" -> {
                AlarmSchedulerHelper.rescheduleAllFromPrefs(this)
                result.success(true)
            }

            "registerDailyPrayerWorker" -> {
                PrayerUpdateWorker.enqueue(this)
                result.success(true)
            }

            "startCountdownService" -> {
                PrayerCountdownService.startIfNeeded(this)
                result.success(true)
            }

            "stopCountdownService" -> {
                stopService(Intent(this, PrayerCountdownService::class.java))
                result.success(true)
            }

            // ── Adhan preview ────────────────────────────────────────────
            // The Settings screen used to preview the call to prayer through
            // `audioplayers`, which meant shipping a second copy of all three
            // ~2.5 MB recordings as Flutter assets alongside the res/raw ones
            // the alarm itself plays. Previewing through the same AdhanPlayer
            // the alarm uses removes ~7 MB from the download *and* makes the
            // preview an honest rehearsal — same stream, same volume, same
            // audio-focus behaviour as the real thing.
            "previewAdhan" -> {
                val soundName = call.argument<String>("soundName") ?: "adhan1"
                previewActive = true
                AdhanPlayer.play(this, AdhanPlayer.getSoundResId(this, soundName)) {
                    previewActive = false
                }
                result.success(true)
            }

            "stopAdhanPreview" -> {
                previewActive = false
                AdhanPlayer.stop()
                result.success(true)
            }

            "isAdhanPreviewPlaying" -> result.success(AdhanPlayer.isPlaying())

            // ── Share sheet ──────────────────────────────────────────────
            // A one-off ACTION_SEND rather than another plugin dependency.
            "shareApp" -> {
                val text = call.argument<String>("text")
                if (text == null) {
                    result.success(false)
                } else {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    result.success(startActivitySafely(Intent.createChooser(send, null)))
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun appDetailsIntent() = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
        .setData(Uri.fromParts("package", packageName, null))

    /** Returns false instead of crashing when nothing can handle the intent. */
    private fun startActivitySafely(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        Log.w(TAG, "No activity for ${intent.action}")
        false
    } catch (e: SecurityException) {
        Log.w(TAG, "Not allowed to start ${intent.action}")
        false
    }

    /**
     * Guards [onStop] from silencing a *real* Adhan.
     *
     * The preview and the alarm share one [AdhanPlayer] singleton, so stopping
     * unconditionally here would cut the call to prayer short for anyone who
     * happened to open and then leave the app while it was sounding.
     */
    private var previewActive = false

    override fun onStop() {
        // A preview left playing when the user leaves the app would otherwise
        // carry on at alarm volume with no visible way to stop it.
        if (previewActive) {
            previewActive = false
            AdhanPlayer.stop()
        }
        super.onStop()
    }

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.myadhan/notification"
    }
}
