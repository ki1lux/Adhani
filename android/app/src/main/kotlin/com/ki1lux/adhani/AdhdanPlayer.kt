package com.ki1lux.adhani

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.util.Log

object AdhanPlayer {
    private const val TAG = "AdhanPlayer"
    private var mediaPlayer: MediaPlayer? = null
    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null
    private var onCompletionCallback: (() -> Unit)? = null

    /**
     * Play Adhan on STREAM_ALARM with AudioFocus GAIN_TRANSIENT_MAY_DUCK.
     * - STREAM_ALARM: not interrupted by notification sounds
     * - GAIN_TRANSIENT_MAY_DUCK: other apps lower volume, don't pause/stop
     */
    fun play(context: Context, soundResId: Int = R.raw.adhan1, onCompletion: (() -> Unit)? = null) {
        stop() // Stop any existing playback first
        onCompletionCallback = onCompletion

        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // Request audio focus with ducking
        val granted = requestAudioFocus()
        if (!granted) {
            Log.w(TAG, "Audio focus not granted, playing anyway")
        }

        try {
            mediaPlayer = MediaPlayer().apply {
                // Set audio attributes to ALARM stream — not interrupted by notifications
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )

                // Load the sound from raw resources
                val afd = context.resources.openRawResourceFd(soundResId)
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()

                prepare()

                setOnCompletionListener {
                    Log.d(TAG, "Adhan playback completed")
                    stop()
                    onCompletionCallback?.invoke()
                }

                setOnErrorListener { _, what, extra ->
                    Log.e(TAG, "MediaPlayer error: what=$what, extra=$extra")
                    stop()
                    onCompletionCallback?.invoke()
                    true
                }

                start()
                Log.d(TAG, "Adhan started playing on ALARM stream")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error playing Adhan: ${e.message}")
            e.printStackTrace()
            stop()
            onCompletionCallback?.invoke()
        }
    }

    fun stop() {
        try {
            mediaPlayer?.let {
                if (it.isPlaying) {
                    it.stop()
                }
                it.release()
                Log.d(TAG, "Adhan stopped")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping: ${e.message}")
        }
        mediaPlayer = null
        abandonAudioFocus()
    }

    fun isPlaying(): Boolean {
        return try {
            mediaPlayer?.isPlaying == true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Get the raw resource ID for a given sound name.
     * Maps Flutter preference names (e.g. "adhan1") to Android resource IDs.
     * Using explicit references prevents the Android resource shrinker from removing them.
     */
    fun getSoundResId(context: Context, soundName: String): Int {
        return when (soundName) {
            "adhan1" -> R.raw.adhan1
            "adhan2" -> R.raw.adhan2
            "adhan3" -> R.raw.adhan3
            "adhan4" -> R.raw.adhan4
            "adhan5" -> R.raw.adhan5
            "adhan6" -> R.raw.adhan6
            "adhan7" -> R.raw.adhan7
            else -> R.raw.adhan1
        }
    }

    private fun requestAudioFocus(): Boolean {
        val am = audioManager ?: return false

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setOnAudioFocusChangeListener { focusChange ->
                    when (focusChange) {
                        AudioManager.AUDIOFOCUS_LOSS -> {
                            Log.d(TAG, "AudioFocus LOSS — ignoring, Adhan keeps playing")
                            // Don't stop! Adhan is important
                        }
                        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                            Log.d(TAG, "AudioFocus LOSS_TRANSIENT — ignoring")
                        }
                        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                            Log.d(TAG, "AudioFocus DUCK — ignoring, keep full volume")
                        }
                        AudioManager.AUDIOFOCUS_GAIN -> {
                            Log.d(TAG, "AudioFocus GAIN — already playing")
                        }
                    }
                }
                .build()

            val result = am.requestAudioFocus(focusRequest!!)
            result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            val result = am.requestAudioFocus(
                { /* ignore focus changes on old API */ },
                AudioManager.STREAM_ALARM,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
            )
            result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    private fun abandonAudioFocus() {
        val am = audioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { am.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(null)
        }
        focusRequest = null
        audioManager = null
    }
}