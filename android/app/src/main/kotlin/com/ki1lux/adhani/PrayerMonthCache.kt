package com.ki1lux.adhani

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Native half of the month-ahead prayer time cache.
 *
 * This is the mirror of `lib/services/prayer_times_cache.dart` — **the two
 * must be changed together**, exactly as CLAUDE.md requires of every shared
 * SharedPreferences key. Dart writes `prayer_month_cache`; the plugin stores
 * plain Strings unmangled, so we read the same bytes back as
 * `flutter.prayer_month_cache` with no MethodChannel involved.
 *
 * Why this exists: the native side is the half that has to keep working with
 * the Dart isolate dead. Before this, every native path that needed a prayer
 * time either had one day of it in prefs or went to the network — so a device
 * offline for two days had no alarms and a frozen countdown. A month of days
 * on disk means [dayFor] can answer for any date without a connection.
 *
 * Schema (v1):
 * ```
 * {"v":1,"lat":36.75,"lng":3.06,"method":19,"school":0,
 *  "fetchedAt":"2026-07-30T09:12:00.000",
 *  "days":{"2026-07-30":{"fajr":"04:12",...,"hijri":"15 محرم 1448"}}}
 * ```
 * Times are already offset-adjusted (+1/+1/+2/+4/+3) by whichever side wrote
 * them, so a cached day is a drop-in for what `prayer_{id}_time` holds.
 */
object PrayerMonthCache {

    private const val TAG = "PrayerMonthCache"
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY = "flutter.prayer_month_cache"
    private const val SCHEMA_VERSION = 1

    /** Matches `PrayerTimesCache._staleDistanceKm` on the Dart side. */
    private const val STALE_DISTANCE_KM = 25.0

    data class Day(
        val fajr: String,
        val dhuhr: String,
        val asr: String,
        val maghrib: String,
        val isha: String,
        val hijri: String
    ) {
        /** Prayer IDs are 1..5 everywhere in this app. */
        fun timeForId(id: Int): String = when (id) {
            1 -> fajr
            2 -> dhuhr
            3 -> asr
            4 -> maghrib
            else -> isha
        }
    }

    data class Cache(
        val latitude: Double,
        val longitude: Double,
        val method: Int,
        val school: Int,
        val fetchedAtMillis: Long,
        val days: Map<String, Day>
    ) {
        fun dayFor(date: Date): Day? = days[dayKey(date)]

        fun coversToday(): Boolean = dayFor(Date()) != null

        /** Latest date this cache can answer for, or null when it holds nothing. */
        fun coverageEndMillis(): Long? {
            val last = days.keys.maxOrNull() ?: return null
            return parseDayKey(last)
        }

        fun isNear(lat: Double, lng: Double): Boolean =
            distanceKm(latitude, longitude, lat, lng) <= STALE_DISTANCE_KM

        /**
         * The Hijri date that is in effect *right now*.
         *
         * The Islamic day begins at sunset, so from Maghrib onwards the date in
         * effect is the next Gregorian day's Hijri value. That is what keeps the
         * displayed date in step with the prayer schedule rather than at odds
         * with it: Maghrib and Isha of a given evening belong to the Islamic day
         * that has just begun, not the one that just ended.
         *
         * This is a pure function of the current time and the cache, evaluated
         * on every notification tick. The date it returns therefore flips the
         * moment Maghrib arrives, with no fetch, no write and no connection.
         * The old behaviour read a single stored `cached_hijri_date` string,
         * which only ever changed when something happened to write it — so in
         * practice the date advanced whenever the 00:05 worker next ran.
         *
         * Returns null when the cache can't answer, leaving the caller on its
         * existing fallback.
         */
        fun hijriNow(now: Calendar = Calendar.getInstance()): String? {
            val today = dayFor(now.time) ?: return null

            val maghribMillis = millisOn(now, today.maghrib)
            if (maghribMillis == null || now.timeInMillis < maghribMillis) {
                return today.hijri.ifEmpty { null }
            }

            // Past Maghrib: the Islamic day has already turned over.
            val tomorrow = (now.clone() as Calendar).apply {
                add(Calendar.DAY_OF_YEAR, 1)
            }
            return dayFor(tomorrow.time)?.hijri?.ifEmpty { null }
                ?: today.hijri.ifEmpty { null }
        }
    }

    /** Resolves an "HH:mm" string against the calendar day of [day]. */
    private fun millisOn(day: Calendar, time: String): Long? {
        val parts = time.split(" ")[0].split(":")
        if (parts.size != 2) return null
        val hour = parts[0].toIntOrNull() ?: return null
        val minute = parts[1].toIntOrNull() ?: return null

        return (day.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }

    fun dayKey(date: Date): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(date)

    fun dayKey(cal: Calendar): String = dayKey(cal.time)

    private fun parseDayKey(key: String): Long? = try {
        SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(key)?.time
    } catch (e: Exception) {
        null
    }

    fun read(context: Context): Cache? =
        read(context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE))

    fun read(prefs: SharedPreferences): Cache? {
        val raw = try {
            prefs.getString(KEY, null)
        } catch (e: ClassCastException) {
            Log.w(TAG, "Cache key held an unexpected type")
            null
        } ?: return null

        if (raw.isEmpty()) return null

        return try {
            val json = JSONObject(raw)
            if (json.optInt("v", -1) != SCHEMA_VERSION) {
                Log.w(TAG, "Ignoring cache with schema v${json.optInt("v", -1)}")
                return null
            }

            val daysJson = json.getJSONObject("days")
            val days = HashMap<String, Day>(daysJson.length())
            val keys = daysJson.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                val d = daysJson.getJSONObject(key)
                days[key] = Day(
                    fajr = d.getString("fajr"),
                    dhuhr = d.getString("dhuhr"),
                    asr = d.getString("asr"),
                    maghrib = d.getString("maghrib"),
                    isha = d.getString("isha"),
                    hijri = d.optString("hijri", "")
                )
            }

            Cache(
                latitude = json.getDouble("lat"),
                longitude = json.getDouble("lng"),
                method = json.optInt("method", 19),
                school = json.optInt("school", 0),
                fetchedAtMillis = parseIso(json.optString("fetchedAt")),
                days = days
            )
        } catch (e: Exception) {
            // A corrupt cache is worth exactly what no cache is worth, and
            // every caller already handles null.
            Log.e(TAG, "Failed to parse cache: ${e.message}")
            null
        }
    }

    /**
     * Merges [days] into whatever is stored and writes the result back.
     *
     * A change of place or calculation method invalidates the existing days
     * outright — they describe somewhere else, not an earlier time.
     */
    fun merge(
        context: Context,
        days: Map<String, Day>,
        latitude: Double,
        longitude: Double,
        method: Int,
        school: Int = 0
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val existing = read(prefs)

        val keepExisting = existing != null &&
                existing.method == method &&
                existing.school == school &&
                existing.isNear(latitude, longitude)

        val merged = HashMap<String, Day>()
        if (keepExisting) merged.putAll(existing!!.days)
        merged.putAll(days)

        write(prefs, prune(merged), latitude, longitude, method, school)
    }

    private fun write(
        prefs: SharedPreferences,
        days: Map<String, Day>,
        latitude: Double,
        longitude: Double,
        method: Int,
        school: Int
    ) {
        try {
            val daysJson = JSONObject()
            for ((key, day) in days) {
                daysJson.put(
                    key,
                    JSONObject()
                        .put("fajr", day.fajr)
                        .put("dhuhr", day.dhuhr)
                        .put("asr", day.asr)
                        .put("maghrib", day.maghrib)
                        .put("isha", day.isha)
                        .put("hijri", day.hijri)
                )
            }

            val root = JSONObject()
                .put("v", SCHEMA_VERSION)
                .put("lat", latitude)
                .put("lng", longitude)
                .put("method", method)
                .put("school", school)
                .put("fetchedAt", isoNow())
                .put("days", daysJson)

            prefs.edit().putString(KEY, root.toString()).apply()
            Log.d(TAG, "💾 Cached ${days.size} days")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write cache: ${e.message}")
        }
    }

    /**
     * Drops days before yesterday. Yesterday stays because just after midnight
     * the countdown service can still be resolving the previous day's Isha.
     */
    private fun prune(days: Map<String, Day>): Map<String, Day> {
        val cutoff = dayKey(Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, -1)
        })
        return days.filterKeys { it >= cutoff }
    }

    /** Great-circle distance, same haversine the Dart side uses. */
    private fun distanceKm(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
        val earthRadiusKm = 6371.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLng = Math.toRadians(lng2 - lng1)
        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                Math.sin(dLng / 2) * Math.sin(dLng / 2)
        return earthRadiusKm * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    }

    private fun isoNow(): String = SimpleDateFormat(
        "yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US
    ).format(Date())

    private fun parseIso(value: String?): Long {
        if (value.isNullOrEmpty()) return 0L
        return try {
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US).parse(value)?.time ?: 0L
        } catch (e: Exception) {
            0L
        }
    }
}
