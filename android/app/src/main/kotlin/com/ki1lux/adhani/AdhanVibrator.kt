package com.ki1lux.adhani

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * The "vibrate instead of the Adhan" alert.
 *
 * Deliberately **not** routed through [AdhanAlarmService]. That service is
 * declared `foregroundServiceType="mediaPlayback"`, which is accurate when it
 * is playing a recording and inaccurate when it is only buzzing — and a
 * foreground service whose declared type doesn't match what it does is exactly
 * what Play's foreground-service review looks for. A vibration also doesn't
 * need a service to stay alive: `Vibrator.vibrate` hands the pattern to the
 * system's vibrator service, which keeps running it after this process is
 * gone, so the receiver can fire and return well inside its ~10s budget.
 */
object AdhanVibrator {
    private const val TAG = "AdhanVibrator"

    private const val CHANNEL_ID = "adhan_vibrate_channel_v1"
    private const val NOTIFICATION_ID = 4711

    /**
     * wait, buzz, pause, buzz, pause, buzz — three deliberate pulses, long
     * enough to be felt through a pocket and distinct from the single short
     * tick of an ordinary notification.
     */
    private val PATTERN = longArrayOf(0, 700, 400, 700, 400, 700)

    /**
     * Vibrates and posts the accompanying notification.
     *
     * The notification matters: a buzz with nothing on screen leaves the user
     * with no way to know which prayer just came in.
     */
    fun alert(context: Context, prayerName: String, prayerTime: String) {
        vibrate(context)
        notify(context, prayerName, prayerTime)
    }

    private fun vibrate(context: Context) {
        try {
            val vibrator = resolveVibrator(context)
            if (vibrator == null || !vibrator.hasVibrator()) {
                Log.w(TAG, "No vibrator on this device — notification only")
                return
            }

            // Alarm usage, matching AdhanPlayer's audio usage: it is what
            // tells the system this is an alarm rather than an incidental
            // buzz, so it is treated the same way the Adhan itself would be
            // under Do Not Disturb and the various OEM "silent" modes.
            //
            // Three branches because the API to say that changed twice:
            // VibrationAttributes from 33, AudioAttributes + VibrationEffect
            // from 26, and a raw pattern before that. `-1` means play the
            // pattern once rather than looping it.
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> {
                    vibrator.vibrate(
                        VibrationEffect.createWaveform(PATTERN, -1),
                        VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM),
                    )
                }

                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(
                        VibrationEffect.createWaveform(PATTERN, -1),
                        alarmAudioAttributes(),
                    )
                }

                else -> {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(PATTERN, -1, alarmAudioAttributes())
                }
            }
            Log.d(TAG, "Vibration pattern started")
        } catch (e: Exception) {
            // Never let a failed buzz take down the alarm path — the
            // notification below is still worth posting.
            Log.e(TAG, "Failed to vibrate: ${e.message}")
        }
    }

    private fun alarmAudioAttributes(): AudioAttributes =
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

    private fun resolveVibrator(context: Context): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager =
                context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            manager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun notify(context: Context, prayerName: String, prayerTime: String) {
        try {
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "تنبيه الصلاة (اهتزاز)",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "تنبيه بالاهتزاز عند دخول وقت الصلاة"
                    // The channel neither sounds nor vibrates: the waveform
                    // above is doing that, with alarm usage attributes the
                    // channel can't express. Leaving channel vibration on
                    // would buzz twice, out of step with itself.
                    setSound(null, null)
                    enableVibration(false)
                }
                manager.createNotificationChannel(channel)
            }

            val tapIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pending = PendingIntent.getActivity(
                context,
                0,
                tapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_adhan)
                .setContentTitle("حان وقت صلاة $prayerName")
                .setContentText(if (prayerTime.isEmpty()) "" else "الوقت: $prayerTime")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setOnlyAlertOnce(true)
                // Silent at the notification level too — same reason as the
                // channel above.
                .setSilent(true)
                .setDefaults(0)
                .setContentIntent(pending)
                .build()

            manager.notify(NOTIFICATION_ID, notification)
            Log.d(TAG, "Vibrate-mode notification posted for $prayerName")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to post vibrate notification: ${e.message}")
        }
    }
}
