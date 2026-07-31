package com.ki1lux.adhani

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

/**
 * Re-arms the prayer schedule when the device's clock or timezone moves.
 *
 * ## Why this exists
 *
 * Prayer alarms are stored as `flutter.prayer_{id}_trigger_millis` — absolute
 * epoch instants, computed from a wall-clock `HH:mm` in whatever timezone the
 * device was in at the time. Nothing recomputed them when that timezone
 * changed.
 *
 * So flying from Algiers to Jakarta (+6h) left five alarms sitting at instants
 * that were still comfortably in the future, and therefore still perfectly
 * valid as far as [AlarmSchedulerHelper] was concerned. They would fire — six
 * hours off — while the notification and widget went on displaying the correct
 * `HH:mm` beside them. Silent, and invisible until the adhan went off at the
 * wrong moment.
 *
 * `TIMEZONE_CHANGED` is also the cheapest reliable signal that the user has
 * travelled any real distance: no location permission, no GPS, no battery
 * cost, and the OS delivers it the moment the network or the user changes the
 * zone.
 *
 * ## What this can and cannot fix
 *
 * It re-derives every trigger from its `HH:mm` string, so the adhan fires at
 * the right *wall-clock* time immediately. It cannot fix the times themselves
 * — those were calculated for the old coordinates, and correcting them needs a
 * new location, which a background receiver has no permission to obtain. That
 * happens on the Dart side via `PrayerTimesNotifier.checkForLocationChange()`
 * the next time the user opens the app. Enqueuing the worker here gets the
 * data refreshed as soon as it's able to be.
 */
class TimeChangeReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "TimeChangeReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d(TAG, "Received $action — re-deriving prayer triggers")

        try {
            // forceRederive: the stored instants were computed in the old zone,
            // so "still in the future" is not evidence that they're correct.
            AlarmSchedulerHelper.rescheduleAllFromPrefs(context, forceRederive = true)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reschedule after $action: ${e.message}")
        }

        try {
            // Repaints the countdown against the new zone straight away.
            PrayerCountdownService.startIfNeeded(context)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to refresh countdown after $action: ${e.message}")
        }

        try {
            // The times themselves may now be for the wrong place. The worker
            // is cache-first and unconstrained, so this is cheap when nothing
            // has actually changed.
            val refresh = OneTimeWorkRequestBuilder<PrayerUpdateWorker>().build()
            WorkManager.getInstance(context).enqueue(refresh)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to enqueue refresh after $action: ${e.message}")
        }
    }
}
