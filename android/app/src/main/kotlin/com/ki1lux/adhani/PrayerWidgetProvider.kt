package com.ki1lux.adhani

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
        if (intent.action == "com.ki1lux.adhani.ACTION_PRAYER_UPDATED") {
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
        /// The ring's unfilled arc reads as a recess, so it's darker than the
        /// card rather than a lighter tint — translucent black over the navy
        /// gradient, which keeps working as that gradient shifts down the card.
        private const val COLOR_RING_TRACK = "#45000000"

        /// The timeline's unspent portion is a rail rather than a recess, so
        /// it stays a light tint.
        private const val COLOR_TRACK = "#33FFFFFF"
        // body at ~40% — passed prayers recede without disappearing.
        private const val COLOR_PASSED = "#66E6F1F9"

        /** Fallback timeline width when the host reports nothing usable. */
        private const val DEFAULT_WIDTH_DP = 320

        /**
         * Row view ids, indexed by prayer id (1..5); index 0 is unused so the
         * arrays line up with the ids used everywhere else in the app.
         *
         * These were resolved with `Resources.getIdentifier("text_name_$i")`,
         * which is a reflection-shaped lookup that R8/AAPT cannot see: it
         * survives today only because resource-name obfuscation happens to be
         * off, and it fails silently — an empty widget, no exception — if that
         * ever changes. Direct R references are checked at compile time.
         */
        private val NAME_VIEW_IDS = intArrayOf(
            0,
            R.id.text_name_1, R.id.text_name_2, R.id.text_name_3,
            R.id.text_name_4, R.id.text_name_5
        )
        private val TIME_VIEW_IDS = intArrayOf(
            0,
            R.id.text_time_1, R.id.text_time_2, R.id.text_time_3,
            R.id.text_time_4, R.id.text_time_5
        )

        /// Shown on the date line once the times are old enough to be visibly
        /// wrong. Deliberately terse — the widget has one line to spare.
        private const val STALE_MARKER = "غير محدّث"

        /// Prayer times drift roughly a minute or two a day, so three days is
        /// where "close enough" stops being true.
        private const val STALE_AFTER_MS = 3 * 24 * 60 * 60 * 1000L

        /// True when the last successful write of prayer data is old enough
        /// that the displayed times can no longer be trusted.
        private fun isStale(prefs: android.content.SharedPreferences): Boolean {
            val raw = prefs.getString("flutter.last_prayer_update", null) ?: return false
            return try {
                val parsed = java.text.SimpleDateFormat(
                    "yyyy-MM-dd'T'HH:mm:ss.SSS", java.util.Locale.US
                ).parse(raw) ?: return false
                System.currentTimeMillis() - parsed.time > STALE_AFTER_MS
            } catch (e: Exception) {
                false
            }
        }

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
            val sizePx = (70 * density).toInt()
            val strokeWidthPx = 7 * density
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
                color = Color.parseColor(COLOR_RING_TRACK)
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
            // Recorded here, where today's parsed time is still known, rather
            // than re-derived later from the rolled-forward trigger. Guessing
            // after the fact ("is it more than 12h away?") misreads Fajr for
            // most of the evening — by 18:00 tomorrow's Fajr is under 12h out,
            // so it looked like it hadn't happened yet today.
            val passedToday = BooleanArray(6)

            // The month cache knows each specific date's times, so it corrects
            // the ~1-2 min/day astronomical drift that the stored HH:mm string
            // freezes in place. Falls back to the prefs when it can't answer —
            // which is what every install has before its first month fetch.
            val monthCache = PrayerMonthCache.read(prefs)
            val cachedToday = monthCache?.dayFor(java.util.Date())

            // 1. Read all 5 prayers, populate text, and find the NEXT prayer
            for (i in 1..5) {
                val name = prefs.getString("flutter.prayer_${i}_name", null)
                val time = cachedToday?.timeForId(i)
                    ?: prefs.getString("flutter.prayer_${i}_time", "--:--")
                    ?: "--:--"

                // Parse the time string directly instead of relying on the alarm trigger_millis
                // because the alarm trigger_millis might not be updated if the user disabled the Adhan for this prayer.
                val todayMillis = todayMillisFor(time)
                passedToday[i] = todayMillis != null && todayMillis <= now

                var actualTriggerMillis = todayMillis ?: 0L
                if (actualTriggerMillis != 0L && actualTriggerMillis <= now) {
                    actualTriggerMillis += 24 * 60 * 60 * 1000L
                }
                computedTriggers[i] = actualTriggerMillis

                // Populate text
                if (name != null) {
                    views.setTextViewText(NAME_VIEW_IDS[i], name)
                    views.setTextViewText(TIME_VIEW_IDS[i], time)
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
                if (computedTriggers[i] == 0L) continue

                val color = when {
                    i == nextPrayerId -> COLOR_ACCENT
                    passedToday[i] -> COLOR_PASSED
                    else -> COLOR_BODY
                }
                views.setTextColor(NAME_VIEW_IDS[i], Color.parseColor(color))
                views.setTextColor(TIME_VIEW_IDS[i], Color.parseColor(color))
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
            // Resolved from the cache, and Maghrib-aware: the Islamic day
            // begins at sunset, so after Maghrib this is already the next
            // Gregorian day's Hijri value. `cached_hijri_date` is a single
            // stored string that only changed when something wrote it, so it
            // showed the date of whenever the last successful fetch happened.
            val hijri = monthCache?.hijriNow()
                ?: prefs.getString("flutter.cached_hijri_date", null)
                ?: ""
            var dateLine = when {
                city.isNotEmpty() && hijri.isNotEmpty() -> "$city • $hijri"
                city.isNotEmpty() -> city
                hijri.isNotEmpty() -> hijri
                else -> ""
            }

            // Say so when the data is old enough that the times on the widget
            // have visibly drifted. `flutter.last_prayer_update` has been
            // written by two different code paths all along and read by none of
            // them, so a month-old table rendered exactly like a fresh one.
            if (cachedToday == null && isStale(prefs)) {
                dateLine = if (dateLine.isEmpty()) STALE_MARKER else "$dateLine • $STALE_MARKER"
            }

            views.setTextViewText(R.id.widget_date_line, dateLine)

            // Instruct the widget manager to update the widget
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
