package com.ki1lux.adhani

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

class AdhanAlarmService : Service() {

    companion object {
        private const val TAG = "AdhanAlarmService"
        private const val CHANNEL_ID = "adhan_playback_channel_v2"
        private const val NOTIFICATION_ID = 1001
        const val ACTION_STOP_ADHAN = "com.ki1lux.adhani.STOP_ADHAN"

        /** Longest the Adhan may run before the service stops itself. */
        private const val MAX_PLAYBACK_MS = 6 * 60 * 1000L
    }

    private var currentPrayerName = "الصلاة"
    private var currentPrayerTime = ""
    private val handler = Handler(Looper.getMainLooper())
    private var isPlaying = false

    /**
     * Hard ceiling on how long this foreground service may live.
     *
     * The service normally stops itself from [AdhanPlayer]'s completion
     * callback. If MediaPlayer stalls without ever reporting completion or an
     * error — a decoder wedged on a corrupt file, audio focus lost to a call
     * that never ends — nothing else would ever call [stopAdhanAndService],
     * and a foreground service with a wake-locked media player would sit there
     * draining the battery until the user rebooted. The longest bundled Adhan
     * is under four minutes.
     */
    private val playbackTimeout = Runnable {
        Log.w(TAG, "Adhan exceeded its maximum duration — stopping")
        stopAdhanAndService()
    }

    // Volume keys silence the Adhan — the same gesture that silences any
    // other alarm.
    private val hardwareButtonReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            Log.d(TAG, "Hardware/Screen action received: ${intent.action}")
            stopAdhanAndService()
        }
    }

    // Receiver for the "Stop" button in the notification
    private val stopReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            Log.d(TAG, "Stop action received")
            stopAdhanAndService()
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        // Register stop receiver
        val filter = IntentFilter(ACTION_STOP_ADHAN)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(stopReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(stopReceiver, filter)
        }

        // Register hardware buttons receiver. VOLUME_CHANGED_ACTION is a
        // protected system broadcast, so NOT_EXPORTED is both correct and
        // what Android 14+ asks for — an unflagged registration is what
        // trips SecurityException on API 34.
        val hardwareFilter = IntentFilter("android.media.VOLUME_CHANGED_ACTION")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(hardwareButtonReceiver, hardwareFilter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(hardwareButtonReceiver, hardwareFilter)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val prayerName = intent?.getStringExtra("prayerName") ?: "الصلاة"
        val prayerTime = intent?.getStringExtra("prayerTime") ?: "حان وقت الصلاة"
        val soundName = intent?.getStringExtra("soundName") ?: "adhan1"

        currentPrayerName = prayerName
        currentPrayerTime = prayerTime

        Log.d(TAG, "Starting Adhan: $prayerName at $prayerTime, sound=$soundName")

        // Build notification with stop action FIRST (required before startForeground)
        val notification = buildNotification(prayerName, prayerTime)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start foreground: ${e.message}")
            // Still try to play audio even if foreground fails
        }


        // Play Adhan on ALARM stream with audio focus
        val resId = AdhanPlayer.getSoundResId(this, soundName)
        AdhanPlayer.play(this, resId) {
            // Called when playback completes
            Log.d(TAG, "Adhan completed, stopping service")
            stopAdhanAndService()
        }

        isPlaying = true
        handler.removeCallbacks(playbackTimeout)
        handler.postDelayed(playbackTimeout, MAX_PLAYBACK_MS)

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        Log.d(TAG, "Service destroyed")
        isPlaying = false
        handler.removeCallbacks(playbackTimeout)
        AdhanPlayer.stop()
        try {
            unregisterReceiver(stopReceiver)
        } catch (e: Exception) {
            // Already unregistered
        }
        try {
            unregisterReceiver(hardwareButtonReceiver)
        } catch (e: Exception) {
            // Already unregistered
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun stopAdhanAndService() {
        isPlaying = false
        handler.removeCallbacks(playbackTimeout)
        AdhanPlayer.stop()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun buildNotification(prayerName: String, prayerTime: String): android.app.Notification {
        // Intent for tapping the notification → open app
        val tapIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val tapPending = PendingIntent.getActivity(
            this, 0, tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Intent for "Stop" action button
        val stopIntent = Intent(ACTION_STOP_ADHAN).apply {
            setPackage(packageName)
        }
        val stopPending = PendingIntent.getBroadcast(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val remoteViews = android.widget.RemoteViews(packageName, R.layout.custom_notification_compact)
        remoteViews.setTextViewText(R.id.notification_title, "حان وقت صلاة $prayerName")
        remoteViews.setTextViewText(R.id.notification_text, "الوقت: $prayerTime")
        remoteViews.setOnClickPendingIntent(R.id.notification_stop_btn, stopPending)

        val bigViews = android.widget.RemoteViews(packageName, R.layout.custom_notification_big)
        bigViews.setTextViewText(R.id.notification_title, "حان وقت صلاة $prayerName")
        bigViews.setTextViewText(R.id.notification_text, "الوقت: $prayerTime")
        bigViews.setOnClickPendingIntent(R.id.notification_stop_btn, stopPending)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("حان وقت صلاة $prayerName")
            .setContentText("الوقت: $prayerTime")
            .setSmallIcon(R.drawable.ic_stat_adhan)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true) // Can't be swiped while Adhan is playing
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(tapPending)
            .setWhen(System.currentTimeMillis())
            .setStyle(androidx.core.app.NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(remoteViews)
            .setCustomBigContentView(bigViews)
            .setSound(null) // No notification sound — audio via MediaPlayer
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Adhan Playback",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Shows when Adhan is playing"
                setSound(null, null) // Silent channel — audio via MediaPlayer on ALARM stream
                enableVibration(true)
                enableLights(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }

            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            mgr.createNotificationChannel(channel)
        }
    }
}