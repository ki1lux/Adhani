package com.ki1lux.adhani

import android.util.Log
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * Lightweight HTTP client for the Aladhan prayer-times API.
 * Uses java.net.HttpURLConnection — no external dependencies.
 *
 * API docs: https://aladhan.com/prayer-times-api
 */
object AladhanApiClient {

    private const val TAG = "AladhanApiClient"
    private const val BASE_URL = "https://api.aladhan.com/v1/timings"
    private const val CALENDAR_URL = "https://api.aladhan.com/v1/calendar"
    private const val TIMEOUT_MS = 15_000

    /** A month's worth of days is a bigger read than one day's timings. */
    private const val MONTH_TIMEOUT_MS = 25_000

    /**
     * Fetches today's prayer times for the given coordinates.
     *
     * @param latitude  User latitude
     * @param longitude User longitude
     * @param method    Calculation method (19 = Algeria)
     * @param school    Juristic school (0 = Shafi)
     * @return [PrayerTimesResponse] on success, null on failure
     */
    fun fetchPrayerTimes(
        latitude: Double,
        longitude: Double,
        method: Int = 19,
        school: Int = 0,
        date: java.util.Date? = null
    ): PrayerTimesResponse? {
        val dateFormat = java.text.SimpleDateFormat("dd-MM-yyyy", java.util.Locale.US)
        val dateString = dateFormat.format(date ?: java.util.Date())
        val urlStr = "$BASE_URL/$dateString?latitude=$latitude&longitude=$longitude&method=$method&school=$school"

        Log.d(TAG, "Fetching: $urlStr")

        var connection: HttpURLConnection? = null
        try {
            connection = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = TIMEOUT_MS
                readTimeout = TIMEOUT_MS
            }

            if (connection.responseCode != 200) {
                Log.e(TAG, "HTTP ${connection.responseCode}")
                return null
            }

            val body = BufferedReader(InputStreamReader(connection.inputStream)).use { it.readText() }
            val json = JSONObject(body)

            if (json.getInt("code") != 200) {
                Log.e(TAG, "API error: ${json.optString("status")}")
                return null
            }

            val data = json.getJSONObject("data")
            val timings = data.getJSONObject("timings")
            val hijriObj = data.getJSONObject("date").getJSONObject("hijri")

            val hijriStr = "${hijriObj.getString("day")} " +
                    "${hijriObj.getJSONObject("month").getString("ar")} " +
                    hijriObj.getString("year")

            return PrayerTimesResponse(
                fajr    = addMinutes(timings.getString("Fajr"), 1),
                dhuhr   = addMinutes(timings.getString("Dhuhr"), 1),
                asr     = addMinutes(timings.getString("Asr"), 2),
                maghrib = addMinutes(timings.getString("Maghrib"), 4),
                isha    = addMinutes(timings.getString("Isha"), 3),
                hijriDate = hijriStr
            )
        } catch (e: Exception) {
            Log.e(TAG, "Fetch failed: ${e.message}")
            return null
        } finally {
            connection?.disconnect()
        }
    }

    /**
     * Fetches a whole month of prayer times in one request.
     *
     * This is what lets the native side survive offline: one call covers ~30
     * days, so [PrayerMonthCache] can arm alarms and drive the countdown for
     * any of them with no connection. It reuses [addMinutes] so a day served
     * from the cache is byte-identical to the same day fetched live — anything
     * else and prayer times would visibly shift the moment the network dropped.
     *
     * @return days keyed "yyyy-MM-dd", or null on any failure.
     */
    fun fetchMonth(
        latitude: Double,
        longitude: Double,
        year: Int,
        month: Int,
        method: Int = 19,
        school: Int = 0
    ): Map<String, PrayerMonthCache.Day>? {
        val urlStr = "$CALENDAR_URL/$year/$month" +
                "?latitude=$latitude&longitude=$longitude&method=$method&school=$school"

        Log.d(TAG, "Fetching month: $urlStr")

        var connection: HttpURLConnection? = null
        try {
            connection = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = TIMEOUT_MS
                readTimeout = MONTH_TIMEOUT_MS
            }

            if (connection.responseCode != 200) {
                Log.e(TAG, "HTTP ${connection.responseCode}")
                return null
            }

            val body = BufferedReader(InputStreamReader(connection.inputStream)).use { it.readText() }
            val json = JSONObject(body)

            if (json.getInt("code") != 200) {
                Log.e(TAG, "API error: ${json.optString("status")}")
                return null
            }

            val data = json.getJSONArray("data")
            val days = HashMap<String, PrayerMonthCache.Day>(data.length())

            for (i in 0 until data.length()) {
                val entry = data.getJSONObject(i)
                val timings = entry.getJSONObject("timings")
                val date = entry.getJSONObject("date")

                // The calendar endpoint dates each entry "DD-MM-YYYY"; the
                // cache is keyed the sortable way round.
                val parts = date.getJSONObject("gregorian").getString("date").split("-")
                if (parts.size != 3) continue
                val key = "${parts[2]}-${parts[1]}-${parts[0]}"

                val hijriObj = date.getJSONObject("hijri")
                val hijriStr = "${hijriObj.getString("day")} " +
                        "${hijriObj.getJSONObject("month").getString("ar")} " +
                        hijriObj.getString("year")

                days[key] = PrayerMonthCache.Day(
                    fajr    = addMinutes(timings.getString("Fajr"), 1),
                    dhuhr   = addMinutes(timings.getString("Dhuhr"), 1),
                    asr     = addMinutes(timings.getString("Asr"), 2),
                    maghrib = addMinutes(timings.getString("Maghrib"), 4),
                    isha    = addMinutes(timings.getString("Isha"), 3),
                    hijri   = hijriStr
                )
            }

            if (days.isEmpty()) {
                Log.e(TAG, "Calendar response contained no usable days")
                return null
            }

            Log.d(TAG, "Fetched ${days.size} days for $year-$month")
            return days
        } catch (e: Exception) {
            Log.e(TAG, "Month fetch failed: ${e.message}")
            return null
        } finally {
            connection?.disconnect()
        }
    }

    /** Strip any timezone suffix like " (CEST)" → keep only "HH:mm" and add minutes */
    private fun addMinutes(raw: String, minutesToAdd: Int): String {
        return try {
            val clean = raw.split(" ").first()
            val parts = clean.split(":")
            var hr = parts[0].toInt()
            var min = parts[1].toInt()
            
            min += minutesToAdd
            if (min >= 60) {
                hr += min / 60
                min %= 60
            }
            if (hr >= 24) hr %= 24
            
            String.format(java.util.Locale.US, "%02d:%02d", hr, min)
        } catch (e: Exception) {
            raw.split(" ").first()
        }
    }

    data class PrayerTimesResponse(
        val fajr: String,
        val dhuhr: String,
        val asr: String,
        val maghrib: String,
        val isha: String,
        val hijriDate: String
    )
}
