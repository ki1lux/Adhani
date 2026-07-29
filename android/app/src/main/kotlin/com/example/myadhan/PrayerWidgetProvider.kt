package com.example.myadhan

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Bundle
import android.os.SystemClock
import android.widget.RemoteViews
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

class PrayerWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        // Update all instances of this widget
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    /**
     * The timeline is drawn as a bitmap sized to the widget's actual width,
     * so a resize has to redraw it — otherwise it stays stretched or
     * squashed at the previous size.
     */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        updateAppWidget(context, appWidgetManager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        // If data was refreshed, update all widgets
        if (intent.action == "com.example.myadhan.ACTION_PRAYER_UPDATED") {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = android.content.ComponentName(context, PrayerWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            onUpdate(context, appWidgetManager, appWidgetIds)
        }
    }

    companion object {
        private const val PREFS_NAME = "FlutterSharedPreferences"

        // Mirrors lib/theme/app_colors.dart — RemoteViews layouts/bitmaps
        // can't reference Dart constants, so these are hand-copied. Keep in
        // sync if the palette changes.
        private const val COLOR_ACCENT = "#7AD2F7"
        private const val COLOR_BODY = "#E6F1F9"
        private const val COLOR_MUTED = "#A9C3D6"
        private const val COLOR_TRACK = "#33FFFFFF"
        // body at ~40% — passed prayers recede without disappearing.
        private const val COLOR_PASSED = "#66E6F1F9"

        /** Fallback timeline width when the host reports nothing usable. */
        private const val DEFAULT_WIDTH_DP = 320

        /// Parses an "HH:mm" prayer time into today's epoch millis.
        private fun todayMillisFor(time: String): Long? {
            val parts = time.split(":")
            if (parts.size != 2) return null
            return try {
                val hour = parts[0].toInt()
                val minute = parts[1].toInt()
                val cal = java.util.Calendar.getInstance()
                cal.set(java.util.Calendar.HOUR_OF_DAY, hour)
                cal.set(java.util.Calendar.MINUTE, minute)
                cal.set(java.util.Calendar.SECOND, 0)
                cal.set(java.util.Calendar.MILLISECOND, 0)
                cal.timeInMillis
            } catch (e: Exception) {
                null
            }
        }

        /// Sunrise for Fajr, sun through the middle of the day, sunset for
        /// Maghrib, moon for Isha — the header icon tracks which prayer is
        /// actually next rather than always showing the same glyph.
        private fun iconForPrayer(prayerId: Int): Int = when (prayerId) {
            1 -> R.drawable.ic_widget_sunrise
            2, 3 -> R.drawable.ic_widget_sun
            4 -> R.drawable.ic_widget_sunset
            else -> R.drawable.ic_widget_moon
        }

        /// Draws the "percent of the interval elapsed" ring shown beside the
        /// next-prayer header — a plain arc plus a knob at its leading edge,
        /// with no baked-in text, so the percentage/caption stay as crisp
        /// overlaid TextViews.
        private fun createRingBitmap(context: Context, percent: Int): Bitmap {
            val density = context.resources.displayMetrics.density
            // Must match the FrameLayout's dp size in the layout, or the
            // bitmap gets rescaled and the stroke goes soft.
            val sizePx = (56 * density).toInt()
            val strokeWidthPx = 5.5f * density
            val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val inset = strokeWidthPx / 2
            val rect = RectF(inset, inset, sizePx - inset, sizePx - inset)

            // Note: `strokeWidth = strokeWidth` inside apply{} would resolve
            // the right-hand side to Paint's own property (a no-op self
            // assignment), not the local variable — hence the Px suffix.
            val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = strokeWidthPx
                strokeCap = Paint.Cap.ROUND
                color = Color.parseColor(COLOR_TRACK)
            }
            canvas.drawOval(rect, trackPaint)

            val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = strokeWidthPx
                strokeCap = Paint.Cap.ROUND
                color = Color.parseColor(COLOR_ACCENT)
            }
            val fraction = percent.coerceIn(0, 100) / 100f
            val sweep = 360f * fraction
            if (sweep > 0f) {
                canvas.drawArc(rect, -90f, sweep, false, progressPaint)

                // Knob at the arc's leading edge.
                val radius = (sizePx - strokeWidthPx) / 2f
                val angle = Math.toRadians((-90f + sweep).toDouble())
                val knobX = sizePx / 2f + radius * cos(angle).toFloat()
                val knobY = sizePx / 2f + radius * sin(angle).toFloat()
                val knobPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.FILL
                    color = Color.WHITE
                }
                canvas.drawCircle(knobX, knobY, strokeWidthPx * 0.62f, knobPaint)
            }

            return bitmap
        }

        /// The day timeline under the countdown. Filled right-to-left to
        /// match the RTL prayer row beneath it, with a knob marking now.
        /// Drawn rather than using a ProgressBar because a clip-based
        /// progress drawable can't render that knob.
        private fun createTimelineBitmap(context: Context, percent: Int, widthDp: Int): Bitmap {
            val density = context.resources.displayMetrics.density
            val widthPx = (widthDp * density).toInt().coerceAtLeast(1)
            // Must match the ImageView's dp height in the layout; the knob's
            // diameter also has to fit inside it or it renders clipped.
            val heightPx = (11 * density).toInt().coerceAtLeast(1)
            val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)

            val centerY = heightPx / 2f
            val lineWidth = 3 * density
            val knobRadius = 4.5f * density
            // Inset by the knob so it isn't clipped at either end.
            val left = knobRadius
            val right = widthPx - knobRadius

            val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = lineWidth
                strokeCap = Paint.Cap.ROUND
                color = Color.parseColor(COLOR_TRACK)
            }
            canvas.drawLine(left, centerY, right, centerY, trackPaint)

            val fraction = percent.coerceIn(0, 100) / 100f
            val knobX = right - (right - left) * fraction

            if (fraction > 0f) {
                val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = lineWidth
                    strokeCap = Paint.Cap.ROUND
                    color = Color.parseColor(COLOR_ACCENT)
                }
                canvas.drawLine(knobX, centerY, right, centerY, fillPaint)
            }

            val knobPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.FILL
                color = Color.WHITE
            }
            canvas.drawCircle(knobX, centerY, knobRadius, knobPaint)

            return bitmap
        }

        internal fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_prayer_times)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            // Intent to open the app when tapped
            val pendingIntent: PendingIntent = Intent(context, MainActivity::class.java).let { intent ->
                PendingIntent.getActivity(
                    context,
                    0,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            }
            views.setOnClickPendingIntent(R.id.widget_countdown, pendingIntent)

            val now = System.currentTimeMillis()
            var nextPrayerId = -1
            var minTriggerMillis = Long.MAX_VALUE
            var nextPrayerName = "جارٍ التحميل"
            var nextPrayerTime = ""

            val computedTriggers = LongArray(6)

            // 1. Read all 5 prayers, populate text, and find the NEXT prayer
            for (i in 1..5) {
                val name = prefs.getString("flutter.prayer_${i}_name", null)
                val time = prefs.getString("flutter.prayer_${i}_time", "--:--") ?: "--:--"

                // Parse the time string directly instead of relying on the alarm trigger_millis
                // because the alarm trigger_millis might not be updated if the user disabled the Adhan for this prayer.
                var actualTriggerMillis = todayMillisFor(time) ?: 0L
                if (actualTriggerMillis != 0L && actualTriggerMillis <= now) {
                    actualTriggerMillis += 24 * 60 * 60 * 1000L
                }
                computedTriggers[i] = actualTriggerMillis

                // Populate text
                val nameResId = context.resources.getIdentifier("text_name_$i", "id", context.packageName)
                val timeResId = context.resources.getIdentifier("text_time_$i", "id", context.packageName)

                if (name != null && nameResId != 0 && timeResId != 0) {
                    views.setTextViewText(nameResId, name)
                    views.setTextViewText(timeResId, time)
                }

                // Determine if this is the upcoming prayer
                if (actualTriggerMillis > now && actualTriggerMillis < minTriggerMillis) {
                    minTriggerMillis = actualTriggerMillis
                    nextPrayerId = i
                    if (name != null) {
                        nextPrayerName = name
                        nextPrayerTime = time
                    }
                }
            }

            // 2. Three states across the row: the next prayer in accent, ones
            // already prayed today dimmed, the rest normal.
            for (i in 1..5) {
                val nameResId = context.resources.getIdentifier("text_name_$i", "id", context.packageName)
                val timeResId = context.resources.getIdentifier("text_time_$i", "id", context.packageName)
                val triggerMillis = computedTriggers[i]
                if (nameResId == 0 || timeResId == 0 || triggerMillis == 0L) continue

                // Anything pushed to tomorrow by the parsing above already
                // happened today; compare against that original time.
                val timeToday = if (triggerMillis > now + 12 * 60 * 60 * 1000L) {
                    triggerMillis - 24 * 60 * 60 * 1000L
                } else {
                    triggerMillis
                }

                val color = when {
                    i == nextPrayerId -> COLOR_ACCENT
                    timeToday <= now -> COLOR_PASSED
                    else -> COLOR_BODY
                }
                views.setTextColor(nameResId, Color.parseColor(color))
                views.setTextColor(timeResId, Color.parseColor(color))
            }

            // The timeline bitmap is sized to the widget's real width so the
            // knob lands at a true position rather than a stretched one.
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
                .takeIf { it > 0 } ?: DEFAULT_WIDTH_DP

            // 3. Header: next prayer's time + name, and the progress ring —
            // percent of the interval since the previous prayer that has
            // already elapsed.
            if (nextPrayerId != -1) {
                views.setTextViewText(R.id.widget_next_prayer_time, nextPrayerTime)
                views.setTextViewText(R.id.widget_next_prayer_name, nextPrayerName)
                views.setImageViewResource(R.id.widget_prayer_icon, iconForPrayer(nextPrayerId))

                val previousId = if (nextPrayerId == 1) 5 else nextPrayerId - 1
                val previousTimeStr = prefs.getString("flutter.prayer_${previousId}_time", null)
                var previousTriggerMillis = previousTimeStr?.let { todayMillisFor(it) }
                // The previous prayer's own next occurrence is always in the
                // future (same parsing rule as above) — its *last*
                // occurrence, which is what the interval start needs, is
                // today's parsed time if that's already past, or yesterday's
                // if today's hasn't happened yet (only possible right after
                // midnight, before the previous prayer's time today).
                if (previousTriggerMillis != null && previousTriggerMillis > now) {
                    previousTriggerMillis -= 24 * 60 * 60 * 1000L
                }

                val percent =
                    if (previousTriggerMillis != null && previousTriggerMillis < minTriggerMillis) {
                        val total = minTriggerMillis - previousTriggerMillis
                        val elapsed = now - previousTriggerMillis
                        ((elapsed.toFloat() / total.toFloat()) * 100).roundToInt().coerceIn(0, 100)
                    } else {
                        0
                    }

                views.setTextViewText(R.id.widget_progress_percent, "$percent")
                views.setImageViewBitmap(R.id.widget_progress_ring, createRingBitmap(context, percent))
                views.setImageViewBitmap(
                    R.id.widget_progress_line,
                    createTimelineBitmap(context, percent, widthDp)
                )

                // Convert epoch millis to SystemClock elapsedRealtime base
                val offset = minTriggerMillis - System.currentTimeMillis()
                val baseTime = SystemClock.elapsedRealtime() + offset
                views.setChronometer(R.id.widget_countdown, baseTime, "%s", true)
            } else {
                views.setTextViewText(R.id.widget_next_prayer_name, "افتح التطبيق للمزامنة")
                views.setTextViewText(R.id.widget_next_prayer_time, "--:--")
                views.setTextViewText(R.id.widget_progress_percent, "--")
                views.setImageViewBitmap(R.id.widget_progress_ring, createRingBitmap(context, 0))
                views.setImageViewBitmap(
                    R.id.widget_progress_line,
                    createTimelineBitmap(context, 0, widthDp)
                )
            }

            // 4. City + Hijri date line — same cached keys and "•" join
            // PrayerCountdownService's notification title already uses.
            val city = prefs.getString("flutter.city_name", null) ?: ""
            val hijri = prefs.getString("flutter.cached_hijri_date", null) ?: ""
            val dateLine = when {
                city.isNotEmpty() && hijri.isNotEmpty() -> "$city • $hijri"
                city.isNotEmpty() -> city
                hijri.isNotEmpty() -> hijri
                else -> ""
            }
            views.setTextViewText(R.id.widget_date_line, dateLine)

            // Instruct the widget manager to update the widget
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
