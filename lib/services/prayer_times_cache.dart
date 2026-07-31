import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// On-disk cache of a month (or two) of prayer times.
///
/// The app used to hold exactly one day of times, live, in memory — so with no
/// connection there was nothing to show and nothing to schedule alarms from.
/// Fetching a whole month at once means one successful request buys ~30 days of
/// full offline operation for the UI, the alarms, the widget and the countdown.
///
/// ## The shared key
///
/// This is written by Dart as `prayer_month_cache` and read by Kotlin as
/// `flutter.prayer_month_cache` (see `PrayerMonthCache.kt`), following the same
/// contract as every other key in CLAUDE.md's shared-storage section. Plain
/// [String] values are stored unmangled by `shared_preferences` — only doubles
/// and lists get a type prefix — so the native side reads it with a plain
/// `prefs.getString` and no MethodChannel is involved.
///
/// **Any change to [_key] or to the JSON schema below must be made on both
/// sides in the same commit**, or the two halves of the app silently diverge.
class PrayerTimesCache {
  static const _key = 'prayer_month_cache';

  /// Bumped when the JSON shape changes incompatibly. A cache written by an
  /// older/newer schema is discarded rather than misread.
  static const _schemaVersion = 1;

  /// How far the user can move before the cached month stops describing where
  /// they are. Prayer times shift by roughly a minute per 25km of longitude at
  /// mid latitudes, which is the same order as the rounding already in play.
  static const _staleDistanceKm = 25.0;

  const PrayerTimesCache();

  Future<MonthCache?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_key));
  }

  /// Reads without a fresh [SharedPreferences] round trip, for callers that
  /// already hold an instance.
  MonthCache? readFrom(SharedPreferences prefs) => _decode(prefs.getString(_key));

  Future<void> write(MonthCache cache) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(cache.toJson()));
  }

  /// Merges [days] into whatever is already cached, so fetching next month
  /// near a month boundary extends coverage instead of replacing it.
  ///
  /// A change of location or calculation method invalidates the old days
  /// entirely — they describe a different place, not an earlier time.
  Future<MonthCache> merge({
    required Map<String, CachedDay> days,
    required double latitude,
    required double longitude,
    required int method,
    required int school,
  }) async {
    final existing = await read();
    final keepExisting = existing != null &&
        existing.method == method &&
        existing.school == school &&
        existing.isNear(latitude, longitude);

    final merged = <String, CachedDay>{
      if (keepExisting) ...existing.days,
      ...days,
    };

    final cache = MonthCache(
      latitude: latitude,
      longitude: longitude,
      method: method,
      school: school,
      fetchedAt: DateTime.now(),
      days: _prune(merged),
    );

    await write(cache);
    return cache;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  MonthCache? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return MonthCache.fromJson(decoded);
    } catch (_) {
      // A corrupt or older-schema cache is worth exactly as much as no cache,
      // and the caller's no-cache path is already correct.
      return null;
    }
  }

  /// Drops days before yesterday. Yesterday is kept because the countdown
  /// service can still be resolving "yesterday's Isha" just after midnight.
  static Map<String, CachedDay> _prune(Map<String, CachedDay> days) {
    final cutoff = MonthCache.dayKey(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    return {
      for (final entry in days.entries)
        if (entry.key.compareTo(cutoff) >= 0) entry.key: entry.value,
    };
  }
}

/// One day's worth of already-offset-adjusted times.
///
/// The `+1/+1/+2/+4/+3` minute offsets live in the API clients and are applied
/// *before* anything reaches this cache, so a cached day is a drop-in
/// replacement for what the `prayer_{id}_time` prefs already hold.
class CachedDay {
  final String fajr;
  final String dhuhr;
  final String asr;
  final String maghrib;
  final String isha;
  final String hijri;

  const CachedDay({
    required this.fajr,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
    required this.hijri,
  });

  /// Indexed the same way prayer IDs are everywhere else: 1..5.
  String timeForId(int id) => switch (id) {
        1 => fajr,
        2 => dhuhr,
        3 => asr,
        4 => maghrib,
        _ => isha,
      };

  factory CachedDay.fromJson(Map<String, dynamic> json) => CachedDay(
        fajr: json['fajr'] as String,
        dhuhr: json['dhuhr'] as String,
        asr: json['asr'] as String,
        maghrib: json['maghrib'] as String,
        isha: json['isha'] as String,
        hijri: (json['hijri'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'fajr': fajr,
        'dhuhr': dhuhr,
        'asr': asr,
        'maghrib': maghrib,
        'isha': isha,
        'hijri': hijri,
      };
}

/// The cache payload: which place and method these days describe, when they
/// were fetched, and the days themselves keyed by `yyyy-MM-dd`.
class MonthCache {
  final double latitude;
  final double longitude;
  final int method;
  final int school;
  final DateTime fetchedAt;
  final Map<String, CachedDay> days;

  const MonthCache({
    required this.latitude,
    required this.longitude,
    required this.method,
    required this.school,
    required this.fetchedAt,
    required this.days,
  });

  static String dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  CachedDay? dayFor(DateTime date) => days[dayKey(date)];

  bool get coversToday => dayFor(DateTime.now()) != null;

  /// The last day this cache can answer for, or null if it holds nothing.
  DateTime? get coverageEnd {
    if (days.isEmpty) return null;
    final last = days.keys.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
    return DateTime.tryParse(last);
  }

  /// True when the cached days still describe roughly where the user is.
  ///
  /// Great-circle distance via the haversine formula — the same approach
  /// `QiblaScreen` already uses for its distance-to-Mecca readout.
  bool isNear(double lat, double lng) =>
      _distanceKm(latitude, longitude, lat, lng) <=
      PrayerTimesCache._staleDistanceKm;

  /// Usable as-is: right place, right method, and it knows about today.
  bool isFreshFor(double lat, double lng, int method) =>
      this.method == method && isNear(lat, lng) && coversToday;

  /// The Hijri date in effect at [at] (defaults to now).
  ///
  /// The Islamic day begins at sunset, so from Maghrib onwards this is the
  /// *next* Gregorian day's Hijri value. That is what keeps the date in step
  /// with the prayer schedule rather than at odds with it: Maghrib and Isha of
  /// a given evening belong to the Islamic day that has just begun, not the one
  /// that just ended.
  ///
  /// Returns null when the cache can't answer, leaving the caller on whatever
  /// fallback it already had.
  String? hijriNow([DateTime? at]) {
    final now = at ?? DateTime.now();
    final today = dayFor(now);
    if (today == null) return null;

    final maghrib = _timeOn(now, today.maghrib);
    if (maghrib == null || now.isBefore(maghrib)) {
      return today.hijri.isEmpty ? null : today.hijri;
    }

    final tomorrow = dayFor(now.add(const Duration(days: 1)));
    final next = tomorrow?.hijri;
    if (next != null && next.isNotEmpty) return next;
    return today.hijri.isEmpty ? null : today.hijri;
  }

  /// Resolves an "HH:mm" string against the calendar day of [day].
  static DateTime? _timeOn(DateTime day, String time) {
    final parts = time.split(' ').first.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  static double _distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    double toRad(double d) => d * math.pi / 180.0;

    final dLat = toRad(lat2 - lat1);
    final dLng = toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat1)) *
            math.cos(toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  factory MonthCache.fromJson(Map<String, dynamic> json) {
    if (json['v'] != PrayerTimesCache._schemaVersion) {
      throw const FormatException('prayer_month_cache: unsupported schema');
    }

    final rawDays = json['days'];
    if (rawDays is! Map) {
      throw const FormatException('prayer_month_cache: malformed days');
    }

    return MonthCache(
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      method: (json['method'] as num).toInt(),
      school: (json['school'] as num?)?.toInt() ?? 0,
      fetchedAt:
          DateTime.tryParse(json['fetchedAt'] as String? ?? '') ?? DateTime.now(),
      days: {
        for (final entry in rawDays.entries)
          entry.key as String:
              CachedDay.fromJson(Map<String, dynamic>.from(entry.value as Map)),
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'v': PrayerTimesCache._schemaVersion,
        'lat': latitude,
        'lng': longitude,
        'method': method,
        'school': school,
        'fetchedAt': fetchedAt.toIso8601String(),
        'days': {
          for (final entry in days.entries) entry.key: entry.value.toJson(),
        },
      };
}
