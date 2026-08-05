import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myadhan/services/app_logger.dart';
import 'package:myadhan/controller/LocationController.dart';
import 'package:myadhan/model/PrayerTimeModel.dart';
import 'package:myadhan/services/app_exception.dart';
import 'package:myadhan/services/connectivity_service.dart';
import 'package:myadhan/services/prayer_times_api_service.dart';
import 'package:myadhan/services/prayer_times_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for the API service instance
final prayerTimesApiServiceProvider = Provider<PrayerTimesApiService>((ref) {
  return PrayerTimesApiService();
});

/// Provider for the location controller
final locationControllerProvider = Provider<LocationController>((ref) {
  return LocationController();
});

final prayerTimesCacheProvider = Provider<PrayerTimesCache>((ref) {
  return const PrayerTimesCache();
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService();
});

/// Where the times on screen came from, and how much to trust them.
///
/// This rides alongside the `AsyncValue<PrayerTimeModel>` rather than inside
/// it: every existing screen already destructures that value with `.when()`,
/// and "we're showing you real times, they're just not fresh" is not one of
/// loading/data/error. Keeping it separate means the offline banner is the
/// only thing that has to know about it.
class PrayerDataStatus {
  /// The last refresh attempt failed for network reasons.
  final bool isOffline;

  /// When the cache these times came from was actually fetched.
  final DateTime? lastSyncedAt;

  /// We're serving times we can no longer vouch for — the cache doesn't cover
  /// today, so these are the closest thing we had rather than the right answer.
  final bool isStale;

  const PrayerDataStatus({
    this.isOffline = false,
    this.lastSyncedAt,
    this.isStale = false,
  });

  /// True when the user should be told something. Fresh data fetched a moment
  /// ago says nothing; week-old data being shown offline says a lot.
  bool get shouldWarn => isOffline || isStale;

  PrayerDataStatus copyWith({
    bool? isOffline,
    DateTime? lastSyncedAt,
    bool? isStale,
  }) {
    return PrayerDataStatus(
      isOffline: isOffline ?? this.isOffline,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      isStale: isStale ?? this.isStale,
    );
  }
}

final prayerDataStatusProvider = StateProvider<PrayerDataStatus>((ref) {
  return const PrayerDataStatus();
});

/// StateNotifier for managing prayer times state with loading/success/error
class PrayerTimesNotifier extends StateNotifier<AsyncValue<PrayerTimeModel>> {
  final PrayerTimesApiService _apiService;
  final LocationController _locationController;
  final PrayerTimesCache _cache;
  final ConnectivityService _connectivity;
  final Ref _ref;

  Timer? _midnightTimer;
  Timer? _retryTimer;
  StreamSubscription<void>? _reconnectSub;

  /// Consecutive failed refreshes, used to back the retry off.
  int _failureCount = 0;

  /// Guards against the reconnect stream, the retry timer and a user tap all
  /// firing a fetch at once.
  bool _fetchInFlight = false;

  /// Remembered so an automatic retry targets the same place the user last
  /// asked for, rather than silently falling back to GPS.
  double? _manualLat;
  double? _manualLng;

  static const _retryBackoff = [
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
  ];

  /// Below this much remaining coverage we top the cache up, so the month
  /// boundary never arrives with nothing on the other side of it.
  static const _coverageFloorDays = 7;

  PrayerTimesNotifier(
    this._apiService,
    this._locationController,
    this._cache,
    this._connectivity,
    this._ref,
  ) : super(const AsyncValue.loading()) {
    // A refresh that failed because the network was down should cost the user
    // nothing to recover from — coming back into coverage is the retry.
    _reconnectSub = _connectivity.onReconnect().listen((_) {
      logDebug('📶 Connectivity restored — refreshing prayer times');
      _retryTimer?.cancel();
      fetchPrayerTimes(lat: _manualLat, lng: _manualLng);
    });
  }

  /// Wakes the app at the next moment the displayed day changes.
  ///
  /// There are two such moments, and they are not the same one:
  ///  * **Maghrib** — the Islamic day turns over at sunset, so the Hijri date
  ///    advances here.
  ///  * **Isha + 35m** — the last prayer of the day is done, so the *times*
  ///    swap to tomorrow's and the countdown starts targeting tomorrow's Fajr.
  ///
  /// Only Isha+35m used to be scheduled, so between Maghrib and Isha the app
  /// kept showing the Hijri date the Islamic day had already left, until
  /// something else happened to refresh it.
  void scheduleNextDayRefresh() async {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    DateTime nextRefresh;

    try {
      final prefs = await SharedPreferences.getInstance();

      final boundaries = <DateTime>[];

      // Maghrib — the Hijri boundary.
      final maghribStr = prefs.getString('prayer_4_time');
      if (maghribStr != null) {
        final m = _parseTimeString(maghribStr).add(const Duration(seconds: 5));
        boundaries.add(m);
        boundaries.add(m.add(const Duration(days: 1)));
      }

      // Isha + 35m — the prayer-schedule boundary.
      final ishaTimeStr = prefs.getString('prayer_5_time');
      if (ishaTimeStr != null) {
        final i = _parseTimeString(ishaTimeStr)
            .add(const Duration(minutes: 35, seconds: 5));
        boundaries.add(i);
        boundaries.add(i.add(const Duration(days: 1)));
      }

      // Whichever comes next. The 15s grace keeps a boundary we're sitting
      // exactly on from scheduling a zero-length timer that re-fires instantly.
      final cutoff = now.add(const Duration(seconds: 15));
      final upcoming = boundaries.where((b) => b.isAfter(cutoff)).toList()
        ..sort();

      nextRefresh = upcoming.isNotEmpty
          ? upcoming.first
          : DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    } catch (e) {
      nextRefresh = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    }

    final delay = nextRefresh.difference(now);
    logDebug('🕛 Next day-boundary refresh in ${delay.inSeconds}s (at $nextRefresh)');

    _midnightTimer = Timer(delay, () {
      logDebug('🕛 Day boundary reached — refreshing prayer times & Hijri date');
      fetchPrayerTimes(lat: _manualLat, lng: _manualLng);
    });
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    _retryTimer?.cancel();
    _reconnectSub?.cancel();
    super.dispose();
  }
  // Note: fetchPrayerTimes() is called from main.dart after permissions are granted

  /// Parses time string "HH:mm" or "HH:mm (TZ)" to DateTime on [onDate].
  DateTime _parseTimeString(String timeStr, {DateTime? onDate}) {
    final cleanTime = timeStr.split(' ').first;
    final parts = cleanTime.split(':');
    final day = onDate ?? DateTime.now();
    return DateTime(day.year, day.month, day.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  /// Gets coordinates from GPS or saved location
  Future<({double lat, double lng})> _getCoordinates() async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final position = await _locationController.determinePosition()
          .timeout(const Duration(seconds: 10));

      // Cache location for offline use
      await prefs.setDouble('last_latitude', position.latitude);
      await prefs.setDouble('last_longitude', position.longitude);

      return (lat: position.latitude, lng: position.longitude);
    } catch (e) {
      logDebug('⚠️ GPS failed: $e');

      // Fallback to cached location
      final savedLat = prefs.getDouble('last_latitude');
      final savedLng = prefs.getDouble('last_longitude');

      if (savedLat != null && savedLng != null) {
        logDebug('📍 Using cached location');
        return (lat: savedLat, lng: savedLng);
      }
      // Classified rather than described: the wording the user reads lives
      // in the UI layer, so it stays consistent with every other error state.
      throw AppException(
        AppErrorKind.location,
        'No GPS fix and no cached coordinates: $e',
      );
    }
  }

  /// Builds the display model for [date] out of a cached day.
  ///
  /// The Hijri date comes from [MonthCache.hijriNow] rather than from [day],
  /// because the two answer different questions: [day] is the Gregorian day
  /// whose *times* we're showing, while the Hijri date turns over at Maghrib.
  /// Between Maghrib and Isha+35m those differ by one, and taking it from
  /// [day] would show the date the Islamic day had already left.
  PrayerTimeModel _modelFromCachedDay(
    CachedDay day,
    DateTime date, {
    MonthCache? cache,
  }) {
    return PrayerTimeModel(
      fajer: _parseTimeString(day.fajr, onDate: date),
      dhuhr: _parseTimeString(day.dhuhr, onDate: date),
      asr: _parseTimeString(day.asr, onDate: date),
      maghrib: _parseTimeString(day.maghrib, onDate: date),
      isha: _parseTimeString(day.isha, onDate: date),
      dateOnHijri: cache?.hijriNow() ?? day.hijri,
    );
  }

  /// Last-ditch data source for installs that predate the month cache.
  ///
  /// `prayer_{id}_time` and `cached_hijri_date` have always been written by
  /// [PrayerAlarmScheduler] and the native writers, so an existing user who
  /// updates the app while offline still sees times on first launch instead of
  /// the error screen they'd have got before the cache existed.
  Future<PrayerTimeModel?> _modelFromLegacyPrefs(DateTime date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final times = <String>[];
      for (var id = 1; id <= 5; id++) {
        final value = prefs.getString('prayer_${id}_time');
        if (value == null) return null;
        times.add(value);
      }
      return PrayerTimeModel(
        fajer: _parseTimeString(times[0], onDate: date),
        dhuhr: _parseTimeString(times[1], onDate: date),
        asr: _parseTimeString(times[2], onDate: date),
        maghrib: _parseTimeString(times[3], onDate: date),
        isha: _parseTimeString(times[4], onDate: date),
        dateOnHijri: prefs.getString('cached_hijri_date') ?? '',
      );
    } catch (e) {
      logDebug('⚠️ Legacy prefs fallback failed: $e');
      return null;
    }
  }

  /// After Isha + 35m the interesting day is tomorrow, not today.
  ///
  /// Reads the same `prayer_5_time` pref the native countdown service uses for
  /// the identical decision, so both halves roll over at the same instant.
  Future<DateTime> _resolveTargetDate(SharedPreferences prefs) async {
    final now = DateTime.now();
    final ishaTimeStr = prefs.getString('prayer_5_time');
    if (ishaTimeStr == null) return now;

    try {
      final parts = ishaTimeStr.split(' ')[0].split(':');
      final ishaTimeObj = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
      if (now.isAfter(ishaTimeObj.add(const Duration(minutes: 35)))) {
        return now.add(const Duration(days: 1));
      }
    } catch (_) {}

    return now;
  }

  /// Whether it's worth spending a request right now.
  ///
  /// Refetching a month we already hold, every time the app resumes, would
  /// burn the user's data for nothing — so we only go to the network when the
  /// cache genuinely can't answer, has drifted, or is about to run out.
  bool _needsRefresh(
    MonthCache? cache,
    DateTime targetDate,
    double lat,
    double lng,
    int method,
  ) {
    if (cache == null) return true;
    if (cache.method != method) return true;
    if (!cache.isNear(lat, lng)) return true;
    if (cache.dayFor(targetDate) == null) return true;

    final end = cache.coverageEnd;
    if (end == null) return true;
    if (end.difference(targetDate).inDays < _coverageFloorDays) return true;

    // Even with coverage to spare, re-sync daily: the Hijri date and the
    // calculation can both be corrected upstream.
    return DateTime.now().difference(cache.fetchedAt).inHours >= 24;
  }

  /// Pulls the month containing [targetDate], plus the next one when the
  /// month is nearly over, and folds both into the cache.
  Future<MonthCache> _refreshCache({
    required DateTime targetDate,
    required double lat,
    required double lng,
    required int method,
  }) async {
    final days = await _apiService.fetchMonth(
      latitude: lat,
      longitude: lng,
      year: targetDate.year,
      month: targetDate.month,
      method: method,
    );

    // Day 0 of next month is the last day of this one.
    final daysInMonth =
        DateTime(targetDate.year, targetDate.month + 1, 0).day;
    if (daysInMonth - targetDate.day < _coverageFloorDays) {
      final next = DateTime(targetDate.year, targetDate.month + 1, 1);
      try {
        days.addAll(await _apiService.fetchMonth(
          latitude: lat,
          longitude: lng,
          year: next.year,
          month: next.month,
          method: method,
        ));
      } catch (e) {
        // The current month is the one that matters today; failing to reach
        // ahead is not a reason to discard what we just fetched.
        logDebug('⚠️ Could not pre-fetch next month: $e');
      }
    }

    return _cache.merge(
      days: days,
      latitude: lat,
      longitude: lng,
      method: method,
      school: 0,
    );
  }

  /// Fetches prayer times, cache first.
  ///
  /// The cache is consulted and emitted *before* any network work, so a cold
  /// start with no connection shows real times immediately instead of a
  /// shimmer that resolves into an error. The network refresh that follows can
  /// only ever improve on that — a failure leaves the cached times on screen
  /// and raises the offline flag rather than replacing them with an error.
  ///
  /// If [lat] and [lng] are provided, uses them directly (manual location).
  /// Otherwise, tries GPS then falls back to cached location.
  Future<void> fetchPrayerTimes({double? lat, double? lng}) async {
    if (_fetchInFlight) {
      logDebug('🕌 fetchPrayerTimes skipped — already in flight');
      return;
    }
    _fetchInFlight = true;
    _retryTimer?.cancel();
    _manualLat = lat;
    _manualLng = lng;

    logDebug('🕌 fetchPrayerTimes called');
    // Keep whatever is already on screen while we work. The old unconditional
    // `AsyncValue.loading()` meant a failed refresh wiped correct times.
    state = const AsyncValue<PrayerTimeModel>.loading().copyWithPrevious(state);

    final status = _ref.read(prayerDataStatusProvider.notifier);
    var servedFromCache = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final method = prefs.getInt('calculation_method') ?? 19;
      final targetDate = await _resolveTargetDate(prefs);

      // 1. Show what we already have, before touching GPS or the network.
      final cached = await _cache.read();
      final cachedDay = cached?.dayFor(targetDate);
      if (cached != null && cachedDay != null) {
        state = AsyncValue.data(
          _modelFromCachedDay(cachedDay, targetDate, cache: cached),
        );
        status.state = status.state.copyWith(
          lastSyncedAt: cached.fetchedAt,
          isStale: false,
        );
        servedFromCache = true;
        logDebug('💾 Served ${MonthCache.dayKey(targetDate)} from month cache');
      }

      // 2. Resolve where we are.
      double latitude;
      double longitude;
      if (lat != null && lng != null) {
        latitude = lat;
        longitude = lng;
        logDebug('📍 Using manual location: $latitude, $longitude');
      } else {
        logDebug('📍 Getting coordinates...');
        final coords = await _getCoordinates();
        latitude = coords.lat;
        longitude = coords.lng;
        logDebug('📍 Got coordinates: $latitude, $longitude');
      }

      // 3. Only spend a request if the cache can't already answer.
      if (!_needsRefresh(cached, targetDate, latitude, longitude, method)) {
        logDebug('✅ Month cache is current — skipping network fetch');
        status.state = status.state.copyWith(isOffline: false);
        _failureCount = 0;
        return;
      }

      final fresh = await _refreshCache(
        targetDate: targetDate,
        lat: latitude,
        lng: longitude,
        method: method,
      );
      logDebug('✅ Month cache refreshed (method=$method, ${fresh.days.length} days)');

      final day = fresh.dayFor(targetDate);
      if (day == null) {
        throw AppException(
          AppErrorKind.server,
          'Calendar response did not include ${MonthCache.dayKey(targetDate)}',
        );
      }

      final model = _modelFromCachedDay(day, targetDate, cache: fresh);
      await prefs.setString('cached_hijri_date', model.dateOnHijri);

      state = AsyncValue.data(model);
      status.state = PrayerDataStatus(
        isOffline: false,
        lastSyncedAt: fresh.fetchedAt,
        isStale: false,
      );
      _failureCount = 0;
    } catch (e, st) {
      logDebug('❌ Error fetching prayer times: $e');
      await _handleFetchFailure(e, st, servedFromCache: servedFromCache);
    } finally {
      _fetchInFlight = false;
      // Outside the success path on purpose: a failed fetch used to leave no
      // day-rollover timer at all, so the app never recovered on its own.
      scheduleNextDayRefresh();
    }
  }

  /// Degrades as gently as the available data allows: cached day, then the
  /// legacy prefs, and only an error screen when there is genuinely nothing.
  Future<void> _handleFetchFailure(
    Object error,
    StackTrace st, {
    required bool servedFromCache,
  }) async {
    final classified = AppException.from(error);
    final status = _ref.read(prayerDataStatusProvider.notifier);

    if (servedFromCache) {
      // Times are already on screen and correct for today — say we couldn't
      // reach the server, don't take them away.
      status.state = status.state.copyWith(isOffline: true);
      _scheduleRetry();
      return;
    }

    final targetDate = DateTime.now();
    final cached = await _cache.read();

    // The cache doesn't cover today, but it covered *something*. Yesterday's
    // times are wrong by a minute or two; a blank screen is wrong by all of
    // them — so show them and label them stale.
    final fallbackDay = cached?.dayFor(targetDate) ??
        cached?.dayFor(targetDate.subtract(const Duration(days: 1)));
    if (cached != null && fallbackDay != null) {
      state = AsyncValue.data(
        _modelFromCachedDay(fallbackDay, targetDate, cache: cached),
      );
      status.state = PrayerDataStatus(
        isOffline: classified.kind == AppErrorKind.network,
        lastSyncedAt: cached.fetchedAt,
        isStale: true,
      );
      _scheduleRetry();
      return;
    }

    final legacy = await _modelFromLegacyPrefs(targetDate);
    if (legacy != null) {
      logDebug('💾 Falling back to legacy prayer_*_time prefs');
      state = AsyncValue.data(legacy);
      status.state = PrayerDataStatus(
        isOffline: classified.kind == AppErrorKind.network,
        lastSyncedAt: null,
        isStale: true,
      );
      _scheduleRetry();
      return;
    }

    // Nothing anywhere. This is the only case that still earns the error view.
    // Classified before it reaches the UI, so the error state never has to
    // interpret a raw exception (and never renders one).
    state = AsyncValue.error(classified, st);
    status.state = PrayerDataStatus(
      isOffline: classified.kind == AppErrorKind.network,
      isStale: false,
    );
    _scheduleRetry();
  }

  /// Backs off after repeated failures so a long outage doesn't turn into a
  /// request every thirty seconds for the rest of the day.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay = _retryBackoff[
        _failureCount.clamp(0, _retryBackoff.length - 1)];
    _failureCount++;
    logDebug('⏳ Retrying prayer times in ${delay.inSeconds}s');
    _retryTimer = Timer(delay, () {
      fetchPrayerTimes(lat: _manualLat, lng: _manualLng);
    });
  }

  /// Refresh prayer times
  Future<void> refresh() {
    // An explicit tap means "try now", so it starts from the top of the
    // backoff ladder rather than inheriting an hour of accumulated patience.
    _failureCount = 0;
    return fetchPrayerTimes(lat: _manualLat, lng: _manualLng);
  }

  /// Notices that the user has travelled, and refetches if so.
  ///
  /// Called when the app comes back to the foreground. The expensive part of a
  /// refresh is acquiring a GPS fix, so this deliberately doesn't: it asks the
  /// OS for the position it already has cached — free, instant, no hardware —
  /// and only escalates to a full [fetchPrayerTimes] when that position is
  /// outside the radius the cached month describes.
  ///
  /// The comparison itself is [MonthCache.isNear], the same 25km test
  /// [_needsRefresh] already uses, so "has the user moved enough to matter?"
  /// has exactly one definition in the app.
  ///
  /// Does nothing when the user picked their city by hand — they've told us
  /// where they want times for, and physically moving doesn't revoke that.
  Future<void> checkForLocationChange() async {
    if (_manualLat != null && _manualLng != null) return;
    if (_fetchInFlight) return;

    try {
      final position = await _locationController.lastKnownPosition();
      // No cached fix, or no permission — "don't know", not "hasn't moved".
      if (position == null) return;

      final cache = await _cache.read();
      if (cache == null) return;

      if (cache.isNear(position.latitude, position.longitude)) return;

      logDebug(
        '📍 Moved outside the cached area '
        '(${cache.latitude}, ${cache.longitude}) → '
        '(${position.latitude}, ${position.longitude}) — refreshing',
      );
      _failureCount = 0;
      await fetchPrayerTimes();
    } catch (e) {
      // A failed check is not worth surfacing: the times on screen are still
      // the best we have, and the next resume tries again.
      logDebug('⚠️ Location change check failed: $e');
    }
  }
}

/// Provider for prayer times with loading, success, and error states
final prayerTimesProvider =
    StateNotifierProvider<PrayerTimesNotifier, AsyncValue<PrayerTimeModel>>((ref) {
  return PrayerTimesNotifier(
    ref.watch(prayerTimesApiServiceProvider),
    ref.watch(locationControllerProvider),
    ref.watch(prayerTimesCacheProvider),
    ref.watch(connectivityServiceProvider),
    ref,
  );
});
