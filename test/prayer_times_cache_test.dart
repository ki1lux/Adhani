import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myadhan/services/app_exception.dart';
import 'package:myadhan/services/prayer_times_api_service.dart';
import 'package:myadhan/services/prayer_times_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// These tests exist because of the warning in CLAUDE.md: Dart and Kotlin
/// share SharedPreferences keys and no compiler checks that they agree. The
/// month cache is now the most load-bearing of those keys — if its JSON shape
/// drifts, the native side silently stops finding days and alarms go quiet,
/// with nothing failing loudly enough to notice.
///
/// So the assertions here are deliberately about the *wire format* (literal
/// key names, the `yyyy-MM-dd` day key, the schema version) rather than about
/// Dart round-tripping with itself, which would pass even if both sides of the
/// contract moved together in a direction Kotlin can't read.
void main() {
  const cache = PrayerTimesCache();

  CachedDay day(String fajr) => CachedDay(
        fajr: fajr,
        dhuhr: '12:54',
        asr: '16:44',
        maghrib: '19:56',
        isha: '21:31',
        hijri: '16 صَفَر 1448',
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('wire format (must match PrayerMonthCache.kt)', () {
    test('writes the exact key and field names Kotlin reads', () async {
      await cache.merge(
        days: {'2026-07-30': day('04:10')},
        latitude: 36.75,
        longitude: 3.06,
        method: 19,
        school: 0,
      );

      final prefs = await SharedPreferences.getInstance();
      // Kotlin reads this as "flutter.prayer_month_cache".
      final raw = prefs.getString('prayer_month_cache');
      expect(raw, isNotNull);

      final decoded = json.decode(raw!) as Map<String, dynamic>;
      expect(decoded['v'], 1, reason: 'schema version Kotlin checks');
      expect(decoded.keys, containsAll(<String>['v', 'lat', 'lng', 'method', 'school', 'fetchedAt', 'days']));

      final days = decoded['days'] as Map<String, dynamic>;
      final entry = days['2026-07-30'] as Map<String, dynamic>;
      expect(
        entry.keys,
        containsAll(<String>['fajr', 'dhuhr', 'asr', 'maghrib', 'isha', 'hijri']),
      );
      expect(entry['fajr'], '04:10');
    });

    test('day keys are zero-padded yyyy-MM-dd', () {
      expect(MonthCache.dayKey(DateTime(2026, 7, 5)), '2026-07-05');
      expect(MonthCache.dayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('a cache written under a different schema is discarded, not misread',
        () async {
      SharedPreferences.setMockInitialValues({
        'prayer_month_cache': json.encode({'v': 99, 'days': {}}),
      });
      expect(await cache.read(), isNull);
    });

    test('corrupt JSON degrades to no cache rather than throwing', () async {
      SharedPreferences.setMockInitialValues({
        'prayer_month_cache': 'not json at all',
      });
      expect(await cache.read(), isNull);
    });
  });

  group('coverage and validity', () {
    test('merging keeps existing days for the same place and method', () async {
      await cache.merge(
        days: {'2026-07-30': day('04:10')},
        latitude: 36.75,
        longitude: 3.06,
        method: 19,
        school: 0,
      );
      final merged = await cache.merge(
        days: {'2026-07-31': day('04:11')},
        latitude: 36.75,
        longitude: 3.06,
        method: 19,
        school: 0,
      );

      expect(merged.days.keys, containsAll(<String>['2026-07-30', '2026-07-31']));
    });

    test('changing the calculation method discards the old days', () async {
      await cache.merge(
        days: {'2026-07-30': day('04:10')},
        latitude: 36.75,
        longitude: 3.06,
        method: 19,
        school: 0,
      );
      final merged = await cache.merge(
        days: {'2026-07-31': day('04:11')},
        latitude: 36.75,
        longitude: 3.06,
        method: 3,
        school: 0,
      );

      // The old day described a different calculation, not an earlier time.
      expect(merged.days.keys, <String>['2026-07-31']);
    });

    test('moving further than the staleness radius discards the old days',
        () async {
      await cache.merge(
        days: {'2026-07-30': day('04:10')},
        latitude: 36.75,
        longitude: 3.06,
        method: 19,
        school: 0,
      );
      // Algiers → Paris.
      final merged = await cache.merge(
        days: {'2026-07-31': day('05:20')},
        latitude: 48.85,
        longitude: 2.35,
        method: 19,
        school: 0,
      );

      expect(merged.days.keys, <String>['2026-07-31']);
    });

    test('isNear tolerates a small move but not a large one', () {
      final c = MonthCache(
        latitude: 36.75,
        longitude: 3.06,
        method: 19,
        school: 0,
        fetchedAt: DateTime.now(),
        days: const {},
      );
      expect(c.isNear(36.76, 3.07), isTrue, reason: 'a few km across a city');
      expect(c.isNear(48.85, 2.35), isFalse, reason: 'Algiers is not Paris');
    });

    test('days older than yesterday are pruned on write', () async {
      final old = MonthCache.dayKey(
        DateTime.now().subtract(const Duration(days: 10)),
      );
      final today = MonthCache.dayKey(DateTime.now());

      final merged = await cache.merge(
        days: {old: day('04:00'), today: day('04:10')},
        latitude: 36.75,
        longitude: 3.06,
        method: 19,
        school: 0,
      );

      expect(merged.days.containsKey(old), isFalse);
      expect(merged.days.containsKey(today), isTrue);
    });

    test('dayFor and coversToday resolve the current date', () async {
      final today = MonthCache.dayKey(DateTime.now());
      final merged = await cache.merge(
        days: {today: day('04:10')},
        latitude: 36.75,
        longitude: 3.06,
        method: 19,
        school: 0,
      );

      expect(merged.coversToday, isTrue);
      expect(merged.dayFor(DateTime.now())?.fajr, '04:10');
      expect(merged.dayFor(DateTime(2000, 1, 1)), isNull);
    });
  });

  group('hijriNow — the Islamic day turns over at Maghrib', () {
    /// Two consecutive days with distinguishable Hijri values, so it's obvious
    /// which one is in effect.
    MonthCache twoDayCache() => MonthCache(
          latitude: 36.75,
          longitude: 3.06,
          method: 19,
          school: 0,
          fetchedAt: DateTime(2026, 7, 30, 9),
          days: {
            '2026-07-30': const CachedDay(
              fajr: '04:11',
              dhuhr: '12:55',
              asr: '16:46',
              maghrib: '20:00',
              isha: '21:34',
              hijri: '16 صَفَر 1448',
            ),
            '2026-07-31': const CachedDay(
              fajr: '04:12',
              dhuhr: '12:55',
              asr: '16:45',
              maghrib: '19:59',
              isha: '21:33',
              hijri: '17 صَفَر 1448',
            ),
          },
        );

    test('before Maghrib it is still the current day', () {
      expect(
        twoDayCache().hijriNow(DateTime(2026, 7, 30, 19, 59)),
        '16 صَفَر 1448',
      );
    });

    test('from Maghrib onwards it is already the next day', () {
      expect(
        twoDayCache().hijriNow(DateTime(2026, 7, 30, 20, 00)),
        '17 صَفَر 1448',
        reason: 'the Islamic day begins at sunset',
      );
    });

    test('it stays on the new day through Isha and past midnight', () {
      final cache = twoDayCache();
      // Isha of the 30th belongs to the Islamic day that began at Maghrib.
      expect(cache.hijriNow(DateTime(2026, 7, 30, 21, 34)), '17 صَفَر 1448');
      expect(cache.hijriNow(DateTime(2026, 7, 30, 23, 59)), '17 صَفَر 1448');
      // Crossing Gregorian midnight must NOT advance it a second time.
      expect(cache.hijriNow(DateTime(2026, 7, 31, 0, 1)), '17 صَفَر 1448');
      expect(cache.hijriNow(DateTime(2026, 7, 31, 12, 0)), '17 صَفَر 1448');
    });

    test('returns null when the cache cannot answer, so callers keep their fallback', () {
      expect(twoDayCache().hijriNow(DateTime(2020, 1, 1, 12)), isNull);
    });

    test('falls back to the current day when tomorrow is not cached', () {
      final cache = MonthCache(
        latitude: 36.75,
        longitude: 3.06,
        method: 19,
        school: 0,
        fetchedAt: DateTime(2026, 7, 30, 9),
        days: {
          '2026-07-30': const CachedDay(
            fajr: '04:11',
            dhuhr: '12:55',
            asr: '16:46',
            maghrib: '20:00',
            isha: '21:34',
            hijri: '16 صَفَر 1448',
          ),
        },
      );
      expect(cache.hijriNow(DateTime(2026, 7, 30, 21, 0)), '16 صَفَر 1448');
    });
  });

  group('fetchMonth', () {
    /// api.aladhan.com answers `application/json` with **no charset** and a
    /// UTF-8 body (verified against the live endpoint), and the Hijri month
    /// names are Arabic. Building the fake response from bytes rather than a
    /// String reproduces that faithfully — `http.Response(String, ...)` would
    /// encode it as latin-1 and never exercise the real decode path.
    http.Response jsonResponse(String body) => http.Response.bytes(
          utf8.encode(body),
          200,
          headers: {'content-type': 'application/json'},
        );

    /// Trimmed to the fields the parser touches, but the shape and the
    /// "HH:mm (TZ)" suffix are exactly what api.aladhan.com returns.
    String calendarBody() => json.encode({
          'code': 200,
          'status': 'OK',
          'data': [
            {
              'timings': {
                'Fajr': '04:10 (CET)',
                'Dhuhr': '12:54 (CET)',
                'Asr': '16:44 (CET)',
                'Maghrib': '19:56 (CET)',
                'Isha': '21:31 (CET)',
              },
              'date': {
                'gregorian': {'date': '30-07-2026'},
                'hijri': {
                  'day': '16',
                  'month': {'ar': 'صَفَر'},
                  'year': '1448',
                },
              },
            },
          ],
        });

    test('keys days by yyyy-MM-dd and applies the per-prayer offsets', () async {
      final service = PrayerTimesApiService(
        client: MockClient((_) async => jsonResponse(calendarBody())),
      );

      final days = await service.fetchMonth(
        latitude: 36.75,
        longitude: 3.06,
        year: 2026,
        month: 7,
      );

      // The API dates entries "DD-MM-YYYY"; the cache key is the sortable
      // way round, and Kotlin's fetchMonth flips it identically.
      final d = days['2026-07-30'];
      expect(d, isNotNull);

      // Same +1/+1/+2/+4/+3 the single-day path applies, so a day served from
      // the cache is identical to the same day fetched live.
      expect(d!.fajr, '04:11');
      expect(d.dhuhr, '12:55');
      expect(d.asr, '16:46');
      expect(d.maghrib, '20:00');
      expect(d.isha, '21:34');
      expect(d.hijri, '16 صَفَر 1448');
    });

    test('a captive-portal HTML 200 is reported as a server error, not unknown',
        () async {
      final service = PrayerTimesApiService(
        client: MockClient(
          (_) async => http.Response('<html>Sign in to Wi-Fi</html>', 200),
        ),
      );

      await expectLater(
        service.fetchMonth(
          latitude: 36.75,
          longitude: 3.06,
          year: 2026,
          month: 7,
        ),
        throwsA(
          isA<AppException>()
              .having((e) => e.kind, 'kind', AppErrorKind.server),
        ),
      );
    });

    test('a transport failure is classified as network', () async {
      final service = PrayerTimesApiService(
        client: MockClient(
          (_) async => throw http.ClientException('Failed host lookup'),
        ),
      );

      await expectLater(
        service.fetchMonth(
          latitude: 36.75,
          longitude: 3.06,
          year: 2026,
          month: 7,
        ),
        throwsA(
          isA<AppException>()
              .having((e) => e.kind, 'kind', AppErrorKind.network),
        ),
      );
    });
  });

  group('AppException classification', () {
    test('a permission failure is not reported as a network failure', () {
      // geolocator's message mentions a connection in passing; the old
      // ordering matched that first and told the user their internet was down.
      final e = AppException.from(
        Exception('Location permissions are denied, connection unavailable'),
      );
      expect(e.kind, AppErrorKind.locationPermission);
    });

    test('genuine transport failures still classify as network', () {
      expect(
        AppException.from(Exception('Failed host lookup: api.aladhan.com')).kind,
        AppErrorKind.network,
      );
      expect(
        AppException.from(Exception('Connection refused')).kind,
        AppErrorKind.network,
      );
    });
  });
}
